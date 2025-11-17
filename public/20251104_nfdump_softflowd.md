---
title: Ansibleでnfdumpとsoftflowdを構成する
tags:
  - ansible
  - netflow
  - softflowd
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

Gatewayで使っているサーバーで通信の記録を保存するため、fprobeを利用していましたが、度々ハングアップするなど可用性に問題があったので、softflowdに変更しました。

また今回設定したサーバーのいくつかはGatewayを構成するために、FD.io/VPP (Vector Packet Processing)を利用しています。

今回はAnsible Playbookと自前のRoleを利用していますが、作業順序を統一するために自前のRoleを作成しているだけなので、それほどの修正なしに既存のモジュール(apt, lineinfile, etc.)に置き換えることができると思います。

# 対象となる環境

Python3の開発環境では全てvenvを利用しています。

* OS: Ubuntu 24.04.3 (LTS)
* 利用しているOS標準パッケージ: python3 python3-venv python3-pip
* Ansible Core: 2.18.1 (venv + pipからインストール)
* Ansible Galaxy Role: [galaxy.ansible.com - YasuhiroABE/myfavorite-setting/](https://galaxy.ansible.com/ui/standalone/roles/YasuhiroABE/myfavorite-setting/)

この他の環境でもansibleは利用していて極端に古いバージョンを使わない限りは問題ないはずです。

# 参考資料

次の記事では``fprobe-ulog``を利用することでネットワークの通信の向きを正確に捉えることができたとレポートされています。

https://pitstop.manageengine.com/portal/en/community/topic/linux-router-expoerting-netflow-sflow-problems-setting-traffic-directions


# 作業の概要

UbuntuでNetflow系のツールを利用する場合には、nfcpadなどを含む``nfdump``パッケージをインストールした上で、ログとしてファイルに記録するために``fprobe``や``softflowd``パッケージを利用することになります。

この他に商用のパッケージなどもありますが、基本的には上記のようになると思います。

## Ansibleの設定内容

"/etc/softflowd/default.conf"に指定する``interface='tap0'``の設定は、記録する通信が経由するNICを指定してください。

fdio/vppを利用しているためtap0を指定しています。

```yaml:playbook.yaml
- hosts: all
  vars:
    mfts_additional_packages:
    - nfdump
    - softflowd
    mfts_lineinfile_after_packages:
    - { path: "/etc/softflowd/default.conf", regexp: "^interface=",  line: "interface='tap0'", state: "present", insertbefore: "" }
    - { path: "/etc/softflowd/default.conf", regexp: "^options=",  line: "options='-n 127.0.0.1:2055'", state: "present", insertbefore: "" }
  roles:
    - YasuhiroABE.myfavorite-setting
```

## FD.io VPPのIPFIX機能を利用する

一部のゲートウェイではVPPを利用しているので、次のように他のノード(192.168.1.5)で動作しているnfcapdにパケットをフォワードしています。

```text:/etc/vpp/local.cfgの設定から抜粋
set ipfix exporter collector 192.168.1.5 port 2055 src 192.168.1.1
flowprobe params record l3 active 20 passive 120
flowprobe feature add-del ens1f0 ip4 both
flowprobe feature add-del bvi0 ip4 both
```

試した範囲ではtap0でLISTENしているlocalhost上のnfcapdにパケットをフォワードすることはできませんでした。

# nfcapdの設定

Ubuntuではデフォルトの状況で2055/udpをLISTENしています。

ufwなどで管理していれば特にnfcapdの設定を変更する必要はないと思いますが、パブリックネットワークに接続しているのであればLISTENしているポートの状態を制御してあげる必要がある点には注意が必要です。

以上
