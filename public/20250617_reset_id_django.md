---
title: DjangoでDBに登録されたデータのIDをリセットしてみた
tags:
  - Django
  - fobi
private: false
updated_at: '2025-06-17T17:03:41+09:00'
id: f577c031b591318d64d4
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

DjangoとFobiを利用して簡易的な帳票アプリを開発・利用しています。

https://qiita.com/YasuhiroABE/items/259f9a471e1b594ffdce

データは永続的にオンラインに置く必要がないため、年度末などのタイミングで保存されたデータをDjangoのAdmin Consoleから定期的に削除しています。

しかしIDは自動的にインクリメントされるためテーブル自体を再作成でもしない限りは最初のデータが1000番から始まるといった事になってしまいます。

個人的にはそういうものだろうと思うのですが、気にする方もいるということで、今回はテーブルを初期化することにしました。

# Djangoでの標準的な対応方法

調べてみると利用しているDBのテーブルを直接操作するようです。

機能を提供しても混乱するだけなのかもしれませんが、ALTER TABLEなどは手動で実行するには怖いコマンドなので自動でしてくれると良いのになと思ったところです。

# Kubernetes上で稼動するMySQLへのrootアクセス

今回はMySQLを利用しているので、まずKubernetesのコンテナ内部に入ります。

``kubectl exec``を利用してMySQLのインスタンスにアクセスします。

```bash:
$ kubectl exec -it $(kubectl get pod -l tier=mysql -o jsonpath={.items[0].metadata.name}) -- bash

## MySQLのコンテナの中から実行
$ mysql -u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE}
```

mysqlコマンドの``-p``オプションは空白を置いてしまうとうまく動作しないのですが、よく忘れてしまいます。

# テーブルの初期化

MySQLの``TRUNCATE TABLE``ステートメントはテーブルの中身を空にするという目的で開発されています。

https://dev.mysql.com/doc/refman/8.0/ja/truncate-table.html

これを使ってAdmin Consoleからデータを全て削除した上で操作を行います。

```mysql:
mysql> truncate table db_store_savedformdataentry ;
Query OK, 0 rows affected (1.98 sec)
```

これで問題なくテーブルを初期化することができ、テストした範囲では問題なく利用できました。

# さいごに

Kubernetesを利用しているのでDBのドロップ・再作成はそれほど難しくないですが、これまで問題なく動いていたシステムの再作成は少し躊躇します。

FOBIのDB Storeが管理するテーブル1つの``TRUNCATE TABLE``で済むのであれば、気楽に実行できるので助かります。

以上
