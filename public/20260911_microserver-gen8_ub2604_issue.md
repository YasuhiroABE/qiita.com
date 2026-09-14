---
title: HP MicroServer Gen8にUbuntu 26.04を入れたらSATAドライブが正常に認識されなくなった件
tags:
  - Ubuntu26.04
  - SATA
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

円安にメモリなどの供給不足の影響で、サーバーを含めたコンピュータ機器が高騰しています。

いまだにHP MicroServer Gen8をNAPTゲートウェイやNASサーバーとして利用していますが、Ubuntu 24.04から26.04にアップグレードしたところ次のようなエラーが記録されていました。

```text:Ubuntu 26.04 Installerに記録されたcrashファイルから抜粋
 [  406.126157] ata1.00: supports DRM functions and may not be fully accessible
 [  406.131667] sd 0:0:0:0: [sda] tag#0 FAILED Result: hostbyte=DID_OK driverbyte=DRIVER_OK cmd_age=0s
 [  406.131675] sd 0:0:0:0: [sda] tag#0 Sense Key : Aborted Command [current]
 [  406.131688] sd 0:0:0:0: [sda] tag#0 Add. Sense: No additional sense information
 [  406.131696] sd 0:0:0:0: [sda] tag#0 CDB: Write(10) 2a 00 0e 2a b7 78 00 01 90 00
 [  406.131701] I/O error, dev sda, sector 237680504 op 0x1:(WRITE) flags 0x0 phys_seg 4 prio class 2
 [  406.131711] EXT4-fs warning (device sda1): ext4_end_bio:369: I/O error 10 writing to inode 7371563 starting block 29710063)
 [  406.131751] EXT4-fs (sda1): failed to convert unwritten extents to written extents -- potential data loss!  (inode 7371563, error -5)
 [  406.132073] Buffer I/O error on device sda1, logical block 29709807
```

結果的に``/``が``read-only``としてre-mountされてしまい、システム障害となっています。

最初はSATA 2.5インチSSD側に問題があるのかと思いましたが、いくつかのメディアとInstallerを動作させたところ、Ubuntu 26.04との相性問題のような挙動をしています。

復旧する必要があったので、原因の調査は十分できていませんが、分かったことは次のような状況です。

1. 2台のProLiant MicroServer Gen8の内、問題が発生しているのは1台のみ
2. Ubuntu 26.04にアップデートしたシステム、Ubuntu 26.04 Installerで起動した場合のいずれも同様のエラーを発生させている
3. 発生するタイミングはランダムで、Installerが完走する場合もあれば、途中でCrashする場合もある

# 解決策

2台のMicroServerの間にある違いは、VT-d(IOMMU)の有効・無効の点です。

片方はFD.io/VPPを利用しているため、VT-dを無効化していました。

https://qiita.com/YasuhiroABE/items/e4235f438b710afdc77e

今回、障害を起したデバイスはこれまでVT-dを有効化したまま、NFSサーバーとして利用してきた個体です。

最終的にVT-dを無効化することで問題なく安定的に動作するようになりました。

:::note
BIOS設定は起動時にF9キーを押下することで入ることができ、先頭のシステム設定の項目からプロセッサの設定項目に入ると、VT-dの有効・無効が変更できるようになります。
:::

# さいごに

SysnologyのActive Backupで必要なバックアップは取得していたので、最低限の設定をしたあと、NAS側から必要なディレクトリを復元させています。

最終的にはansibleを実行して元の状態に復旧しました。

使っていた起動用のSSDが2014年のプロジェクトで購入したものだったので、この機会に起動ドライブは別のメディアに変更して、Ubuntu 24.04.1を新規にインストールしています。

最終的にVT-dを無効化した状態で別のSSDにインストールしたUbuntu 26.04が問題なく動作することが判ったので、24.04.1をインストールしたSSDから26.04.1にアップグレードしています。
