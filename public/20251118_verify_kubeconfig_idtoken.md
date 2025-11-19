---
title: kubectlで利用しているid-tokenをJWT.ioで検証してみた
tags:
  - Ruby
  - JWT
  - dex
private: false
updated_at: '2025-11-19T11:05:39+09:00'
id: f098887ec6bc47beb2f3
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

別記事でdexidp/dexのOIDC IdPから発行されたid-tokenを検証する方法について記事にまとめました。

https://qiita.com/YasuhiroABE/items/ceb1142d70770fb7e7cf

今回はOIDC IdPと連携しているKubernetesに接続するために設定した ~/.kube/config に記述しているid-tokenの情報を``jwt.io``で検証してみます。

dexidp/dexに付属するexample-appが改造されて、それっぽいUIになって、``jwt.io``ページへのリンクも追加されています。

以前の記事をまとめて検証用にPEM形式の公開鍵を取り出す仕組みについて記事にまとめます。

なおコード中の前半部分の``jwt_text``変数に、id-token文字列を代入してしまえば後の処理は同じなのであまりおもしろくないと思います。

# セキュリティについて

JWT.ioのトップページにも警告されていますが、id-token(JWT)の情報は認証情報そのものです。

悪意を持った第三者に自分自身を詐称される可能性があるため少なくともインターネット上からアクセス可能なシステムで利用可能なJWTを送信することは止めましょう。

# 環境

Rubyはソースコードからデフォルトのままビルドしたものを利用しています。

* Ubuntu 24.04.3 (LTS)
* Ruby 3.4.6

# コード

ライブラリはGemfileで設定しています。

## 本体

以前の記事のコードをつなげて、~/.kube/config を読むように変更しています。

```ruby:verify-kubeconfig.rb
#!/usr/bin/ruby

require 'bundler/setup'
Bundler.require

def usage()
  puts "Usage: #{$0} <path to kubeconfig>"
  puts "  e.g.: #{$0} ~/.kube/config"
  exit 1
end

## Parse command line arguments and validate kubeconfig file exists
KUBE_CONFIG = ARGV.length == 1 ? ARGV[0] : "#{ENV['HOME']}/.kube/config"
usage unless File.exist?(KUBE_CONFIG)

## Extract JWT token from kubeconfig file
jwt_text = nil
## Load kubeconfig YAML and extract id-token from auth-provider config
kubeconfig_object = YAML.load_file(KUBE_CONFIG)
if kubeconfig_object["users"].nil? || kubeconfig_object["users"].length == 0
  puts "No users found in kubeconfig: #{KUBE_CONFIG}"
  usage
elsif kubeconfig_object["users"][0]["user"].nil? || kubeconfig_object["users"][0]["user"]["auth-provider"].nil?
  puts "No OIDC auth-provider found in kubeconfig: #{KUBE_CONFIG}"
  usage
elsif kubeconfig_object["users"][0]["user"]["auth-provider"]["config"].nil?
  puts "No auth-provider config found in kubeconfig: #{KUBE_CONFIG}"
  usage
elsif kubeconfig_object["users"][0]["user"]["auth-provider"]["config"]["id-token"].nil?
  puts "No id-token found in kubeconfig: #{KUBE_CONFIG}"
  usage
end
jwt_text = kubeconfig_object["users"][0]["user"]["auth-provider"]["config"]["id-token"]

puts "--- JWT text ---"
puts jwt_text

## Decode JWT (unverified) to get issuer, then fetch JWKS URI from OIDC discovery endpoint
claim,algo = JWT.decode(jwt_text, nil, false)
oidc_config = JSON.parse(HTTPClient.new.get(claim["iss"] + "/.well-known/openid-configuration").body, symbolize_names: true)
JWKS_URI = oidc_config[:jwks_uri]

puts "--- verified output ---"
## Define JWK loader function to fetch and cache public keys from JWKS URI
jwk_loader = ->(options) do
  ## Fetch public keys from JWKS endpoint and cache them
  pub_keys = JSON.parse(HTTPClient.new.get(JWKS_URI).body, symbolize_names: true)
  @cached_keys = nil if options[:invalidate] # need to reload the keys
  @cached_keys ||= pub_keys
end
begin
  claim,algo = JWT.decode(jwt_text, nil, true, { algorithms: [algo["alg"]], jwks: jwk_loader }) ## algo["alg"] == "RS256"
  puts claim,algo
rescue JWT::DecodeError => e
  puts "JWT Decode Error: #{e.message}"
  puts "Failed to find the proper public key from JWKS URI: #{JWKS_URI}"
  exit(1)
end

require 'base64'
@cached_keys[:keys].each do |ent|
  next unless ent[:kid] == algo["kid"]
  ## Extract and display the RSA public key in PEM format
  n_b64 = ent[:n].tr('-_', '+/')
  e_b64 = ent[:e].tr('-_', '+/')
  n_bytes = Base64.decode64(n_b64)
  e_bytes = Base64.decode64(e_b64)

  n_bn = OpenSSL::BN.new(n_bytes, 2)
  e_bn = OpenSSL::BN.new(e_bytes, 2)
  key_sequence = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer.new(n_bn),
      OpenSSL::ASN1::Integer.new(e_bn)
  ])
  rsa_key = OpenSSL::PKey::RSA.new(key_sequence.to_der)
  puts rsa_key.to_pem
end
```

