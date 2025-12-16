---
title: Kubernetesクラスターを組織内で自由に使えるようにしてみた
tags:
  - kubernetes
  - OIDC
  - CustomControl
  - Kubebuilder
  - CRD
private: false
updated_at: '2025-08-30T21:45:54+09:00'
id: babaa0710bffbdffbe5f
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

OIDCを使って認証したユーザー毎にnamespaceによって隔離された環境を作成するCustom Controllerを作成してユーザー管理を自動化してみたので顛末を記録しておきます。

教育的な用途もあるので隔離といっても厳密なものではありません。各ユーザーには他のnamespaceにどんなPodが動作しているかといった情報が得られる程度にはget/watch/listの権限を各オブジェクトに付与しています。

もちろんpod/log, configmap, secretといったオブジェクトの参照権限は落しています。

これまでは限られたメンバーにIDと同名のnamespaceを準備するためにYAMLファイルを生成する仕組みを作って手作業で作業をしてきました。この仕組みは年に数回のタイミングで人を入れ替える用途には十分なのですが、いざシステムを開放して人数を増やそうとすると線形に負担が増えるだけでなく、不定期な作業が発生してしまうことになります。

メモリ使用量の上限のようなパラメータは使いながらチューニングによる変更が想定されるため、そういった変更に強い仕組みが必要になります。

Custom Controllerを利用する良いusecaseだと思いつつ、わざわざ作成するのも面倒だなと構想だけ温めてきましたました。

## 参考資料

Custom Controllerを作成するために全体をとおして参照した資料は次のとおりです。

