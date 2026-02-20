---
title: 時々Ubuntuサーバーのsshが自動更新に失敗している
tags:
  - Ubuntu
  - SSH
  - kubernetes
private: false
updated_at: '2025-09-01T09:41:37+09:00'
id: 711785ad5b1e0d71ff1a
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

基本的に自分が運用するサーバー類はUbuntuを利用していて、cron-aptによって自動的にパッケージを適用し、crontabによって定期的にリスタートを行っています。

主にKubernetesのクラスターが時々SSH接続を拒否するようになるので、現象が発生した時の状況をまとめています。

:::note
原因は最後にまとめていますが、sshdプロセスを監視していたことだと考えています。

パッケージの更新処理の最中にプロセスが起動していたことが原因だと思われるため、監視スクリプトに遅延処理を加えて運用しています。
:::

## ログメッセージ

現象を確認した時点での状況をまとめています。

まず、``sudo apt install -f``で修正しようとすると次のようなメッセージが出力されます。

```bash:apt install -f実行時の出力
$ sudo apt install -f
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
1 not fully installed or removed.
After this operation, 0 B of additional disk space will be used.
Setting up openssh-server (1:9.6p1-3ubuntu13.13) ...
Could not execute systemctl:  at /usr/bin/deb-systemd-invoke line 148.
dpkg: error processing package openssh-server (--configure):
 installed openssh-server package post-installation script subprocess returned error exit status 1
 Errors were encountered while processing:
 openssh-server
needrestart is being skipped since dpkg has failed
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

``systemctl status ssh.service``の出力は次のようになっています。

```bash:systemctl statusの出力
$ sudo systemctl status ssh.service
○ ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; enabled; preset: enabled)
     Active: inactive (dead)
TriggeredBy: × ssh.socket
       Docs: man:sshd(8)
             man:sshd_config(5)
   Main PID: 3433
      Tasks: 1 (limit: 38387)
     Memory: 5.6M (peak: 7.3M)
        CPU: 648ms
     CGroup: /system.slice/ssh.service
             └─3433 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"

Jul 17 06:01:21 u109ls03 systemd[1]: Dependency failed for ssh.service - OpenBSD Secure Shell server.
Jul 17 06:01:21 u109ls03 systemd[1]: ssh.service: Job ssh.service/start failed with result 'dependency'.
Jul 30 06:50:35 u109ls03 systemd[1]: Dependency failed for ssh.service - OpenBSD Secure Shell server.
Jul 30 06:50:35 u109ls03 systemd[1]: ssh.service: Job ssh.service/start failed with result 'dependency'.
```

``/usr/sbin/sshd``は既に置き換えられているので、**(deleted)** となっています。

古いプロセスが残存して停止できない状況であることは分かりますが、それ以上のことは分かっていません。

```bash:lsofの出力
~$ sudo lsof -p 3433
COMMAND  PID USER   FD   TYPE             DEVICE SIZE/OFF     NODE NAME
sshd    3433 root  cwd    DIR                8,2     4096        2 /
sshd    3433 root  rtd    DIR                8,2     4096        2 /
sshd    3433 root  txt    REG                8,2   921416 10355968 /usr/sbin/sshd (deleted)
sshd    3433 root  DEL    REG                8,2          10360544 /usr/lib/x86_64-linux-gnu/libc.so.6
sshd    3433 root  mem    REG                8,2  5305304 10357109 /usr/lib/x86_64-linux-gnu/libcrypto.so.3
sshd    3433 root  DEL    REG                8,2          10360568 /usr/lib/x86_64-linux-gnu/libresolv.so.2
sshd    3433 root  mem    REG                8,2    22600 10358645 /usr/lib/x86_64-linux-gnu/libkeyutils.so.1.10
sshd    3433 root  DEL    REG                8,2          10359442 /usr/lib/x86_64-linux-gnu/libkrb5support.so.0.1
sshd    3433 root  DEL    REG                8,2          10359465 /usr/lib/x86_64-linux-gnu/libk5crypto.so.3.1
sshd    3433 root  mem    REG                8,2   625344 10355300 /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0.11.2
sshd    3433 root  mem    REG                8,2    26848 10355994 /usr/lib/x86_64-linux-gnu/libcap-ng.so.0.0.0
sshd    3433 root  mem    REG                8,2   113000 10359519 /usr/lib/x86_64-linux-gnu/libz.so.1.3
sshd    3433 root  mem    REG                8,2    18504 10355571 /usr/lib/x86_64-linux-gnu/libcom_err.so.2.1
sshd    3433 root  DEL    REG                8,2          10355627 /usr/lib/x86_64-linux-gnu/libkrb5.so.3.3
sshd    3433 root  DEL    REG                8,2          10355230 /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2
sshd    3433 root  mem    REG                8,2   174472 10360249 /usr/lib/x86_64-linux-gnu/libselinux.so.1
sshd    3433 root  DEL    REG                8,2          10355848 /usr/lib/x86_64-linux-gnu/libpam.so.0.85.1
sshd    3433 root  mem    REG                8,2   133200 10355210 /usr/lib/x86_64-linux-gnu/libaudit.so.1.0.0
sshd    3433 root  mem    REG                8,2    44064 10356954 /usr/lib/x86_64-linux-gnu/libwrap.so.0.7.6
sshd    3433 root  mem    REG                8,2   198664 10360321 /usr/lib/x86_64-linux-gnu/libcrypt.so.1.1.0
sshd    3433 root  DEL    REG                8,2          10360341 /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
sshd    3433 root    0r   CHR                1,3      0t0        5 /dev/null
sshd    3433 root    1u  unix 0xffffa01b640bf000      0t0    15093 type=STREAM (CONNECTED)
sshd    3433 root    2u  unix 0xffffa01b640bf000      0t0    15093 type=STREAM (CONNECTED)
sshd    3433 root    3u  IPv6               7880      0t0      TCP *:ssh (LISTEN)
```

``journalctl -xe``の出力は次のようになっています。

```bash:
$ sudo journalctl -xe
░░ Defined-By: systemd
░░ Support: http://www.ubuntu.com/support
░░
░░ The unit ssh.socket has entered the 'failed' state with result 'resources'.
Aug 08 02:13:53 u109ls03 systemd[1]: Failed to listen on ssh.socket - OpenBSD Secure Shell server socket.
░░ Subject: A start job for unit ssh.socket has failed
░░ Defined-By: systemd
░░ Support: http://www.ubuntu.com/support
░░
░░ A start job for unit ssh.socket has finished with a failure.
░░
░░ The job identifier is 1629462 and the job result is failed.
Aug 08 02:13:53 u109ls03 systemd[1]: Dependency failed for ssh.service - OpenBSD Secure Shell server.
░░ Subject: A start job for unit ssh.service has failed
░░ Defined-By: systemd
░░ Support: http://www.ubuntu.com/support
░░
░░ A start job for unit ssh.service has finished with a failure.
░░
░░ The job identifier is 1629459 and the job result is dependency.
Aug 08 02:13:53 u109ls03 systemd[1]: ssh.service: Job ssh.service/start failed with result 'dependency'.
Aug 08 02:13:53 u109ls03 sudo[2460912]: pam_unix(sudo:session): session closed for user root
Aug 08 02:13:55 u109ls03 kubelet[1985384]: I0808 02:13:55.018378 1985384 kubelet.go:2414] "SyncLoop UPDATE" source="api" pods=["dex/>
Aug 08 02:14:04 u109ls03 sudo[2461110]:   ubuntu : TTY=pts/0 ; PWD=/home/ubuntu ; USER=root ; COMMAND=/usr/bin/journalctl -xe
Aug 08 02:14:04 u109ls03 sudo[2461110]: pam_unix(sudo:session): session opened for user root(uid=0) by ubuntu(uid=1000)
```

### ログ出力のおかしなところまとめ

``lsof``の出力では/usr/sbin/sshdが既に置き換わっているので、表示が違います。

```text:
## 正常系
sshd    731 root  txt    REG                8,2   921288 16515820 /usr/sbin/sshd

## 障害時
sshd    3433 root  txt    REG                8,2   921416 10355968 /usr/sbin/sshd (deleted)
```

``systemctl``の出力ではPIDのところが正常系と比較すると少し違います。

```text:
## 正常系
   Main PID: 731 (sshd)

## 障害時
   Main PID: 3433
```

いずれも/usr/sbin/sshdが既に置き換わっているからですが、改めてみるとTCPポートの部分に差があるようです。

```text:
## 正常系
sshd    731 root    3u  IPv4              10282      0t0      TCP *:ssh (LISTEN)
sshd    731 root    4u  IPv6              10288      0t0      TCP *:ssh (LISTEN)

## 障害時
sshd    3433 root    3u  IPv6               7880      0t0      TCP *:ssh (LISTEN)
```

ただ、この状態でも問題なく外部からのssh経由での接続はできています。

## 対応

標準的な方法ではPID:3433が停止できないことが根本原因ではあるので、強制的に再起動します。

```bash:
$ sudo kill -9 3433
$ sudo systemctl restart ssh.service
$ sudo systemctl status ssh.service
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; enabled; preset: enabled)
     Active: active (running) since Fri 2025-08-08 02:17:42 UTC; 3s ago