## Gemfile

```ruby:Gemfile
source 'https://rubygems.org'

gem 'json'
gem 'jwt'
gem 'httpclient'
gem 'openssl'
gem 'mutex_m'
gem 'yaml'

```

# 実行方法

GemfileとRubyスクリプトを適当なディレクトリに配置してから進めます。

必要なライブライは"./lib"ディレクトリに格納しているので初回にライブラリをセットアップします。

```bash:
$ bundle config set path lib
$ bundle install
```

以降はbundleコマンドはスクリプトを実行する時にだけ使用します。

```bash:
$ bundle exec ruby ./verify-kubeconfig.rb
```

デフォルトでは、``~/.kube/config``ファイルを読みますが、他のファイルを指定したい場合には、引数に渡します。

```bash:他のkubeconfigファイルを渡す例
$ bundle exec ruby ./verify-kubeconfig.rb ~/.kube/config.test
```

成功すれば、次の3つの情報を順番に表示します。

1. id-token文字列
2. デコードしたid-tokenの情報
3. 対応するPEM形式の公開鍵

jwt.ioに最後の公開鍵の情報をコピー&ペーストすれば、検証結果が画面に表示されます。


# JWK(JSONフォーマット)を利用した検証

JWT.ioではJWK形式の鍵情報も受け付けてくれます。

ただ``https://example.org/dex/keys``のようなOIDC IdPの公開鍵のエンドポイントにアクセスすると、次のようなJSON形式のデータが表示されています。

```json:https://example.org/dex/.well-known/openid-configurationのjwks_uri情報
{
  "keys": [
    {
      "use": "sig",
      "kty": "RSA",
      "kid": "aa00...",
      "alg": "RS256",
      "n": "30...",
      "e": "AQAB"
    },
    {
      ...
    }
  ]
}
```

この情報全体をコピ&ペーストしてもid-tokenの検証はできません。

ここからid-tokenの``kid``をみて適当な情報だけをコピーすると、検証に成功するはずです。

```json:jwt.ioのJWKタイプの公開鍵情報の入力例
    {
      "use": "sig",
      "kty": "RSA",
      "kid": "aa00...",
      "alg": "RS256",
      "n": "30...",
      "e": "AQAB"
    }
```

注意するところは、jwt.ioのサイトで公開鍵タイプを"PEM"から"JWK"に変更すること、コピーする時に``},``のように最後にカンマを入力しないようにするところぐらいかなと思います。


