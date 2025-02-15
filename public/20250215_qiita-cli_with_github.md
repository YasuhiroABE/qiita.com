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

