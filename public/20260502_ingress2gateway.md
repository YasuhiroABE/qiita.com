---
title: IngressからGateway APIに移行した時のメモ
tags:
  - kubernetes
  - ingress
  - envoy
private: false
updated_at: '2026-05-10T11:03:39+09:00'
id: 75803ceda3feafcf4dbd
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

ingress-nginxがEnd of Serviceになってセキュリティパッチを含めた全てのサービス提供が終了しました。

nginxは馴染みがあるので便利なツールでしたが、細かい制御では課題も感じていたところです。

とはいえkubesprayもv2.30.0を最後に提供を終了しているので、現在の最新版ではingress-nginxを更新することはできません。

この機会に後継のGateway APIに移行することにしたので、その際のメモを残しておきます。

# 作業全体の流れ

まずGateway APIはIngressと同様に実装から切り離された抽象度の高いAPI(規約)です。

新しいだけあってモダンなAPIの実装として参考になりそうです。

https://gateway-api.sigs.k8s.io/

実際に制御を行うコントローラーとしてはいくつかの実装がありますが、今回はEnvoy Gatewayをバックエンドに導入することにしました。

https://gateway.envoyproxy.io/

このEnvoy Gatewayがingress-nginxの代わりに(移行が終るまでは並行して)動作することになります。

またいきなり移行はできないので、ingress-nginxと同様のホスト名でサービスを行うようにして、URLのsub-path毎に移行するようにします。

また``ingress2gateway``といったツールも提供されていますが、まずはGatewayの実装を導入する必要がありそうです。x

https://github.com/kubernetes-sigs/ingress2gateway

## 全体の構成

一見すると``ns/envoy-gateway-system``と``ns/gateway-system``の2つにnamespaceを分割する必要性はなさそうに思えますが、Envoy Gatewayは更新などの際にHelmによってupgradeされます。

混乱を避けるためにシステム管理者が設定するGateway全体の設定(ns/gateway-system)と、Helmが管理する領域(ns/envoy-gateway-system)を分けています。

```plantuml:
package Kubernetes {
[GatewayClass(gc)] as GC

node "ns/envoy-gateway-system" {
  [Envoy Gateway] AS EG
}

node "ns/gateway-system" {
  [Gateways(gtw)] AS GTW
  "Admin User"
  note right of GTW : Create manually
}

node "ns/username" {
  [HTTPRoute] AS Route
  "Custom Operator"
  [Pods]
  "User"
  [<username>-svc] as USVC
}


note left of GC
  Cluster scoped resource
  Create manually
end note
note top of "ns/envoy-gateway-system" : Managed by Helm system

}

"Admin User" -> GC : define
"Admin User" -> GTW : define
"Custom Operator" -> Route : define
Route -> USVC : routing
"User" ->  USVC : create
USVC -> [Pods]

EG -- GTW
GC -- GTW
GTW -- Route
```

## サービス環境

外部からはNginxで構成しているフロントエンドのReverse Proxy Serverを中継してバックエンドのPrivate Networkに配置しているKubernetesに接続しています。

```plantuml:
actor "User / Web Browser" AS UW
node "Frontend Reverse Proxy" {
    component Nginx AS NX
    interface "Port 443" AS I443
}
package Kubernetes {
    node "ns/gateway-system" {
        component "Gateways(gtw) Instance" AS GTW
        interface "Port 443" AS E443
    }
}
component "TLS Certificate and Key" AS TLS

UW -> I443 : Public (Global) IP
I443 - NX
NX -> E443 : Private Network
E443 - GTW

TLS -- NX
TLS -- GTW
```

``Gateways(gtw) Instance``ではNginxに設置しているTLS証明書を流用してHTTPS(Port:443)のみで接続を受け付けています。

このためフロントエンドのNginxでは必要なヘッダーを付与しないと接続に失敗することになります。

具体的にはHTTPヘッダーの``Host:``行にTLS証明書のSANと同じ名前を指定する必要があります。

SANをある程度コントロールできる状況であればバックエンドのIPアドレスを含めても良いかもしれませんが、結局``Envoy Gateway``では``Host:``行をみてルーティングするので、TLSなネットワークレイヤーと、Gatewaysのアプリケーションレイヤーを分けるよう意識しないと混乱するかもしれません。

# 環境

* Kuberentes v1.34.3 (Kubespray v2.30.0)
* ingress-nginx/controller v1.13.3
* MetalLB v0.13.9 (managed by kubespray)

