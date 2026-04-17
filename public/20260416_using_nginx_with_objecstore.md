---
title: Rook/CephのObjectStoreにNginxのコンテンツを配置する
tags:
  - nginx
  - Rook
  - ObjectStore
private: false
updated_at: '2026-04-17T11:30:07+09:00'
id: 4e3e7da4cdbedeea4488
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

Rook/Cephは、自分が管理しているほぼ全てのKubernetesクラスターにPersistent Volumeを管理するために利用しています。

しばらく前からAWS S3互換のObjectStore(Bucket)を有効にしていました。

https://qiita.com/YasuhiroABE/items/55897bd0822984c35e05

いままでは複数のPodからファイルを共有するために Filesystem(storageclass/rook-cephfs)をNginxクラスターで利用してきましたが、今回は次の資料を参考にObjectStore上にコンテンツを配置して使用感をテストすることにしました。

https://github.com/nginx/nginx-s3-gateway/blob/main/docs/getting_started.md

# 環境

* Kubernetes v1.34.3
* Rook/Ceph enabled ObjectStore (1.18.8)

```bash:StorageClassの設定状況
NAME                        PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
rook-ceph-block (default)   rook-ceph.rbd.csi.ceph.com      Delete          Immediate           true                   2y70d
rook-ceph-bucket            rook-ceph.ceph.rook.io/bucket   Delete          Immediate           false                  6d18h
rook-cephfs                 rook-ceph.cephfs.csi.ceph.com   Delete          Immediate           true                   2y70d
```

## Rook/Cephに定義されたObjectStorageの状況

次のような``ObjectBucketClaim (obc)``を定義しています。

```yaml:kubectl get obc obc-yasu-abe-1 -o yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  creationTimestamp: "2026-04-16T08:18:03Z"
  finalizers:
  - objectbucket.io/finalizer
  generation: 2
  labels:
    app.kubernetes.io/created-by: operator-sccp-setup-controller
    app.kubernetes.io/instance: yasu-abe
    app.kubernetes.io/name: obc-yasu-abe-1
    bucket-provisioner: rook-ceph.ceph.rook.io-bucket
  name: obc-yasu-abe-1
  namespace: yasu-abe
  resourceVersion: "324176707"
  uid: 454b73bb-efd7-4235-a3f0-4cc7b9adb558
spec:
  additionalConfig:
    maxSize: 1000Mi
  bucketName: obc-yasu-abe-1
  objectBucketName: obc-yasu-abe-obc-yasu-abe-1
  storageClassName: rook-ceph-bucket
status:
  phase: Bound
```

これに対応して自動的にConfigMap(cm)やSecretが作成されています。

```bash:kubectl get cm,secret obc-yasu-abe-1
NAME                       DATA   AGE
configmap/obc-yasu-abe-1   5      17h

NAME                    TYPE     DATA   AGE
secret/obc-yasu-abe-1   Opaque   2      17h
```

# 作業の流れ

参考資料に挙げた説明では``ghcr.io/nginxinc/nginx-s3-gateway/nginx-oss-s3-gateway:latest-20220916``を利用していますが、ここでは``docker.io/nginxinc/nginx-s3-gateway:latest-20260413``コンテナを利用することにしました。

## nginx-s3-gatewayの稼動

Rook/Cephで定義された情報を利用するようにDeploymentを定義します。

```yaml:deploy-nginxs3.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-s3-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-s3-gateway
  template:
    metadata:
      labels:
        app: nginx-s3-gateway
    spec:
      containers:
      - name: nginx-s3-gateway
        image: nginxinc/nginx-s3-gateway:latest
        ports:
        - containerPort: 80
        env:
        - name: AWS_SIGS_VERSION
          value: "4"
        - name: S3_SERVER
          value: rook-ceph-rgw-sccp.rook-ceph.svc.cluster.local
        - name: S3_SERVER_PORT
          value: "80"
        - name: S3_SERVER_PROTO
          value: "http"
        - name: S3_REGION
          value: "sccp"
        - name: S3_BUCKET_NAME
          valueFrom:
            configMapKeyRef:
              name: obc-yasu-abe-1
              key: BUCKET_NAME
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: obc-yasu-abe-1
              key: AWS_ACCESS_KEY_ID
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: obc-yasu-abe-1
              key: AWS_SECRET_ACCESS_KEY
        - name: S3_STYLE
          value: "path"
        - name: ALLOW_DIRECTORY_LIST
          value: "false"
        - name: PROVIDE_INDEX_PAGE
          value: "true"
        - name: DEBUG
          value: "false"
```

