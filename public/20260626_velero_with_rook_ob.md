---
title: VeleroでRook/CephのObjectStorageにバックアップを取得してみた
tags:
  - backup
  - minio
  - Rook
  - velero
private: false
updated_at: '2026-06-26T17:01:43+09:00'
id: 3d4c438a66078aeba621
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

これまでVeleroによるバックアップはMinIOをS3互換オブジェクト・ストレージとして利用してきました。

S3互換機能を安定的に稼動させるためMinIOからRook/CephのObjectStorageに移行を進めています。

Rook/CephのRGWを導入した時の顛末と、接続に必要な情報、``s5cmd``コマンドの使い方などは次の記事にまとめています。

https://qiita.com/YasuhiroABE/items/55897bd0822984c35e05

## 環境

* Kubernetes v1.34.3 (Kubespray v2.30.0)
* Rook/Ceph v1.18.11 (Ceph v19.2.3-20250717)
* Velero v1.18.1

MinIO用の設定がされたVeleroのバージョン(v1.16.x)をアップグレード(v1.17.2→v1.18.1)してから作業を行っています。

## 変更作業

既存のデータは保存せずにデータストア全体を切り替えています。

ポイントとなるリソースは次の2つになります。

1. sudo kubectl -n velero get bsl default
2. sudo kubectl -n velero get secret cloud-credentials

### BackupStorageLocation (bsl) リソースの変更

``bsl/default``には認証子(Credential)以外の接続に必要な情報が格納されています。

```yaml:変更後の設定例
spec:
  config:
    region: staging
    s3ForcePathStyle: "true"
    s3Url: http://rook-ceph-rgw-staging.rook-ceph.svc.cluster.local
    checksumAlgorithm: ""
  default: true
  objectStorage:
    bucket: ceph-bkt-42735dac-b883-4553-a7c3-0216595be485
  provider: aws
```

MinIOに接続していた状況から変更が必要なものは、``region``、``s3Url``、``bucket`` の3つだと思います。

また新たに``checksumAlgorithm: ""``を加えています。

#### regionの設定値

Rook/Cephで構成した``CephObjectStore (cephos)``の構成によって指定する文字列が変化します。

```bash:
$ sudo kubectl get --all-namespaces cephos
NAMESPACE   NAME      PHASE   ENDPOINT                                        SECUREENDPOINT   AGE
rook-ceph   staging   Ready   http://rook-ceph-rgw-staging.rook-ceph.svc:80                    8d
```

Rook/CephでToolboxを構成している場合には、Zoneを確認することもできます。

```bash:ToolBox Pod内部からzoneを確認する
bash-5.1$ radosgw-admin zone list
{
    "default_info": "f194ef75-4cbc-442e-bb0e-530b919f3d2c",
    "zones": [
        "staging",
        "default"
    ]
}
```

#### s3Urlの設定値

前述の例ではKubernetesのCNIで認識できるホスト名になっていました。

バックアップのために別クラスターのS3エンドポイントを指定する場合には、LoadBalancerを別途定義しています。

```yaml:別クラスターから接続用のService定義
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: rook-ceph-rgw
  name: rook-ceph-rgw-staging-lb
  namespace: rook-ceph
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: rook-ceph-rgw
    ceph_daemon_id: staging
    rgw: staging
    rook_cluster: rook-ceph
    rook_object_store: staging
  type: LoadBalancer
  loadBalancerIP: 192.168.1.153
```

既に定義されているエンドポイントの定義をコピーして、``type: LoadBalancer``、``loadBalancerIP: 192.168.1.153`` へと変更しています。

必要に応じてIPアドレスを``s3Url``に指定しています。

#### bucketの設定値

``ObjectBucketClaim (obc,obcs)`` をみて実際に作成されているbucket名を確認します。

```yaml:sudo kubectl -n velero get obcs velero-bucket -o yamlの出力から抜粋
...
spec:
  bucketName: ceph-bkt-42735dac-b883-4553-a7c3-0216595be485
  generateBucketName: ceph-bkt
  objectBucketName: obc-velero-velero-bucket
  storageClassName: rook-ceph-bucket
```

