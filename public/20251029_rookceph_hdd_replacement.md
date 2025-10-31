---
title: Rook/Cephで利用している10年前に製造されたHDDを交換してみた
tags:
  - Ceph
  - kubernetes
  - Rook
private: false
updated_at: '2025-10-31T11:25:02+09:00'
id: 1b2d546f0c0d1bcccd44
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

以前SMARTのSelf-Testで``servo/seek failure``メッセージを出していたHDDを交換した記事を書きました。

https://qiita.com/YasuhiroABE/items/22bda9043014b3b70b97

今回はとくに異常はレポートされていないのですが、おそらく同時期に購入した他のHDDで、明確に異常はなかったのですが予防的に交換した時の手順をまとめておきました。

# 問題のありそうなHDDの状態

そもそも製造から10年以上が経過している時点で問題があるのですが、一応24時間稼動が前提のHDDなので壊れるまで使おうとK8sのノードに転用したのでした。

問題がありそうだと気がついたのは、別の理由でHDDを交換した際に、健全な別ノードで実行したhdparmの出力を確認した時でした。

```bash:Rook/CephのBlueStoreに利用している/dev/sdbに対するhdparmベンチマークの出力(異常)
$ sudo hdparm -Tt /dev/sdb

/dev/sdb:
 Timing cached reads:   22522 MB in  1.99 seconds = 11316.31 MB/sec
 Timing buffered disk reads: 236 MB in  3.00 seconds =  78.63 MB/sec
```

古い低回転のNAS用HDDとはいえ製品のスペック上は、180MB/sec程度の転送速度があるはずです。

裏では重いRook/CephのPGsのremap処理が発生したので、パフォーマンスに影響があるかなと思ったのですが、同じクラスターの別のノードを確認すると次のようになっていて、先ほどのHDDは明らかにパフォーマンスが悪化しているようでした。

```bash:同じタイミングで他のノードで取得したhdparmの出力(正常)
/dev/sdb:
 Timing cached reads:   25382 MB in  1.99 seconds = 12762.24 MB/sec
 Timing buffered disk reads: 502 MB in  3.01 seconds = 166.60 MB/sec
```

Cephの状態はあまり関係なさそうなので、Remap処理が終ってからパフォーマンスの低かったHDDで再度ベンチマークを取得すると、やはりパフォーマンスは改善していませんでした。

```bash:異常だったHDDの定常時のベンチマーク結果
/dev/sdb:
 Timing cached reads:   25232 MB in  1.99 seconds = 12686.92 MB/sec
 Timing buffered disk reads: 242 MB in  3.03 seconds =  79.78 MB/sec
```

作業の前にSMARTのSelf-Testを実行して問題は報告されていなかったのですが、他のノードでも似たような状態のHDDを使用していたので、同時にクラッシュすることを怖れて早めに交換することにしました。

# 交換手順

まず試したのは以前の記事を参考にRook/Cephに含まれているosd-purge.yamlを使用する方法ですが、今回はうまく進めることができませんでした。

原因としては以前にosd-purge.yamlを適用した時点では、OSDは既にdownしていた状態でしたが、今回は表面上はエラーはまったくない状態だったので、OSDはupのまま有効なPGsが配置されている状態だったことにあります。

今回はあらかじめOSDをdownさせる手順を追加して進めた形になります。

対象となったOSDは``3``で、今回の作業の流れは次のようになりました。

1. 手動で``rook-ceph-operator``を停止(replicas: 0)した
2. rook-ceph-toolsのshellから手動で``ceph osd out osd.3``を実行した
3. PGsの退避後、osd-purge.yamlを実行したが、osd.3は削除されなかった
4. 手動で``deploy/rook-ceph-osd-3``を停止(replicas: 0)した
5. 再度、osd-purge.yamlを実行し、osd.3を削除した
6. 対象ノードをcordon/drainし、shutdownした
7. HDDを交換後、ノードを起動し、uncordonして、クラスターに復帰させた
8. ``rook-ceph-operator``を起動(replicas: 1)した

``deploy/rook-ceph-sd-3``は停止(replicas: 0, scale down)しただけで、削除(delete)していませんが、osd-purge.yamlを実行したタイミングで削除されています。

最終的にHDDは交換しているので、Operatorが起動すると``rook-ceph-sd-prepare-*``が起動され、新しい``deploy/rook-ceph-osd-3``が作成されます。

## 準備作業

事前に作業対象のノードとOSD番号の対応を確認します。

