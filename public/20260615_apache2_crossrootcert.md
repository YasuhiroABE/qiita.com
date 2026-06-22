---
title: Apache2をTLSとHTTP/2に対応させてみた
tags:
  - Ubuntu
  - apache2
  - TLS
  - http2
private: false
updated_at: '2026-06-22T14:07:10+09:00'
id: b046a7f4cfe0cd29acc8
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

古くからMediawikiを利用しているUbuntuサーバーでは、Apache2を利用してphp_module(libphp8.3.so)を利用したPHPの上で動作させています。

TLSの証明書を更新するタイミングで中間CA局証明書(intermediate certificate)に加えてクロスルート証明書を利用するようになったので、2つのCA情報を更新する必要が出てきました。

Mediawiki関連の記事の中ではテスト用の設定だけを紹介していたので、本番で利用しているMediawikiのTLS設定を載せておきます。

https://qiita.com/YasuhiroABE/items/7c46a65db8f0aa2f91cd

# これまで利用していた証明書の構成

これまで利用していた中間CA局の証明書は次のようになっています。

```bash:
$ openssl x509 -text -in nii-odca4g7rsa.cer | egrep 'Issuer|Subject:'

Issuer: C=JP, O=SECOM Trust Systems CO.,LTD., OU=Security Communication RootCA2
Subject: C=JP, O=SECOM Trust Systems CO.,LTD., CN=NII Open Domain CA - G7 RSA
```

```plantuml

node "クライアントが知っているCA" {
  agent "OU=Security Communication RootCA2"
}

node "添付が必要な証明書" {
  agent "CN=NII Open Domain CA - G8 RSA"
  agent "Certificate"
}

"OU=Security Communication RootCA2" -> "CN=NII Open Domain CA - G8 RSA"

"CN=NII Open Domain CA - G8 RSA" -> "Certificate" : "発行"
```

このIssuerはトップレベルのCA局になっていて一般的な``ca-certificates``パッケージに含まれています。

```bash:Ubuntuのca-certificatesパッケージに含まれるCA局の情報
$ ls -al /etc/ssl/certs/|grep RootCA2

lrwxrwxrwx 1 root root     69 May  1  2018 Security_Communication_RootCA2.pem@ -> /usr/share/ca-certificates/mozilla/Security_Communication_RootCA2.crt
lrwxrwxrwx 1 root root     34 May  1  2018 cd58d51e.0@ -> Security_Communication_RootCA2.pem
```

これらの情報は一般的なWebブラウザと同様だと思って問題ないので、これまでは中間CA局の証明書だけを追加でサーバーに登録していました。

Nginxでは中間CA局の証明書はサーバーの証明書に連結するようになっています。

Apache2の場合は複数の設定方法があり、現在では非推奨の``SSLCerticiateChainFile``を使っていたため、今回はNginxと同様の設定に変更することにしました。

## 新しい証明書の構造

新しいTLS証明書は次のような中間CA局証明書を利用しています。

```bash:
$ openssl x509 -text -in nii-odca4g8rsa-pem.cer | egrep 'Issuer|Subject:'
Issuer: C=JP, O=SECOM Trust Systems Co., Ltd., CN=SECOM TLS RSA Root CA 2024
Subject: C=JP, O=SECOM Trust Systems Co., Ltd., CN=NII Open Domain CA - G8 RSA
```

このIssuer(発行元)になっているCA局(〜Root CA 2024)がこれまでの中間CA局のように〜RootCA2によって署名されています。

```bash:
$ openssl x509 -text -in tlsrsarootca2024cross-pem.cer | egrep 'Issuer|Subject:'
Issuer: C=JP, O=SECOM Trust Systems CO.,LTD., OU=Security Communication RootCA2
Subject: C=JP, O=SECOM Trust Systems Co., Ltd., CN=SECOM TLS RSA Root CA 2024
```

Webブラウザが知っているCA局情報は``〜RootCA2``だけなので、``〜G8 RSA``と``〜Root CA 2024``の2つの証明書を合わせて提供する必要があります。

