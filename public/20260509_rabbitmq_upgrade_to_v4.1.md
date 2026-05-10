---
title: RabbitMQをv3.13.7からv4.1.3にアップグレードした時のメモ
tags:
  - RabbitMQ
  - kubernetes
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

RabbitMQ Operatorで長く``v3.13.7``のまま運用していたのですが、特に問題なさそうなので、v4.1.3までOperatorを最新にしてRabbitMQのバージョンを上げることにしました。

Operatorの最新でもデフォルトのサービスバージョンがv4.1.3とv4.2ではないのですが、とりあえずOperatorを最新にしていきます。

# Operatorの適用順序

現行のOperatorは``v2.11.0``です。

最新版は``v2.20.1``なので、これを順番に上げていくのは少し大変そうです。

そのため今回は``v2.12.1`` (v4.0.5) → ``v2.13.0``(v4.1.0) → ``v2.16.1``(v4.1.3) → ``v2.18.0`` → ``v2.20.1``のように少しスキップしつつ、RabbitMQのバージョンが変更になるところを中心に更新していくことにしました。

バージョンについてはRabbitMQ OperatorのReleasesページを確認してください。

https://github.com/rabbitmq/cluster-operator/releases

# 過去の関連記事

RabbitMQ Operatorを``v2.11.0``にするまでの顛末は次の記事にまとめています。

https://qiita.com/YasuhiroABE/items/7c1e82e006ea37e0fe25#%E4%BD%9C%E6%A5%AD%E3%83%A1%E3%83%A2

# 作業の概要

過去の作業と流れは同じですが、整理すると大まかな流れは次のようになります。

1. WebブラウザからManagement UI(Port: 15672)を確認し、正常に稼動していることを確認する
2. kubectlコマンドを利用してYAMLファイルを適用(apply)し、全ての状態が定常化するまで見守る
3. RabbitMQのバージョンが変更された時は、RabbitMQClusterオブジェクトを編集し、``image:``行を削除しデフォルトのRabbitMQバージョン(v4.0.5, v4.1.0, v4.1.3)に移行する
4. RabbitMQのバージョンが変更された時は、Pod上で``rabbitmqctl enable_feature_flag all``を実行する

特に最後の``feature flags``の推奨値をすべて有効(enabled)にすることは、RabbitMQのマイナーバージョンを上げるための重要なステップです。

RabbitMQのバージョンは今回の作業ではv4.1.xに留まっていますが、v4.2になったタイミングで内部状態を保持するデータストアが``Mnesia``から``Khepri``に変更されます。

``Khepri``は素性は良さそうですが、より安定性が確認されてから移行した方が良さそうです。

## Operator v2.12.1の適用

``cluster_operator.yml``を適用した時に、StatefulSetの構成に変更があると古いバージョンでReconcileプロセスが起動されてクラスターが再起動してしまいます。

その最中にRabbitMQのアップグレードを進めてしまうのは障害につながる可能性があるため、次のような手順で更新します。

```bash:
## pause reconciliationを有効にする
$ sudo kubectl -n rabbitmq-system label rabbitmqclusters rabbitmq rabbitmq.com/pauseReconciliation=true

## Operatorを適用する
$ sudo kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.12.1/cluster-operator.yml

## image:行を削除して保存する
$ sudo kubectl -n rabbitmq-system edit rabbitmqcluster.rabbitmq.com/rabbitmq

## pauseを解除し、アップグレードプロセス(reconciliation)を進める (Podの再起動を含む)
$ sudo kubectl -n rabbitmq-system label rabbitmqclusters rabbitmq rabbitmq.com/pauseReconciliation-

## Finishedメッセージを確認する (完了まで数分かかります)
$ sudo kubectl -n rabbitmq-system logs -l app.kubernetes.io/name=rabbitmq-cluster-operator -f

## feature flagsを更新する (v2.16.1→v2.20.1などRabbitMQのバージョンに変更がなければ不要)
$ sudo kubectl -n rabbitmq-system exec -it rabbitmq-server-0 -- rabbitmqctl enable_feature_flag all
```

## Operator v2.13.0 〜 v2.20.1の適用

基本的には前述の``v2.12.1``の手順を繰り返すだけです。

URLの中に含まれているバージョン番号(``v2.12.1``)を該当のOperatorのバージョンにすれば、手順自体は同じです。

### v2.13.0適用時の対応

RabbitMQのバージョンが``v4.1.0``になるので、``rabbitmqctl enable_feature_flag all``を必ず実行しておきます。

### v2.16.1, v2.20.1適用時の対応

v2.16.1にしたタイミングでRabbitMQ本体は``v4.1.3``になります。

いまのところ最新のv2.20.1までこのバージョンに変更はないので、feature flagの変更などは不要です。

v2.20.1では自動的にStatefulSetが更新されPodが再起動されるので、``rabbitmqcluster``オブジェクトを``edit``コマンドで編集し、``image:``行を削除する必要はありませんが、``image:``行を削除しても問題はありません。

# 既知の問題

Issuesをみるとv3.13からv4.0に更新したタイミングで不具合が報告されていました。

https://github.com/rabbitmq/rabbitmq-server/discussions/14233

パスワードに":"文字が入っていたために、":"文字までがSaltのようなものだと勘違いされ暗号化文字列だと判定されてしまう障害が発生していたようです。

単純に文字列に":"文字が入っているかで判定するよりも適切なPrefixなり付与して誤判定しないようにするべきなのでしょうけれど、汎用ライブラリ側の想定を越えていたようです。

一応対処はされていますが完全ではないようなので、パスワードに":"文字が含まれている場合は変更してから作業を進めた方が安全でしょう。

# 今後の対応

RabbitMQ v4.2.xでの大きな変更は``Khepri``への移行が強制されることです。

とはいえ、Operatorのデフォルトが変更になる頃には、ほとんどの問題は対処されているはずですから、それほど気にすることはないと思います。

しかしRabbitMQを運用するのであれば適切なStaging環境を準備することが必要でしょう。

いつもどおり事前に検証してから移行作業を進めるようにしていれば問題にはならないはずです。

:::note
SNSをチェックしているとクラウドへの移行が進む中で、開発環境と本番環境しか持っていない組織があるように感じられます。

開発環境はシングルインスタンスで稼動していたり、適切なTLS証明書を利用していなかったりするかもしれません。

コスト的には負担が大きいですが、本番環境をスケールダウンしつつ同等の機能を備えたStaging環境を準備するようにしましょう。
:::
