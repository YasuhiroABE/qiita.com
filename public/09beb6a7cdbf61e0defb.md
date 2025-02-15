---
title: Ansible Galaxyに登録していたroleをCLIから更新する
tags:
  - Ansible
  - ansible-galaxy
private: false
updated_at: '2023-12-07T09:31:36+09:00'
id: 09beb6a7cdbf61e0defb
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

いつのまにかAnsible GalaxyのWebサイトが更新されていて、Galaxy-NGベースになったようです。

これまでAnsible Galaxyに登録していた自分のroleを更新する作業はGitHubと連携させて、新しいコードとTagをGitHubにpushしてから、Ansible GalaxyのWeb UIで"Import"ボタンを押していました。

どうやら新しいサイトでは管理系操作ができなくなっているようなので、Galaxy NGのドキュメントを確認しつつ対応する手順をメモしておきます。

普段はansible-galaxy installコマンドを実行する以外の操作は使ってこなかったので、まったく勘が働かず少し困ってしまいました。

v3 Tokenを更新する必要がある点以外は、CLIの手順自体に特に新しい情報はないはずです。

# 参考資料

* [https://ansible.readthedocs.io/projects/galaxy-ng/en/latest/](https://ansible.readthedocs.io/projects/galaxy-ng/en/latest/)

# 操作手順

## 環境

Galaxyに登録するrole群は、作業環境の~/ansible/dev/以下にディレクトリが並ぶ形で保存しています。


```bash:
$ cd ~/ansible/dev/
$ ls 
ansible.cfg                       ansible-homegw-openvpn/           ansible-netflow-nfcapd/  ansible-uoa-metaldap/
ansible-fprobe-ng/                ansible-homegw-postfix/           ansible-nfcapd/          ansible-uoa-opmldap/
ansible-homegw-dnsmasq/           ansible-homegw-pppoe/             ansible-test-metaldap/   ansible-uoa-transldap/
...
```

このディレクトリに後述するansible.cfgファイルを保存していて、``ansible-galaxy role import``コマンドはこのディレクトリで実行します。

## 準備作業

まずAnsible Galaxyサイトにログインします。

* [https://galaxy.ansible.com/ui/](https://galaxy.ansible.com/ui/)

ログイン後にProfileページや、他のページに遷移しても自分が保有するRoleのリストなどは自動的には出てきません。

**Search**メニューから自分の名前を入力し、**Role namespaces**に表示された自分のアイコンをクリックすると自分が登録したroleのリストが表示されます。

ただ、ここでRoleを選択しても参照のみで操作はまったくできませんでした。

## v3 Tokenの取得と保存

**Collections** → **API Token** メニューからTokenを取得して安全な場所に保存しておきます。

"Load Token"ボタンを押すことで再生成され古いTokenは無効化されてしまうようなので、確実に保存しておきます。

## ansible.cfgファイルの作成

作業を実施するカレントディレクトリにansible.cfgファイルを配置します。

テンプレートファイルは次のようになっています。

```text:ansible.cfg
[galaxy]
server_list = beta

[galaxy_server.beta]
url = https://galaxy.ansible.com/api/
token = <your-api-token>
```

**token =** の右辺は先ほど取得して保存しておいたTokenに置き換えます。

## GitHubに登録した新しいTagをGalaxyに登録する

コマンドラインは次のとおり。

"YasuhiroABE"はGitHubのアカウント名で、"ansible-myfavorite-setting"はリポジトリ名です。
meta/main.ymlファイルに"role_name: myfavorite-setting"を指定しています。

```bash:
$ ansible-galaxy -v role import YasuhiroABE ansible-myfavorite-setting
...
===== PROCESSING LOADER RESULTS ====
enumerated role name myfavorite-setting

===== COMPUTING ROLE VERSIONS ====
adding new version from tag: v1.0.17
tag: v1.0.0 version: 1.0.0
tag: v1.0.1 version: 1.0.1
...
```

新しいタグが認識されてroleが更新され、以降のinstallでは更新された最新のタグが取り出されます。

# 考慮点

ansible.cfgファイルにはToken情報が記述されるため、公開Gitリポジトリとは別に管理する必要があります。

ansible.cfg自体はansible-playbook作業ディレクトリには普通に存在する見慣れているファイルなので、Galxy roleの作業環境と手順を整えないとansible.cfgファイルをうっかり誤って公開リポジトリに登録する可能性もありそうで、少し注意が必要です。