```bash:pod/rook-ceph-tools-*からOSD番号とHOSTの対応を確認しておく。
$ ceph osd status
ID  HOST    USED  AVAIL  WR OPS  WR DATA  RD OPS  RD DATA  STATE
 0  node3   367G  1495G      1     13.5k     10      236k  exists,up
 1  node2   411G  1451G      1     12.7k     31      177k  exists,up
 2  node4   335G  1527G      4     36.0k     14      320k  exists,up
 3  node1   350G  1512G      5     86.3k     86      336k  exists,up
```

## Operatorの停止 (1)

一般的な方法は``scale``を利用して、deploymentオブジェクトでreplicasを``0``に設定することです。

```bash:
$ kubectl -n rook-ceph scale deploy rook-ceph-operator --replicas=0
```

kubectlから直接``edit``コマンドでreplicas:行を編集することもできます。

## 手動でのOSDの停止方法 (2)

最初に``ceph osd out osd.3``を実行すると、PGsが他のノードに再配置され始めます。

500GBほどの利用状況で、この処理に24時間ほどかかっています。その間はOSDのステータスは**up**のままです。

```bash:remap中のcephコマンドの出力
$ ceph osd df
ID  CLASS  WEIGHT   REWEIGHT  SIZE     RAW USE  DATA     OMAP     META     AVAIL    %USE   VAR   PGS  STATUS
 3    hdd  1.81940   1.00000  1.8 TiB  310 GiB  308 GiB   34 KiB  2.0 GiB  1.5 TiB  16.64  0.84   76      up
 1    hdd  1.81940   1.00000  1.8 TiB  410 GiB  409 GiB   41 KiB  1.1 GiB  1.4 TiB  22.02  1.12   74      up
 0    hdd  1.81940   1.00000  1.8 TiB  367 GiB  364 GiB   34 KiB  2.1 GiB  1.5 TiB  19.68  1.00   66      up
 2    hdd  1.81940   1.00000  1.8 TiB  382 GiB  379 GiB   30 KiB  2.6 GiB  1.4 TiB  20.49  1.04   75      up
                       TOTAL  7.3 TiB  1.4 TiB  1.4 TiB  141 KiB  7.8 GiB  5.8 TiB  19.71
MIN/MAX VAR: 0.84/1.12  STDDEV: 1.96
```

``pod/rook-ceph-osd-3-*``が動作している間は、OSDのステータスはUPのままです。

## osd-purge.yamlの編集と反映 (3)

このファイルは必ずOSDの番号を記入してから適用する必要があります。

```diff:
diff --git a/deploy/examples/osd-purge.yaml b/deploy/examples/osd-purge.yaml
index 4c62da285..09f074b49 100644
--- a/deploy/examples/osd-purge.yaml
+++ b/deploy/examples/osd-purge.yaml
@@ -44,7 +44,7 @@ spec:
             - "--force-osd-removal"
             - "false"
             - "--osd-ids"
-            - "<OSD-IDs>"
+            - "3"
           env:
             - name: POD_NAMESPACE
               valueFrom:
```

編集後に、kubectlコマンドからapplyします。

```bash:
$ kubectl -n rook-ceph apply -f osd-purge.yaml
```

今回、これはうまく動作しませんでしたが、次の工程を終えてから、再度実行します。

## 手動でのpod/rook-ceph-osd-3-*の停止 (4)

Operatorと同様に``scale``を利用するか、手動でdeployオブジェクトの定義を編集します。

```bash:
$ kubectl -n rook-ceph scale deploy rook-ceph-osd-3 --replicas=0
```


## 残りの作業 (5〜8) と、よくある失敗

あとは繰り返しや他で説明している内容なので省略します。

問題になりそうなところは交換するHDDが新品でない場合に、適切に初期化されていない場合でしょう。

HDDの初期化についてはrook.ioのドキュメントに記述があるので、交換してからuncordonする前に``sgdisk --zap-all $DISK``などを適切に実行しましょう。

https://rook.io/docs/rook/latest-release/Getting-Started/ceph-teardown/#delete-the-data-on-hosts

# まとめ

HDDを予防的に交換するといってもSMARTなどで異常が報告されてから対応する場合がほとんどだと思います。

今回の交換対象HDDは、ニアラインHDDではなく、初期の低回転なNAS用HDDでした。

ディスクの回転数が低いため全体のパフォーマンスも低かったのですが、さらに悪化してしまいアプリケーションレベルでもファイルの保存に体感で時間がかかっているのが分かるほどでした。

SMARTの出力もhdparmの出力も、これ自体は異常ではないと思います。

パフォーマンスが我慢できるならそのまま使い続ける選択もありましたが、今回はとりあえず全て7200rpmのニアラインHDDに揃えることにしました。

