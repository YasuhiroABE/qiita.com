---
title: Envoy Gateway を v1.7.2 から v1.8.1 にアップグレードした時の作業メモ
tags:
  - kubernetes
  - envoy
  - EnvoyGateway
private: false
updated_at: '2026-06-09T12:53:44+09:00'
id: e3a7d73993eee75ac3f8
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

Ingress-NginxからEnvoy Gatewayに移行して、平和に日々をすごしています。

nginxはよく使っているので安心ではあるのですが、Endpointが頻繁に定義・更新される環境には向かなかったと感じています。

さて、後述するEnvoy GatewayのEoLを確認すると、約3ヶ月毎にアップグレードが必要になることが分かります。

更新作業の手順を準備するためにも、最新のv1.8.1に更新することにしましたので、この作業手順をメモしておきます。

# 資料

Envoy Gateway v1.7.2を導入した時の顛末は次の記事にまとめています。

https://qiita.com/YasuhiroABE/items/75803ceda3feafcf4dbd

公式のEnvoy Gatewayのアップグレード手順は次のページに掲載されています。

https://gateway.envoyproxy.io/docs/install/install-yaml/

公式の手順はkubectlで新規インストールした環境では、そのまま適応できないので注意が必要です。

# 概要

公式でガイドされている手順では、Helmを利用したアップグレード手順が掲載されています。

```bash:公式ページでガイドされているアップグレード手順
## 1. CRDsの手動アップグレード
$ (省略)

## 2. helmによるアップグレード
$ helm upgrade eg oci://docker.io/envoyproxy/gateway-helm --version v1.8.1 -n envoy-gateway-system
```

Helmでは指定したターゲットが存在しないため、当然ながら``helm upgrade``コマンドはエラーになってしまいます。

またこのセクションは、Helmを利用したインストール手順のページからアップグレード時の手順としてリンクが張られているため、実質的にHelmで導入した環境のアップグレード手順がガイドされています。

## v1.8.1の主な変更点

目立つ違いはv1.8になってTLSRoutesのバージョンがv1alpha3からv1になった程度のようです。

Breaking ChangesにはHelmを利用して導入している場合には、ValidatingAdmissionPolicy がCRDsからHelmのアップグレード対象に移動されたことで対応が必要だとありますが、オンプレミスの環境にkubectlで導入している場合にはどっちのタイミングで更新されるかは関係がないので問題なさそうです。

https://gateway.envoyproxy.io/news/releases/notes/v1.8.1/

この他にクラウドプロバイダーがGateway APIを提供している場合には、そのCRDsを壊さないように注意することなどが記載されていますが、オンプレミスでは関係ありません。

## 対応するKubernetesのバージョン

一応、Envoy Gatewayには、どのKubernetesのバージョンと整合するか確認するための表が準備されています。

https://gateway.envoyproxy.io/news/releases/matrix/

いまのところKubernetesの1.36.xに対応するバージョンはないようですが、1.36.xを適用するタイミングで確認した方がよさそうです。

またこの表にはEnd of Life(EoL)についても情報があり、約3ヶ月毎にマイナー・バージョンアップが行われていることが分かります。

# 全体の手順

最終的にインストール時と同様にinstall.yamlを適用します。

```bash:実際に適用したアップグレード手順
## 1. CRDsの手動アップグレード
$ helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm \
  --version v1.8.1 \
  --set crds.gatewayAPI.enabled=true \
  --set crds.envoyGateway.enabled=true \
  | sudo kubectl apply --force-conflicts --server-side -f -

## 2. kubectlによるアップグレード
$ sudo kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.8.1/install.yaml
```

CRDsの定義はinstall.yamlにも含まれるので、重複して適用されますが、CRDs定義は冪等性が確保されていると考えて良いでしょうから副作用はないはずです。

実際にはこれをMakefileのタスクに入れて、問題なくアップグレードに成功しました。

```text:コマンド適用時の画面出力
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/listenersets.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tcproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/udproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/clienttrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyextensionpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoypatchpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyproxies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutefilters.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/securitypolicies.gateway.envoyproxy.io serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
namespace/envoy-gateway-system serverside-applied
serviceaccount/envoy-gateway serverside-applied
configmap/envoy-gateway-config serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-role serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-rolebinding serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-role serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-rolebinding serverside-applied
service/envoy-gateway serverside-applied
deployment.apps/envoy-gateway serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
serviceaccount/eg-gateway-helm-certgen serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied
```



