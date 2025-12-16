---
title: Django 5.2.1に以降したらlogoutボタンが動作しない事に気がついた
tags:
  - Django
private: false
updated_at: '2025-05-21T16:38:16+09:00'
id: 338a9efcbad4df8430cc
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

外部に公開しているサイトがあって頻繁にDjangoのバージョンを上げています。

LTSのバージョンが4.2から5.2に変更になったので対応したのですが、ほぼほぼ問題ないことを確認した後でlogoutリンクが動作しない事に気がつきました。

実際の変更は昨年入っていたのですが、セキュリティ面を考慮して**csrf_token**を必須としたようです。

https://forum.djangoproject.com/t/deprecation-of-get-method-for-logoutview/25533/5

GETでログアウトできるといたずらでの総攻撃には弱そうなので妥当だなと思いつつ、単純なテキストリンクをボタンで再実装しました。

# 対策

HTML上でシンプルなAnchorタグをButtonに変更します。

Bootstrap5を利用していて、だいたい次のような差分で見た目には同様になったと思います。

```diff:git diffによる差分
diff --git a/templates/base.html b/templates/base.html
index 47f3c79..6e11be1 100644
--- a/templates/base.html
+++ b/templates/base.html
@@ -32,7 +32,12 @@
                <li class="list-inline-item ps-4"><a href="{% url 'top' %}">Home</a></li>
                {% if request.user and request.user.is_authenticated %}
                <li class="list-inline-item"><a href="{% url 'profile' %}">Profile</a></li>
-               <li class="list-inline-item"><a href="{% url 'logout' %}">Logout</a></li>
+               <li class="list-inline-item">
+                 {# See also: "https://forum.djangoproject.com/t/deprecation-of-get-method-for-logoutview/25533/2" #}
+                 <form method="post" action="{% url 'logout' %}">{% csrf_token %}
+                   <button class="btn btn-link p-0 m-0 b-0 mb-1" type="submit">Logout</button>
+                 </form>
+               </li>

                <li class="list-inline-item mx-4"><a href="{% url 'password_change' %}">Change password</a></li>

```

# さいごに

この他にDjango 5.2系列へのアップグレード時に問題になったのは、4.2で既にプランに入っていた **|length_is:** フィルターの廃止でした。

単純な置き換えで対応できるので問題はまったくありませんが、エラー画面をみるのはあまり気持ちの良いものではありません。

今回利用しているライブラリの中では``django-fobi``でこの問題への対応をしています。

該当するコードは添付されているthemeに含まれるdjango2テンプレートなので、ライブラリ側にパッチをあてる必要はありませんでした。

Djangoは便利な点は多いですが、過去の経験からORMを利用しているところはかなり怖いです。

