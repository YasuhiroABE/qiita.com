---
title: RabbitMQをkube-prometheusでモニター & 監視した作業ログ
tags:
  - RabbitMQ
  - grafana
  - kubernetes
  - Jsonnet
  - kube-prometheus
private: false
updated_at: '2026-05-10T19:02:19+09:00'
id: b94b7d48f3425e02300a
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

kube-prometheusをjsonnetを使って構成した経緯は過去の記事に残しています。

https://qiita.com/YasuhiroABE/items/dca43cff82d7991658fa

今回はこれで構成している環境にRabbitMQの監視を加えたいので、その顛末を残しておくことにしました。

# 環境

* Kubernetes v1.34.3 (Kubespray v2.30.0)
* kube-prometheus v0.17.0
* RabbitMQ v4.1.3 (RabbitMQ Operator v2.20.1)

次のページをGrafanaに追加します。

https://grafana.com/grafana/dashboards/10991-rabbitmq-overview/

# 変更作業

過去の記事でRook/CephのダッシュボードをGrafanaに追加する方法は記載しているので、それを参考に今回はRabbitMQをkube-prometheusに加えていきます

## 準備作業

あらかじめ``kube-prometheus``ディレクトリで、v0.17.0のtagからcheckoutしたディレクトリで作業を行います。

```bash:準備作業
$ cd kube-prometheus
$ git checkout main
$ git pull
$ git checkout refs/tags/v0.17.0 -b my_v0.17.0
```

過去記事のように``examples/kustomize.jsonnet``ファイルを適切に変更して、デプロイ済みの時点から作業を始めていきます。

## ダッシュボードJSONをConfigMapに追加する

Grafana LabsのダッシュボードのページからJSONファイル(``10991_rev15.json``)をダウンロードしておきます。

```bash:wgetコマンドでのダウンロード
$ wget -O10991_rev15.json https://grafana.com/api/dashboards/10991/revisions/15/download
```

kubectlコマンドを利用してConfigMapに追加します。

```bash:
$ sudo kubectl -n monitoring create configmap grafana-dashboard-rabbitmq-overview --from-file=10991_rev15.json
```

jsonファイルの最新は後述するGitHubの``observability/``ディレクトリにあります。

## examples/kustomize.jsonnetファイルを編集する

既にRook/Ceph用の追加設定を実施しているので、並列にRabbitMQ用の設定を追加していきます。

```diff:examples/kustomize.jsonnetの差分
diff --git a/examples/kustomize.jsonnet b/examples/kustomize.jsonnet
index bee356f3..82ffe15d 100644
--- a/examples/kustomize.jsonnet
+++ b/examples/kustomize.jsonnet
@@ -122,6 +122,11 @@ local kp =
                           name: "grafana-dashboard-ceph-pools",
                           readOnly: false,
                         },
+                        {
+                          mountPath: "/grafana-dashboard-definitions/0/rabbitmq-overview",
+                          name: "grafana-dashboard-rabbitmq-overview",
+                          readOnly: false,
+                        },
                       ],
                     }
                   else
@@ -147,6 +152,12 @@ local kp =
                   },
                   name: "grafana-dashboard-ceph-pools",
                 },
+                {
+                  configMap: {
+                    name: "grafana-dashboard-rabbitmq-overview",
+                  },
+                  name: "grafana-dashboard-rabbitmq-overview",
+                },
               ],
             },
           },
```

## manifestsの生成

```bash:
$ make generate
```

編集・生成されたファイルは次のとおりです。

```bash:git-statusの出力
$ git status
On branch t_v0.17.0
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   examples/kustomize.jsonnet
        modified:   manifests/grafana-deployment.yaml

no changes added to commit (use "git add" and/or "git commit -a")
```

``manifests/grafana-deployment.yaml``の差分は次のとおりです。

```diff:
diff --git a/manifests/grafana-deployment.yaml b/manifests/grafana-deployment.yaml
index 1f5a5eaf..0ba0551f 100644
--- a/manifests/grafana-deployment.yaml
+++ b/manifests/grafana-deployment.yaml
@@ -175,6 +175,9 @@ spec:
         - mountPath: /grafana-dashboard-definitions/0/ceph-pool
           name: grafana-dashboard-ceph-pools
           readOnly: false
+        - mountPath: /grafana-dashboard-definitions/0/rabbitmq-overview
+          name: grafana-dashboard-rabbitmq-overview
+          readOnly: false
       nodeSelector:
         kubernetes.io/os: linux
       securityContext:
@@ -303,3 +306,6 @@ spec:
       - configMap:
           name: grafana-dashboard-ceph-pools
         name: grafana-dashboard-ceph-pools
+      - configMap:
+          name: grafana-dashboard-rabbitmq-overview
+        name: grafana-dashboard-rabbitmq-overview
```