S3_SERVERの指定は本来は次のように``valueFrom:``でConfigMapから導出されるべきです。

```yaml:
        - name: S3_SERVER
          valueFrom:
            configMapKeyRef:
              name: obc-yasu-abe-1
              key: BUCKET_HOST
```

ただ``.cluster.local``は自動的にsuffixとして追加されるはずなのですが、どうしてもうまく動作しなかったので手動でFQDNを指定しています。

各環境に合わせて``BUCKET_HOST``の値に``.cluster.local``を加えた文字列をS3_SERVERに指定する必要があります。

このDeployment定義から自動的に作成されたPodに接続するために``Service``オブジェクトを定義します。

```yaml:svc-nginxs3.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-s3-gateway-svc
  labels:
    app: nginx-s3-gateway
spec:
  type: ClusterIP
  ports:
     -  port: 80
        protocol: TCP
        targetPort: 80
  selector:
    app: nginx-s3-gateway
```

## ObjectBucketへの配置

適当なAlpineコンテナにtestingリポジトリを追加すると、s5cmdがapkコマンドでインストール(add)できます。

```bash:alpineコンテナでの事前準備
$ kubectl run -it s3-toolbox --image=alpine:edge -o json --overrides='{
    "spec": {
      "stdin": true,
      "tty": true,
      "containers": [{
        "name": "s3-toolbox",
        "image": "alpine:edge",
        "command": ["sh"],
        "stdin": true,
        "tty": true,
        "envFrom": [{
          "configMapRef": {
            "name": "obc-yasu-abe-1"
          }}, {
          "secretRef": {
            "name": "obc-yasu-abe-1"
          }
        }]
      }]
    }
  }' | kubectl apply -f -
$ kubectl attach -it s3-toolbox
# echo https://dl-cdn.alpinelinux.org/alpine/edge/testing | tee -a /etc/apk/repositories
# apk --no-cache add s5cmd@testing
```

とりあえずこのPodの中で作業している前提で必要な設定を付与していきます。

``s5cmd``が利用できるようになったら次のように設定ファイルを作成し、``index.html``をObjectBucketに転送します。

```bash:kubectl attachで入ったalpineコンテナ内部で実行すること
# mkdir -p ~/.aws
# cat > ~/.aws/credentials << EOF

[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

# echo "Hello World, $(id -un) at $(date)" > /tmp/index.html
# s5cmd --endpoint-url http://${BUCKET_HOST}:${BUCKET_PORT} cp /tmp/index.html s3://${BUCKET_NAME}/
```

これでGateway APIやport-forwardingで``nginx-s3-gateway-svc``に接続するとコンテンツが表示されます。

```bash:curlコマンドでPodにアクセスした結果
$ curl https://kubecamp.example.com/yasu-abe/

Hello World, yasu-abe at Fri Apr 17 01:32:26 UTC 2026
```

# さいごに

個人的には``ReadWriteMany``でアクセスができるFilesystemタイプの``sc/rook-cephfs``が使いやすいと感じています。

ただObjectBucketのメリットはサイズをあらかじめ定義しておく必要がないので、Quotaのような制限も柔軟に動作しますし、新しいタイプのファイルシステムとしてよく出きていると思います。

S3互換ツールは多いので使いこなせれば便利なのだと思いますが、``nginx-s3-gateway``の設定では互換性を網羅するための部分で、Rook/Cephの場合にどう設定するべきか読み解くのに少し苦労しました。

``S3_TYPE``設定ではデフォルトで``virtual``が指定されていますが、Rook/CephのObjectBucketでは``path``に変更する必要があります。

また先に書いたようにホスト名がFQDNでないとうまく動作しませんでしたが、nginx-s3-gatewayのPod内部からはresolveできたので、原因は少し調べないと分からないので状況しか分かっていません。

AWS S3は圧倒的な分散配置によって負荷分散と柔軟性を実現していますが、Rook/Cephの場合は冗長性は確保できますが、ObjectBucketだからといってパフォーマンスが劇的に上がるというものではないはずです。

nginx-s3-gatewayが力を発揮するのは、Blob専用のコンテンツ配信用バックエンドとして利用する時だと思うので、あまりhugoで作成するような普通のWebサイトに利用することはないと思います。

少し設定が面倒だったので備忘録としてメモとして残しておきます。