```plantuml

node "クライアントが知っているCA" {
  agent "OU=Security Communication RootCA2"
}

node "添付が必要な証明書" {
  agent "CN=SECOM TLS RSA Root CA 2024"
  agent "CN=NII Open Domain CA - G8 RSA"
  agent "Certificate"
}

"クライアントが知っているCA" -[hidden]down- "添付が必要な証明書"

"OU=Security Communication RootCA2" -> "CN=SECOM TLS RSA Root CA 2024"
"CN=SECOM TLS RSA Root CA 2024" -> "CN=NII Open Domain CA - G8 RSA"

"CN=NII Open Domain CA - G8 RSA" -> "Certificate" : "発行"
```

## 古い設定方法

これまで次のような設定ファイルを利用していました。

```apache:古いsite-enabled/www-ssl.confファイルの抜粋
        #   SSL Engine Switch:
        #   Enable/Disable SSL for this virtual host.
        SSLEngine on

        #   A self-signed (snakeoil) certificate can be created by installing
        #   the ssl-cert package. See
        #   /usr/share/doc/apache2/README.Debian.gz for more info.
        #   If both key and certificate are stored in the same file, only the
        #   SSLCertificateFile directive is needed.
        SSLCertificateFile    /usr/share/ca-certificates/local/www.example.com.cer
        SSLCertificateKeyFile /etc/ssl/private/www.example.com.key

        #   Server Certificate Chain:
        #   Point SSLCertificateChainFile at a file containing the
        #   concatenation of PEM encoded CA certificates which form the
        #   certificate chain for the server certificate. Alternatively
        #   the referenced file can be the same as SSLCertificateFile
        #   when the CA certificates are directly appended to the server
        #   certificate for convinience.
        SSLCertificateChainFile /usr/share/ca-certificates/local/nii-odca4g7rsa.cer
```

``SSLCertificateChainFile``は2.4.8以降は非推奨扱いですが、Ubuntu 24.04ではまだ利用できます。

非公式のドキュメントによっては廃止されたと書かれているものもありますが、最新版のsslモジュールにもコードは含まれているので利用できるはずです。

各種証明書はサーバー証明書に含めることでコントロールポイントが一箇所に集約できるため、主に管理上の理由から今回変更することにしました。

# 変更した設定ファイル

設定ファイルの変更はシンプルで、``SSLCertificateChainFile``をコメントアウトします。

```apache:古いsite-enabled/www-ssl.confファイルの抜粋
        #   SSL Engine Switch:
        #   Enable/Disable SSL for this virtual host.
        SSLEngine on

        #   A self-signed (snakeoil) certificate can be created by installing
        #   the ssl-cert package. See
        #   /usr/share/doc/apache2/README.Debian.gz for more info.
        #   If both key and certificate are stored in the same file, only the
        #   SSLCertificateFile directive is needed.
        SSLCertificateFile    /usr/share/ca-certificates/local/www.example.com.cer
        SSLCertificateKeyFile /etc/ssl/private/www.example.com.key

        #   Server Certificate Chain:
        #   Point SSLCertificateChainFile at a file containing the
        #   concatenation of PEM encoded CA certificates which form the
        #   certificate chain for the server certificate. Alternatively
        #   the referenced file can be the same as SSLCertificateFile
        #   when the CA certificates are directly appended to the server
        #   certificate for convinience.
        #SSLCertificateChainFile /usr/share/ca-certificates/local/nii-odca4g7rsa.cer
```

## 証明書ファイルへのCA局情報の統合

同時に複数の証明書を変更するため、次のようなスクリプトを実行しています。

```bash:複数のcerファイルから中間、クロス証明書を含む*.combined.cerを出力するbashスクリプト
for file in *example.com.cer
do
  cat $file nii-odca4g8rsa-pem.cer tlsrsarootca2024cross-pem.cer > $(basename $file .cer).combined.cer
done
```

生成された``www.example.com.combined.cer``ファイルをansibleで元ファイルに指定して、サーバーの``/usr/share/ca-certificates/local/www.example.com.cer``にコピーしています。

連結の順序はnginxでもapache2でも同様で、下位から上位に向かって、サーバー → 中間CA → クロスルートCA の順で連結する必要があります。

## Apache2のHTTP/2への切り替え作業

TLSの設定を見直すタイミングでHTTP/2にも対応させました。

Ansibleでは次のようなコマンドを実行させるようにしています。

