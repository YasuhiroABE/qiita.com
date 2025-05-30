---
title: Gitlab(v17)のリストアに失敗したので調べてみた
tags:
  - GitLab
private: false
updated_at: '2025-05-25T21:27:26+09:00'
id: 82110434907ce2050e71
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

GitlabのPostgreSQLのバージョンをv14からv17にアップグレードする際に、DBのテーブル情報とGitLabのバージョンで不整合が発生してしまいました。

:::note
Gitlabのリストア時にはPostgreSQLのバージョンは同じである必要はありませんが、Gitlabのバージョンは完全に一致(identical)している必要があります。

今回はそこを失念してGitlabのバージョンも変更してしまったため、リストアタスクが正常に実行できない状況になってしまったことがきっかけです。
:::


別のクラスターでGitlabのバージョンはそのままPostgreSQLをv14からv17に更新したところ、Repositoryが空になる現象に遭遇しました。

発生条件は不明ですが、Gitlab v16の時には正常に完了したリストア手順だけでは対応できない状況に遭遇したので顛末をまとめておくことにしました。

# エラーの状況

PVCも再作成してバックアップから戻してやりなおそうと思ったのですが、次のようなメッセージが出てリストアタスクがうまく完了しません。

```
Caused by:                                                                                                                      
ActiveRecord::StatementInvalid: PG::ConnectionBad: PQconsumeInput() server closed the connection unexpectedly                   
        This probably means the server terminated abnormally                                                                    
        before or while processing the request.
```

このエラーに続いて次のようなエラーも出力されています。

```
Tasks: TOP => gitlab:backup:restore
(See full trace by running task with --trace)
root@gitlab-g7jtb:/home/git/gitlab# E0523 18:27:20.512574  989608 v2.go:129] "Unhandled Error" err="next reader: local error: tls: bad record MAC"
                  E0523 18:27:20.512574  989608 v2.go:150] "Unhandled Error" err="next reader: local error: tls: bad record MAC"
error: error reading from error stream: next reader: local error: tls: bad record MAC
$
```

Gitlabのリストアは成功するものだと思っていたので顛末をメモしておきます。

また途中ではGitlab自体は正常に起動するものの、リポジトリにファイルが含まれていない状態にもなりました。

![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/78296/9a5c9663-48f6-4327-9114-9305aa8c6651.png)

これは後述するように再度``SKIP=db``をリストアコマンドに指定して回復しています。

# 参考資料

Gitlabのリストアタスクは次の記事に掲載しています。

https://qiita.com/YasuhiroABE/items/58e1e4b0f600d29e6166

# 現在の環境

Gitlabのリストアでは、Gitlabのバージョンはバックアップを取得した時と同一でなければいけません。

PostgreSQLのバージョンは新しくしています。障害の調査で同じPostgreSQLのバージョンでも確認していますが、現象に違いはありませんでした。

