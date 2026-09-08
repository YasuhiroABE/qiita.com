---
title: VPPを利用しているサーバーのUbuntu 26.04へのアップグレード手順
tags:
  - Network
  - Ubuntu
  - vpp
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
posting_campaign_uuid: null
agreed_posting_campaign_term: false
---
# はじめに

今回の対象はVPPのみを利用してネットワークに接続しているサーバーで、NICは全てVPPの管理下にあります。``ip addr``コマンドの出力は次のようになっています。

```text:ip addrコマンドの出力
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
6: tap0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UNKNOWN group default qlen 1000
    link/ether 02:fe:34:36:4e:a5 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.10/24 scope global tap0
       valid_lft forever preferred_lft forever
    inet6 fe80::fe:34ff:fe36:4ea5/64 scope link
       valid_lft forever preferred_lft forever
```

これまでFD.io/VPPを利用してきて、いくつかの不具合に遭遇してきました。

例えばパッケージの自動アップデートを利用していたために、次のような問題が発生しています。

まず、Ubuntu 22.04を利用していて、HWEカーネルを利用したところVPPが起動しない問題に遭遇しました。

https://qiita.com/YasuhiroABE/items/e4235f438b710afdc77e

次に、VPPをv25系からv26系にアップグレードしたところ、``tap_plugin.so enable``の設定が不足していて起動しない問題がありました。

https://qiita.com/YasuhiroABE/items/0abe6ebe7a35006bcd65

そのため、通常は次のコマンドを実行してVPP関連のパッケージを自動更新の対象から外しています。

```bash:パッケージをhold状態にするコマンドライン
$ sudo apt-mark hold vpp* libvpp*
```

こうするとパッケージは通常の``ii``ステータスではなく、``hi``ステータスになり、自動アップデートの対象から外れます。

```text:$ dpkg -l |grep vppの出力
hi  libvppinfra         26.06-release   amd64    Vector Packet Processing--runtime libraries
hi  vpp                 26.06-release   amd64    Vector Packet Processing--executables
hi  vpp-plugin-core     26.06-release   amd64    Vector Packet Processing--runtime core plugins
hi  vpp-plugin-dpdk     26.06-release   amd64    Vector Packet Processing--runtime dpdk plugin
```

他にもまだVPPを利用しているサーバーがあるので、簡単にアップグレード手順をまとめておきます。

:::note
まだ公式からはUbuntu 26.04(resolute)に対応したパッケージは提供されていません。

現状では24.04(noble)用のパッケージを利用しています。
:::


# 作業において気をつけること

VPP固有の問題はあまりないと思います。

ただし、unhold状態に変更してからパッケージを更新するとアップデートされてしまうので、設定ファイルの更新はunhold設定とセットで行います。

# 手順

## VPPバージョンの確認と設定の変更

v26では設定ファイルの変更が必要かもしれないので、あらかじめ必要な変更を行っておきます。

v25を利用していれば前述のように``tap_plugin.so enable``を``/etc/vpp/startup.cfg``に追記しておきます。

## パッケージのHOLD状態の解除

まず次のコマンドでパッケージの状態を元に戻します。

```bash:パッケージの状態を通常に戻す
$ sudo apt-mark unhold vpp* libvpp*
```

## 他のパッケージの状態を確認

他に``hi``(hold)状態のパッケージがないか確認しておきます。

```bash:
$ dpkg -l | grep -v ^ii
```

hold状態のものがあれば、unholdにするなど適切に対応します。

削除してまだファイルが残っている``rc``状態のものは、そのままでも良いですが、状況に応じて削除します。

```bash:
$ dpkg -l | grep ^rc | awk '{print $2}' | sudo xargs dpkg --purge
```

## パッケージを最新に更新

VPP以外のパッケージを最新にしておきます。

```bash:
$ sudo apt update
$ sudo apt dist-upgrade -y
```

最終的にはアップグレードの中で再起動が必要であれば促されますが、この時点で再起動を行って次に進みます。

## Ubuntu 26.04へのアップグレード

``sudo do-release-update -d``を実行することで、Ubuntu 26.04.1にアップデートすることができます。

通常は``-d``は必要ないはずですが、執筆時点では、``26.04.1``はリリースされたもののrust-coreutilsパッケージの修正待ちだという事が技評の記事で言及されています。

https://gihyo.jp/admin/clip/01/ubuntu-topics/202609/04

# Ubuntu 26.04へのアップグレード後の注意点

## /etc/sysctl.confが更新されなかった

VPPとは関係ありませんが、いくつかアップグレードしたところ``/etc/sysctl.conf``が更新されずに、/etc/sysctl.conf.*のようにrenameされていました。

これによってip_forwardingが無効化されたままとなり、OpenVPNで接続した時だけ、そのネットワーク内のデバイスにアクセスできなくなったので、少し気がつくのに時間がかかりました。

## postfixが正常に更新されない

/etc/postfix/main.cfファイルが存在しないことでエラーとなり、アップグレード自体は成功しましたが、エラーのために途中でインストーラーが終了しました。

``touch``コマンドでファイルを作成して、``apt dist-upgrade``コマンドを実行したところ、postfixパッケージの後処理が正常に完了し、問題のない状態になっています。

# その他に気がついた点

Ubuntuの問題ではないのですが、nginxの26.04(resolute)対応の公式パッケージが``x86_64-3``以上を要求するようになっているので、古いハードウェアでは動作しないことがありました。

```bash:readelf -n /usr/sbin/nginxの出力抜粋
Displaying notes found in: .note.gnu.property
  Owner                Data size        Description
  GNU                  0x00000020       NT_GNU_PROPERTY_TYPE_0
      Properties: x86 feature: IBT, SHSTK
        x86 ISA needed: x86-64-baseline, x86-64-v2, x86-64-v3

Displaying notes found in: .note.package
  Owner                Data size        Description
  FDO                  0x00000064       FDO_PACKAGING_METADATA
    Packaging Metadata: {"type":"deb","os":"ubuntu","name":"nginx","version":"1.31.5-1~resolute","architecture":"amd64"}
```

古くてもAPU1を除くとほとんどは``x86_64-v2``までは対応しているのですが、``*-v3``を要求されるようになるとデバイスを購入しないといけません。

ただのプロキシーサーバーにそこまでの性能は求めないので、しばらくは公式の最新版ではなくディストリビューションの標準パッケージで対応することになりそうです。


