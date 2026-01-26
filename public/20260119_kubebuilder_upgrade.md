---
title: KubeBuilderをv4.10.1にアップグレードしてみた
tags:
  - kubernetes
  - Kubebuilder
private: false
updated_at: '2026-01-26T16:18:18+09:00'
id: 6fd88bdf4e8539a2a21b
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

これまでKubebuilder v3.14.0で作成したCustom Controllerをベースに変更を加えてきました。

https://qiita.com/YasuhiroABE/items/babaa0710bffbdffbe5f

これまでもGo言語のPackagesを更新してきて、都度コードの変更は行ってきましたが、根本的なコントローラーのコードベースはv3.14.0のものを使い続けてきたので、最新のKubebuilderのコードベースに移行することにしました。

ソフトウェア工学的には、動作しているシステムのコード全体を再生成するようなことは影響範囲がみえないので避けるべきだと思います。

ただ個人的なプロジェクトなのと、あまりにもKubebuilderのバージョンが古かったので、乖離が広がるとcontroller-runtimeの更新だけでは対応が難しくなるような状況になるのは避けたかったので、複雑化する前にリフレッシュする方が大切かなと判断しました。

# 環境

* OS: Ubuntu 24.04 LTS (VMware Workstation上のVMとして稼動)

# 作業内容

前提としてCustom Controllerのコード全体はGitで管理しています。

Kubebuilderを使うと.git/以外のディレクトリ・ファイルはすべて変更の対象となるため、全てのコードをGitの管理下に置いておくことが事故を防ぐために大切です。

.gitignoreを独自に変更しているようであれば、念のためディレクトリ全体のバックアップもtarなどで取得しておく方が良いでしょう。

:::note warn
これから実行する``kubebuilder alpha generate``コマンドは破壊的な動作をするため、バックアップは必須です。
:::

## Kubebuilderのアップグレード

GithubのReleasesページで配布されているバイナリを/usr/local/binなどに配置します。

https://github.com/kubernetes-sigs/kubebuilder/releases

私の環境では /usr/local/sbin/kubebuilder に手動で配置しています。

## Kubebuilderによるコードのアップグレード

Kubebuilderのv4.10.1のRelease文には次のような説明があります。

https://github.com/kubernetes-sigs/kubebuilder/releases/tag/v4.10.1

> Automate updates with kubebuilder edit --plugins="autoupdate.kubebuilder.io/v1-alpha" or run them manually with kubebuilder alpha update. If your PROJECT file does not include cliVersion, you may need a one-time manual upgrade, and kubebuilder alpha generate can fully re-scaffold the project in one step. After that, updates work seamlessly.

v3.14.0で生成されたコードベースは古すぎるので、PROJECTファイルには``cliVersion:``の記載はありません。

そのため自動更新機能は使えないため、``kubebuilder alpha generate``コマンドを実行して、もう１度プロジェクトディレクトリ全体を初期化してコードをMergeします。


### kubebuilder alpha updateコマンドを実行した時の挙動

元が古いのでダメ元で、``kubebuilder alpha update``を試してみると、次のようなエラーが表示されました。

```text:
ERROR CLI run failed error=error executing command: failed to prepare update: failed to determine the version to use for the upgrade from: no version specified in PROJECT file. Please use --from-version flag to specify the version to update from
```

試しに``--from-version``を追加すると次のような出力になり、やはり失敗します。

```text:
WARN No --from-branch specified, using 'main' as default
INFO Checking if is a git repository
INFO Checking if branch has uncommitted changes
INFO Binary version available version=v3.14.0
INFO Binary version available version=v4.10.1
INFO Checking out base branch branch=main
INFO Preparing Ancestor branch branch_name=tmp-ancestor-19-01-26-10-30
ERROR Update failed error=failed to prepare ancestor branch: failed to cleanup the tmp-ancestor-19-01-26-10-30 : failed to clean up files: exit status 1
```

``--from-branch``を追加しないと、作業用ブランチに移動していてもmainブランチから作業用ブランチを作成して進めようとするので、v3.14.0のコードベースのbranchを指定しましたが、結果は同じでした。

メッセージのように新しいbranchで作業するのですが、失敗するため中身はほぼないので``main``などをcheckoutしてから削除しておきます。

```bash:
$ git branch -D tmp-ancestor-19-01-26-10-30
```

### kubebuilder alpha generateコマンドの実行

``kubebuilder alpha generate``を実行する時に何の支援もないかといえばそうでもなく、一応PROJECTファイルは読み込んでくれるのでオプションを指定する必要はありません。

こちらは作業用ブランチで実行すると、そのブランチ上で``.git/``ディレクトリを残したまま、他のファイルを初期化してくれます。

```bash:
$ cd my-operator-code/

$ ls
api/  bin/  cmd/  config/  Dockerfile  go.mod  go.sum  hack/  internal/  Makefile  PROJECT  README.md  test/

$ kubebuilder alpha generate
```

次のような出力が得られます。

