---
title: AnsibleでLinuxホストのVMware Workstation Pro 16に実験環境を構築する
tags:
  - Ubuntu
  - vmware
  - Ansible
  - ansible-playbook
private: false
updated_at: '2024-01-05T09:38:38+09:00'
id: 9ebcda4cd8503df9ad81
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

Ryzen 7000シリーズのリリースを控えて5000シリーズのCPUが安くなっています。実際に7000シリーズが出たら待っていれば良かったと思うのかもしれませんが、当初リリースされるJEDEC規格のDDR5-4800やOC版のDDR5-5600は価格の割にそんなに魅力的でもないですし、単体CPUのパフォーマンスはそんなに必要ないのでコア数は多い方が嬉しいですが、基本的な構成に変化はないようです。それでもAVX-512命令に対応する点は魅力的に映ります。

Ryzen 5900Xの価格が最高値の半額近くに下ったので、この機会にほとんど使わなくなったOpteron 3280 (32GB, 128GB SATA/SSD, 3Ware 9750 RAID10 4TB)で構築したWSの内部を一新しました。仮想化環境もこれまで単体テスト用だったものを、Kubernetesクラスターのテストができるように変更することにしました。

狙いはDNSからVMのホスト名、IPアドレスを、正引き、逆引きできるようにしつつ、固定IPも利用できるようにすることです。こんな環境があるとkeepalivedを使ったload balancerや、Kubernetesクラスターのテストなど本格的なアプリケーションのテストが十分に行えます。

## 参考資料

ずいぶん昔に本格的なWeb環境を構築した記事を書きました。

これは前段のロードバランサー(L2,mac-based)でホスト名のSPoFを防ぎ、Proxyサーバーで複数のバックエンド環境(別ネットワーク)にURLのcontext-rootベースで経路制御を行い、後段のロードバランサー(L2,mac-based)で最後段にある静的・動的コンテンツに処理を分散する仕組みを実現しています。

小規模な環境ではここまでの複雑さは不要ですが、自前で複数開発チームがアプリケーションをデプロイするような環境を作ろうとすると、サイト全体のコンテキストと各開発ドメインを分割するために前段・後段に分けた環境が必要になります。

