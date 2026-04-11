---
title: 久し振りにRook/CephにObjectStoreを構成してみた
tags:
  - Ceph
  - kubernetes
  - ObjectStorage
  - Rook
private: false
updated_at: '2025-12-18T11:20:51+09:00'
id: 55897bd0822984c35e05
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

かなり前、Rook.ioにはMinioが付属していてS3互換のAPIを利用することができました。

v0.xの時代にもObjectStorage機能は提供されていたように思いますが、RookのObject Storage機能はバージョンが変更される毎に修正されたり、廃止されたり、いろいろあった部分です。

短い間でしたがCassandraを構成することも出来ましたね。

現在のRookはCephのみに注力するようになってきて、RGWは今後もサポートされそうです。

Minioの雲行きが少し怪しいので移行先として検証しておこうと思い、既存のRook/CephにObject Storage機能を追加してみることにしました。

# 環境 & 構成

* Kubernetes - v1.32.8
* Rook - v1.8.8 (Ceph v19.2.3)

Rook/Cephは稼動していて、StorageClassには **rook-ceph-block** と **rook-cephfs** は設定済みの状態です。

```:text
NAME                        PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
rook-ceph-block (default)   rook-ceph.rbd.csi.ceph.com      Delete          Immediate           true                   4y102d
rook-cephfs                 rook-ceph.cephfs.csi.ceph.com   Delete          Immediate           true                   4y102d
```

# 参考文献

ObjectStoreの構成はいくつかのバリエーションがありますが、今回は **Create Local Object Store(s) with Shared Pools** を設定していきます。

https://rook.io/docs/rook/v1.18/Storage-Configuration/Object-Storage-RGW/object-storage/#create-local-object-stores-with-shared-pools

この手順に従って作業を進めていきます。

# 変更作業

まず **CephBlockPool** オブジェクを作成します。

```bash:
$ cd rook/deploy/examples/
$ kubectl -n rook-ceph apply -f object-shared-pools.yaml

## 作成されたCephBlockPoolsの状況は次のコマンドで確認可能
$ kubectl -n rook-ceph get cephblockpools
## 短縮されたNAMEを使った等価なコマンドの例
$ kubectl -n rook-ceph get cephbp

NAME            PHASE   TYPE            FAILUREDOMAIN   AGE
replicapool     Ready   Replicated      host            4y102d
rgw-data-pool   Ready   Erasure Coded   osd             22m
rgw-meta-pool   Ready   Replicated      host            22m
rgw-root        Ready   Replicated      host
```

実際のデータを格納する入口になるCephObjectStoresを作成します。

object-a.yamlファイルを使用していますが、実際にはこのファイルを元にしてNameなどを変更することになると思います。

```bash:
# object-a.yamlファイルを編集
$ vi object-a.yaml

## object-a.yamlファイルの name: などを編集後、内容を反映させる
$ kubectl -n rook-ceph apply -f object-a.yaml

## 作成されたCephObjectStoresは次のコマンドで確認可能
$ kubectl -n rook-ceph get cephobjectstores
## 以下のコマンドも等価
$ kubectl -n rook-ceph get cephos

NAME      PHASE   ENDPOINT                                        SECUREENDPOINT   AGE
store-a   Ready   http://rook-ceph-rgw-store-a.rook-ceph.svc:80                    24m
```

最後に実行したgetコマンドの出力でENDPOINTのURLが確認できます。

実際にServicesオブジェクトが定義されていることも確認できます。

```bash:
$ kubectl -n rook-ceph get svc rook-ceph-rgw-store-a

NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
rook-ceph-rgw-store-a   ClusterIP   10.233.8.176   <none>        80/TCP    25m
```

とりあえず namespace: rook-ceph での作業は終りです。

## StorageClassを定義する

ユーザーがBucketを定義できるようにStorageClassを登録します。