```bash:kbuebuilder-alpha-generateコマンドの実行結果
WARN Using current working directory to re-scaffold the project
WARN This directory will be cleaned up and all files removed before the re-generation
INFO Cleaning directory dir=..../my-operator-code
INFO Running cleanup
INFO Running cleanup
INFO kubebuilder init
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO Get controller runtime
INFO Update dependencies
Next: define a resource with:
$ kubebuilder create api
INFO kubebuilder create api
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO api/v1/members_types.go
INFO api/v1/groupversion_info.go
INFO internal/controller/suite_test.go
INFO internal/controller/members_controller.go
INFO internal/controller/members_controller_test.go
INFO Update dependencies
INFO Running make
mkdir -p "..../my-operator-code/bin"
Downloading sigs.k8s.io/controller-tools/cmd/controller-gen@v0.19.0
"..../my-operator-code/bin/controller-gen" object:headerFile="hack/boilerplate.go.txt" paths="./..."
Next: implement your new API and generate the manifests (e.g. CRDs,CRs) with:
$ make manifests
INFO kubebuilder create webhook
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO internal/webhook/v1/members_webhook.go
INFO internal/webhook/v1/members_webhook_test.go
INFO internal/webhook/v1/webhook_suite_test.go
INFO Update dependencies
INFO Running make
INFO Running make
"..../my-operator-code/bin/controller-gen" object:headerFile="hack/boilerplate.go.txt" paths="./..."
Next: implement your new Webhook and generate the manifests with:
$ make manifests
INFO Grafana plugin not found, skipping migration
INFO Auto Update plugin not found, skipping migration
INFO Deploy-image plugin not found, skipping migration
INFO Running make fmt
go fmt ./...
INFO Running make vet
go vet ./...
INFO Running make lint-fix
Downloading github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.5.0
"..../my-operator-code/bin/golangci-lint" run --fix
0 issues.
```

一応これで中身のないスケルトンコードが生成された状態になっています。

### v3.14.0とv4.10.1が生成するコードベースの違い

``git status``コマンドで差分を確認すると、いくつかの違いが確認できます。

* config/ディレクトリの構成が大きく変化している点
* api/v1/にあったwebhook関連のコードがinternal/webhook/v1/に移動している点

最初にkubebuilderを利用した時には別に実行していたwebhook関連のコード生成は既に行われた状態です。

念のため次のようにwebhook関連のコードを再生成してみても変化はありませんでした。

```bash:
$ kubebuilder create webhook --group "mygroupname" --version v1 --kind Members --defaulting --programmatic-validation --force
```

## コードの統合作業

### ``api/``ディレクトリと``internal/``ディレクトリ

古いコードリポジトリから``api/``ディレクトリと``internal/``ディレクトリの内容を統合します。

この時にwebhook関連のコードは``api/``ディレクトリにあるので、diffコマンドで差分を確認しながらコードを手動でマージしました。

webhook関連のコードは``cmd/main.go``から呼ばれる際の関数名が変更されているため、単純にファイル全体を置き換える方法では失敗します。

### ``config/``ディレクトリ

前のセクションで書いた``config/``ディレクトリの構成が変更されていますが、元々自動的に生成されていたものなので、そのままcommitして手動での変更は行っていません。

### Dockerfileの構成変更への対応

生成されるDockerfileの中でCOPY命令が変更(個別ファイルのCOPYから``COPY . .``に変更)されているのですが、トップディレクトリにあるgo.mod,go.sum等を除くと必要なファイルがコピーされない状況になったので``.dockerignore``ファイルに以下の3行を追加しました。

```text:.dockerignoreファイルに追加した部分
!cmd/
!api/
!internal/
```

### Makefileの変更

``make``コマンドの実行時に引数でIMG変数を変更することもできますが、gitで管理するためにMakefileを編集して``IMG``変数と``CONTAINER_TOOL``変数を変更しています。

``IMG``変数には``make docker-push``コマンドで送信先になるコンテナ・レジストリとしてローカルのHarborのホスト名とPROJECT名とタグ名を指定しています。

``CONTAINER_TOOL``変数は、``docker``コマンドから``podman``に変更しています。

```Makefile:Makefileの変更例

IMG ?= harbor.example.org/myproject/controller:20260119.1200

CONTAINER_TOOL ?= podman

```

## コードのビルドとアップグレード作業

作成したCustom ControllerをKubernetesクラスターにデプロイするためには次の2つが必要です。

1. コンテナ・レジストリ(ここではharbor.example.org)にpushしたコンテナ・イメージ
2. dist/install.yamlファイル

この2つを準備するためのコマンドラインは概ね次のようになります。

```bash:
$ make generate
$ make manifests
$ make build
$ make docker-build
$ make docker-push
$ make build-installer
```

最終的に``dist/install.yaml``ファイルが出力されるので、これをKubernetesクラスターに接続できる``kubectl``コマンドから``apply -f``で導入すればコンテナ・レジストリからイメージが導入されます。

```bash:kubectlを利用したインストール手順例
$ kubectl -n <ns-name> apply -f dist/install.yaml
```

MakefileでHarbor(コンテナ・レジストリ・サーバー)名を含む完全修飾名をIMG変数で指定しているため、install.yamlにもその完全修飾名がコピーされるため、作業は単純化されています。

:::note
アップグレードの際にはdeploymentオブジェクトが更新できなかったので、手動で削除(``kubectl -n <my-custom-controller-ns> delete deploy controller``)を実行してから``apply -f``で導入しています。
:::

以上