``networking.k8s.io``関連のCRDは次のようなものが導入されています。

```text:sudo kubectl api-resources | grep -i networking.k8s の出力結果
ingressclasses                                                networking.k8s.io/v1                         false        IngressClass
ingresses                           ing                       networking.k8s.io/v1                         true         Ingress
ipaddresses                         ip                        networking.k8s.io/v1                         false        IPAddress
networkpolicies                     netpol                    networking.k8s.io/v1                         true         NetworkPolicy
servicecidrs                                                  networking.k8s.io/v1                         false        ServiceCIDR
adminnetworkpolicies                anp                       policy.networking.k8s.io/v1alpha1            false        AdminNetworkPolicy
baselineadminnetworkpolicies        banp                      policy.networking.k8s.io/v1alpha1            false        BaselineAdminNetworkPolicy
```

MetalLBのバージョンは後述するServiceオブジェクトへの静的なExternal-IPsの割り当てに影響します。

# インストール作業

## Envoy Gatewayのインストール

公式サイトの導入手順に従ってinstall.yamlファイルを導入しました。

https://gateway.envoyproxy.io/docs/install/install-yaml/

```bash:
$ sudo kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.7.2/install.yaml
```

変更点は``sudo``コマンドを指定しただけです。

## GatewayClassオブジェクトの作成

インストールした``Envoy Gateway``は、手順どおりであれば``ns/envoy-gateway-system``に展開されています。

この状態ではGatewayClass(gc)オブジェクトが存在しないため、ここに``kind: GatewayClass``を定義します。

```yaml:01.gatewayclass.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  description: "Envoy Gateway Controller for campus services"
```

このYAMLファイルはLLM/Geminiに生成させています。

このままでもMetalLBから自動的にExternal-IPが割り当てられて利用できますが、IPを静的に固定するため後で編集しています。

## Gateway用namespaceの作成

外部にあるフロントエンドとなるReverse Proxy Server(nginx)からの処理を受け付けるためのGatewayオブジェクトを作成します。

この作業はgateway用のnamespace ``gateway-system`` を利用するため、まずこれを作成します。

```bash:
$ sudo kubectl create ns gateway-system
```

続いてこのnamespace上にGatewayオブジェクトを作成していきます。

## TLSファイルの配置

TLSの証明書の有効期間はどんどん短くなっているので最終的にはACME+Envoyを利用することになると思いますが、まだ環境が整っていないのでファイルを一定周期で更新する必要があります。

コマンドを覚えていられないので、ファイルを``tls/``ディレクトリに配置した前提で、コマンドをMakefileに書いておきます。

```makefile:Makefileから抜粋
NS = gateway-system

.PHONY: setup-sec
setup-sec:
        sudo kubectl -n $(NS) create secret tls example.com-tls --cert=./tls/example.com.crt --key=./tls/example.com.key

.PHONY: delete-sec
delete-sec:
        sudo kubectl -n $(NS) delete secret example.com-tls
```

## Gatewayオブジェクトの作成

作成したTLS証明書のSecretを参照するよう、次のようなYAMLファイルを準備しました。

```yaml:01.gateway.yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    hostname: "example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - name: example-com-tls
    allowedRoutes:
      namespaces:
        from: All
```

無事にGateway(gtw)オブジェクトが作成できたか確認していきます。

    ```bash:
$ sudo kubectl -n gateway-system get gtw
```

作成当初は``ADDRESS``が空欄になっていますが、しばらく待つとMetalLBからExternal-IPが払い出されて次のようになるはずです。

```text:画面出力
NAME             CLASS           ADDRESS           PROGRAMMED   AGE
shared-gateway   envoy-gateway   192.168.100.165   True         31s
```

``PROGRAMMED``はHTTPRouteの有無に関わらず**True**になっているはずです。

リソースが不足していたり、何等かの理由でPodが起動できなかったりするとFalseになったままになるので、``kubectl describe``などで原因を調査してください。

デフォルトでLoadBalancerが使わて、特に設定なくMetalLBに割り当てているExternal-IP(192.168.100.0/24)のレンジから割り当てられています。

静的にIPアドレスを割り当てる方法は後述しますが、まずはこのままテストしていきます。

:::note
ここまでで192.168.100.165で、``Host: example.com``が指定されたHTTPリクエストを受け付ける準備ができているはずなので、これをテストしていきます。
:::

# 稼動状況のテスト

テストのためにhttpbinアプリケーションを利用します。