### Secret/cloud-credentials リソースの変更

最初にveleroを構成した時に、接続に必要な``AWS_ACCESS_KEY_ID``と、``AWS_SECRET_ACCESS_KEY=``情報をファイルに保存してコマンドの引数に渡したと思います。

今回はSecretオブジェクトだけを作り直せば良いので、またファイルを作成し、``secret/cloud-credentials`` を作り直します。

繰り返すことも考えられたので、次のようなmakefileタスクを定義しています。

```makefile:
.PHONY: delete-aws-cred
delete-aws-cred:
        sudo kubectl -n velero delete secret cloud-credentials

.PHONY: setup-aws-cred
setup-aws-cred:
        sudo kubectl -n velero create secret generic cloud-credentials --from-file=cloud=credentials-velero
```

``credentials-velero``ファイルを準備して、``make delete-aws-cred && make setup-aws-cred``を実行しました。

```text:credentials-veleroの内容
[default]
aws_access_key_id = xxxxxxxxxxxxxxx
aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### checksumAlgorithm パラメータについて

Pluginsに指定している ``velero-plugin-for-aws`` のドキュメントにはCeph ObjectStoreについての記述があります。

https://github.com/velero-io/velero-plugin-for-aws

この中で ``checksumAlgorithm="" to avoid api error XAmzContentSHA256Mismatch`` との記述があり、APIエラーを避けるために、YAML形式では``checksumAlgorithm: ""``を設定しています。

これを外してもテストの範囲では実用上の問題には遭遇しませんでしたが、念のため設定しています。

### 変更結果の反映

ファイルや設定を変更しただけでは反映されないので、``deploy/velero``をリスタートします。

```bash:
$ sudo kubectl -n velero rollout restart deploy velero
```

これで古い情報は全て失われてしまいましたが、新たにscheduleを設定してバックアップを取得することができるようになりました。

## 遭遇したエラー

バックアップ自体は問題なく行われているのはオブジェクト・ストレージ側をみて確認していたのですが、``sudo velero backup describe <backup-name>``で確認すると次のようにエラーメッセージが含まれています。

### 現象

``Backup Volumes:``には対象となったボリュームについての情報が掲載されるはずなのですが、次のようなエラー・メッセージが含まれています。

```text:
Total items to be backed up:  45
Items backed up:              45

Backup Volumes:
  <error getting backup volume info: request failed: <?xml version="1.0" encoding="UTF-8"?><Error><Code>SignatureDoesNotMatch</Code><Message></Message><RequestId>tx0000074dbe3864cff587d-006a3e0cda-122028230-staging</RequestId><HostId>122028230-staging-staging</HostId></Error>>

HooksAttempted:  0
HooksFailed:     0
```

### 対応

``kubectl get bsl``で``BucketStorageLocation``オブジェクトの内容を修正してURLにポート番号(``:80``)を含まないように修正しました。

```bash:
## 修正前
    s3Url: http://192.168.1.153:80

## 修正後
    s3Url: http://192.168.1.153
```

### 確認

保存自体は行われているので、先ほどと同じ対象のログを確認すると、表示が変化します。

```text: 修正後にはエラーがなくなり、同じログの表示が変化する
Total items to be backed up:  45
Items backed up:              45

Backup Volumes:
  Velero-Native Snapshots: <none included>

  CSI Snapshots: <none included>

  Pod Volume Backups - kopia (specify --details for more information):
    Completed:  2

HooksAttempted:  0
HooksFailed:     0
```

## さいごに

VeleroのSchedule機能は優秀で、本番運用しているアプリケーションが削除されてもすぐに復元できるので便利です。

とはいえPVCに適切なラベルを付与するといった準備作業は必要なので、サービス前に問題なく復元できるかどうか確認することが必要だと思います。

Veleroに限らずPCなんかのバックアップは取っていても、実際に適用できるかリストアをしていない人はそこそこいるようです。

Veleroは別のnamespaceにリストアすることができるので、サービスに影響のない範囲で不足なくリストアできるか確認しておくとよいでしょう。


