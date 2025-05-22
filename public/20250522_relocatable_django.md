---
title: RelocatableなDjangoアプリを作る
tags:
  - Django
  - RelocatableApp
private: false
updated_at: '2025-05-22T12:57:24+09:00'
id: 7652a3388c0c22321939
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

DjangoフレームワークはORM機構の他に管理コンソールなど、データ管理についての包括的な仕組みを備えています。

またPythonで記述できることからつい小さなアプリケーションを量産してしまう良い意味での手軽さも備えていると思います。

単一のWebサイトの中に複数のWebアプリケーションを含める場合にはReverse Proxyを利用するわけですが、この時にURLの変換もする

# Reverse ProxyサーバーによるURL変換の問題

Webアプリケーションを作成する時にJinja2テンプレートを含むHTMLファイル内でのリソース参照を全て相対パスで記述する必要があります。

この時に外部ライブラリを利用している時に問題が生じる可能性があります。

外部ライブラリも同様に全てを相対パスで記述してくれれば問題ないのですが、それが徹底できない場合に到達できないURLを返却する可能性が高まります。

原理的に他者を完全にコントロールすることはできないので、Reverse Proxyの構成ルールとしては、入力として受け付けるURLパス(context)とProxy先のURLパス(context)は同じであるべきです。

```nginx:問題となる可能性のあるProxyルールの例
    location /my-app/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
```

# RelocatableなWebアプリケーションとは

Webアプリケーションを作成する時にURLパス上のどこにでも配置できるように、あらかじめ仕組みを入れておくわけですが、フレームワークとして対応しているものは実はあまり多くありません。

代表的なものはJ2EE(Java2 Enterprise Edition)ですが、Tomcatをコンテナとして利用している場合にはWARファイルだけを構成すれば良いで、このルールを適用しなくても自由に作成が可能です。

そもそもWEB-INF/application.xmlはオプションなので、WARファイルだけで動作させることができるので、J2EEなら大丈夫というわけでもありませんが、一応仕様として対応しています。

## Djangoで設定で反応するURLを変更する

Djangoに限らずLL言語では起動時にroot-context(基底となるパス, e.g., /my-app)を追加するようなロジックを記述するだけで、ほぼほぼ対応できると思います。

```python:top-directory(myapp/)に配置しているurls.pyファイルから抜粋
context_root = settings.CONTEXT_ROOT[1:]

urlpatterns = [
    ....
    path('%sadmin/' % (context_root), admin.site.urls),
    path('%saccounts/' % (context_root), include('django_registration.backends.activation.urls')),
    path('%saccounts/' % (context_root), include('django.contrib.auth.urls')),
    path(context_root, MyAppMainView.as_view(), name='top'),
	path('%sdownload/' % (context_root), include('myapp.download.urls')),
    path('%sfobi/' % (context_root), include('fobi.urls.class_based.view')),
    ....
]
```

特別なことはなにもしていませんが、djangoは良くできているのでサブディレクトリのurls.pyまで変更する必要はありません。

## Reverse Proxyサーバーで対応できないのか

残念ながらブラウザからアクセスがあった時に、到達先のURLとRequest内容を調整するのが仕事なので、戻されるデータの内容を書き換えたりはしてくれません。

SquidなどのFrontend Proxyサーバーには組織内からのアクセスを禁止したい外部サイトを内部サイトに誘導するといった目的でレスポンスに含まれるURLを書き換える仕組みが備わっている場合があります。

ただセキュリティ向上などが目的で、一般的な使い方とまではいえないと思います。

# Djangoの使い方

RDBMSを必要とする要件であれば、Djangoで効率的にアプリケーションを開発できるスキルを習得して、積極的にDjangoを利用するべきだと思います。

個人的にはNoSQLを利用する頻度が高いため、Djangoを利用する場面は限定的ですが、典型的な用途には良いと思います。

ただ機能が豊富で広く利用されているため脆弱性対策はきちんと行う必要があります。頻繁にライブラリのバージョンを上げていく必要はあるでしょう。

またMySQLやPostgreSQLなどは計算機資源を要求するミドルウェアです。

クラウド環境では簡単にDBのインスタンスを生成することができますが(Provisioning)、規模が小さいWebアプリケーションはできるだけ共有のDBサーバーを構築して区画を分けて利用する方が効率は高まります。

## Djangoアプリケーションが要求する資源

DjangoはPythonベースだし、そんなに重くないでしょうと思うかもしれませんが、Kubernetesで確認すると案外Podの消費メモリが大きかったりします。

```bash:"kc"はkubectlコマンド+αへのaliasです。
$ kc top pod
NAME                      CPU(cores)   MEMORY(bytes)
mysql-5c4658ccd6-ttmt6    4m           481Mi
redis-98cfcdffd-9vdbp     1m           14Mi
webapp-57dd4b8b5c-bvs92   0m           427Mi
webapp-57dd4b8b5c-nm6nz   0m           427Mi
webapp-57dd4b8b5c-rvg6n   0m           427Mi
webapp-57dd4b8b5c-s6kjq   0m           426Mi
```

さすがにこれは大きすぎるので、別のクラスターで動かしている同じDjangoアプリケーションの再起動からあまり時間が経過していないPodを調べてみると90MiB前後になっています。

```bash:別クラスターでの同じアプリケーションの稼動状況
NAME                     CPU(cores)   MEMORY(bytes)
mysql-6d6698b4dc-5prjv   8m           433Mi
redis-7c86d76796-2qdx6   4m           3Mi
webapp-6cf5fd9d9-2zm8q   4m           90Mi
webapp-6cf5fd9d9-sbstk   3m           91Mi
webapp-6cf5fd9d9-zm4kh   1m           91Mi
```

比較のためK8sクラスター全体のPodについて眺めてみると、Ruby/Sinatraで構成しているアプリケーションの中で一番メモリを使用しているのは次のような状況です。

```bash:Ruby/Sinatraで構成しているアプリケーション
$ sudo kubectl top pod --all-namespaces | sort -k4 -n | grep web
...
solr                       webapi-7bb9fc5fcf-pqzzb                              0m           44Mi
maildir                    maildir-webapi-5b8f978768-jpnnd                      14m          47Mi
scopus                     scopus-webapi-688dddcd7d-zrvmw                       0m           50Mi
...
```

もちろん使い方によるわけですが、あまり特別なことはしていません。

あまり使用メモリが大きいようであればメモリリークや適切に管理されていないグローバルスコープのオブジェクトがありそうですが、いまのところはobjgraphなどを使ってテストしている範囲では問題は見つけられていません。

