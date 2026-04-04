---
title: BitnamiのDiscourseをオフィシャルのイメージに移行した時のメモ
tags:
  - BITNAMI
  - Discourse
private: false
updated_at: '2026-04-04T10:07:33+09:00'
id: d14bb84b498918021693
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

BitnamiはVMWareが買収したアプリケーションパッケージ企業で、Kubernetes上でHelmを利用して本番レベルのサービスを利用することができ、よく利用していました。

BroadcomによるVMWareの買収後、サービスやその提供方法について様々な変更が行われていますがBitnamiもDockerHubからタグ付きバージョンのコンテナイメージの公開を取り止める決定を行っています。

結果的にHelmで動作させていたサービスは再起動などのタイミングで、DockerHubから削除されたコンテナをpullできなくなり、動作しなくなっています。

MinIOも同様にコンテナイメージを非公開にしていますが、基本的に全てのノードに展開される点と、単一バイナリに依存しているため、バージョンを変更しなかったり、別コンテナを指定するなどすれば、それほど環境を維持するのは難しくありません。

Discourseは残念ながらRailsアプリケーションで依存関係が複雑です。

自前でちゃんと動作するコンテナをビルドするのは難易度が高いので、本番環境での動作は推奨されていませんが、本家のDiscourseコンテナに移行することにしました。

https://hub.docker.com/r/discourse/discourse/

:::note warn
繰り返しになりますが、本家は``discourse/discourse``コンテナを本番利用できるレベルとは位置付けていません。
:::

# 現状

Helmを利用して導入したDiscourseについては次の記事で導入方法などを説明しています。

https://qiita.com/YasuhiroABE/items/811b04b3d9cfff58dcc3

これをHelmを利用せずに、一般的なYAMLファイルを利用して、PosgreSQL、Redisなどを別途稼動させた上で、``discourse/discourse``コンテナをDeploymentで動作させます。

## 動作環境について

BitnamiのHelmを利用していた旧環境は次のような構成でした。

