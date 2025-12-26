---
title: Open WebUIのLDAP認証の改造
tags:
  - LDAP
  - OpenWebUI
private: false
updated_at: '2025-06-08T12:16:46+09:00'
id: 29ebf47bf4ce9b7ee1be
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

ローカルLLMやリモートのChatGPT互換APIを実行するために、Open WebUIを利用しています。

https://github.com/open-webui/open-webui

LDAP認証をしようとしたところBIND DN, BIND Passwordが必須扱いだったので、これを修正して``Anonymous BIND``に対応することにしました。

# LDAPの接続形態

Active Directory(AD)ではサーバーに接続する際にBINDが必要ですが、LDAPのプロトコルではBINDを行わないAnonymous BINDも可能になっています。

```plantuml
User -> LDAP : Anonymous BIND without BIND-DN and BIND-Password
User -> LDAP : search query e.g., uid=yasu,ou=People,dc=example,dc=com
LDAP -> User : Return the directory information for uid=yasu,...
```

LDAP自体は自由度が高い設計になっているため、以前から特定の用途にしか使えない設計のアプリケーションは存在していました。

しかしADの普及によって、BIND DN、BIND Passwordの入力を強制するアプリケーションが増えた印象があります。

情報セキュリティの観点からはAnonymous BINDを許可する容易に表層的な情報を収集されてしまうため、企業のように誰が情報にアクセスをしたか記録しなければいけない状況では望ましくないことは事実です。

一方で無制限にBINDを試みるブルートフォースアタックなどの不適切な利用をログファイルなどから検出する必要があることは、どのような利用形態でも必要で、Simple/SASL BINDであれば安全であるということはほぼありません。

なによりも個別にBIND用のIDを発行したり、権限を管理したりすることは面倒でコストもかかります。

実際にはほぼ不要にも関わらずAD連携をするために、そのような形態でLDAPサーバーを利用している環境もあると思います。

不特定多数の利用者が存在するWebアプリケーションの利用形態は不定にも関わらず、BIND DNの入力を強制するのは、世の中への啓蒙という意味があるとしても、少しやり過ぎだと思います。

実際は自分のDNでBINDすれば利用上は問題ないのですが、Kubernetesのようなサーバー上でアプリを稼動させ、不特定多数に利用してもらおうとすると自分の情報を登録しておきたくはなく、整合性が良くないのは事実です。

そのためOpen WebUIをAnonymous BINDでも利用できるようにすることにしました。

Open WebUIで利用しているPython3のldap3モジュール自体はAnonymous BINDにも当然対応しているため、接続時にBIND用のDNとPasswordを送信しないことで切り替えることができます。

https://ldap3.readthedocs.io/en/latest/bind.html

最終的に次のようにBIND DNに``ANONYMOUS``を指定することで目的の動作を達成しました。

![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/78296/1fe6b33c-c951-4df4-9626-fe3f30b07f26.png)

以下では変更箇所のポイントを残しておきます。

# 改造作業

面倒なことはしたくないので最小限の変更に留めることにします。

まずはGitHubからopen webuiのプロジェクトをcloneして必要な修正を行います。

```bash:
$ git clone https://github.com/open-webui/open-webui.git
cd open-webui/
```

理想的にはBIND DNの利用有無を確認するようなチェックボックスを作るか、内容が空であれば自動的にAnonymous BINDを選択するようにすれば良いのですが、今回はBIND DNにキーワードを入力させることで動作を変更することにしました。

```diff:変更箇所の差分
diff --git a/backend/open_webui/routers/auths.py b/backend/open_webui/routers/auths.py
index 06e506228..b1a8e7039 100644
--- a/backend/open_webui/routers/auths.py
+++ b/backend/open_webui/routers/auths.py
@@ -221,10 +221,10 @@ async def ldap_auth(request: Request, response: Response, form_data: LdapForm):
         )
         connection_app = Connection(
             server,
-            LDAP_APP_DN,
-            LDAP_APP_PASSWORD,
+            LDAP_APP_DN if LDAP_APP_DN != "ANONYMOUS" else "",
+            LDAP_APP_PASSWORD if LDAP_APP_DN != "ANONYMOUS" else "",
             auto_bind="NONE",
-            authentication="SIMPLE" if LDAP_APP_DN else "ANONYMOUS",
+            authentication="SIMPLE" if LDAP_APP_DN != "ANONYMOUS" else "ANONYMOUS",
         )
         if not connection_app.bind():
             raise HTTPException(400, detail="Application account bind failed")
```

これでldap3の仕様に従ってBIND DNとBIND Passwordを空文字にしました。

ただUI上では何等かのパスワード文字列を入力しなければ設定の保存ができないままです。

# コンテナの作成と実行

Dockerfileは既に含まれているので次のような手順でビルドします。

```
$ docker build . -t myopenwebui:latest --build-arg="USE_CUDA=true" --build-arg="USE_OLLAMA=true"
```

ビルドはGPUを搭載したWorkstation上で行っているため、そのまま実行します。

```
$ docker run -it  --gpus all  --rm -p 8088:8080 -e OLLAMA_API_BASE_URL=http://192.168.1.51:11434/api -v $(PWD)/open-webui:/app/backend/data --name open-webui myopenwebui:latest
```

これで自分の利用範囲では問題なく動作するようになりました。

## コンテナ・レジストリーへの登録

ローカルのコンテナ・レジストリを``harbor.example.com``とすると、次のようなコマンドで転送できます。
``yasu-abe``はHarbor上のProject名で、デフォルトの``docker.io``でいうところのログイン時に使用するIDになります。

```
$ docker tag myopenwebui:latest harbor.example.com/yasu-abe/myopenwebui:latest
$ docker push harbor.example.com/yasu-abe/myopenwebui:latest
```

実際には前後で、``docker login harbor.example.com``(実行後は``docker logout``)を実行する必要があるでしょう。

``docker.io``の場合には次のような``tag``, ``push``コマンドになります。

```
$ docker tag myopenwebui:latest docker.io/yasuhiroabe/myopenwebui:latest
$ docker push docker.io/yasuhiroabe/myopenwebui:latest
```

最終的にはKubernetes上で動作させて、GPUが稼動するWorkstationのOllamaにリモートで接続し、一部の利用者に公開する予定です。

以上