* Kubernetes v1.31.4
* Gitlab v17.11.2 - [sameersbn/docker-gitlab版](https://github.com/sameersbn/docker-gitlab)
* PostgreSQL 17.5 - kkimurak/sameersbn-postgresql:17-20250522

## バックアップを取得した環境

* Kubernetes v1.31.4
* Gitlab v17.11.2 - [sameersbn/docker-gitlab版](https://github.com/sameersbn/docker-gitlab)
* PostgreSQL 14 - sameersbn/postgresql:14-20230628

# 検証作業

エラーを再現しながら原因を絞りこんでいきました。

## バックアップイメージの健全性の検証

まず他の日付のバックアップイメージを利用して同様のエラーになることを確認しています。

想定される原因は次のようになります。

1. バックアップイメージが全滅
2. リストア環境かリストア工程が、何等かの理由で不整合を起している

バックアップイメージが全滅している可能性は過去の経験からも低いと思われたので、なんとかリストアする方向で進めます。

## バックアップを取得した環境と同様にする

PostgreSQLのPVCを作り直してから、元のv14にバージョンを落して再起動します。

この状態でリストアを試みたものの、最終的にメッセージは少し違いますが、同様のエラーで停止しました。

```
/home/git/gitlab/vendor/bundle/ruby/3.2.0/gems/rake-13.0.6/exe/rake:27:in `<top (required)>'
/usr/local/bin/bundle:25:in `load'
/usr/local/bin/bundle:25:in `<main>
Tasks: TOP => gitlab:backup:restore
(See full trace by running task with --trace)
$
```

この状態ではGitlabへWebブラウザからアクセスしても通常のページは表示されませんでした。

##  DB以外の部分をリストアしてみる

``gitlab-rc.yml``ファイルの``image:``行と同じレベルに``args: ["sh","-c","--","while true; do sleep 30; done"]``の行を追加してから反映し、gitlabのpodを再起動し、サーバープロセスが起動されないようにします。

次にGitlabのバックアップイメージを``kubectl cp``コマンドで退避してから、GitlabのPVCを作り直してまっさらな状態にします。

作業を簡単にするために次のようなShell関数を利用しています。

```bash:gitlabのバックアップイメージを操作するためのbash関数
function gitlab_backup_list {
  name=$(get_gitlab_podname)
  sudo kubectl -n gitlab exec -it "${name}" -- ls /home/git/data/backups/
}

function gitlab_backup_get {
  name=$(get_gitlab_podname)
  sudo kubectl -n gitlab cp "${name}":/home/git/data/backups/"$1" backups/"$1"
}

function gitlab_backup_put {
  name=$(get_gitlab_podname)
  sudo kubectl -n gitlab cp "$1" "${name}":/home/git/data/backups/"$1"
}
```

何回か繰り返しリストアを試してみるとテーブルに何か不具合はあっても、ほぼほぼ復元できているようにみえます。

GitlabはWebブラウザからアクセスするとファイルが復元されていない状態でした。

よくメッセージをみると、DBのリストア→Repositoryのリストアという流れの最後でDB接続関連のエラーが出ているので、後半のRepositoryのリストアだけを実行してみます。

```
root@gitlab-7xfmt:/home/git/gitlab# /sbin/entrypoint.sh app:rake gitlab:backup:restore SKIP=db BACKUP=1747843231_2025_05_22_17.11.2
```

この後、``gitlab-rc.yml``から``args: ["sh","-c","--","while true; do sleep 30; done"]``の行をコメントにして反映させて、``kubectl -n gitlab delete pod ...``でGitlabのPodを再起動しました。

こうするとWebブラウザからのアクセスはGitリポジトリのファイル以外は正常にアクセスでき動作して復旧することができました。

# まとめ

ここまでの作業で無事に復旧し、gitリポジトリからの``git pul``でも問題なくファイルがダウンロードできました。

1. ``args: [...]``をgitlab-rc.ymlファイルで有効にし、反映後再起動する
2. リストアコマンドの実行 
3. 再度、同じリストアコマンドに``SKIP=db``を追加して実行
4. ``# args: [...]``とコメントに変更した``gitlab-rc.yml``ファイルをapplyしてからPodの再起動
5. 稼動確認

Gitlabはバックアップさえきちんと保存しておけば大丈夫だとは思っていましたが、今回は少し手間取りました。

# PostgreSQL 14から17への自動マイグレーション

``postgresql-rc.yml``ファイルでimage:行を変更してv14からv17に変更し、Podをリスタートしてからログをよく確認するとマイグレーションタスクが自動的に実行されています。

```text:
Initializing datadir...
Initializing certdir...
Initializing logdir...
Initializing rundir...
Setting resolv.conf ACLs...
Initializing database...
‣ Migrating PostgreSQL 14 data to 17...
‣ Installing PostgreSQL 14...
W: http://apt.postgresql.org/pub/repos/apt/dists/jammy-pgdg/InRelease: Key is stored in legacy trusted.gpg keyring (/etc/apt/trusted.gpg), see the DEPRECATION section in apt-key(8) for details.
debconf: delaying package configuration, since apt-utils is not installed
‣ Migration in progress. Please be patient...Performing Consistency Checks
-----------------------------
Checking cluster versions                                     ok
Checking database user is the install user                    ok
Checking database connection settings                         ok
Checking for prepared transactions                            ok
Checking for contrib/isn with bigint-passing mismatch         ok
Checking data type usage                                      ok
Creating dump of global objects                               ok
...
```

Gitlabのpodを停止した状態で、PostgreSQLをv14からv17へこの方法でマイグレーションしてみましたが、Gitlabを起動しても正常には起動完了しませんでした。

ログには次のような内容が繰り返し出力されている状況です。

```
2025-05-24 17:21:08,457 INFO spawned: 'puma' with pid 16403
2025-05-24 17:21:09,459 INFO success: puma entered RUNNING state, process has stayed up for > than 1 seconds (startsecs)
2025-05-24 17:21:14,310 INFO exited: sidekiq (exit status 1; not expected)
2025-05-24 17:21:15,313 INFO spawned: 'sidekiq' with pid 16409
```

``SKIP=db``などを付けて実行してみても解決せず引き続き同様の症状のままです。

コンテナの中に入ってログを確認すると以前遭遇した時と同じようなメッセージが出力されたままとなっています。

```
time="2025-05-24T17:29:02+09:00" level=error correlation_id= duration_ms=0 error="badgateway: failed to receive response: dial unix /home/git/gitlab/tmp/sockets/gitlab.socket: connect: no such file or directory" method=GET uri=
 ```
 
最終的にv17に更新した時のテーブルの自動マイグレーションでは解決せず、再度リストア作業を実行することで解決しました。
 
以上