* Helm chart: [bitnami/discourse/15.1.6](https://artifacthub.io/packages/helm/bitnami/discourse/15.1.6) (Discourse 3.4.1)
* Kubernetes version: 1.34.3 (Kubespary 2.30.0)

これを同じKubernetesクラスターの中にnamespaceを別にして導入していきます。

環境を並行して維持させることはできますが、既にdiscourseは正常に稼動しない状況になっているので、Helm chartはuninstallしています。

# 移行方法

前述の記事で紹介しているバックアップファイルを利用したリストアによって環境を移行します。

Helmで動作しているPodの``/opt/bitnami/discourse/public/backups/default/``ディレクトリにあるバックアップファイルを入手しておく必要があります。

``discourse/discourse``コンテナでは``/var/www/discourse/public/backups/default/``以下にバックアップファイルを配置します。

# Helmを利用しないDiscourseのインストール

Helmは利用せずにDeploymentなどを利用して、Redis/PostgreSQLなどを個別に導入しています。

:::note
このページに掲載しているYAMLファイルを生成するために生成AI``Claude``を利用しました。
:::

## インストール作業の概要

主に次のような流れになります。

1. Redisの導入 (version 7系列の最新版公式コンテナ)
2. PostgreSQLの導入 ([ZalandoのPostgreSQL Operator](https://github.com/zalando/postgres-operator)を利用)
3. PostgreSQL接続用にパスワード情報などの確認
4. Discourseの導入
5. リバースプロキシーの設定
6. バックアップファイルの転送
7. リストア作業

## Redisの導入

とりあえずRedisはパスワードをかけずに公式コンテナを動作させています。

```yaml:01.svc-redis.yaml
---
apiVersion: v1
kind: Service
metadata:
  namespace: discourse2
  name: redis-svc
spec:
  type: ClusterIP
  ports:
    - port: 6379
      targetPort: 6379
      protocol: TCP
  selector:
    app: redis
```

```yaml:02.pvc-redis.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-pvc
  namespace: discourse2
spec:
  accessModes: [ "ReadWriteOnce" ]
  storageClassName: rook-ceph-block
  resources:
    requests:
      storage: 10Gi
```

```yaml:03.deploy-redis.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: discourse2
  name: redis
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.4.8
        ports:
        - containerPort: 6379
          name: redis
        volumeMounts:
        - name: redis-pvc
          mountPath: /data
      volumes:
      - name: redis-pvc
        persistentVolumeClaim:
          claimName: redis-pvc
```

### PostgreSQLの導入

これはHelmで導入しているZalandoのOperatorを利用しています。

https://github.com/zalando/postgres-operator

Operator自体は別のnamespaceに導入しています。StorageClass(``sc``)などの指定は下記のような設定ファイルでするため、Operatorの導入にはカスタマイズはおこなっていません。

設定ファイルでは``sc``を指定する他に、PostgreSQLのversionを``17``に指定していますが、現時点では``15``にするのが安全です。

:::note
``17``を利用した場合の不具合については後述します。
:::

```yaml:04.operator-pgcluster.yaml
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  labels:
    team: discourse-team
  name: pgcluster
  namespace: discourse2
spec:
  allowedSourceRanges: []
  databases:
    discoursedb: pguser
  numberOfInstances: 2
  postgresql:
    version: '17'
  resources:
    limits:
      cpu: 500m
      memory: 1500Mi
    requests:
      cpu: 100m
      memory: 100Mi
  teamId: discourse-team
  users:
    pguser:
      - superuser
      - createdb
  volume:
    size: 50Gi
    storageClass: rook-ceph-block
```

ここまでの導入が終わると次のような状況になっているはずです。

```bash:ns/discrouse2の導入状況
$ sudo kubectl -n discourse2 get pod,deploy,postgresql.acid.zalan.do
NAME                             READY   STATUS    RESTARTS   AGE
pod/pgcluster-0                  1/1     Running   0          28h
pod/pgcluster-1                  1/1     Running   0          28h
pod/redis-585dcbd9d5-p6c5g       1/1     Running   0          78m

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/discourse   2/2     2            2           23h
deployment.apps/redis       1/1     1            1           28h

NAME                                 TEAM             VERSION   PODS   VOLUME   CPU-REQUEST   MEMORY-REQUEST   AGE   STATUS
postgresql.acid.zalan.do/pgcluster   discourse-team   17        2      50Gi     100m          100Mi            28h   Running
```

### DB接続用にパスワード情報などの確認

Operatorが自動的にランダムなパスワードを設定してくれるので、その値を利用します。

```bash:Secretに格納されたパスワード情報の確認
## postgresユーザーのパスワード (基本的に利用しない)
$ sudo kubectl -n discourse2 get secret postgres.pgcluster.credentials.postgresql.acid.zalan.do -o jsonpath='{.data.password}' | base64 -d; echo ""

## pguserユーザーのパスワード (アプリから利用するのはこちら)
$ sudo kubectl -n discourse2 get secret pguser.pgcluster.credentials.postgresql.acid.zalan.do -o jsonpath='{.data.password}' | base64 -d; echo ""
```

これらのコマンドで表示された文字列(e.g.: ``Qs1F96GrQ3pPI7VCv9iGQXG5KavYLjc7ocFCvjx+nA37UNVaC094o/qJqdNzmK2r``)がパスワードです。

### Discourseの導入

``discourse/discourse``を導入していきます。

```yaml:05.cm-discourse.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: discourse-config
  namespace: discourse2
data:
  DISCOURSE_HOSTNAME: "discourse.example.com"
  DISCOURSE_SMTP_ADDRESS: "mailhost.example.com"
  DISCOURSE_SMTP_PORT: "25"
  DISCOURSE_SMTP_ENABLE_START_TLS: "false"
  DISCOURSE_SMTP_AUTHENTICATION: "none"
  DISCOURSE_DB_HOST: "pgcluster"
  DISCOURSE_DB_PORT: "5432"
  DISCOURSE_DB_NAME: "discoursedb"
  DISCOURSE_DB_USERNAME: "pguser"
  DISCOURSE_REDIS_HOST: "redis-svc"
  DISCOURSE_REDIS_PORT: "6379"
  DISCOURSE_DEVELOPER_EMAILS: "dev@example.com"
```

次の``06.secret-discourse.yaml``には先ほど調べたパスワードの情報を記入します。

``DISCOURSE_DB_PASSWORD``にpguserユーザーのパスワード、もう一方にpostgresユーザーのパスワードを記載します。

```yaml:06.secret-discourse.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: discourse-secrets
  namespace: discourse2
type: Opaque
stringData:
  DISCOURSE_DB_PASSWORD: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  DISCOURSE_POSTGRES_PASSWORD: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

```

```yaml:07.svc-discourse.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: discourse-svc
  namespace: discourse2
spec:
  selector:
    app: discourse
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  type: ClusterIP
```

```yaml:08.pvc-discourse.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: discourse-data
  namespace: discourse2
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: rook-cephfs
  resources:
    requests:
      storage: 10Gi

```

```yaml:09.deploy-discourse.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: discourse
  namespace: discourse2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: discourse
  template:
    metadata:
      labels:
        app: discourse
    spec:
      initContainers:
      - name: discourse-init
        image: discourse/discourse:2026.1.3-amd64
        command:
          - /bin/bash
          - -c
          - |
            set -e
            echo "Checking database connection..."
            while ! pg_isready -h $DISCOURSE_DB_HOST -p $DISCOURSE_DB_PORT -U $DISCOURSE_DB_USERNAME; do
              echo "Waiting for database..."
              sleep 2
            done
            echo "Database is ready"
        env:
        - name: DISCOURSE_DB_HOST
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_HOST
        - name: DISCOURSE_DB_PORT
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_PORT
        - name: DISCOURSE_DB_USERNAME
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_USERNAME
        - name: DISCOURSE_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: discourse-secrets
              key: DISCOURSE_DB_PASSWORD
        - name: DISCOURSE_DB_NAME
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_NAME
        - name: DISCOURSE_REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_REDIS_HOST
        - name: DISCOURSE_REDIS_PORT
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_REDIS_PORT
        volumeMounts:
        - name: discourse-data
          mountPath: /shared
      containers:
      - name: discourse
        image: discourse/discourse:2026.1.3-amd64
        ports:
        - containerPort: 80
          name: http
        env:
        - name: DISCOURSE_USE_X_FORWARDED_HOST
          value: "true"
        - name: DISCOURSE_FORCE_HTTPS
          value: "false"
        - name: RAILS_FORCE_SSL
          value: "false"
        - name: DISCOURSE_LOG_LEVEL
          value: "debug"
        - name: DISCOURSE_HOSTNAME
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_HOSTNAME
        - name: DISCOURSE_DB_HOST
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_HOST
        - name: DISCOURSE_DB_PORT
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_PORT
        - name: DISCOURSE_DB_USERNAME
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_USERNAME
        - name: DISCOURSE_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: discourse-secrets
              key: DISCOURSE_DB_PASSWORD
        - name: DISCOURSE_DB_NAME
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DB_NAME
        - name: DISCOURSE_REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_REDIS_HOST
        - name: DISCOURSE_REDIS_PORT
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_REDIS_PORT
        - name: DISCOURSE_SMTP_ADDRESS
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_SMTP_ADDRESS
        - name: DISCOURSE_SMTP_PORT
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_SMTP_PORT
        - name: DISCOURSE_DEVELOPER_EMAILS
          valueFrom:
            configMapKeyRef:
              name: discourse-config
              key: DISCOURSE_DEVELOPER_EMAILS
        volumeMounts:
        - name: discourse-data
          mountPath: /shared
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "800m"
      volumes:
      - name: discourse-data
        persistentVolumeClaim:
          claimName: discourse-data
```

### リバースプロキシーサーバーの設定

Ingressは2026年3月でdiscontinuedとなりました。

Gateway APIに移行する準備はしていますが、準備が終わらなかったので、引き続きIngressを使っています。

tls.crtとtls.nopass.keyファイルを準備して次のように``secret/tls``を作成しています。

```bash:secret/tlsオブジェクトの作成
$ sudo kubectl -n discourse2 create secret tls tls --cert=./conf/tls.crt --key=./conf/tls.nopass.key
```

Ingressにはこの設定を与えてTLSを有効化しています。

```yaml:10.ingress-discourse.yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: discourse-ingress
  namespace: discourse2
  labels:
    group: ingress-nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/ssl-redirect: 'false'
    nginx.ingress.kubernetes.io/force-ssl-redirect: 'false'
    nginx.ingress.kubernetes.io/proxy-read-timeout: '600'
    nginx.ingress.kubernetes.io/proxy-send-timeout: '600'
    nginx.ingress.kubernetes.io/backend-protocol: 'HTTP'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - discourse.example.com
    secretName: tls
  rules:
  - host: discourse.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: discourse-svc
            port:
              number: 80
```

### バックアップファイルの転送、リストア作業

Bitnamiのdiscourseではバックアップファイルは``/opt/bitnami/discourse/public/backups/default/``に存在していましたが、``discourse/discourse``では``/var/www/discourse/public/backups/default/``に配置します。

最初は``default``ディレクトリが作成されていないため、この作成から始めます。

また実際にはPVC上のパス``/shared/public/backups/default/``が実体となり、永続化の対象となっています。

何かあってもこのPVCにアクセスするPodを動作させることでバックアップファイルにアクセスできます。

あらかじめカレントディレクトリにバックアップファイルを、ファイル名の日付部分を変更せずに配置します。ここでは``backupfile-2026-02-26-033236-v20250130205841.tar.gz``ファイルだとしてコマンドを実行しています。

```bash:ファイルの転送例
$ podname="$(sudo kubectl -n discourse2 get pod -l app=discourse -o jsonpath='{.items[*].metadata.name}')"
$ sudo kubectl -n discourse2 exec ${podname} -it  -- mkdir /var/www/discourse/public/backups
$ sudo kubectl -n discourse2 cp backupfile-2026-02-26-033236-v20250130205841.tar.gz ${podname}:/var/www/discourse/public/backups/
```

### WebブラウザからのDiscourseのリストア作業

Discourseが動作すると最初は初期設定の画面が表示されています。

最低限のサイト名や管理者IDの登録などを行いますが、これらはリストアによって削除されます。

まず初期設定を行い、Admin画面から``Advanced``→``Backups``に進み、``Settings``からリストアを有効にするチェックを反映させてから、少し待つとBackupsタブに表示されている該当ファイルのメニューでリストアが選択できるようになります。

# 継続的バックアップを取得する際の不具合

定期的に指定した世代分のバックアップが取得されますが、pg_dumpコマンドのバージョンのミスマッチによって通常のバックアップ取得タスクが失敗します。

今回利用したPostgreSQLのバージョンは``17``でしたが、利用したDiscourseコンテナはUbuntuベースで``postgresql-client-15```パッケージが導入されています。

このパッケージは複数バージョンが導入できるので、``postgresql-client-17```パッケージを導入することで解決します。

単純なことではあるのですが、コンテナは再起動のたびに初期化されるため、これを永続化することが少し難しい状況です。

とりいそぎKubernetesのControl-planeのノード上で、定期的にクライアント導入のタスクを実行するように設定しておくことで対応しています。

```bash:Control-plane上で実行するbashスクリプト
#!/bin/bash
for pod in $(sudo kubectl -n discourse2 get pod -l app=discourse -o jsonpath='{.items[*].metadata.name}')
do
  sudo kubectl -n discourse2 exec -it ${pod} -- apt update
  sudo kubectl -n discourse2 exec -it ${pod} -- apt-get install -y postgresql-client-17
done
```