**rook/deploy/examples/** ディレクトリの ``storageclass-bucket-delete.yaml`` ファイルについて、``parameters.objectStoreName``の値は、前に定義した **CephObjectStore** の名前に変更する必要があります。

ここでは``my-store``から、``store-a`` に変更しています。

```bash:
$ kubectn -n rook-ceph apply -f storageclass-bucket-delete.yaml
```

うまく定義されると次のようにSrorageClassに ``rook-ceph-delete-bucket`` が追加されます。

```bash:"kubectl get sc"の出力
NAME                        PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
rook-ceph-block (default)   rook-ceph.rbd.csi.ceph.com      Delete          Immediate           true                   4y103d
rook-ceph-delete-bucket     rook-ceph.ceph.rook.io/bucket   Delete          Immediate           false                  16s
rook-cephfs                 rook-ceph.cephfs.csi.ceph.com   Delete          Immediate           true                   4y103d
```

``storageclass-bucket-store-a.yaml`` を利用すると、**rook-ceph-bucket** StorageClass が定義されます。

名前が違うので、この点は実運用を考慮して変更した方が良いかもしれません。

::note
本番環境では``rook-ceph-bucket``を利用しています。
:::

## 各namespaceでBucketを作成して利用する

異なるnamespaceでBucketを作成するため、次のようなYAMLファイルを準備します。

```yaml:test-ceph-bucket.yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ceph-bucket
  namespace: yasu-abe
spec:
  generateBucketName: ceph-bkt
  storageClassName: rook-ceph-delete-bucket
```

作成されたObjectBucketClaimは次のように確認できます。

```bash:
$ kubectl -n yasu-abe get obc

NAME          AGE
ceph-bucket   4m58s
```

## access-key, secret-key を確認する

正しくObjectBucketClaimが作成されると自動的に同じNameでSecret, ConfigMapオブジェクトが作成されます。

```bash:
$ kubectn -n yasu-abe get cm ceph-bucket
NAME          DATA   AGE
ceph-bucket   5      6m19s

$ kubectn -n yasu-abe get secrets ceph-bucket
NAME          TYPE     DATA   AGE
ceph-bucket   Opaque   2      6m33s
```

設定された値にアクセスする方法は公式ガイドに記載がありますが、"PORT"など他の設定とぶつかりそうなので、変数名はAWS,ないしBUCKETをprefixとして持つように変更しています。

```bash:公式ガイドの例をもとに少し変更
## namespace名を変数nsに格納
$ ns=yasu-abe

$ export AWS_HOST=$(kubectl -n $ns get cm ceph-bucket -o jsonpath='{.data.BUCKET_HOST}')
$ export BUCKET_PORT=$(kubectl -n $ns get cm ceph-bucket -o jsonpath='{.data.BUCKET_PORT}')
$ export BUCKET_NAME=$(kubectl -n $ns get cm ceph-bucket -o jsonpath='{.data.BUCKET_NAME}')
$ export AWS_ACCESS_KEY_ID=$(kubectl -n $ns get secret ceph-bucket -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
$ export AWS_SECRET_ACCESS_KEY=$(kubectl -n $ns get secret ceph-bucket -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
```

設定された環境変数を次のようなコマンドで確認していきます。

```bash:設定された環境変数の確認
$ env |egrep 'AWS|BUCKET' | sort

AWS_ACCESS_KEY_ID=REWDFFPM6CK0JP7R5MWF
AWS_HOST=rook-ceph-rgw-store-a.rook-ceph.svc
AWS_SECRET_ACCESS_KEY=VzGQfLL5oyqEZ9te7OCUYIAJ6gIi43ezSZeMNx2C
BUCKET_NAME=ceph-bkt-b29d078b-3502-4715-87a8-329fa4df059b
BUCKET_PORT=80
```

エンドポイントのTLS化は後で考えることにして、とりあえずこのまま利用してみます。

:::note
実際には変数を格納するためのコマンドを``envrc.obs``などのファイルに格納しておいて、適宜``$ . ./envrc.obs``などで読み込んだり、表示させてPodに設定するべき値を確認しています。
:::

## toolbox-operator-image から s5cmd コマンドを利用する

個別のnamespaceではなく、システム管理者が確認するための仕組みとして``namespace/rook-ceph``にObjectStorageにアクセスできるPodを準備しておきます。

通常のRook/Cephで利用しているtoolboxコンテナにはs5cmdコマンドが配置されていないので、rook/deploy/examples/toolbox-operator-image.yaml を利用して、専用のtoolbox PODを稼動させます。

この作業は namespace: rook-ceph で行う点に注意が必要です。

```bash:s5cmdコマンドを含むtoolboxコンテナの稼動
$ kubectl apply -f toolbox-operator-image.yaml
```

Deployした ``rook-ceph-tools-operator-image`` に入ってから、公式ガイドに書かれているように s5cmd を実行します。

```bash:s5cmdによる動作確認
$ sudo kubectl -n rook-ceph exec -it "$(sudo kubectl -n rook-ceph get pod -l app=rook-ceph-tools-operator-image -o jsonpath='{.items[*].metadata.name}')" -- bash

## あらかじめ ~/.aws/credentials ファイルを作成する
# mkdir -p ~/.aws
# cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = REWDFFPM6CK0JP7R5MWF
aws_secret_access_key = VzGQfLL5oyqEZ9te7OCUYIAJ6gIi43ezSZeMNx2C
EOF

## 環境変数を設定
# export AWS_HOST=rook-ceph-rgw-store-a.rook-ceph.svc
# export BUCKET_NAME=ceph-bkt-b29d078b-3502-4715-87a8-329fa4df059b
# export BUCKET_PORT=80  ## 変数名はPORTからBUCKET_PORTに変更

## 公式ドキュメントに従ってs5cmdを実行
# echo "Hello, Rook" > /tmp/hogebar.txt
# s5cmd --endpoint-url http://$AWS_HOST:$BUCKET_PORT cp /tmp/rookObj s3://$BUCKET_NAME

# s5cmd --endpoint-url http://$AWS_HOST:$BUCKET_PORT cp s3://$BUCKET_NAME/rookObj /tmp/rookObj-download
# cat /tmp/rookObj-download
Hello, Rook
```

アプリケーションから設定を行う場合には環境変数にSecretオブジェクトの値を代入させるよう設定します。

ここまでで基本的な使い方については問題なさそうな事を確認できました。

## ユーザー(namespace)毎にQuotaを設定する

利用者に開放しているシステムで利用したいので、無制限にオブジェクトを登録されると困るので最大サイズを指定します。

CRDを眺めているといくつか方法はありそうで、``maxSize:``パラメータが定義されているのは、``CephObjectStore`` の ``.spec.dataPool.quotas`` に maxSize などのパラメータがあります。また ``CephObjectStoreUser`` の ``.spec.quotas`` の中に maxSize や maxBucket といった設定があります。

``CephObjectStore``ではプール全体のサイズが指定できるだけなので、この設定はストレージ領域の過剰な消費を防止するためにシステム全体では必要ですが、ユーザー毎という今回の目的には向きません。

また``CephObjectStoreUser`` の設定はk8sのRBACとは関係がないので、ユーザーが複数のBucketを作成すれば複数のユーザーがCeph内部に作成されてしまい、目的を達成するには管理が複雑になってしまいます。

### 本命のQuotaの設定はObjectBucketClaimを利用する

公式ガイドをみると、CephのCRD(crds.yaml)で管理されている ``ObjectBucketClaim`` の ``.spec.additionalConfig`` の中で bucketMaxSize などが指定できるようです。

https://rook.io/docs/rook/v1.18/Storage-Configuration/Object-Storage-RGW/ceph-object-bucket-claim/#example

今回はOperatorを利用してユーザーにnamespaceを払い出しているので、ユーザーからはObjectBucketClaimは参照しかできないようにして、自作のOperatorからユーザーのnamespace上にObjectBucketClaimを作成するような挙動にしようと思います。

ユーザーは任意のBucketを利用できなくなりますが、Quotaを強制するには仕方がないかなと思います。

他の方法はユーザーがBucketを作成した時点で、対応する``CephObjectStoreUser``を作成する方法があります。

ただ``CephObjectStoreUser``による方法では、Rook/Cephの実装ではBucket毎に対応するオブジェクトを作成することになります。

それぞれのサイズは制御できても、全体のBucket数やサイズを制御することができないため、実装上の工夫で対応はできそうですが、欲しい機能そのものではなさそうです。

## ObjectBucketについて

``kubectl get obc``などで``ObjectBucketClaim``(obc)は確認していましたが、最終的に作成されるオブジェクトは``ObjectBucket``(ob もしくは obs)です。

この存在を無視してきたわけですが、実際にはConfigMap(cm)とSecretに設定されている変数の情報でアクセスすることになり、意識することはないと思います。

ちなみに``ob``を確認すると次のようになっています。

```bash:
$ kubectl -n yasu-abe get obs
NAME                          AGE
obc-yasu-abe-ceph-bucket      93m
```

``obc-``をprefixとして、namespaceの``yasu-abe``が続き、obcのNameである``ceph-bucket``が付与される形になっています。

この名前は実際に利用する場合には関係がないので、設定されているオブジェクト数やサイズの上限値を確認する場合にだけ参照することになります。

# まとめ - サービスでの利用方法

RBACを使ってOIDC経由での認証されたユーザーには``ClusterRole``に``ObjectBucketClaim``の参照権限だけを与えています。

Roleでは全てのオブジェクトに参照権限を与えているので、``ObjectBucketClaim``の参照ができれば対応する``ObjectBucket``は自動的に参照だけできるようになりました。

実際のBucketはOperatorで数を制限して、``obc/<namespace name>-1`` などのように設定された数だけ自動的に作成するようにしています。

OperatorでObjectBucketをあらかじめ準備する方法のデメリットは、ユーザーが任意のタイミングで削除することができなる点です。

各ユーザーがs5cmdなどを使って手動でファイルを削除して利用してもらうことになるのは面倒そうですが、全体のバランスとしては丁度良いところに納まったと思います。

