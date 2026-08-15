---
title: RabbitMQ Operatorをv2.21.1に更新してみた (khepri対応)
tags:
  - RabbitMQ
  - kubernetes
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
posting_campaign_uuid: null
agreed_posting_campaign_term: false
---
# はじめに

現在はRabbitMQ Operator v2.20.1を適用して、RabbitMQ v4.1.3を利用しています。

この状態からOperatorを``v2.20.1`` → ``v2.21.1`` → ``v2.22.4``と変更していく予定です。

Operatorの``v2.21.0``からRabbitMQは``v4.2.6``に更新されているため、``v2.21.1``を適用した段階で、内部DBが``khepri``へと移行します。

たぶん大丈夫だと思うのですが、この部分が一番神経を使うところかなと思われます。

なお``v2.22.4``からRabbitMQのバージョンが``v4.3.4``に更新されています。

:::note
結果的に、v2.22.4を適用した時にcert-managerがなかったためにエラーになった対応が、一番影響の大きい変更だったと思います。
またv2.22.4からはRabbitMQのバージョンが4.3.4になるので、pauseReconciliationを設定した方が良いかもしれません。
:::

# 環境

作業開始時の各バージョンは次のとおりです。

* Kubernetes v1.34.3 (Kubespray v2.30.0)
* RabbitMQ Operator v2.20.1

# 手順

基本的な操作手順は過去の記事に掲載しています。

https://qiita.com/YasuhiroABE/items/7c1e82e006ea37e0fe25

cluster-operator.ymlファイルはGitHubのReleasesページにリンクが掲載されています。

https://github.com/rabbitmq/cluster-operator/releases

具体的なコマンドラインは次のようになります。

```bash:v2.21.1更新時の手順
## RabbitMQClustersのインスタンス名を確認
$ sudo kubectl -n rabbitmq-system get rabbitmqclusters

## v2.21.1のOperator YAMLファイルを適用
$ sudo kubectl -n rabbitmq-system apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.21.1/cluster-operator.yml

## rabbitmq-cluster-operator Podの再起動が始まるので、Operatorのログを確認し、"Finished reconciling"のメッセージを確認する
$ sudo kubectl -n rabbitmq-system logs -l app.kubernetes.io/component=rabbitmq-operator

## 無事に導入が終ったらRabbitMQClustersのインスタンス(e.g. "rabbitmq" or definition)から.spec.imageを削除する
$ sudo kubectl -n rabbitmq-system edit rabbitmqclusters rabbitmq

## "image: rabbitmq:4.1.3-management" 行を削除し、編集結果を保存してからEditorを終了する

## rabbitmq:4.2.6-managementにimage:が変更されていることを確認すう
$ sudo kubectl -n rabbitmq-system get rabbitmqclusters rabbitmq -o yaml |grep image:

## 全てのPodが再起動するまで待機する
$ sudo kubectl -n rabbitmq-system get pod -w
```

全てのPodが更新されたら、feature_flagsを全て有効にします。

```bash:
## 現状の確認 ("khepri_db disabled" の確認)
$ sudo kubectl -n rabbitmq-system exec -it rabbitmq-server-0  -- rabbitmqctl list_feature_flags

## 有効化
$ sudo kubectl -n rabbitmq-system exec -it rabbitmq-server-0  -- rabbitmqctl enable_feature_flag all
```

最初に``list_feature_flags``を実行した時の出力は次のようになっています。

```text:RabbitMQ-v4.2.6に更新した直後のfeature_flagsの状況
Listing feature flags ...
name    state
classic_mirrored_queue_version  enabled
classic_queue_type_delivery_support     enabled
detailed_queues_endpoint        enabled
direct_exchange_routing_v2      enabled
drop_unroutable_metric  enabled
empty_basic_get_metric  enabled
feature_flags_v2        enabled
implicit_default_bindings       enabled
khepri_db       disabled
listener_records_in_ets enabled
maintenance_mode_status enabled
message_containers      enabled
message_containers_deaths_v2    enabled
quorum_queue    enabled
quorum_queue_non_voters enabled
rabbit_exchange_type_local_random       enabled
rabbitmq_4.0.0  enabled
rabbitmq_4.1.0  enabled
rabbitmq_4.2.0  disabled
restart_streams enabled
stream_filtering        enabled
stream_queue    enabled
stream_sac_coordinator_unblock_group    enabled
stream_single_active_consumer   enabled
stream_update_config_command    enabled
tracking_records_in_ets enabled
user_limits     enabled
virtual_host_metadata   enabled
```

有効化した時の``rabbitmq-server-0``のログは次のようになっていました。

