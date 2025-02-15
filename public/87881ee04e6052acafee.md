---
title: Githubを使ってQiitaの記事を管理してみた
tags:
  - 'qiita-cli'
  - 'github'
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

QiitaでGitHub Actionsを使って記事を管理する方法が掲載されていたので、試してみました。

https://qiita.com/Qiita/items/32c79014509987541130

https://github.com/increments/qiita-cli

```bash:
$ npx qiita new 20250215_newarticle
$ emacs public/20250215_newarticle.md
$ git add public/20250215_newarticle.md
$ git push
```

この記事を含む私のQiita記事はGitHub上で公開しています。

https://github.com/YasuhiroABE/qiita.com

# 下書きに登録されている記事の取り扱い

``npx qiita pull``を実行すると公開されている記事が全てダウンロードされます。

裏を返すと``下書き``に登録されている記事はそのままになってしまいます。

１度記事を投稿して公開すれば``npx qiita pull``で新規記事としてダウンロードできるはずなので、一応確認しておきます。

## 下書きに登録されている記事を公開してから同期を取る

記事を完成させて反映させてから同期させます。

```bash:
$ npx qiita pull
```

``git``コマンドで差分を確認します。

```bash:
$ git status
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   .gitignore
        modified:   Makefile

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        public/20250215_newarticle.md
        public/36dbe88619c258eb5b74.md

no changes added to commit (use "git add" and/or "git commit -a")
```

## 登録済みの記事をpushして変化がないか確認する

``public/36dbe88619c258eb5b74.md``をcommitして``git push``してみます。

この時の記事の更新時刻は``updated_at: '2025-02-15T21:18:13+09:00'``でした。

```bash:
$ git add public/36dbe88619c258eb5b74.md
$ git commit -m 'Added new published article public/36dbe88619c258eb5b74.md.'
$ git push
```

この後、``npx qiita pull``を実行しても特に変化はなく、既存の記事がGitHub Actionsで処理されることはありませんでした。

## 新規記事を投稿する

書きかけの ``public/20250215_newarticle.md`` を登録します。

```bash:
$ git add public/20250215_newarticle.md
$ git commit -m 'Added new article public/20250215_newarticle.md.'
$ git push
```

GitHubのプロジェクトページに移動して、Actionsタブから経過を見守ります。

30secで処理が完了したと記録されていますが、``git push``してからは2分ぐらいは経過していた印象です。

# 気がついたこと

## preview機能が秀逸

ファイルの更新に応じてpreviewも更新されるためQiita公式サイトで編集するのと大きな違いを感じませんでした。

画像ファイルのアップロードはpreviewページのリンクを辿って公式サイトで手動で管理しなければいけない点は少し面倒ですが、クリップボードからのコピーができてMarkdown形式でURLのコピーが出来るので、これは大きな障害ではないと思っています。

![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/78296/304c6df0-e6b9-4167-9e3d-79a838823dd7.png)

## 内容の重複するファイルが作成されてしまう

``npx qiita new``で作成したファイルを``git push``すると、ActionsによってQiitaに記事が登録されます。

この後に``npx qiita pull``を実行するとQiita側に登録された記事が``public/87881ee04e6052acafee.md``のようなファイル名で新しく作成されます。

こちらで適当に作成したファイル名とQiita側で統一的にIDで管理されているファイルの2つが出来るのは当然ですが、どちらを編集するべきか、考えなければいけないという点では少し悩ましいです。

GitHub側から全てのファイルをpushして、``npx qiita pull``を止めれば良いというのは、revalidationが出来なくなる点で問題があります。

これは結構悩ましく、投稿したことでIDが確定するのでファイル名は予測不可能です。

後から``git mv``でIDのファイル名に変更するのが最善手のように考えています。

:::note
手元ファイルの編集途中に``npx qiita pull``をすると上書きされてしまう点には少しだけ注意が必要ですが、これはこの問題とは無関係で他の管理形態であっても発生する課題です。
:::