既にクラスター内で稼動しているので、このServiceに接続させてみます。

## httpbinアプリの稼動状況

次のように稼動しています。

```bash:
$ sudo kubectl -n my-httpbin get pod,svc,deploy
```

```text:画面出力
NAME                              READY   STATUS    RESTARTS   AGE
pod/my-httpbin-6c5d46bf6b-9qjpt   1/1     Running   0          66d
pod/my-httpbin-6c5d46bf6b-n852c   1/1     Running   0          66d
pod/my-httpbin-6c5d46bf6b-pbbdz   1/1     Running   0          66d

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/my-httpbin   ClusterIP   10.233.58.239   <none>        80/TCP    632d

NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-httpbin   3/3     3            3           631d
```

## HTTPRouteオブジェクトの作成

Geminiに指示をして作成してもらったHTTPRouteオブジェクトが次のようになっています。

```yaml:ClaudeCodeが生成したHTTPRouteオブジェクトのYAMLファイル
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-httpbin-route
  namespace: my-httpbin
spec:
  parentRefs:
  - name: shared-gateway
    namespace: gateway-system
    sectionName: https
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /httpbin
    timeouts:
      request: 15s
      backendRequest: 15s
    backendRefs:
    - name: my-httpbin
      port: 80
```

:::note
【2026/06/09追記】.spec.rules.timeouts を追加しました。デフォルトが15秒であるためファイルのダウンロード等のデータ生成処理を行う場合には長めにするなど適宜調整してください。
:::

これを適用すると一見、ちゃんとした状態にみえます。

```bash:
$ sudo kubectl -n my-httpbin get httproute
```

```text:
NAME               HOSTNAMES   AGE
my-httpbin-route               5m36s
```

``HOSTNAMES``欄が空なのは、Ingressがサービス名を表示していた事を考えると少し不安ですが、テストしていきます。

HTTPSで接続を受け付けるのに、IPアドレスで接続しても絶対にうまくいかないので、Gatewayに指定したホスト名(この例ではexample.com)で接続してみます。

```bash:
curl -k --resolve example.com:443:192.168.100.165 https://example.com/httpbin/get -H "accept: application/json" | jq .
```

実際にはサービス名(example.com)を実際の環境に変更しています。


```text:直接curlからGatewayのExternal-IPに接続した時の出力
{
  "args": {},
  "headers": {
    "Accept": "application/json",
    "Host": "example.com",
    "User-Agent": "curl/8.5.0",
    "X-Envoy-External-Address": "192.168.100.1"
  },
  "origin": "192.168.100.1",
  "url": "https://example.com/httpbin/get"
}
```

本来のサービス名でアクセスすると次のようになるはずで、この段階ではまず動いているようです。

```text:本来のReverseProxyからIngressを中継した時の出力
{
  "args": {},
  "headers": {
    "Accept": "application/json",
    "Host": "example.com",
    "User-Agent": "curl/8.5.0",
    "X-Forwarded-Host": "example.com",
    "X-Forwarded-Scheme": "https",
    "X-Forwarded-Server": "example.com",
    "X-Nginx-Proxy": "true",
    "X-Original-Forwarded-For": "192.168.1.1",
    "X-Original-Forwarded-Host": "example.com",
    "X-Scheme": "https"
  },
  "origin": "10.233.113.0",
  "url": "https://example.com/httpbin/get"
}
```

フロントエンドのReverseProxyを変更してリクエストを``192.168.100.165``に変更して結果をみてみます。

```text:ReverseProxyを中継してEnvoyGatewayを通った時の出力
{
  "args": {},
  "headers": {
    "Accept": "application/json",
    "Host": "example.com",
    "User-Agent": "curl/8.5.0",
    "X-Envoy-External-Address": "192.168.1.1",
    "X-Forwarded-Host": "example.com",
    "X-Forwarded-Server": "example.com",
    "X-Nginx-Proxy": "true"
  },
  "origin": "192.168.1.1,192.168.100.1",
  "url": "https://example.com/httpbin/get"
}
```

細かい点でヘッダーの有無などに違いがありそうです。

何よりoriginには経由したプロキシーの情報が残っているものの、``X-Original-Forwarded-For``などは失なわれています。

一部のアプリケーションはこの挙動に依存しているはずなので、``origin:``をみるかどうかなど確認する必要がありそうです。

## ここまでのまとめ

少なくともローカルで稼動させている``httpbin``が、Ingressと併用できることは確認しました。

