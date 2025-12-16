---
title: OpenAPI GeneratorのRuby/Sinatraテンプレートを改造して実装ロジックを分離してみた
tags:
  - Ruby
  - Sinatra
  - mustache
  - OpenAPIGenerator
private: false
updated_at: '2025-01-21T09:23:01+09:00'
id: b3cf17aec64ba62baf88
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

OpenAPI Generator CLIのバージョンも気がつけば6.6.0になっていて、いまでも"ruby-sinatra"のサーバーテンプレートを好んで利用しています。しかし以前からopenapi.yamlを変更し、generateを繰り返し行うとテンプレートの再編集が面倒だなと感じていました。

OpenAPI Generatorを改造し、Sinatraのhelpers機能を利用することで、実装用のファイルを分離することにしました。

管理が容易になることを目指した変更ですが、目的にかなっているのかしばらく使ってみます。

# 参考資料

* [openapi-generator で自作テンプレートを用いて iOS API クライアントを自動生成した話](https://qiita.com/tasuwo/items/5e3aa7af8d4fee55714f)
* [Debugging | OpenAPI Generator](https://openapi-generator.tech/docs/debugging/)
* [SinatraはDSLなんかじゃない、Ruby偽装を使ったマインドコントロールだ！](https://melborne.github.io/2011/06/03/Sinatra-DSL-Ruby/)

また別のアプローチでテンプレートを改造している記事があります。

* [OpenApiGeneratorのRubySinatraServerのテンプレをカスタマイズして開発しやすくした](https://qiita.com/to_muu_mas/items/b86b5decb504d3b106c7)

# 現状のコード

``openapi-generator-cli generate -g ruby-sinatra -o code -i openapi.yaml`` のようなコマンドラインで生成されるコードに含まれる code/api/default_api.rb の内容は次のようになっています。

```ruby:api/default_api.rbの抜粋
MyApp.add_route('GET', '/context-root/types', {...}) do
  cross_origin
  # the guts live here

  {"message" => "yes, it worked"}.to_json
end
```

## 出力させたい変更後のコード

次のように2つのファイルに処理を分割します。

```ruby:api/default_api.rb
MyApp.add_route('GET', '/context-root/types', {...}) do
  cross_origin
  # the guts live here

  types_get()
end
```

```ruby:api/helpers.rb
class MyApp
  helpers do
    def types_get
      {"message" => "yes, it worked", "request.url" => request.url, "params" => params}.to_json
    end
end
```

Sinatra.helpersを利用することで、メソッドにparamsなどのパラメーターを引数として渡さずにcontext内で処理をすることができます。

テンプレートにはrequest,paramsなどのローカル変数にアクセスできることを示すためのコードを追加しました。実際には ``to_json`` メソッドではなく、JSON.pretty_generate を使用しています。

## Sinatra.helpersメソッド

Sinatra.helpersメソッドは、Sinatraの動作を拡張したり、重複する処理を削減することなどを目的に準備された機構です。

後方互換性を確保するなど、異なるpathでも動作は同じといった処理をさせるために、処理内容をメソッドにまとめることは一般的ですが、そのメソッドをSinatra.helpersに渡し、Moudle::class_evalで処理することで動的に現在のコンテキストに機能を追加します。

詳細は参考資料にリンクを追加しているので、そちらの記事をご覧ください。

# OpenAPI Generatorの改造

GitHubから最新版のコードをcloneしたところから作業を開始します。
変更する・追加するファイルは次のとおりです。

* modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/RubySinatraServerCodegen.java
* modules/openapi-generator/src/main/resources/ruby-sinatra-server/api.mustache
* modules/openapi-generator/src/main/resources/ruby-sinatra-server/helpers.mustache (新規追加)

api.mustacheのようにhelpers.mustacheを作成すれば良いのかと思ったところ少しはまりました。
参考資料のところにリンクがあるのでテンプレートについてはそちらを参照してください。

api.mustache ファイルは、apiTemplateとして扱われていて、Mustacheから参照できるデータはOperationsです。参考資料では、debugOpenAPI=true だけが紹介されていましたが、apiTemplate から参照するファイルからアセクスできるデータ構造は debugOperations オプションで確認できます。

```bash:apiTemplateから参照できるデータ構造を表示させる
$ openapi-generator-cli generate -g ruby-sinatra -o code -i openapi.yaml --global-property debugOperations
```

新たに追加するhelpers.mustacheはSupportingFileとして追加するため、参照できるデータ構造は debugSupportingFiles となります。

単純に ``{{#operations}}{{#operation}} ... {{/operations}}{{/opearation}}`` で囲めばループができるのかと思ったのですが、そうはいきませんでした。

実際に追加した helpers.mustache ファイルの内容は以下のとおりです。

```mustache:helpers.mustache
## nicknameと同名のメソッドを生成するテンプレート
class MyApp
  helpers do
{{#apiInfo}}
{{#apis}}
{{#operations}}{{#operation}}
    def {{nickname}}
      JSON.pretty_generate({"message" => "yes, it worked", "request.url" => request.url, "params" => params})
    end
{{/operation}}{{/operations}}
{{/apis}}
{{/apiInfo}}
  end
end
```

MyAppクラスはSinatra::Base → OpenAPIingクラスから派生していて、my_app.rb で定義されています。

他のGeneratorのmustacheファイルを参考にすれば、ちゃんとこのように{{#operations}}にアクセスできる利用例が確認できますが、ruby-sinatraのapi.mustacheファイルだけをみていたので気がつくのに少し時間がかかりました。

ApiTemplateから参照するOperationsのデータ構造は次のようになっています。

```json:Operations
[ {
  "importPath" : "api.Default",
  "infoName" : "Yasuhiro ABE",
  "appVersion" : "0.0.1",
  ...
  "operations" : {
    "classname" : "DefaultApi",
    "operation" : [ {
    ...
```

このため直接Mustacheテンプレートに``{{#operations}}...{{/operations}}``のように書けます。

SupportingFilesのデータ構造は次のようになっています。

```json:SupportingFiles
{
  "infoName" : "Yasuhiro ABE",
  ...
  "apiInfo" : {
    "apis" : [ {
      ...
      },
      "generateModels" : true,
      "operations" : {
        "classname" : "DefaultApi",
        "operation" : [ {
          ...
```

このためApiTemplateと同様に記述すると描画されず、ループにならないため、``{{#apiInfo}}``から記述する必要があります。

## 全体の変更点

v6.6.0をベースにしたmasterブランチのコードとの差分は次のようになります。

```diff:
diff --git a/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/RubySinatraServerCodeg
en.java b/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/RubySinatraServerCodegen.
java
index 1e51a349e0d..e82f673b6e6 100644
--- a/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/RubySinatraServerCodegen.java
+++ b/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/RubySinatraServerCodegen.java
@@ -88,6 +88,7 @@ public class RubySinatraServerCodegen extends AbstractRubyCodegen {
         supportingFiles.add(new SupportingFile("README.md", "", "README.md"));
         supportingFiles.add(new SupportingFile("openapi.mustache", "", "openapi.yaml"));
         supportingFiles.add(new SupportingFile("Dockerfile", "", "Dockerfile"));
+        supportingFiles.add(new SupportingFile("helpers.mustache", "api", "helpers.rb"));
     }
 
     @Override
diff --git a/modules/openapi-generator/src/main/resources/ruby-sinatra-server/api.mustache b/modules/openapi-g
enerator/src/main/resources/ruby-sinatra-server/api.mustache
index 92db211f619..da650f3b2f3 100644
--- a/modules/openapi-generator/src/main/resources/ruby-sinatra-server/api.mustache
+++ b/modules/openapi-generator/src/main/resources/ruby-sinatra-server/api.mustache
@@ -54,9 +54,9 @@ MyApp.add_route('{{httpMethod}}', '{{{basePathWithoutHost}}}{{{path}}}', {
     {{/bodyParams}}
     ]}) do
   cross_origin
-  # the guts live here
+  # the guts live with helpers
 
-  {"message" => "yes, it worked"}.to_json
+  {{nickname}}
 end
 
 {{/operation}}
diff --git a/modules/openapi-generator/src/main/resources/ruby-sinatra-server/helpers.mustache b/modules/opena
pi-generator/src/main/resources/ruby-sinatra-server/helpers.mustache
new file mode 100644
index 00000000000..0e491dd2749
--- /dev/null
+++ b/modules/openapi-generator/src/main/resources/ruby-sinatra-server/helpers.mustache
@@ -0,0 +1,14 @@
+
+class MyApp
+  helpers do
+{{#apiInfo}}
+{{#apis}}
+{{#operations}}{{#operation}}
+    def {{nickname}}
+      JSON.pretty_generate({"message" => "yes, it worked", "request.url" => request.url, "params" => params})
+    end
+{{/operation}}{{/operations}}
+{{/apis}}
+{{/apiInfo}}
+  end
+end
```

## OpenAPI Generatorをビルドする

改造したコードをビルドする方法は複数ありますが、ここではmavenを利用しています。

さらにビルドしたJARファイルを最新版のopenapi-generator-cliにコピーしています。

```bash:変更したコードのビルド
$ mvn clean install
```

maven(mvn)はJAVA_HOME環境変数を参照します。
JDK8 or 11でない場合にはjavadoc関連のテストに失敗するため、JAVA_HOMEを適切に設定してください。

:::note
v7.10.0でJDK21を利用したところエラーになりました。

openapi-generator-gradle-pluginを実行中にエラーになりました。

```
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for openapi-generator-project 7.10.0:
...
[INFO] openapi-generator-gradle-plugin (maven wrapper) .... FAILURE [01:03 min]
[INFO] openapi-generator-online ........................... SKIPPED
[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
...
[ERROR] Failed to execute goal org.fortasoft:gradle-maven-plugin:1.0.8:invoke (default) on project openapi-generator-gradle-plugin-mvn-wrapper: org.gradle.tooling.BuildException: Could not execute build using connection to Gradle distribution 'https://services.gradle.org/distributions/gradle-7.6.4-bin.zip'. -> [Help 1]
```

v7.10.0のビルドにはAdoptiumからダウンロードしたJDK11を利用しています。
:::

```text:mvn clean install実行時のエラーメッセージ
MavenReportException: Error while generating Javadoc: Project contains Javadoc Warnings
```

```bash:JAVA_HOME環境変数の設定と確認
## 設定
$ export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64

## 確認
$ echo $JAVA_HOME
/usr/lib/jvm/java-1.8.0-openjdk-amd64
```

openapi-generator-cli は npm を利用して、/usr/local/ に導入しています。

生成されたJARファイルを置き換えてテストします。

```bash:生成したコードのコピー
$ sudo cp modules/openapi-generator-cli/target/openapi-generator-cli.jar /usr/local/lib/node_modules/@openapitools/openapi-generator-cli/versions/6.6.0.jar
```

## 実行例 - デフォルトの挙動

生成されたコードは次のようなメッセージを返すようになっています。

```bash:curlによるAPIへのアクセス例
## GETメソッドでアクセスした場合
$ curl 'http://localhost:8080/api/v1/person' 
{
  "message": "yes, it worked",
  "request.url": "http://localhost:8080/api/v1/person",
  "params": {
  }
}

## POSTメソッドでアクセスした場合
$ curl -X POST 'http://localhost:8080/api/v1/person' -d 'name=yasu&age='
{
  "message": "yes, it worked",
  "request.url": "http://localhost:8080/api/v1/person",
  "params": {
    "name": "yasu",
    "age": ""
  }
}
```


## 生成したhelpers.rbの読み込み処理について

my_app.rbの中でapi/ディレクトリに配置されたRubyスクリプトをrequireで読み込む処理が実行されています。

```ruby:my_app.rbから抜粋
# include the api files
Dir["./api/*.rb"].each { |file|
  require file
}
```

このためファイルを分割することも可能ですし、今回はこの機能を利用してapi/helpers.rbファイルを追加するだけで自動的に読み込まれるようになっています。

# さいごに

今回の変更によって、 api/default_api.rb ファイルは基本的に編集する必要がなくなりました。

また別のファイルを編集するようになっただけのように思われますが、生成するhelpers.rbに記述されるメソッド名はpathとrequest methodから予測可能になったため、先ほどのapi/ディレクトリに置かれたファイルの自動requireの仕組みから、処理毎にファイルを分割し管理することも可能です。

私はOpenAPI Generatorを利用する最大のメリットは開発手順の標準化だと思います。
クライアントのスケルトンコードの生成などにはそれほど期待していません。

Ruby/Sinatraのフレームワークを利用しても、現状ではvalidationなどのロジックはほぼないので、OpenAPI Specification で定義された内容と違う入力があっても、そのまま処理されます。

Pythonなど別のフレームワークでは、入出力の検証が厳格な場合があって、油断していると少し面喰いますが、コードの品質向上に貢献するかどうかは選択したgeneratorとフレームワークの品質次第かなと思います。

Ruby/Sinatraが出力するコードはオリジナルは別の方が書かれたものなので、PRではDockerfileを追加するだけで、Makefileの出力は追加しませんでしたが、個人的には次のようなMakefileを準備しています。

```makefile:様々なプロジェクトで利用しているSinatra用のMakefile
NAME = my-nginx
DOCKER_IMAGE = my-nginx
DOCKER_IMAGE_VERSION = 1.0
IMAGE_NAME = $(DOCKER_IMAGE):$(DOCKER_IMAGE_VERSION)
REGISTRY_SERVER = harbor.example.com
REGISTRY_LIBRARY = yasu.private

PROD_IMAGE_NAME = $(REGISTRY_SERVER)/$(REGISTRY_LIBRARY)/$(IMAGE_NAME)

.PHONY: all build build-prod tag push run stop check

all:
	@echo "Please specify a target: make [run|docker-build|docker-build-prod|docker-push|docker-run|docker-stop|check|clean]"

run: bundle-install
	env FORM_BASEURI="$(PROTOCOL)://$(HOST):$(PORT)/$(URI_PATH)" \
		bundle exec rackup --host $(HOST) --port $(PORT)

bundle-install:
	bundle config set path lib
	bundle install

docker-build:
	sudo docker build . --tag $(DOCKER_IMAGE)

docker-build-prod:
	sudo docker build . --tag $(IMAGE_NAME) --no-cache

docker-tag:
	sudo docker tag $(IMAGE_NAME) $(PROD_IMAGE_NAME)

docker-push:
	sudo docker push $(PROD_IMAGE_NAME)

docker-run:
	sudo docker run -it --rm -d \
		--env NGINX_PORT=80 \
		-p 8080:80 \
		-v `pwd`/html:/usr/share/nginx/html \
		--name $(NAME) \
                $(DOCKER_IMAGE)

docker-stop:
	sudo docker stop $(NAME)

clean:
	find . -name '*~' -type f -exec rm {} \; -print
```

いろいろな仕組みを組合せて、開発作業に統一感を持たせています。

# 後日談 〜 Dockerにまとめてみた

当初はローカルにインストールしたopenapi-generator-cliのJARファイルを置き換えて利用していましたが、バージョンアップも頻繁にあるため自分用のDockerコンテナにまとめることにしました。

その関連作業の結果、openapi-generator-cliコマンドをdocker環境から実行するためカスタマイズした ``docker.io/yasuhiroabe/my-ogc:6.6.0`` コンテナを作成・登録しています。

```bash:コンテナの基本的な使い方
$ docker run -it --rm -v `pwd`:/local docker.io/yasuhiroabe/my-ogc:6.6.0 version
6.6.0

$ ls openapi.yaml
openapi.yaml

## Mount the current working directory ($PWD) to /local of the invoked container.
$ podman run -it --rm -v `pwd`:/local docker.io/yasuhiroabe/my-ogc:6.6.0 generate -g ruby-sinatra -o code -i openapi.yaml
```

Dockerfileの内容は以下のとおりです。

```Dockerfile:Dockerfile
FROM openapitools/openapi-generator-cli:v6.6.0

## replaced the cli JAR file with my modified version.
COPY openapi-generator-cli.jar /opt/openapi-generator/modules/openapi-generator-cli/target/openapi-generator-cli.jar

WORKDIR /local
```

オリジナルのWORKDIRの指定がなさそうなので明示的に/localを指定しています。

``-v `pwd`:/local`` をオプションに指定することで、``-o``オプションに指定する出力先がカレントディレクトリに生成されます。

これは当たり前のように思えますが、``-o``オプションに指定するパスを他の場所にしようとすると少し問題です。

コンテナ内部では、openapi.yamlファイルと、出力先のディレクトリパスが両方とも、``/local``経由でアクセスできるようになるように調整してください。

以上