```text:文字列"khepri"を含むログ出力の抜粋
2026-08-15 10:40:08.302039+00:00 [notice] <0.334.0> Feature flags: attempt to enable `khepri_db`...
2026-08-15 10:40:08.322158+00:00 [info] <0.1591.0> Feature flag `khepri_db`: syncing cluster membership
2026-08-15 10:40:08.322315+00:00 [info] <19660.2145.0> Feature flag `khepri_db`: syncing cluster membership
2026-08-15 10:40:08.323147+00:00 [info] <19661.2771.0> Feature flag `khepri_db`: syncing cluster membership
2026-08-15 10:40:10.077266+00:00 [info] <19660.2145.0> Feature flag `khepri_db`: cluster membership synchronized; members are: ['rabbit@rabbitmq-server-0.rabbitmq-nodes.rabbitmq-system',
2026-08-15 10:40:10.078630+00:00 [info] <19660.2145.0> Feature flag `khepri_db`: unregistering legacy projections
2026-08-15 10:40:10.083319+00:00 [info] <0.1591.0> Feature flag `khepri_db`: cluster membership synchronized; members are: ['rabbit@rabbitmq-server-0.rabbitmq-nodes.rabbitmq-system',
2026-08-15 10:40:10.083680+00:00 [info] <0.1591.0> Feature flag `khepri_db`: unregistering legacy projections
2026-08-15 10:40:10.195500+00:00 [info] <19660.2145.0> Feature flag `khepri_db`: registering projections
2026-08-15 10:40:10.382416+00:00 [info] <0.1591.0> Feature flag `khepri_db`: registering projections
2026-08-15 10:40:12.572074+00:00 [info] <19661.2771.0> Feature flag `khepri_db`: cluster membership synchronized; members are: ['rabbit@rabbitmq-server-0.rabbitmq-nodes.rabbitmq-system',
2026-08-15 10:40:12.572697+00:00 [info] <19661.2771.0> Feature flag `khepri_db`: unregistering legacy projections
2026-08-15 10:40:12.941769+00:00 [info] <19661.2771.0> Feature flag `khepri_db`: registering projections
2026-08-15 10:40:16.281068+00:00 [notice] <19660.2145.0> Feature flags: `khepri_db`: starting migration of 20 tables from Mnesia to Khepri; expect decrease in performance and increase in memory footprint
2026-08-15 10:40:17.222084+00:00 [notice] <0.1591.0> Feature flags: `khepri_db`: starting migration of 20 tables from Mnesia to Khepri; expect decrease in performance and increase in memory footprint
2026-08-15 10:40:19.600334+00:00 [notice] <19661.2771.0> Feature flags: `khepri_db`: starting migration of 20 tables from Mnesia to Khepri; expect decrease in performance and increase in memory footprint
2026-08-15 10:40:22.269222+00:00 [notice] <19660.2145.0> Feature flags: `khepri_db`: migration from Mnesia to Khepri finished
2026-08-15 10:40:22.977631+00:00 [notice] <19661.2771.0> Feature flags: `khepri_db`: migration from Mnesia to Khepri finished
2026-08-15 10:40:23.020074+00:00 [notice] <0.1591.0> Feature flags: `khepri_db`: migration from Mnesia to Khepri finished
2026-08-15 10:40:36.657358+00:00 [notice] <0.334.0> Feature flags: `khepri_db` enabled
```

ログの行間にはMnesiaからの移行状況が細かく出力されています。

結果的には何も問題なくスムーズにkhepri_dbへの移行が完了しました。

# v2.22.4を適用した時のエラー対応

影響が一番大きかったのが、``cert-manager``を要求してきたことです。

v2.21.1と同様にv2.22.4を適用したところ次のようなエラーが出力されました。

```text:
$ sudo kubectl -n rabbitmq-system apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.22.4/cluster-operator.yml
namespace/rabbitmq-system unchanged
customresourcedefinition.apiextensions.k8s.io/rabbitmqclusters.rabbitmq.com unchanged
serviceaccount/rabbitmq-cluster-operator unchanged
role.rbac.authorization.k8s.io/rabbitmq-cluster-leader-election-role unchanged
clusterrole.rbac.authorization.k8s.io/rabbitmq-cluster-operator-role unchanged
clusterrole.rbac.authorization.k8s.io/rabbitmq-cluster-service-binding-role unchanged
rolebinding.rbac.authorization.k8s.io/rabbitmq-cluster-leader-election-rolebinding unchanged
clusterrolebinding.rbac.authorization.k8s.io/rabbitmq-cluster-operator-rolebinding unchanged
service/cluster-operator-webhook-service created
service/rabbitmq-cluster-operator-metrics-service configured
deployment.apps/rabbitmq-cluster-operator configured
mutatingwebhookconfiguration.admissionregistration.k8s.io/cluster-operator-mutating-webhook-configuration created
validatingwebhookconfiguration.admissionregistration.k8s.io/cluster-operator-validating-webhook-configuration created
Error from server (InternalError): error when creating "https://github.com/rabbitmq/cluster-operator/releases/download/v2.22.4/cluster-operator.yml": Internal error occurred: failed calling webhook "webhook.cert-manager.io": failed to call webhook: Post "https://cert-manager-webhook.cert-manager.svc:443/mutate?timeout=10s": service "cert-manager-webhook" not found
Error from server (InternalError): error when creating "https://github.com/rabbitmq/cluster-operator/releases/download/v2.22.4/cluster-operator.yml": Internal error occurred: failed calling webhook "webhook.cert-manager.io": failed to call webhook: Post "https://cert-manager-webhook.cert-manager.svc:443/mutate?timeout=10s": service "cert-manager-webhook" not found
Error from server (InternalError): error when creating "https://github.com/rabbitmq/cluster-operator/releases/download/v2.22.4/cluster-operator.yml": Internal error occurred: failed calling webhook "webhook.cert-manager.io": failed to call webhook: Post "https://cert-manager-webhook.cert-manager.svc:443/mutate?timeout=10s": service "cert-manager-webhook" not found
```