個別に状況を確認すれば少しづつアプリケーションを移動させることができそうです。

とはいえまったくingress-nginxと同じとはいえないので、調整は必要そうですが、利用した感触からは別のものに移動させる必要は感じていません。

Custom Operatorで制御している公開用のクラスターは、あらかじめCRDを定義してEnvoy Gatewayを動作させてから、Ingressの設定もいれたままHTTPRouteを定義して、稼動確認を並行して進めていく事になりそうです。

ただWebSocketの動作をまだ確認していないので、とりあえずそちらの確認を優先に追加の検証を進めていきます。

ちなみにCRDsが定義された状態では次のようなAPIにアクセスが可能となっています。

```text:sudo kubectl api-resources | grep -i networking.k8s の出力結果
backendtlspolicies                  btlspolicy                gateway.networking.k8s.io/v1                 true         BackendTLSPolicy
gatewayclasses                      gc                        gateway.networking.k8s.io/v1                 false        GatewayClass
gateways                            gtw                       gateway.networking.k8s.io/v1                 true         Gateway
grpcroutes                                                    gateway.networking.k8s.io/v1                 true         GRPCRoute
httproutes                                                    gateway.networking.k8s.io/v1                 true         HTTPRoute
referencegrants                     refgrant                  gateway.networking.k8s.io/v1beta1            true         ReferenceGrant
tcproutes                                                     gateway.networking.k8s.io/v1alpha2           true         TCPRoute
tlsroutes                                                     gateway.networking.k8s.io/v1alpha3           true         TLSRoute
udproutes                                                     gateway.networking.k8s.io/v1alpha2           true         UDPRoute
ingressclasses                                                networking.k8s.io/v1                         false        IngressClass
ingresses                           ing                       networking.k8s.io/v1                         true         Ingress
ipaddresses                         ip                        networking.k8s.io/v1                         false        IPAddress
networkpolicies                     netpol                    networking.k8s.io/v1                         true         NetworkPolicy
servicecidrs                                                  networking.k8s.io/v1                         false        ServiceCIDR
adminnetworkpolicies                anp                       policy.networking.k8s.io/v1alpha1            false        AdminNetworkPolicy
baselineadminnetworkpolicies        banp                      policy.networking.k8s.io/v1alpha1            false        BaselineAdminNetworkPolicy
```

# 静的なIPアドレスの割り当て

停電や事故などでクラスター全体の再起動がかかるとMetalLBから自動的に割り当てられるExternal-IPの順序が変化する可能性があります。

静的にMetalLBのアドレスプールの後ろ側から静的にIPアドレスを指定しておく方が安全です。

このために必要な設定は次のようになります。

1. ``kind: EnvoyProxy``を作成し、MetalLBにリクエストするIPアドレスを指定する
2. ``kind: Gateway``の中で作成したEnvoyProxyのパラメータを指定します

## EnvoyProxyの作成

次のようなYAMLファイルを準備して、``ns/gateway-system``に設定します。

このEnvoyProxyオブジェクトは``kind: Gateway``と同じnamespaceに配置します。

```yaml:00.envoyproxy.yaml
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: example-proxy-config
  namespace: gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: LoadBalancer
        annotations:
          metallb.universe.tf/loadBalancerIPs: "192.168.110.221"
          metallb.universe.tf/address-pool: "primary"
```

## Gatewayの変更

最初に準備したYAMLファイルに作成したEnvoyProxyを参照するように``.spec.infrastructure.parametersRef``セクションを加えます。

```yaml:01.gateway.yaml(変更版)
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-system
spec:
  gatewayClassName: envoy-gateway
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: example-proxy-config
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    hostname: "example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - name: example-com-tls
    allowedRoutes:
      namespaces:
        from: All
```

## 設定の反映

これらのYAMLファイルを反映すると自動的にGatewayのADDRESSが変化しました。

# まとめ

ingress-nginxでは変更時にnginx.confファイルが内部で再生成、読み直しされるタイミングが発生します。

また利用側の都合で複数のIngressを同タイミングで作成したり、Endpoints側のServiceが頻繁に再作成されるような状況が発生する場合がある環境です。

これらの状況が重なってingress-nginxを経由するサービスが少し不安定になることがあるように感じてきました。

もう少し使ってみないと分かりませんが、Gateway APIに移行したことで、より宣言的にトラフィックが定義できるようになってシステム全体の安定感は増した印象です。







