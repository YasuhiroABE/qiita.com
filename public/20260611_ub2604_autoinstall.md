---
title: Ubuntu 26.04でのAutoInstall
tags:
  - Ubuntu
  - Ansible
  - AutoInstall
  - Ubuntu26.04
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

GitHubで公開しているプロジェクトをUbuntu 26.04に対応させました。

https://github.com/YasuhiroABE/ub-autoinstall-iso

Ubuntu 24.04に対応した時の顛末は記事にしています。

https://qiita.com/YasuhiroABE/items/db3339ee057447431bbc

基本的にはmainブランチを使って問題ありませんが、26.04タグを設定しています。

対応しているのはx86アーキテクチャの次のような機器です

* Intel/AMD64系のUEFIデバイス
* 同様にIntel/AMD64系のMBR(BIOS)な非UEFIデバイス
* PC Engines社製APUなどシリアルポート出力のみを有するデバイス

古い機器を使いたい個人的な必要性からisolinuxを使って起動するようにしている点が特徴になっています。

AutoInstallについてはCanonicalが出しているガイドを参照するのがベストだと思います。

https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html

# Ubuntu 26.04 での変更点

特に大きな違いはなく、Subiquityなどのコンポーネントのマイナーな改善点の影響を受けるのみのようです。

https://github.com/canonical/subiquity/releases/tag/26.04

ユーザーの作成タイミングがインストール中に変更されたり、gropusの指定ができるようになったりしているので、地味ですが実用上の重要なポイントが改善されている印象です。

ただ24.04の記事にも書いていますが、複数台のデバイスを同様の状態に保ちたいのであれば、Ansibleを利用することをお勧めします。

ユーザーのgroups管理などは、インストーラーに含めるのはシステムユーザーなど最小限に留めるべきです。

# HDDにインストールする場合

config/user-dataではインストールデバイスの選択基準として、最大容量の**SSD**を採用しています。

サーバーではHDDをKubernetesのRook/CephのBlueStorageとしてHDD全体を利用するため、単純に最大容量のデバイスは選択されないようになっています。

もしHDDにUbuntuを導入したいのであれば、curtin/storageの記述は変更する必要があります。

# 注意点

AutoInstallはkernelパラメータに**autoinstall**を含めると、起動してからストレージを初期化して後戻りできなくなる作業を警告なしに実行します。

USBメモリに書き込んで起動した後、10秒後くらいにはストレージが初期化されていると思うので十分に注意してください。

# さいごに

UbuntuがPreseedを捨ててAutoInstallに移行した当初は戸惑いがありましたが、かなり慣れたという印象です。

2台以上のデバイスにUbuntuを導入するのであれば、自動インストールに挑戦してみてください。