## YAMLファイルの反映

ConfigMapの名前などに間違いがないようであれば、個別にファイルを指定するか次のようにディレクトリ全体を指定して設定を反映します。

```bash:
$ sudo kubectl apply -f manifests/
```

## PrometheusへのServiceMonitorの追加

Grafanaの設定が完了したらPrometheusに**external-ip:15692/metrics**からデータを収集するように設定を追加します。

必要なファイルはGitHubのRabbitMQ Operatorのコードの中に含まれていますが、Operatorは自動的には反映しないので、手動で必要なファイルを追加します。

https://github.com/rabbitmq/cluster-operator/tree/main/observability/prometheus

まずServiceMonitorを追加します。

```bash:v2.20.1のtagに含まれているrabbitmq-servicemonitor.ymlを適用する
$ sudo kubectl -n rabbitmq-system apply -f https://raw.githubusercontent.com/rabbitmq/cluster-operator/refs/tags/v2.20.1/observability/prometheus/monitors/rabbitmq-servicemonitor.yml
$ sudo kubectl -n rabbitmq-system apply -f https://raw.githubusercontent.com/rabbitmq/cluster-operator/refs/tags/v2.20.1/observability/prometheus/monitors/rabbitmq-cluster-operator-podmonitor.yml
```

この状態ではまだGrafanaのダッシュボードには値は表示されていません。

## Prometheusからのアクセスを許可するRBAC設定の追加

Grafanaダッシュボードに数値を表示させるためPrometheusにデータ収集の指示をServiceMonitorを追加することで行いましたが、権限が不足している旨のエラーメッセージが``pod/prometheus-k8s-0``に記録されています。

ちなみにエラーログは次のようなメッセージでした。

```text:pod/prometheus-k8s-0に記録されていたメッセージ
time=2026-05-10T07:48:04.677Z level=ERROR source=reflector.go:204 msg="Failed to watch" component=k8s_client_runtime logger=UnhandledError err="failed to list *v1.Service: services is forbidden: User \"system:serviceaccount:monitoring:prometheus-k8s\" cannot list resource \"services\" in API group \"\" at the cluster scope" reflector=pkg/mod/k8s.io/client-go@v0.35.0/tools/cache/reflector.go:289 type=*v1.Service
```

このエラーメッセージをClaudeに伝えて、次のClusterRoleを設定しました。

```yaml
# prometheus-k8s-cluster-discovery.yaml # Generated by Claude Opus 4.7
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-k8s-cluster-discovery
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "pods", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["discovery.k8s.io"]
  resources: ["endpointslices"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-k8s-cluster-discovery
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-k8s-cluster-discovery
subjects:
- kind: ServiceAccount
  name: prometheus-k8s
  namespace: monitoring
```

これで必要な値が/metricsからPrometheusに蓄えられ、ダッシュボードに数値が表示されました。

## PrometheusへのAlertRuleの登録

このままではGrafanaにメトリックス・データは表示されますが、監視はされていません。

同様にPrometheusRuleのYAMLファイルがOperatorのGitHubに登録されているので、これを追加します。

```bash:
$ sudo kubectl -n rabbitmq-system apply -f https://raw.githubusercontent.com/rabbitmq/cluster-operator/refs/tags/v2.20.1/observability/prometheus/rules/rabbitmq-cluster-operator/unavailable-replicas.yml

$ sudo kubectl -n rabbitmq-system apply -f https://raw.githubusercontent.com/rabbitmq/cluster-operator/refs/heads/main/observability/prometheus/rules/rabbitmq/unroutable-messages.yml

$ sudo kubectl -n rabbitmq-system apply -f https://raw.githubusercontent.com/rabbitmq/cluster-operator/refs/heads/main/observability/prometheus/rules/rabbitmq/cluster-alarms.yml
```

必要に応じて該当のYAMLファイルを順次適用していきます。

# まとめ

新しいダッシュボードを追加するための手順としては、およその流れは他の対象でも同じになると思います。

昔のRabbitMQの実装では運用上の問題にいろいろ遭遇しましたが、現在ではこういった監視は不要とはいいませんが、必要性はかなり減ったと思えます。


