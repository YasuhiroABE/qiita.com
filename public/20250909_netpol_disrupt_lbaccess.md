---
title: GitlabにNetworkPolicyを適用した時のメモ
tags:
  - kubernetes
  - loadbalancer
  - NetworkPolicy
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: falsef
---
# はじめに

以前LoadBalancerの制御はNetworkPolicyでは出来無いということを説明する記事を投稿しました。

https://qiita.com/YasuhiroABE/items/44136ff12745e1014e4d

今回はGitlabのRedisなどへの通信を制御するタイミングでRailsへの通信についてもNetworkPolicyを設定したのですが、その際に挙動がおかしかったので調べることにしました。

# 実環境での課題

## 共用環境でのサービスの運用

各メンバーのNamespaceにはNetworkPolicyをデフォルトで適用していて、外部からの通信を遮断しているのですが、共用サービスについては各Helmなどの初期値のまま放置していました。

このためSession管理に使用しているRedisなどへの通信を防いでいないことに気がついたので、いろいろ設定を進めています。

## Redis, PostgreSQLへのNetowkrPolicyの適用

次のようなNetowrkPolicyを設定しています。

```yaml:
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-pgsql-within-same-namespace
  namespace: gitlab
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: gitlab
    ports:
    - protocol: TCP
      port: 5432
  podSelector:
    matchLabels:
      name: postgresql
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-redis-within-same-namespace
  namespace: gitlab
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: gitlab
    ports:
    - protocol: TCP
      port: 6379
  podSelector:
    matchLabels:
      name: redis
  policyTypes:
  - Ingress
```

## RailsにうまくNetworkPolicyが適用できない

KubernetesでGitlabを稼動させていますが、リポジトリへの``git clone``などの操作のため外部からのSSHアクセスを許可しています。

このポートは10022番としてフロントエンドのFirewallからDNATを利用して内部のKubernetesクラスターにルーティングしています。

```plantuml:
actor User

node "Firewall" {
  agent Nginx
  note left: Port: 443

  agent VPP
  note left: Port: 10022
}

node "Kubernetes" {
  agent Ingress
  agent Gitlab
  note left: Port 22,80
  agent ClusterIP
  note left: Port 80
  agent LoadBalancer
  note left: Port: 10022
}

User .. Nginx
User .. VPP

[Nginx] .. [Ingress] : <<HTTPS>>
[Ingress] .. [ClusterIP]
[ClusterIP] .. [Gitlab]

[VPP] .. [LoadBalancer] : <<SSH>>
[LoadBalancer] .. [Gitlab]
```

ここでGitlabのPodに対してIngressからの通信を制御するようなNetworkPolicyを適用すると、SSHの接続ができなくなります。

これはNetworkPolicyの内容ではなく、NetworkPolicyの適用対象となることでSSH経由でのアクセスができなくなる現象が発生します。

例えば次のようなNetworkPolicyを適用します。

```yaml:問題のあるNetworkPolicy
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-all
  namespace: gitlab
spec:
  ingress:
  - ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 10022
  podSelector:
    matchLabels:
      name: gitlab
  policyTypes:
  - Ingress
```

この設定の元ではIngress経由での接続は可能ですが、SSHアクセスのみできなくなります。

```bash:NetworkPolicyを設定した場合の通信状況
## ssh経由でのアクセス
$ ssh ssh://git@example.org:10022/
ssh: connect to host example.org port 10022: Connection refused

## LoadBalancerのIPアドレスを直接指定した場合
$ ssh ssh://git@192.168.1.10:10022/
ssh: connect to host 192.168.1.10 port 10022: Connection refused

## curl
$ curl https://example.org/gitlab/
<html><body>You are being <a href="http://example.org/gitlab/users/sign_in">redirected</a>.</body></html>

## LoadBalancerのIPアドレスを直接指定した場合
$ curl http://192.168.1.10/gitlab/
<html><body>You are being <a href="http://192.168.1.10/gitlab/users/sign_in">redirected</a>.</body></html>
```

FirewallのNginxからはLoadBalancerへのIPアドレス(192.168.1.10)を指定した``proxy_pass``を設定しています。

この挙動の違いを調査するためにFirewall側でtcpdumpを設定してみます。

```bash:LBのアドレスを指定してsshを実行した場合
$ sudo tcpdump -i any -n port 10022
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes

11:38:41.770738 IP 192.168.1.1.35618 > 192.168.1.10.10022: Flags [S], seq 2736378513, win 64240, options [mss 1386,sackOK,TS val 1034531383 ecr 0,nop,wscale 7], length 0
11:38:42.818601 IP 192.168.1.1.35618 > 192.168.1.10.10022: Flags [S], seq 2736378513, win 64240, options [mss 1386,sackOK,TS val 1034532431 ecr 0,nop,wscale 7], length 0
...
```

LBのアドレスについては[S]パケットを投げているものの反応がありません。

結論としては、設定ファイルの10022の指定が正しくなく、これを22とするべきでした。

サービスの待ち受けアドレスではなく、サービスが転送する先のPodが使用する22番ポートを指定することで問題なく動作します。

```yaml:正しく修正したNetworkPolicy
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-all-to-gitlab
  namespace: gitlab
spec:
  ingress:
  - ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 22
  podSelector:
    matchLabels:
      name: gitlab
  policyTypes:
  - Ingress
```

# さいごに

分かってしまえば単純にNetworkPolicyの使い方を間違えていて、NetworkPolicyをServiceオブジェクトの制御に利用しようとした点に問題がありました。

最終的にこの他のサービスについても適切なNetworkPolicyの設定を進めています。





