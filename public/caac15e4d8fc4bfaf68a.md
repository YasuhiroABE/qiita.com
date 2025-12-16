---
title: discourse-sso-oidc-bridge + dexidp/dex で Discourse にログインしてみた
tags:
  - LDAP
  - Discourse
  - SSO
  - dexidp
private: false
updated_at: '2025-11-13T11:03:45+09:00'
id: caac15e4d8fc4bfaf68a
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

この方法はまだ未検証の部分が多いですが、とりあえず管理者としては無事にログインできるようになったので、ここまでの作業を記事にまとめることにします。

:::note
最終的に2024年時点で稼動させたDiscourseではPluginを利用してOIDC Providerを利用しています。[Qiita.com - DiscourseをHelmで導入してみた + API経由でのサーバー設定](https://qiita.com/YasuhiroABE/items/811b04b3d9cfff58dcc3)
:::

## この記事以外の成果物

https://github.com/YasuhiroABE/discourse-sso-oidc-bridge

# 解決したい問題・問題になりそうな環境要因

* バックエンドにLDAPがあるので個別にパスワードを発行せずに、[Discourse](https://www.discourse.org/)を利用したい。
* 既に[dexidp/dex](https://github.com/dexidp/dex)はLDAPと連携しているため、これを利用したい。[前回の投稿](https://qiita.com/YasuhiroABE/items/2effa6d68316b9dc3b10)
* Discourse標準のSSOを利用するためdiscourse-sso-oidc-bridge(Bridge)を利用したい。
* dexidp/dex, Bridgeはプライベートネットワークで稼動しているkubernetes(k8s)クラスターで稼動させる。
* dexidp/dex, BridgeへのアクセスはTLS(https)を有効にしているNginxのproxy_passを経由させる。
* バックエンドのdexidp/dex, Bridgeはnon-TLS(http)で稼動している。ingressは使用しない。

# 解決案の概要

DiscourseでOpenID Connectを利用したい場合の方法は、大枠で次の2つ。

* Pluginを利用する [OpenID Connect Authentication Plugin](https://meta.discourse.org/t/openid-connect-authentication-plugin/103632)など
* 標準のSSO(SingleSignOn)機能を利用する

この2つの比較は、リンクしたmeta.discourse.orgの記事中にある[Erik Sundellさんのコメント](https://meta.discourse.org/t/openid-connect-authentication-plugin/103632/18)が参考になると思います。

SSOの仕組みを利用した方がよりシームレスに使えそうという事で、SSOを利用したいと思いました。

そこで、このBridgeというアイデアに乗ったのですが、dexに接続したところうまく動かない状況になったので、解決するまでの顛末をまとめます。最終的な変更点は2行ぐらいですが、先頭のリンク先(github)に掲載しています。

# 対応の詳細

## 標準的な方法によるdiscourseのデプロイ

ベアメタルなサーバーを準備して、[標準的な方法(Beginner Docker install guide)](https://github.com/discourse/discourse/blob/master/docs/INSTALL-cloud.md)でDiscourseを動かしています。

## KubernetesへのBridgeのデプロイ

あらかじめnamespaceを準備してから、次の2つのファイルをapplyします。

```yaml:01-service.yaml
---
apiVersion: v1
kind: Service
metadata:
  namespace: discourse
  name: sso
spec:
  type: LoadBalancer
  loadBalancerIP: "10.1.200.135"
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: sso
```

```yaml:02-deploy-discourse-sso-bridge.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: discourse
  name: sso
  labels:
    app: sso
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sso
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: sso
    spec:
      imagePullSecrets:
      - name: dockerhubreg
      containers:
      - name: sso
        image: _yourid_/discourse-sso-oidc-bridge:1.0
        ports:
        - containerPort: 8080
          name: sso
        env:
        - name: DEBUG
          value: "true"
        - name: SERVER_NAME
          value: "proxy.example.org"
        - name: SECRET_KEY
          value: "de78cc50b47a1de6d9a8d83bbed6deb26e63529694a5f2dae20a62666b8e87d1"
        - name: OIDC_ISSUER
          value: "https://proxy.example.org/dex"
        - name: OIDC_CLIENT_ID
          value: "discourse-test"
        - name: OIDC_CLIENT_SECRET
          value: "de4c6e9941a7ae4a6cc4ba518a1fcd132166e8aebd7d3b22da7c425ef7172e81"
        - name: OIDC_SCOPE
          value: "openid,profile,email"
        - name: DISCOURSE_URL
          value: "http://discourse.example.org"
        - name: DISCOURSE_SECRET_KEY
          value: "eb553c1ad5d2e4321e87a89f0ed97550f23b460707986eb6fe0d4f005a76ef87"
        - name: USERINFO_SSO_MAP
          value: "{ \"sub\": \"external_id\", \"name\": \"username\", \"email\": \"email\" }"
```

SECRET_KEY、DISCOURSE_SECRET_KEY等は、```openssl rand -hex 32```で生成しています。


この中で、```_yourid_/discourse-sso-oidc-bridge:1.0```はPrivateに設定しているためアクセスできません。

先のgithubをclone ＆ buildして、自分の適当なdockerhubアカウントにpushしておきます。
そのdockerhubアカウントにアクセスするための情報をsecret/dockerhubregに登録しておきます。

準備ができたら作成したファイルを適応させます。
ファイルとコマンドラインの*_yourid_*, *_youremail_*, *_yourpassword_* と書かれた計4箇所は適宜変更してください。

```bash
$ kubectl create ns sso
$ kubectl -n sso create secret docker-registry dockerhubreg --docker-username=_yourid_ --docker-email=_youremail_ --docker-password=_yourpassword_
$ kubectl -n sso apply -f 01-service.yaml
$ kubectl -n sso apply -f 02-deploy-discourse-sso-bridge.yaml
```

## nginxの構成

nginxは次のようなconfigで稼動しています。

```nginx
server{
    listen 80;
    server_name proxy.example.org;
    return 301 https://$host$request_uri;
}

server{
    listen 443 ssl;
    server_name    proxy.example.org;
    ssl_certificate     /etc/ssl/certs/proxy.example.org.cer;
    ssl_certificate_key /etc/ssl/private/proxy.example.org.nopass.key;

    proxy_set_header    Host    $host;
    proxy_set_header    X-Real-IP    $remote_addr;
    proxy_set_header    X-Forwarded-Host      $host;
    proxy_set_header    X-Forwarded-Server    $host;
    proxy_set_header    X-Forwarded-For    $proxy_add_x_forwarded_for;
    proxy_set_header    X-Forwarded-Proto https;

   ## dex
    location /dex {
        proxy_pass    http://web36.k8snet.example.org:5556/dex;
    }
    ## discourse-sso
    location /sso/ {
        proxy_pass    http://web35.k8snet.example.org/sso/;
    }
    location /redirect_uri {
        proxy_pass    http://web35.k8snet.example.org/redirect_uri;
    }
}
```

## dexidp/dex のconfig-ldap.yamlへの追加点

staticClientsにidを追加しています。

```yaml:config-ldap.yaml
   staticClients:
   - id: discourse-test
     redirectURIs:
     - 'http://proxy.example.org/redirect_uri'
     name: 'Discourse Test'
     secret: de4c6e9941a7ae4a6cc4ba518a1fcd132166e8aebd7d3b22da7c425ef7172e81
```

redirectURIs:の中で、"http://"とnon-TLSを指定しているのはわざとです。

## Discourse管理者画面での変更点

あらかじめ管理者として登録しているユーザーでログインしておきます。
http\://discourse.example.org/admin/site_settings/category/login に進み、"sso url"に https\://proxy.example.org/sso/login を指定します。

たぶんこの設定が一番分かりにくいのかもしれません。Bridgeのリポジトリを作ったSundellさんが参考にした https://github.com/fmarco76/DiscourseSSO のREADME.rst の中で説明されています。

次に、"sso secret"にDISCOURSE_SECRET_KEY環境変数に指定した値を設定してから、"enable sso"のチェックを有効にしています。

# discourse-sso-oidc-bridgeへの変更点

https://github.com/YasuhiroABE/discourse-sso-oidc-bridge はオリジナルを利用する時にあった次のような問題を解決しています。

* OpenID ConnectのIssuer(この場合ではdexidp/dex)が、cookieに"userinfo"をキーにして情報を返してくる点
* この"userinfo"に含まれる情報として、"email"、"external_id"の2つは最低限必要としているが、Issuerは"sub"にユニークなIDを格納してくる点

前者はapp.pyを変更して、"userinfo"を"id_token"に書き換えています。

後者については、k8sのconfigファイルの中でUSERINFO_SSO_MAP環境変数でマッピングを指定する事で解決しています。

さらに"nonce"という変数がdiscourseとWebアプリが利用するFlaskフレームワークの両方のCookieに設定されるため、両方を一つのqueryに展開する箇所で、Flaskのnonceは除いて、discourseに戻しています。

## 差分

:::note
現在はPluginを利用しているので十分に確認していませんが、この動作に関連するDexの挙動はこの時点から変更されているはずで、私が変更したコードは最新のDexとの組み合せでは動作しない可能性があります。

オリジナルのコードで問題なく動作することを期待していますが、もしうまく動作しなければ、ここに掲載した情報を参考にしてsessionが返す内容を確認してください。
:::

https://github.com/YasuhiroABE/discourse-sso-oidc-bridge/commit/a034ed6276112b32ee9d4e6a4217875506f90927


```diff
diff --git a/discourse_sso_oidc_bridge/app.py b/discourse_sso_oidc_bridge/app.py
index 154778b..6a5437d 100644
--- a/discourse_sso_oidc_bridge/app.py
+++ b/discourse_sso_oidc_bridge/app.py
@@ -181,7 +181,7 @@ def create_app(config=None):
         attribute_map = app.config.get('USERINFO_SSO_MAP')
 
         sso_attributes = {}
-        userinfo = session['userinfo']
+        userinfo = session['id_token']
 
         # Check if the provided userinfo should be used to set information to be
         # passed to discourse. Do it by checking if the userinfo field is...
@@ -212,7 +212,7 @@ def create_app(config=None):
         # Check if we got the required attributes
         for required_attribute in REQUIRED_ATTRIBUTES:
             if not sso_attributes.get(required_attribute):
-                app.logger.info(f'/sso/auth -> 403: {required_attribute} not found in userinfo: ' + json.dumps(session['userinfo']))
+                app.logger.info(f'/sso/auth -> 403: {required_attribute} not found in userinfo: ' + json.dumps(session['id_token']))
                 abort(403)
 
         # All systems are go!
@@ -221,6 +221,9 @@ def create_app(config=None):
         # Construct the response inner query parameters
         query = session['discourse_nonce']
         for sso_attribute_key, sso_attribute_value in sso_attributes.items():
+            # key:'nonce' was already registered by session['discourse_nonce'].
+            if sso_attribute_key == "nonce":
+              continue
             query += f'&{sso_attribute_key}={quote(str(sso_attribute_value))}'
         app.logger.debug('Query string to return: %s', query)
```

以上

