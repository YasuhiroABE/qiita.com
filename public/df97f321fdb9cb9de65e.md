---
title: Ansible GalaxyのRoleに対するネーミングルールが変更になってた
tags:
  - Ansible
private: false
updated_at: '2018-09-19T23:02:07+09:00'
id: df97f321fdb9cb9de65e
organization_url_name: null
slide: false
ignorePublish: false
---

Ansible Galaxyでのワークフローは、"ansible-role_name"で始まるリポジトリをGithubに登録し、Ansible Galaxy側で"ansible-"を取り除いた"role_name"を名前として登録する流れになっていました。

しばらくぶりにAnsible GalaxyにRoleを登録したところ、このネーミングルールが撤廃されてとまどったのでメモを残しておきます。

# 参考資料

* [公式Ansible Galaxyドキュメント - Role Metadata](https://galaxy.ansible.com/docs/contributing/creating_role.html#role-metadata)

# 解決方法

参考資料のドキュメントの先頭にあるように、"role_name"という項目が```meta/main.yml```に追加されています。

Optionalに分類されていますが、Githubのリポジトリ名がそのまま反映される事には違和感がありますし、従来のネーミングルールはとても良くできていたので事実上は必須ではないかなと思います。

改めてmeta/main.ymlを編集し、```$ git commit -m 'comment' && git push```をしておきました。

```markdown:meta/main.yml
galaxy_info:
  role_name: foo
  author: your name
```

Github上では"ansible-"で始まるリポジトリが、Ansible Galaxy関連のものだと分かりやすいので、このルール自体は撤廃されても自主的に守った方が良さそうです。

# 【閑話休題】Ansible Galaxyのすゝめ

何かしら前提はあったとしても、汎用的に設定が変更できるような、変数と処理フローが分離しているansible roleを作成した場合には、Ansible Galaxyに追加することを検討してみてください。

基本的なワークフローは、次のようなものです。
1. ```$ ansible-galaxy init <role name>``` で雛形roleディレクトリを作成
2. tasks/main.yml, defaults/main.yml などにファイルを配置し、roleを作成する
3. README.md ファイルを編集する
4. meta/main.yml を編集する
5. Githubに適当なディレクトリを作成し、commit & push する
6. Ansible GalaxyにGithub連携でログインし、追加

慣れないと余計なREADME.mdやmeta/main.ymlを記述するのが面倒そうですが、制約事項などはきちんと書くとして、自分が以前作ったファイルを元にするなどして、いくらか工程は省略できます。

Ansible Galaxyに登録されているRole自体は、羃等性に対する検討があまりされておらず、そのままでは使いずらいものがよくあります。
私自身もそんなRoleを登録していると思います。

しかし、そのまま使えずとも貴重な参考資料になることは間違いありません。
自分の成果を残す事は、自分の作業ログを残す事、コミュニティへの貢献という点でも、大切です。

公開すると叩かれる燃料を投下するだけという印象を持つようですが、叩くだけのような悪い人の事は気にせずに、足跡を残して実績を積み上げて欲しいなと思っています。