TriggeredBy: ● ssh.socket
       Docs: man:sshd(8)
             man:sshd_config(5)
    Process: 2465850 ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: 2465852 (sshd)
      Tasks: 1 (limit: 38387)
     Memory: 1.2M (peak: 1.6M)
        CPU: 31ms
     CGroup: /system.slice/ssh.service
             └─2465852 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"

Aug 08 02:17:42 u109ls03 systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Aug 08 02:17:42 u109ls03 sshd[2465852]: Server listening on 0.0.0.0 port 22.
Aug 08 02:17:42 u109ls03 sshd[2465852]: Server listening on :: port 22.
Aug 08 02:17:42 u109ls03 systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
```

解決自体は問題ないのですが、これを検出してパッケージの更新が問題なくできるようにする必要があります。

```bash:
$ sudo apt install -f
```

sshdが再起動されているためPIDは最初の2465852から変更されていますが、sshがLISTENしているポートはIPv4が加わっています。

```bash:
$ sudo lsof -p 2467577 |grep :ssh
sshd      2467577            root    3u  IPv4 2842979676      0t0  TCP *:ssh (LISTEN)
sshd      2467577            root    4u  IPv6 2842972956      0t0  TCP *:ssh (LISTEN)
```

# まとめ

cron-aptを利用しているので、その時点での状況がなにか影響していることは分かりますが、正常に停止できないことの原因が不明です。

# Geminiによる原因分析と再発防止策

生成AIを利用して、この記事のMarkdownファイルをそのまま渡して原因を解析させてみました。

いろいろな出力が得られたのですが、その中でパッケージの更新処理中に、プロセスの再起動が行われた可能性について言及されていました。

その時に**sshd**プロセスの監視を行っていたことを思い出しました。

そもそもの原因は不明ですが、システムの定期リスタートの後にプロセスが起動しないことがあり、cronからプロセスの有無をチェックして、必要に応じて ``systemctl restart sshd.service`` を実行するようにしています。

原因がcron-aptにあれば引き続き現象は発生するかもしれませんが、とり急ぎスクリプトを改修して更新処理が完了するであろう時間分の遅延を入れることにしました。