```bash:ansibleで実行させたコマンド群
# /usr/sbin/a2dissite -q 000-default
# /usr/sbin/a2enmod -q ssl
# /usr/sbin/a2enmod -q rewrite
# /usr/sbin/a2enmod -q ldap
# /usr/sbin/a2dismod -q php8.3
# /usr/sbin/a2dismod -q mpm_prefork
# /usr/sbin/a2enmod -q mpm_event
# /usr/sbin/a2enmod -q proxy_fcgi setenvif
# /usr/sbin/a2enmod -q http2
# /usr/sbin/a2enconf -q php8.3-fpm
# /usr/sbin/a2ensite -q example.com
# /usr/sbin/a2ensite -q example.com-ssl
```

設定ファイルを変更せずとも``mods-enabled/http2.conf``が配置されるため、HTTP/2は自動的に有効になります。

ただ非TLS版の``h2c``モードも含まれていて、これは実質的に意味がないので気になる場合は設定ファイルから削除しても良いかもしれません。

# 変更作業の際に遭遇したトラブル

問題が発生したので、その顛末をまとめておきます。

## 設定ミスによるエラーメッセージ

方法を検討していた時に``SSLCertificateChainFile``を引き続き使用しようとして、次のようなエラーに遭遇しました。

これは2つにまとめたと思っていた証明書ファイルの内容に問題があってサーバーは起動したものの、期待した動作にはならなかったものです。

```text:curl -v https://www.example.com/ のエラーメッセージ
* Host www.example.com:443 was resolved.
* IPv6: (none)
* IPv4: 192.168.100.120
*   Trying 192.168.100.120:443...
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* SSL Trust Anchors:
*   CAfile: /etc/ssl/certs/ca-certificates.crt
*   CApath: /etc/ssl/certs
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / x25519 / RSASSA-PSS
* ALPN: server accepted http/1.1
* Server certificate:
*   subject: C=JP; O=Example COM; CN=www.example.com
*   start date: Jun 12 01:28:07 2026 GMT
*   expire date: Dec 27 01:28:07 2026 GMT
*   issuer: C=JP; O="SECOM Trust Systems Co., Ltd."; CN=NII Open Domain CA - G8 RSA
*   Certificate level 0: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type RSA (4096/152 Bits/secBits), signed using sha384WithRSAEncryption
*   subjectAltName: "www.example.com" matches cert's "www.example.com"
* SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)
* closing connection #0
```

このエラーになってもサーバーは起動するので、``curl -k``のように証明書の検証を省略した場合には正しく動作します。

端末に中間局CA証明書などをインストールすれば問題なく閲覧できるのですが、当然その他のユーザーはエラーになってしまうため注意が必要です。

またWindowsでESETのインターネット保護機能を使っている場合には、ESETはエラーにならずに問題なく閲覧できてしまったので、注意が必要だと感じました。

最終的に検証チェインが正常に動作するように1つのファイルに必要な情報をまとめて、エラーは止み問題は解決しました。

## php-fpmのパフォーマンスチューニング

Ubuntu 24.04でPHP 8.3を利用していますが、デフォルトのphp-fpmのパラメータは少し保守的のようです。

設定は``/etc/php/8.3/fpm/pool.d/www.conf``に記載されていて、主なパラメータは次のようになっていました。

```apache:初期値
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

現在は次のように設定を変更しています。

```apache:変更後の設定値
pm = dynamic
pm.max_children = 25
pm.start_servers = 4
pm.min_spare_servers = 4
pm.max_spare_servers = 10
```

わずかな変更ですが、体感的にはパフォーマンスが向上したと感じていますが、Uptime Kumaのログでは変化は検出されていません。

# さいごに

Apache2(Apache HTTPd)は古くからあるために、その設定方法は良く知られています。

しかしHTTP/2などの新しい機能を有効にするための手順はよく整理されている一方で、慣れていないこともありnginxと比べると複雑に感じてしまいます。

Apache2はPHPを利用するために利用してきましたが、php-fpmを有効化した現在では、全てをnginxにしても問題ない環境になってきてしまいました。

Kubernetesのフロントエンドなどでnginxを使う場面は今後も広がっていくことが想定されますが、Apache2を利用する場面は減っていくのかもしれません。