``cert-manager``が存在しないためなのはすぐに分かるのですが、Operatorの再起動はすぐに始まっていていますが、止まっています。

```bash:
$ sudo kubectl -n rabbitmq-system get pod
NAME                                         READY   STATUS              RESTARTS   AGE
rabbitmq-cluster-operator-78d765df49-xh7rg   0/1     ContainerCreating   0          2m36s
rabbitmq-cluster-operator-7b77d64fdf-jlslr   1/1     Running             0          83m
rabbitmq-server-0                            1/1     Running             0          12m
rabbitmq-server-1                            1/1     Running             0          13m
rabbitmq-server-2                            1/1     Running             0          15m
```

Operatorの再起動の手前で停止しているので、サービスへのインパクトは発生していません。

停止したPodの状況をdescribeで確認すると、cert-manager関連の処理が進んでいないことが分かります。

```text:describeでoperatorの状況を確認
Events:
  Type     Reason       Age                   From               Message
  ----     ------       ----                  ----               -------
  Normal   Scheduled    4m24s                 default-scheduler  Successfully assigned rabbitmq-system/rabbitmq-cluster-operator-78d765df49-xh7rg to u139tx02
  Warning  FailedMount  14s (x10 over 4m23s)  kubelet            MountVolume.SetUp failed for volume "cluster-operator-webhook-certs" : secret "cluster-operator-webhook-server-cert" not found
```

急遽kubesprayからaddons.ymlファイルを``cert_manager_enabled: true``の部分だけ変更してplaybookを動かし、``cert-manager``を導入します。

```bash:kubespray-v2.30.0から追加でcert-managerをdeploy
## ansible環境の準備
$ rm -rf venv
$ /usr/bin/python3 -m venv venv/k8s
$ . venv/k8s/bin/activate
(k8s) $ pip install -r requirements.txt

## cert-managerの有効化
(k8s) $ vi inventory/mycluster/group_vars/k8s_cluster/addons.yml
(k8s) $ git status
(k8s) $ git add inventory/mycluster/group_vars/k8s_cluster/addons.yml
(k8s) $ git commit -m 'Enable the cert-manager in addons.yml.'

## ansible環境の確認
(k8s) $ ansible kube_node -i inventory/mycluster/inventory.ini -m command -a 'uname -n'

## tagsを指定してcluster.ymlの実行
$ ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini -e kube_version=1.34.3 --tags=apps
```

最終的にRabbitMQ Operator v2.22.4のcluster-operator.ymlを再度適用して、CRDsを更新します。

次に止まっているPodを起動しているreplicasetオブジェクトを削除してPodを作り直すことで無事にOperatorが再起動しました。

なおOperatorが再起動したタイミングで、RabbitMQ Clusterが自動的に再起動されています。

RabbitMQ自体のバージョンはdefaultが4.3.4に更新されているので、Clusterの再起動が終わってから再度editコマンドで、image:行を削除してクラスターを再起動して、バージョンを最新にしました。

クラスターの停止時間を最小限にしたい場合など、複数回の再起動がいやな場合には、``rabbitmq.com/pauseReconciliation=true``ラベルを適切に設定してください。

https://www.rabbitmq.com/kubernetes/operator/using-operator#pause

## v2.22.4でもenable_feature_flags allが必要

なおfeature_flagsをすべて有効にする必要があります。

```text:v2.22.4を適用後にdisabledになっているfeature_flags
Listing feature flags ...
name    state
rabbitmq_4.3.0  disabled
tie_binding_to_dest_with_keep_while_cond        disabled
topic_binding_projection_v4     disabled
topic_binding_projection_v5     disabled
track_qq_members_uids   disabled
```

v2.21.1と同様に全てのfeature_flagsを有効(enabled)にします。

# さいごに

ReleaseNoteにはcert-managerが必須という記述はなかったので油断していました。

追加自体は難しい作業ではないので、すぐに対応することができました。

この手順で本番環境のRabbitMQもバージョンを上げていく予定です。