* [少しだけ気合いを入れてkeepalived, lighttpdを試してみた](https://yasu-2.blogspot.com/2010/02/keepalived-lighttpd.html)
![http://www.yasundial.org/blog/images/20100130.1.webinfra.png](http://www.yasundial.org/blog/images/20100130.1.webinfra.png)

こういった環境を完全仮想化環境でテストするのは、少し無理があるなと感じていましたが、現代では1台のWSで十分に実現可能です。

この記事を書いた頃もVMware Workstationを利用していましたが、手動で仮想ネットワークエディタを利用していくつもネットワークを作っていました。その後にdnsmasqを利用した環境を利用するようになり、自宅のPC上にも同様の環境を構築したくなったのですが、現在利用している環境は業務用のThinkPad T14 Gen2上に手動で構築した環境なので、手軽にセットアップできるようにansibleのplaybookにまとめることにしました。

## 成果物

記事中にもリンクがありますが、ここにまとめておきます。

* [GitHub YasuhiroABE/ansible-setup-vmware-devhome](https://github.com/YasuhiroABE/ansible-setup-vmware-devhome.git) (この記事で扱うansible-playbookの実行に必要なプロジェクト)

# 作業環境

* OS: Ubuntu 22.04.1 LTS
* CPU: Ryzen 5900X
* Memory: 64GB (DDR4-3200 ECC UDIMM)
* Drive#1: 2TB (NVMe PCIe gen3)
* Drive#2: 4TB (/home, SATA RAID-10, 3ware 9750)
* GPU: NVIDIA Quadro P620 (2GB)
* Monitor: 4K x2

# アーキテクチャ

VMware Workstation Pro 16を動かすことの最大のメリットは、[仮想ネットワークエディタ](https://docs.vmware.com/jp/VMware-Workstation-Pro/16.0/com.vmware.ws.using.doc/GUID-AC956B17-30BA-45F7-9A39-DCCB96B0A713.html)が利用できる点です。

デフォルトでは、vmnet0, vmnet1, vmnet8の3つのネットワークが定義されています。ここに、vmnet2(10.1.1.0/24)とvmnet3(10.2.1.0/24)の2つのトワークを追加し、トップレベルのVM(devhome)に接続してテスト環境を構成しています。

仮想ネットワークエディタの設定は次のようになっています。

|Name |Type |External Connection |Host Connection |DHCP |Subnet IP Address|
|-----|-----|--------------------|----------------|-----|-----------------|
|vmnet0|bridged|auto-bridging|-             |-    |-
|vmnet1|host-only|none|vmnet1     |yes  |172.16.240.0/24     |
|vmnet2|host-only|none|none       |no   |10.1.1.0/24         |
|vmnet3|host-only|none|none       |no   |10.2.1.0/24         |
|vmnet8|NAT      |NAT|vmnet8     |yes  |192.168.189.0/24    |

> 少なくともLinux環境のVMware Workstation Pro 16.2.4ではHost Connectionのチェックを付けた状態で"Save"することで、/dev/vmnet2等が作成されます。/dev/vmnet2等が作成された後はチェックを外して問題ありません。
これをしないと、VMの設定からネットワーク・アダプタを追加した際にHost-Onlyネットワークの選択肢に/dev/vment2などが表示されません。

これを利用するdevhomeの設定を含めた全体図は次のようになります。

![20220912-vmware-workstation-pro-virtual-network.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/78296/74e48481-3f98-1c12-bfd8-d076d9539d0c.png)


今回は、これらの設定をansibleを利用して自動化したいと思います。

# 作業

## ホストVM(devhome)での作業

まず最低限必要なパッケージを導入します。

```bash:aptによるパッケージの導入
$ sudo apt update
$ sudo apt install python3-venv make openssh-server git
```

次に適当な作業用ディレクトリを準備して、ansibleの環境をセットアップします。
既に作業が完了したディレクトリ全体をgithubに公開しているので次の手順で環境がセットアップできます。

```bash:ansible環境の構築
$ mkdir -p ansible/devhome
$ cd ansible/devhome
$ ansible -m venv venv/ansible
$ . venv/ansible/bin/activate
(ansible) $ pip install ansible
(ansible) $ git clone https://github.com/YasuhiroABE/ansible-setup-vmware-devhome.git .
(ansible) $ make setup-role
```

そのままでは利用しずらい部分があるので、下記のように適宜ファイルの内容を変更します。

## カスタマイズ方法

1) 利用したいドメインを files/dnsmasq/ 以下の各ファイルに反映させる
2) ネットワークのDNSサーバーのIPアドレスを files/dnsmasq/dnsmasq.resolv.conf ファイルを編集する
3) 実際のネットワークデバイスの値に応じて、files/netplan/ 以下の各ファイルを編集する

netplanのところでファイル名は変更する必要はありませんが、内容とファイル名を一致させたい場合には、playbook/default.yaml でコピー対象のファイル名も一緒に変更する必要があるので注意してください。

## ansbile-playbookの実行

必要な変更を加えたらansible-playbookコマンドで内容を反映させます。

```bash:ansible-playbook site.yamlコマンドの実行
$ make
```

設定に問題がなければ、10.1.1.0/24, 10.2.1.0/24ネットワークが設定され、dnsmasqが起動します。

53番ポートがsystemd-resolved.serviceによって使用されていた環境では、ansibleで停止するようにはしていますが、タイミングによってはdnsmasqの利用に失敗する可能性があります。手動でdnsmasqを起動するか、もう一回、ansible-playbook(``make``)を実行してください。

```bash:設定状況の確認
$ ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    altname enp2s1
    inet 192.168.189.129/24 metric 100 brd 192.168.189.255 scope global dynamic ens33
       valid_lft 1450sec preferred_lft 1450sec
    inet6 fe80::20c:29ff:fe84:7756/64 scope link 
       valid_lft forever preferred_lft forever
3: ens37: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    altname enp2s5
    inet 10.1.1.1/24 brd 10.1.1.255 scope global ens37
       valid_lft forever preferred_lft forever
    inet6 fe80::20c:29ff:fe84:7760/64 scope link 
       valid_lft forever preferred_lft forever
4: ens38: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    altname enp2s6
    inet 10.2.1.1/24 brd 10.2.1.255 scope global ens38
       valid_lft forever preferred_lft forever
    inet6 fe80::20c:29ff:fe84:776a/64 scope link 
       valid_lft forever preferred_lft forever

$ systemctl status dnsmasq.service
● dnsmasq.service - dnsmasq - A lightweight DHCP and caching DNS server
     Loaded: loaded (/lib/systemd/system/dnsmasq.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2022-09-12 18:45:51 JST; 1h 16min ago
     ...
```

dnsmasqは *Active: active (running)* になっていれば成功です。

# 使い方

まず基本的な設定を済ませたVMをSeedsとして準備します。
その後に具体的な利用のために、クローンすることで設定を引き継ぎ、変更を最小限にします。

## SeedsとなるVMの変更箇所

あらかじめubuntu-serverをminimal設定でインストールするなどし、元になるVMを準備し、次のような設定を反映しておきます。

1) VMの設定からネットワークデバイスの設定を変更し、NATからvmnet2かvmnet3に変更します
2) VMを起動し、/etc/netplan/ 以下の設定ファイルに ``dhcp-identifier: mac`` 設定を加えます ([説明記事](https://qiita.com/YasuhiroABE/items/2ee090cb50c6933207ba))
3) ~/.ssh/authorized_keys にdevhomeのid_ed25529.pubファイルの内容をコピーしておきます
4) その他、パッケージでお気に入りのエディタを追加するなど、必要な共通設定をあらかじめ実施しておきます