* 書籍: [実践入門 Kubernetesカスタムコントローラーへの道](https://nextpublishing.jp/book/11389.html)
* Web: [つくって学ぶKubebuilder](https://zoetrope.github.io/kubebuilder-training/)
* Web: https://pkg.go.dev/k8s.io/api
* Web: https://kubernetes.io/docs/concepts/overview/components/

これらの参考資料とそこから派生する資料だけで十分だと思います。KubernetesのControl-Planeがapi-serverを中心にどのように動作しているのかは把握しておくことは必須です。

### repoについて

引数で指定するrepositoryにはgithub.ioではなく、自分で運用している手元のgitlabのpathを指定しています。

```bash:
$ grep init 00.history.txt
kubebuilder init --domain yadiary.net --repo gitlab.example.com/gitlab/yasu/operator-kubecamp-setup
```

### その他の資料

個別の事象に対応するため、参考にした資料は以下にまとめます。

* https://infosecwriteups.com/the-bind-escalate-and-impersonate-verbs-in-the-kubernetes-cluster-e9635b4fbfc6
* https://stackoverflow.com/questions/54043691/roles-rbac-authorization-k8s-io-is-forbidden-even-added-in-apigroups


## 環境

* エディター
  * Emacs with GitHub Copilot
  * JetBrains Goland with JetBrains AI Assistant
* Utilities: KubeBuidler v3.14.0 
* K8s Cluster: Kubernetes v1.27.7
* 開発環境: Ubuntu 22.04


# おおまかな構成

これまで次のようなYAMLファイルを生成してkubectlコマンドから手動で設定してきました。

* Ingress (namespace: ingress-nginx)
* Service (namespace: ingress-nginx)
* Namespace (Cluster-wide)
* ClusterRole (Cluster-wide)
* ClusterRoleBinding (Cluster-wide)
* Role
* RoleBinding

ClusterRoleBindingから参照するClusterRoleはあらかじめ定義したものを静的に参照しています。

システムを公開しようとすると、CPUやMemory、PVCについての制限が必要になるのでユーザーのnamespaceに次のような制約を加えます。

* NetworkPolicy
* ResourceQuota
* LimitRange

LimitRangeを使うことで1つ目のPodがQuotaの制限値を越えないようにすることができるので、全てのDeploymentやStatefulSet, あるいはPodの定義にresources設定を追加する手間が削減できます。

## ユースケース

![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/78296/ac57fe22-afa8-9b57-1598-74ec81b6a95d.png)

以下の操作はこのCustom Controllerの範囲外です。

1. ユーザーがWebアプリなどを通して利用を申請する
1. 管理者が何らかの方法でユーザー名を記入したYAML形式のCRDsファイルを作成し、kubectl apply -fなどで適用する

以下の操作がCustom Controllerの守備範囲です。

1. Controllerがユーザー毎にNamespaceを作成し、必要な権限をRoleBinding, ClusterRoleBindingを通して与える
1. Controllerは作成したNamespaceに自身のCRDsをコピーする
1. ControllerはNamespaceとCRDsの定義名が一致した場合にRole,RoleBinding,NetworkPolicyなどのオブジェクトをNamespaceを親として作成する

これらの作業が管理用した後でユーザーでは次のような操作が発生します。

1. ユーザーはOIDCサーバーからID tokenを取得する
1. 取得したID Token情報を元に、~/.kube/configファイルを配置する
1. kubectlコマンドからapi-serverに接続し、自身のnamespace上にオブジェクトを生成・配置する

ユーザーがデプロイしたアプリケーションは次のような形でアクセス可能となります。

1. 管理者はネットワーク境界にNginxを配置します
1. 全てのリクエストをIngress(namespace: ingress-nginxのnginx pod)に転送するよう構成します
1. Custom Controllerにより作成されたIngressとServiceのオブジェクトによって、Ingressはユーザーのcontext-rootに届いたリクエストをユーザーのnamespace上にあるservices/<username>-svcに転送します
1. 利用者はsvc/<username>-svcを作成し、selectorを適切に設定することでユーザーからのアクセスを制御します

これによって **https\://代表ホスト名/<username>/** で各ユーザーのnamespace上のPodにアクセスできるようにします。必要に応じてユーザー側でnginxをproxyサーバーとして利用してもらうことで単純化しています。

![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/78296/f71a7c08-7da7-c24e-71cb-ccbd39993287.png)


## CRDs

ここでは次のようなCustom Resouceを想定しています。

```yaml:01.members.yaml
---
apiVersion: crds.yadiary.net/v1
kind: Members
spec:
  members:
    - member: yasu
      maxCPUm: 500
      maxMemoryMiB: 500
      defaultCPUm: 100
      defaultMemoryMB: 100
      numOfPVCs: 5
      maxPVCSizeMiB: 1000
      type: admin
```

memberとtype以外のパラメータはオプションにして設定していない場合にはwebhookによってデフォルト値を与えています。

## 考慮点

kubebuilderのチュートリアルで想定しているのは特定のnamespace上にCustom Resourceを作成し、そのnamespaceに対してServicesなどのオブジェクトを設定していくユースケースです。

Database Server系のOperatorの多くは特定のnamespace上にCustom Resourceを作成すると、そのnamespace上でクラスター化されたRDBMSが起動するといった挙動をします。

今回はIngressなど他のnamespaceに所属するオブジェクトやCluster-wideなClusterRoleBindingなどを管理しなければいけなくなるので一般的なCRDsのユースケースから少し外れる部分もそれなりにあります。

Custom Resourceと異なるNamespace上のオブジェクトはFinalizerでCustom Controllerが削除しますが、それ以外の各namespace毎に作成するオブジェクトのOwnerReferenceを管理・設定するのは少し面倒だったので、作成した各namespaceにCustom Resrouceの内容をコピーして、作業を分担しています。

# 実装時に苦労した点

LimitRangeのようなリソースを定義する時にはYAMLファイルに対応したオブジェクトを作成しなければいけませんが、サンプルコードなしではかなり難しいパズルのような作業でした。

GitHub Copilotなどもそれなりに便利でしたが、動作しない不完全なコードを提案する場面がほとんどで、Golang Pkgのドキュメントを参照しながら修正しました。

作成するオブジェクトの種類によっては都度変更する必要のないものもあります。その場合には存在したら無視、そうでなければ作成するといった単純な作業に変更するといった判断を適宜行いました。

必要の都度Server Side Applyに変更するというアプローチをとっています。

## Reconcile本体の概要

```golang:CustomContollerのimportとRBAC関連の宣言部分
import (
	"context"
	corev1 "k8s.io/api/core/v1"
	networkv1 "k8s.io/api/networking/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	metav1apply "k8s.io/client-go/applyconfigurations/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/apiutil"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"strings"

	kubecampv1 "gitlab.example.com/yasu/operator-kubecamp-setup/api/v1"
)


//+kubebuilder:rbac:groups=kubecamp.example.com,resources=members,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=kubecamp.example.com,resources=members/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=kubecamp.example.com,resources=members/finalizers,verbs=update

//+kubebuilder:rbac:groups="core",resources=namespaces,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="core",resources=services,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="core",resources=resourcequotas,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="core",resources=limitranges,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="core",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="apps",resources=deployments,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="networking.k8s.io",resources=ingresses,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="networking.k8s.io",resources=networkpolicies,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="rbac.authorization.k8s.io",resources=rolebindings,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="rbac.authorization.k8s.io",resources=roles,verbs=get;list;watch;create;update;patch;delete;escalate;bind
//+kubebuilder:rbac:groups="rbac.authorization.k8s.io",resources=clusterrolebindings,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="rbac.authorization.k8s.io",resources=clusterroles,verbs=get;list;watch;create;update;patch;delete;bind
```

Reconcile処理の本体は次のような構造になっています。

```golang:Reconcile処理の本体
func (r *MembersReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	// get Members object
	var kubecampview kubecampv1.Members
	err := r.Get(ctx, req.NamespacedName, &kubecampview)
	if errors.IsNotFound(err) {
		return ctrl.Result{}, nil
	}
	if err != nil {
		mylog.Error(err, "Failed to get kubecampview", "req.NamespacedName", req.NamespacedName)
		return ctrl.Result{}, err
	}

	mylog.Info("Reconciler", "req.Namespace", req.Namespace, "kubecampview.GetName", kubecampview.GetName())
	if !strings.HasSuffix(kubecampview.GetName(), req.Namespace) { // if kubecampview.GetName(), "kubecamp-yasu-abe", contains req.NamespacedName.Namespace, "yasu-abe"

		// load configmap
		var custom_cm corev1.ConfigMap
		err := r.Get(ctx, types.NamespacedName{Name: "kuecamp-config", Namespace: req.Namespace}, &custom_cm)
		if err != nil {
			mylog.Error(err, "Failed to get configmap")
			// do nothing
		} else {
			mylog.Info("Reconsile", "load configmap", custom_cm)
			if hostname, exists := custom_cm.Data["hostname"]; exists {
				serviceHostName = hostname
			}
		}

		// manage finalizer
		mylog.Info("manage finalizer")
		if !kubecampview.ObjectMeta.DeletionTimestamp.IsZero() {
			mylog.Info("Reconciler", "DeletionTimestamp", "not zero")
			if controllerutil.ContainsFinalizer(&kubecampview, finalizerName) {
				mylog.Info("Reconciler", "finalizer", "finalizing objects ...")
				for i, member := range kubecampview.Spec.Members {
					mylog.Info("cleanup member", "count", i, "value", member)
					err = r.cleanupExtResources(ctx, kubecampview, member)
					if err != nil {
						mylog.Error(err, "Failed to cleanup resources")
						return ctrl.Result{}, err
					}
				}

				controllerutil.RemoveFinalizer(&kubecampview, finalizerName)
				err = r.Update(ctx, &kubecampview)
				if err != nil {
					mylog.Error(err, "Failed to remove finalizer")
					return ctrl.Result{}, err
				}
			}
			return ctrl.Result{}, nil
		}
		// Add all "finalizer" mark to all Members object
		mylog.Info("Reconciler", "finalizer", "adding finalizer ...")
		if !controllerutil.ContainsFinalizer(&kubecampview, finalizerName) {
			controllerutil.AddFinalizer(&kubecampview, finalizerName)
			err = r.Update(ctx, &kubecampview)
			if err != nil {
				return ctrl.Result{}, err
			}
		}

		// loop for each member if req.NamespacedName is not kubecampview.Name
		for i, member := range kubecampview.Spec.Members { //
			mylog.Info("member", "count", i, "value", member)
			err = r.reconcileService(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile service")
				return ctrl.Result{}, err
			}
			err = r.reconcileNamespace(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile namespace")
				return ctrl.Result{}, err
			}

			err = r.reconcileUserMembers(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile user members")
				return ctrl.Result{}, err
			}

			// create ClusterRoleBinding for kubecamp users
			err = r.reconcileClusterRoleBinding(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile clusterrolebinding")
				return ctrl.Result{}, err
			}

			// create Ingress
			err = r.reconcileIngress(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile Ingress")
				return ctrl.Result{}, err
			}
		}
	} else {
		mylog.Info("Found user's namespace", "req.NamespacedName.Namespace", req.NamespacedName.Namespace, "kubecampview.GetName", kubecampview.GetName())
		// create role and rolebindign for user
		for i, member := range kubecampview.Spec.Members {
			mylog.Info("member", "count", i, "value", member)

			// create Role
			err = r.reconcileRole(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile Role")
				return ctrl.Result{}, err
			}
			// create RoleBinding
			err = r.reconcileRoleBinding(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile RoleBinding")
				return ctrl.Result{}, err
			}
			// create ResourceQuota if type is guest-user
			err = r.reconcileQuota(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile ResourceQuota")
				return ctrl.Result{}, err
			}
			// manage NetworkPolicies
			err = r.reconcileNetworkPolicy(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile NetworkPolicy")
				return ctrl.Result{}, err
			}
			// manage LimitRange
			err = r.reconcileLimitRange(ctx, kubecampview, member)
			if err != nil {
				mylog.Error(err, "Failed to reconcile LimitRange")
				return ctrl.Result{}, err
			}
		}
	}
	return ctrl.Result{}, nil
}
```

Finalizerが実際に実行する処理は次のようになっています。

```golang:
// cleanup Service and Namespace object placed in different namespaces
func (r *MembersReconciler) cleanupExtResources(ctx context.Context, kubecampview kubecampv1.Members, kubecampitem kubecampv1.MembersItem) error {
	_ = log.FromContext(ctx)

	// cleanup Service
	mylog.Info("cleanup service")
	serviceName := kubecampitem.Member + "-svc"
	var current corev1.Service
	err := r.Get(ctx, client.ObjectKey{Namespace: ingressNamespace, Name: serviceName}, &current)
	if err != nil {
		if !errors.IsNotFound(err) {
			return err
		}
		mylog.Info("cleanupExtResources", "service not found", serviceName)
	} else {
		mylog.Info("cleanupExtResources", "svc", current)
		err = r.Delete(ctx, &current)
		if err != nil {
			mylog.Error(err, "Failed to delete service")
			return err
		}
	}

	//cleanup Namespace
	mylog.Info("cleanup namespace")
	targetNamespace := kubecampitem.Member
	currentNs := &corev1.Namespace{}
	err = r.Get(ctx, types.NamespacedName{Name: targetNamespace}, currentNs)
	if err != nil {
		if !errors.IsNotFound(err) {
			return err
		}
		mylog.Info("cleanupExtResources", "namespace not found", kubecampitem.Member)
	} else {
		mylog.Info("cleanupExtResources", "ns", currentNs)
		err = r.Delete(ctx, currentNs)
		if err != nil {
			mylog.Error(err, "Failed to delete namespace")
			return err
		}
	}

	// cleanup ClusterRoleBinding
	mylog.Info("cleanup clusterrolebinding")
	targetName := clusterRoleBindingKubecampNamePrefix + kubecampitem.Member
	currentClusterRoleBinding := &rbacv1.ClusterRoleBinding{}
	err = r.Get(ctx, client.ObjectKey{Name: targetName}, currentClusterRoleBinding)
	if err != nil {
		if !errors.IsNotFound(err) {
			return err
		}
		mylog.Info("cleanupExtResources", "clusterrolebinding not found", targetName)
	} else {
		mylog.Info("cleanupExtResources", "clusterrolebinding", currentClusterRoleBinding)
		err = r.Delete(ctx, currentClusterRoleBinding)
		if err != nil {
			mylog.Error(err, "Failed to delete clusterrolebinding")
			return err
		}
	}

	// cleanup Ingress
	mylog.Info("cleanup ingress")
	ingressName := kubecampitem.Member
	currentIngress := networkv1.Ingress{}
	err = r.Get(ctx, client.ObjectKey{Namespace: ingressNamespace, Name: ingressName}, &currentIngress)
	if err != nil {
		if !errors.IsNotFound(err) {
			return err
		}
		mylog.Info("cleanupExtResources", "ingress not found", ingressName)
	} else {
		mylog.Info("cleanupExtResources", "ingress", currentIngress)
		err = r.Delete(ctx, &currentIngress)
		if err != nil {
			mylog.Error(err, "Failed to delete ingress")
			return err
		}
	}

	// successfully finished.
	return nil
}
```

## Reconcileのパターン

「つくって学ぶKubebuilder」にはCreateOrUpdate()を使うパターンと、Patch()を使って差分を適用するパターンの2つが紹介されています。

CreateOrUpdate()やCreate()を使う場合には作成するオブジェクトを"k8s.io/api/"以下に所属する基本的な型で表現できるpackageを使って作成します。

Patch()などServer-side Applyを利用する場合には"k8s.io/client-go/applyconfigurations/"以下に所属する"core/v1"などのパッケージを利用します。``r.Patch()``は[controller-runtime](https://pkg.go.dev/sigs.k8s.io/controller-runtime/pkg/client#Client)のClient.Patch()を呼び出していて、このドキュメントには詳細な例が掲載されています。

CreateOrUpdateは変更するべき差分がどこにあるか完全に把握できる自分で定義したCustom Resourceに適用するには便利な手法です。ただ規模が大きくなるとServer-side Applyが使いたくなるので、実質的にCreateOrUpdate()を使うことはほとんどありませんでした。

## LimitRangeオブジェクトの作成

定義はcore/v1にあるので作成自体にはそれほど難しくありません。

最終的には次のようなコードになりました。

```golang:reconcile_limitrange.go
import (
	"context"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	corev1apply "k8s.io/client-go/applyconfigurations/core/v1"
	"k8s.io/utils/pointer"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

     myv1 "...."
)

//var mylog = logf.Log.WithName("controller_members")
//var fieldManager = "...controller-name..."

func (r *MembersReconciler) reconcileLimitRange(ctx context.Context, myview myv1.Members, myitem myv1.MembersItem) error {
	_ = log.FromContext(ctx)

	limitsName := "default-limits"

	limits := corev1apply.LimitRange(limitsName, myitem.Member).
		WithLabels(map[string]string{
			"app.kubernetes.io/name":       limitsName,
			"app.kubernetes.io/instance":   myitem.Member,
			"app.kubernetes.io/created-by": fieldManager,
		}).
		WithSpec(corev1apply.LimitRangeSpec().
			WithLimits(corev1apply.LimitRangeItem().
				WithType("Container").
				WithDefault(map[corev1.ResourceName]resource.Quantity{
					corev1.ResourceCPU:    *resource.NewMilliQuantity(myitem.DefaultCPU, resource.DecimalSI),
					corev1.ResourceMemory: *resource.NewQuantity(myitem.DefaultMemory*1024*1024, resource.BinarySI),
				}).
				WithDefaultRequest(map[corev1.ResourceName]resource.Quantity{
					corev1.ResourceCPU:    *resource.NewMilliQuantity(myitem.DefaultCPU, resource.DecimalSI),
					corev1.ResourceMemory: *resource.NewQuantity(myitem.DefaultMemory*1024*1024, resource.BinarySI),
				}),
			))

	obj, err := runtime.DefaultUnstructuredConverter.ToUnstructured(limits)
	if err != nil {
		return err
	}
	patch := &unstructured.Unstructured{
		Object: obj,
	}

	// try to find current LimitRange object
	var current corev1.LimitRange
	err = r.Get(ctx, client.ObjectKey{Namespace: myitem.Member, Name: limitsName}, &current)
	if err != nil && !errors.IsNotFound(err) {
		return err
	}
	currApplyConfig, err := corev1apply.ExtractLimitRange(&current, fieldManager)
	if err != nil {
		return err
	}
	if equality.Semantic.DeepEqual(limits, currApplyConfig) {
		return nil
	}
	err = r.Patch(ctx, patch, client.Apply, &client.PatchOptions{
		FieldManager: fieldManager,
		Force:        pointer.Bool(true),
	})
	if err != nil {
		return err
	}
	mylog.Info("reconcile LimitRange successfully")
	return nil
}
```

とりあえず動いているのでlimitsオブジェクトの構造以外はちゃんと確認せずに「つくって学ぶKubebuilder」のコードをそのまま利用しています。

DeepEqual()の第一引数と第二引数の順序がこれで良いのかといった点はこれから確認していきます。

## ClusterRoleやRoleを操作するためのRBAC権限

kubebuilderが出力してくれたコードはコメントに書かれている定義をみて自動で必要な権限をServiceAccountに付与してくれます。

普通はverbとしてget;list;watch;create;update;patch;deleteで範囲が広すぎるので狭めるか検討するところですが、今回はこの他のverbを追加している部分があります。

```golang:members_controller.go
//+kubebuilder:rbac:groups="rbac.authorization.k8s.io",resources=roles,verbs=get;list;watch;create;update;patch;delete;escalate;bind
//+kubebuilder:rbac:groups="rbac.authorization.k8s.io",resources=clusterroles,verbs=get;list;watch;create;update;patch;delete;bind
```

RoleやClusterRoleを作成する場合には**escalate**を追加しますが、今回はClusterRoleを手動で追加しているのでRoleだけに追加しています。

Binding(RoleBinding or ClusterRoleBinding)を作成するために、bind権限を追加しています。

調べてみると、**inpersonate**というverbを設定する場合もあるようです。

https://infosecwriteups.com/the-bind-escalate-and-impersonate-verbs-in-the-kubernetes-cluster-e9635b4fbfc6

## Ingressオブジェクトの作成

Ingressオブジェクトをnamespace: **ingress-nginx**に追加した時には少し特殊な処理が必要でした。

PathTypeは"Exact", "Prefix", "ImplementationSpecific"のいずれかで、constで"k8s.io/api/networking/v1"に定義されています。

これを格納する時の型が**PathType *PathType**と指定されているので、そのまま直接アドレスに変換しようとするとエラーになります。

検索するとconst値とポインターの変換はよくある質問のようですが、temp変数を経由して次のようになりました。

```golang:reconcile_ingress.goからの抜粋
...
	temp := networkv1.PathTypePrefix
	var pathPrefix *networkv1.PathType = &temp
	ingress := &networkv1.Ingress{}
	ingress.SetName(targetName)
	ingress.SetNamespace(ingressNamespace)
	ingress.SetLabels(map[string]string{"group": "ingress-nginx"})
	ingress.Spec.Rules = []networkv1.IngressRule{
		{
			IngressRuleValue: networkv1.IngressRuleValue{
				HTTP: &networkv1.HTTPIngressRuleValue{
					Paths: []networkv1.HTTPIngressPath{
						{
							Backend: networkv1.IngressBackend{
								Service: &networkv1.IngressServiceBackend{
									Name: targetName + "-svc",
									Port: networkv1.ServiceBackendPort{
										Number: 80,
									},
								},
							},
							Path:     "/" + targetName,
							PathType: pathPrefix,
						},
					},
				},
			},
		},
	}
 ...
```

Ingressオブジェクトは変更する必要がないので、有れば無視(return nil)し、なければr.Create()で作成するようにしています。このためapplyconfigurationsは使っていません。

### Ingressオブジェクトのapplyconfigurations化

バックエンドのTLS化をする中でIngressオブジェクトについてもreconcileの対象となったので、設定に応じて内容を変更できるように"k8s.io/client-go/applyconfigurations/networking/v1"パッケージを使うように変更しました。

中心部分は概ね次のような内容になっています。

```golang:applyconfigurationsパッケージに以降したIngressのreconcile処理
...

        ingress := networkv1apply.Ingress(targetName, ingressNamespace).
                WithLabels(map[string]string{
                        "app.kubernetes.io/name":       targetName,
                        "app.kubernetes.io/instance":   targetName,
                        "app.kubernetes.io/created-by": fieldManager,
                        "group":                        "ingress-nginx",
                }).
                WithSpec(networkv1apply.IngressSpec().
                        WithRules(networkv1apply.IngressRule().
                                WithHost(serviceHostName).
                                WithHTTP(networkv1apply.HTTPIngressRuleValue().
                                        WithPaths(networkv1apply.HTTPIngressPath().
                                                WithBackend(networkv1apply.IngressBackend().
                                                        WithService(networkv1apply.IngressServiceBackend().
                                                                WithName(targetName + "-svc").
                                                                WithPort(networkv1apply.ServiceBackendPort().
                                                                        WithNumber(80)))).
                                                WithPath("/" + targetName).
                                                WithPathType(networkv1.PathTypePrefix)))))

        obj, err := runtime.DefaultUnstructuredConverter.ToUnstructured(ingress)
        if err != nil {
                return err
        }
        patch := &unstructured.Unstructured{
                Object: obj,
        }
        // try to find current networkpolicy object
        var current networkv1.Ingress
        err = r.Get(ctx, client.ObjectKey{Name: targetName, Namespace: ingressNamespace}, &current)
        if err != nil && !errors.IsNotFound(err) {
...
```

こう書き換えると``networkv1.PathTypePrefix``がPathTypeとしてそのまま素直に使えてすっきりしました。

### OwnerReferencesを間違って付与した場合の挙動

現在は修正していますが、このPatchを使ったIngressのServer-Side Applyのコードを追加したタイミングで間違って``WithOwnerReferences(owner)``を追加していました。

不適切なOwnerFerencesを加えたコードをPatchで適用すると、成功(err==nil)するもののIngressオブジェクトは作成されませんでした。

コード全体をレビューするまで原因の確認ができなかったので少しやっかいな挙動だと思います。おそらくapi-serverのログまで追えばもう少し情報があったかもしれません。

## ClusterRoleBindingについて

ClusterRoleBindingはreconcile処理をしていますが、頻繁に発生するであろう**roleRef**の変更はできません。

ほぼ必ず削除する必要がありますが、まずreconcile処理によってPatch()を呼び出す変更処理を試みてからエラーが発生すれば削除して一旦``return err``を返す処理にして、再度reconcile処理が呼び出されれば成功するという流れになっています。

## Finalizerについて

ドキュメントを読んだ最初はよく理解できていなかったのですが、Finalizerのマークを付けるのは基本的に自分で定義したCustom Resourceのオブジェクトだけです。

Finalizerを付けておくことで作成したCustom Resourceオブジェクトを消そうとした段階でControllerに制御が移るので、手動で他のnamespaceに作成したIngressのようなオブジェクトや、Cluster-wideなClusterRoleBindingなどを削除します。

OwnerReferenceは分かりやすい仕組みなので、必要なannotationsをどうやって付与するのかに注目すればドキュメントの理解が進みそうです。namespaceを消すタイミングでnamespace-scopeのオブジェクトは消えていくのですが一応はOwnerReferenceを設定しています。

開発の過程で消せないTerminatingなオブジェクトをいくつも作成しましたが、手動でfinalier:を空にしたり、親のCRDs定義そのものが悪さをしていたり一通りの経験はできたかなと思います。

結果としては他のOperatorを使っている時に感じた疑問は解消しました。

# さいごに

Cunstom Controllerは簡単に作成できるので便利ですが、きちんと動作させるにはKubernetesのapi-serverの動作について概要程度の知識はあった方が良いでしょう。

Custom Controllerを作成したのは、Kubernetesに対する知識が深まる良い機会でした。

開発作業のメインはEmacsでしたが、language-serverを設定していないので、pkgの内容に従ってメソッドやTypeの候補を表示したい場合にはGolandを使いました。

EmacsとGitHub Copilotの組み合わせはとても便利ですが、そのまま提案されたコードを使うという感じではありません。しかしGitHub Copilotはいろいろと考えさせてくれるという点ではこれからも使いたいと感じさせてくれる動きをしてくれました。

JetBrainsのAI Assistantもそれなりに便利でRefactoring機能など既存のコードに対してはちゃんと動作するなという印象です。ただ何もないところから始まるコーディングのサポート機能は情報が少ないのか、今後学習して強化されるのかもしれませんが、現時点ではGitHub Copilotほどの能力はないように感じました。

総じてAIによる開発支援は、開発者の技量によって良い結果にも反対の結果にもつながっていくと思います。

手放しでAIが便利だという人はおそらくAIからの提案を取捨選択するだけの技量も伴っているのではないでしょうか。そのレベルまで到達できる技術者がさらに能力を引き出すために使っていくように感じます。

Kubernetesがある程度使えるようになったらCustom Conrollerの作成に挑戦することをお勧めします。

# 後日談

いざ使ってみるといろいろ発見があったので、まとめておきます。

## Ingressへの接続が頻繁に切れてしまう

Ingressはnginxで実装されていますが、nginxの設定ファイルではproxy_passに指定した接続先が存在することを期待しています。

これが接続できていないとフォールバックが発生することになり、この時の動作により接続が頻繁に切断されてしまいます。

nginxが設定ファイルを触る間はLoadBalancerからのアクセスはなくなるはずですが、次のような状況では問題が発生します。

1. Ingressオブジェクトを作成し、``https://<proxy-server/<namespace>/`` のようなリクエストを ``<namespace>-svc.ingress-nginx.svc.cluster.local`` に転送するよう定義する
1. ``service/<namespace>-svc`` オブジェクトを作成し、type: ExternalName で``<namespace>-svc.<namespace>.svc.cluster.local`` を指定する
1. この時点では、``<namespace>-svc.<namespace>.svc.cluster.local`` は作成されていない

この状態で他のIngressオブジェクトを変更したりすると、他のサービスへのアクセスが中断されるといった問題が発生します。

### 回避策

Operatorはユーザー情報が登録されると自動的にIngressオブジェクトとExternalNameを設定するServiceオブジェクトをingress-nginxネームスペースに作成します。

この段階ではユーザーのnamespace上にはServiceオブジェクトを含めて何ら設定がされていないため、ingressのnginx側では名前解決ができないことでproxy_passがエラーとなります。

これを回避する方法は、いまのところ次の2つがあると考えています。

1. ユーザーのnamespaceに対応するServiceオブジェクトが作成されるまで、Ingressオブジェクトの作成をPendingにする
1. ユーザーのnamespace上に対応するServiceオブジェクトをOperatorが作成し、Ingressオブジェクトの作成も行う

それぞれPros. & Cons.がありますが、Ingressオブジェクトの作成をPendingにするとReconcileプロセスが長期間終わらずAPIサーバーの負荷が高くなります。

次にユーザーのnamespaceにServiceオブジェクトを作成するといっても管理下に置くことは現状ではできないため、ユーザーは自由に削除ができます。このデメリットは実は両方の案に共通する課題なので、こちらの考え方の方が良いように思えます。

Operatorがユーザー領域のServiceオブジェクトまで管理してしまえば問題は解決するのですが、管理領域がシステムとユーザーで重複するのは良い方法ではありません。管理領域の線引きはシンプルにしておかないと別の問題を招く可能性が高くなります。

まずはAPIサーバーの負荷がどれくらいになるか興味があるので、より簡単に実装ができるユーザーがnamespaceを定義するまでPendingにする方法を採用したOperatorを作成してみます。

まずユーザーのServiceオブジェクトの存在を確認するcheckService関数を追加します。

```golang:checkService()
func (r *MembersReconciler) checkService(ctx context.Context, kubecampview kubecampv1.Members, kubecampitem kubecampv1.MembersItem) (bool, error) {
        memberNamespace := kubecampitem.Member
        serviceName := memberNamespace + "-svc"
        var current corev1.Service
        err := r.Get(ctx, client.ObjectKey{Namespace: memberNamespace, Name: serviceName}, &current)
        if err != nil {
                if errors.IsNotFound(err) {
                        // Expected, not yet created the external-ip service endpoint
                        return false, nil
                }
                return false, err
        }
        return true, nil
}
```

これを使ってServiceオブジェクトが存在した場合だけIngressオブジェクトを作成し、そうでなければ新しいエラーを返し続けます。

```golang:
if ok, err := r.checkService(ctx, kubecampview, member); ok {
	err := r.reconcileService(ctx, kubecampview, member) // create service on ingress-nginx namespace
	if err != nil {
		return ctrl.Result{}, err
	}
	err = r.reconcileIngress(ctx, kubecampview, member)
	if err != nil {
		return ctrl.Result{}, err
	}
} else if err != nil { // check the err state returned from checkService()
	return ctrl.Result{}, err
} else { // returned (false,nil) from checkService()
  return ctrl.Result{}, errors.NewNotFound(corev1.Resource("service"), member.Member+"-svc")
}
```

これを適用してみると、案外ちゃんと動いてくれていてメモリやCPU負荷がどんどん上がっていくということはありません。

もう少し状況を観察して、最終的にはcheckService()ではなく、reconcileUserService()を作成してネストしたif文は削除する予定です。

## Controller-Runtime等のCustom Operatorコードのメンテナンス

Operatorを格納しているHarborのScannerがいくつものCVEを報告してくるのが気になるようになりました。

Dockerfileでgolangのバージョンを1.21から1.24に変更するのは出来そうですが、他にもgoパッケージの更新が必要です。

何も考えずにgo.modを変更するとはまりそうだったので、作成したOperatorのコードをどうやってメンテナンスするのかメモをまとめておきます。

### Dockerfileの更新

Dockerfile上にgolangのバージョンが指定されているので、任意の最新版に変更します。

ここでは ``1.24`` にしています。

```diff:
diff --git a/Dockerfile b/Dockerfile
index e3b15d0..845fafc 100644
--- a/Dockerfile
+++ b/Dockerfile
@@ -1,5 +1,5 @@
 # Build the manager binary
-FROM docker.io/golang:1.21 AS builder
+FROM docker.io/golang:1.24 AS builder
 ARG TARGETOS
 ARG TARGETARCH

```

### controller-runtimeの更新

Operatorのコードの元になるバージョンを最新に変更します。

```bash:go.mod等があるディレクトリで最新のcontroller-runtimeを導入する
$ go get sigs.k8s.io/controller-runtime@v0.22.0
```

## その他のツール類の更新

Makefile上にツールのバージョンがまとめられているので、最新に変更します。

```diff:
diff --git a/Makefile b/Makefile
index 4b03413..4cb867c 100644
--- a/Makefile
+++ b/Makefile
@@ -163,10 +163,10 @@ ENVTEST ?= $(LOCALBIN)/setup-envtest-$(ENVTEST_VERSION)
 GOLANGCI_LINT = $(LOCALBIN)/golangci-lint-$(GOLANGCI_LINT_VERSION)

 ## Tool Versions
-KUSTOMIZE_VERSION ?= v5.3.0
-CONTROLLER_TOOLS_VERSION ?= v0.14.0
+KUSTOMIZE_VERSION ?= v5.7.1
+CONTROLLER_TOOLS_VERSION ?= v0.19.0
 ENVTEST_VERSION ?= latest
-GOLANGCI_LINT_VERSION ?= v1.54.2
+GOLANGCI_LINT_VERSION ?= v2.4.0

 .PHONY: kustomize
 kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
```

この状態で ``make build`` などを実行すると、go.modやgo.sumなども適切に更新されました。

## Webhookの変更

controller-tools/runtimeのバージョンが上がったため、``webhook.Defaulter``から``webhook.CustomDefaulter``を利用するように変更する必要がありました。

公式ガイドの通りに進めれば問題ありませんが、ポイントは次のとおりです。

https://book.kubebuilder.io/cronjob-tutorial/webhook-implementation

1. ガイドにあるようにパッケージの参照、関数名などの変更を行う
2. ``var _ webhook.Defaulter = ..``の部分を``var _ webhook.CustomDefaulter``に変更
3. webhook.Defaulterに代入していたオブジェクトについて、インタフェースの変更などはないので、そのままでOK
4. ただし、webhook.CustomDefaulterに代入しているオブジェクトは、SetupWebhookWithManager(..)の中で明示的にWithDefaulter()、WithValidator()を利用して明示的に登録する
5. webhook.CustomDefaulterに代入しているオブジェクトを取り出す際には、``obj.(..)``のようにobjから取り出す

公式ガイドではCronJobのコントロールについて書かれていて、CronJobCustomDefaulterを定義していますが、必ずしもstructを作る必要はありませんでした。

ただ明示的にSetupWebhookWithManager()の中でオブジェクトを登録していなかったので、コンパイルエラーにはならないものの、正常に動作しないランタイムをビルドしてしまいました。

それほど複雑な変更が必要なわけではないですが、久し振りにメンテナンスするには少しハードルの高い変更でした。

以上
