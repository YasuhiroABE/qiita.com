---
title: SSHdが再起動できなくなった
tags:
  - Ubuntu
  - SSH
private: false
updated_at: '2025-04-28T13:01:09+09:00'
id: ffcf4cef2d237aa57c68
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

SylonogyのNASから定期的にバックアップを取得しているジョブがあるのですが、ジョブに失敗したというメールに気がつきました。

対象サーバーのサービスは問題なく動作しているのですが、SSHでの接続ができない状態になっていました。

Uptime Kumaでサービスレイヤーの監視はしていて問題はないものの、メンテナンス用のSSHサーバーの稼動状況は常時監視はしていませんでした。

よくよくログを確認すると10日ほど前から同様の症状が発生しており、パッケージの自動更新と再起動がトリガーになっているようです。

# エラーメッセージ

システムにコンソールから入って状況を確認しました。

## ログファイル

後から``/var/log/syslog``を確認すると``sudo systemctl restart ssh.service``を実行した時のメッセージが確認できます。

```text:/var/log/syslogからの抜粋
2025-04-28T02:01:30.741401+00:00 localhost (sd-listen)[951246]: ssh.socket: Failed to create listening socket ([::]:22): Address already in use
2025-04-28T02:01:30.741645+00:00 localhost systemd[1]: ssh.socket: Failed to receive listening socket ([::]:22): Input/output error
2025-04-28T02:01:30.741723+00:00 localhost systemd[1]: ssh.socket: Failed to listen on sockets: Input/output error
2025-04-28T02:01:30.741796+00:00 localhost systemd[1]: ssh.socket: Failed with result 'resources'.
2025-04-28T02:01:30.742029+00:00 localhost systemd[1]: Failed to listen on ssh.socket - OpenBSD Secure Shell server socket.
```

前後のログからパッケージが自動更新された後でリスタートするはずなのに、自身が動作していることを認識できていないようです。

## lsofの出力

lsofでプロセスの状態を確認すると次のようになっています。

```text:lsof -pの出力
COMMAND  PID USER   FD   TYPE             DEVICE SIZE/OFF    NODE NAME
sshd    4539 root  cwd    DIR                8,1     4096       2 /
sshd    4539 root  rtd    DIR                8,1     4096       2 /
sshd    4539 root  txt    REG                8,1   921416 5901223 /usr/sbin/sshd (deleted)
sshd    4539 root  mem    REG                8,1  2125328 5925336 /usr/lib/x86_64-linux-gnu/libc.so.6
sshd    4539 root  mem    REG                8,1  5305304 5899846 /usr/lib/x86_64-linux-gnu/libcrypto.so.3
sshd    4539 root  mem    REG                8,1    68104 5925350 /usr/lib/x86_64-linux-gnu/libresolv.so.2
sshd    4539 root  mem    REG                8,1    22600 5898529 /usr/lib/x86_64-linux-gnu/libkeyutils.so.1.10
sshd    4539 root  mem    REG                8,1    47904 5901399 /usr/lib/x86_64-linux-gnu/libkrb5support.so.0.1
sshd    4539 root  mem    REG                8,1   178648 5899231 /usr/lib/x86_64-linux-gnu/libk5crypto.so.3.1
sshd    4539 root  mem    REG                8,1   625344 5908158 /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0.11.2
sshd    4539 root  mem    REG                8,1    26848 5898629 /usr/lib/x86_64-linux-gnu/libcap-ng.so.0.0.0
sshd    4539 root  mem    REG                8,1   113000 5908853 /usr/lib/x86_64-linux-gnu/libz.so.1.3
sshd    4539 root  mem    REG                8,1    18504 5899226 /usr/lib/x86_64-linux-gnu/libcom_err.so.2.1
sshd    4539 root  mem    REG                8,1   823488 5899829 /usr/lib/x86_64-linux-gnu/libkrb5.so.3.3
sshd    4539 root  mem    REG                8,1   338696 5899613 /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2
sshd    4539 root  mem    REG                8,1   174472 5910876 /usr/lib/x86_64-linux-gnu/libselinux.so.1
sshd    4539 root  mem    REG                8,1    67888 5898373 /usr/lib/x86_64-linux-gnu/libpam.so.0.85.1
sshd    4539 root  mem    REG                8,1   133200 5908062 /usr/lib/x86_64-linux-gnu/libaudit.so.1.0.0
sshd    4539 root  mem    REG                8,1    44064 5899084 /usr/lib/x86_64-linux-gnu/libwrap.so.0.7.6
sshd    4539 root  mem    REG                8,1   198664 5900005 /usr/lib/x86_64-linux-gnu/libcrypt.so.1.1.0
sshd    4539 root  mem    REG                8,1   236616 5924248 /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
sshd    4539 root    0r   CHR                1,3      0t0       5 /dev/null
sshd    4539 root    1u  unix 0xffff9c22dca92800      0t0   25023 type=STREAM (CONNECTED)
sshd    4539 root    2u  unix 0xffff9c22dca92800      0t0   25023 type=STREAM (CONNECTED)
sshd    4539 root    3u  IPv6               7112      0t0     TCP *:ssh (LISTEN)
```

先頭の方にあるsshdプロセスについて``(deleted)``という表示が気になります。

これはパッケージの入れ替えなどで本体のファイルを指し示すinodeが変更されていることを示しています。

``ssh -v``でログを確認すると、この状態のsshdに接続することはできていますが、``debug1: SSH2_MSG_KEXINIT sent``行までで接続がクローズされてしまいます。

# 対応

事実上ゾンビ化したような状況なので、``kill``コマンドで明示的にsshdプロセスを停止しました。

systemdは停止済みという認識のようで自動的にプロセスが起動されることもなく、手動で``sudo systemctl restart ssh.service``を実行することで元に戻っています。

# 他のサーバーの状況

このサーバーはKubernetesのクラスターで、``cron-apt``によって定期的にパッケージの自動更新を行っていました。

4台中、3台がこの影響を受けてリモートからログインできない状態でした。

また他のクラスターでも同じバージョンのUbuntuとcron-aptで運用していて、ほぼ同じansibleでの構成を行っていますが、問題は発生していません。

サーバーは稼動してから48日ほど経過している状況ですが、不自然なほどに長期間無停止というわけでもなく、これまでcron-aptについてシステム側に起因する障害は発生していません。