## クローンしたVMに行う変更箇所

次に、この元となるVMをCloneし、VMを起動し、利用する前に次のような設定を行います。

1) VM内の /etc/hosts に、設定したいホスト名を追加します (sudoがホスト名のlookupにtimeoutするため、現在のホスト名を変更 or 削除しないこと。127.0.0.1か127.0.1.1のいずれかに新しいホスト名を加えればOK)
2) 必ず(1)の後に、``sudo hostnamectl set-hostname <hostname>``でユニークなホスト名を設定する

## クローン追加後に、devhomeのdnsmasqに追加する変更箇所

クローンしたVM上で動作するであろうsshdやnginxにネットワーク経由でアクセスできるように、dnsmasqに必要な設定を追加します。

1) 固定IPを利用したい場合には、MACアドレスとIPアドレスの組をdevhomeのfiles/dnsmasq/default.confの最下行に``dhcp-host=<mac address>,<ip address>``で指定する
2) 再起動し、ホスト名とIPアドレスがdnsmasqに登録され、ホスト名でアクセスできる事を確認する (devhomeから``nslookup <hostname>``や``ping <hostname>``を実行するなどする)

固定IPを利用できることはKubernetesなどをテストする際には必須で、dnsmasqのDNSとDHCPサービスの連携はとても便利だと思います。

# さいごに

最近はVMware社がWorkstationやFusionといったデスクトップ製品の日本語サポートを打ち切るなど、厳しい状況が続いています。

個人的にもKubernetesなどコンテナ環境に本番アプリケーションはほぼ移行していて、完全仮想環境を利用するのは、ホストOSの環境(Windows)に依存せずに開発環境(Linux)を維持するための手段だったり、本番環境のkubernetesで利用するRook/CephやMinioの検証だったり、必要だけれども一段下がったポジションで利用することが増えています。

VMware Workstation Pro製品がなくなると本当に困るのですが、おそらくDockerを利用すれば十分なほとんどの人達は、完全仮想化環境から離れているのでしょう。

今回は新しく構築した環境(Ryzen 5900X)にVMware Workstation Pro 16をインストール(ライセンスの移行)をしましたが、その過程で新規に導入したXubuntu DesktopのVMがまともに実行できない状況に陥りました。

最終的に分かった原因は、十分な性能を持っていないグラフィックスカードに対して、デフォルトで3D Accelerationが有効(On)になっていたことでした。

GT 730を利用しているXeon E3-1230v2な環境では、自動的にアクセラレーションがOffになっていてサクサク動いているので、しばらく気がつきませんでした。最後にこの時にglxgearsを実行した結果を添付しておきます。

## Linux VMの3D Accelerationの効果

Xubuntu Desktopを導入したVMのレスポンスが実用に耐えなかったので、glxgearsでフレームレートをチェックしましたが、ネガティブな結果にはなりませんでした。

```text:3D Acceleration Off
$ glxgears
9086 frames in 5.0 seconds = 1817.112 FPS
8525 frames in 5.0 seconds = 1704.989 FPS
8664 frames in 5.0 seconds = 1732.600 FPS
8053 frames in 5.0 seconds = 1610.520 FPS
```

```text:3D Acceleration On
$ __GL_SYNC_TO_VBLANK=0 glxgears
13661 frames in 5.0 seconds = 2732.083 FPS
15145 frames in 5.0 seconds = 3028.973 FPS
15734 frames in 5.0 seconds = 3146.746 FPS
14842 frames in 5.0 seconds = 2968.144 FPS
```

3D Acceleration Onの方が数値は良いですが、体感的にはキーボード入力やマウスカーソルの軌跡について、0.数秒待たされるような状況なので、低スペックのグラフィックスカードでも3D Accelerationが有効になってしまう初期設定に問題がありそうです。

手動で3D AccelerationをOffにすることで、とても満足する結果になりましたが、機会があれば高性能なGPUに変更し、3D Accelerationを利用してみたいと思います。
