---
title: 久し振りにRook/CephにObjectStoreを構成してみた
tags:
  - Ceph
  - Rook
  - kubernetes
  - ObjectStorage
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

かなり前、Rook.ioにはMinioが付属していてS3互換のAPIを利用することができました。

v0.xの時代にもObjectStorage機能は提供されていたように思いますが、RookのObject Storage機能はバージョンが変更される毎に修正されたり、廃止されたり、いろいろあった部分です。

RookはCephに注力するようになってきてRGWは今後もサポートされそうです。

Minioの雲行きが少し怪しいので移行先として検証しておこうと思い、既存のRook/CephにObject Storage機能を追加してみようと思います。

# 環境 & 構成

* Kubernetes - v1.32.8
* Rook - v1.8.8 (Ceph v19.2.3)

既にStorageClassに **rook-ceph-block** と **rook-cephfs** は設定済み。

```:text
NAME                        PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
rook-ceph-block (default)   rook-ceph.rbd.csi.ceph.com      Delete          Immediate           true                   4y102d
rook-cephfs                 rook-ceph.cephfs.csi.ceph.com   Delete          Immediate           true                   4y102d
```

# 参考文献

ObjectStoreの構成はいくつかのバリエーションがありますが、今回は **Create Local Object Store(s) with Shared Pools** を設定していきます。

https://rook.io/docs/rook/v1.18/Storage-Configuration/Object-Storage-RGW/object-storage/#create-local-object-stores-with-shared-pools

# 変更作業

まずCephBlockPoolオブジェクを作成します。

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

## 各namespaceでBucketを作成して利用する

異なるnamespaceでBucketを作成するため、次のようなYAMLファイルを準備します。

```yaml:test-ceph-bucket.yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ceph-bucket
spec:
  generateBucketName: ceph-bkt
  storageClassName: rook-ceph-delete-bucket
```

作成されたObjectBucketClaimは次のように確認できます。

```bash:
$ kubectl -n <my-namespace> get obc

NAME          AGE
ceph-bucket   4m58s
```

ただ

## access-key, secret-key を確認する

正しくObjectBucketClaimが作成されると自動的に同じNameでSecret, ConfigMapオブジェクトが作成されます。

```bash:
$ kubectn -n <my-namespace> get cm ceph-bucket
NAME          DATA   AGE
ceph-bucket   5      6m19s

$ kubectn -n <my-namespace> get secrets ceph-bucket
NAME          TYPE     DATA   AGE
ceph-bucket   Opaque   2      6m33s
```

設定された値にアクセスする方法は公式ガイドに記載がありますが、"PORT"など他の設定とぶつかりそうなので、変数名はAWS,ないしBUCKETをprefixとして持つように変更しています。

```bash:公式ガイドの例をもとに少し変更
$ ns=my-namespace

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
AWS_HOST=rook-ceph-rgw-sccp.rook-ceph.svc
AWS_SECRET_ACCESS_KEY=VzGQfLL5oyqEZ9te7OCUYIAJ6gIi43ezSZeMNx2C
BUCKET_NAME=ceph-bkt-b29d078b-3502-4715-87a8-329fa4df059b
BUCKET_PORT=80
```

エンドポイントのTLS化は後で考えることにして、とりあえずこのまま利用してみます。

## toolbox-operator-image から s5cmd コマンドを利用する

通常のtoolboxコンテナにはs5cmdコマンドが配置されていないので、rook/deploy/examples/toolbox-operator-image.yaml を利用して、専用のtoolbox PODを稼動させます。

この作業は namespace: rook-ceph で行う点に注意が必要です。

```bash:s5cmdコマンドを含むtoolboxコンテナの稼動
$ kubectl apply -f toolbox-operator-image.yaml
```

公式ガイドに書かれているように s5cmd を

以上
