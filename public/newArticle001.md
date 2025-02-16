---
title: qiita-cliのテスト
tags:
  - qiita-cli
private: false
updated_at: '2025-02-16T20:48:07+09:00'
id: 1b4b539245b45d9f1d0f
organization_url_name: null
slide: false
ignorePublish: false
---
# qiita-cliを利用した記事投稿のテスト

``npx qiita publish newArticle001``を実行してから、``npx qiita pull``を実行するとファイル名はIDで作成されるのかテストするための記事です。

## ファイル名は変更されない

``npx qiita``コマンドだけを使っている範囲では、``public``ディレクトリの中に同一記事のファイルが重複して作成されるということはありませんでした。

```bash:git statusの出力
On branch main
Your branch is up to date with 'origin/main'.

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        public/newArticle001.md

nothing added to commit but untracked files present (use "git add" to track)
```

次にこの顛末を追記したファイルをgit add/commitしてActions経由で投稿してみましょう。




