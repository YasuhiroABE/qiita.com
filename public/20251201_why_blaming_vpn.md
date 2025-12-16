---
title: どうしてVPNは悪者にされてしまうのか
tags:
  - Security
  - VPN
  - Malware
private: false
updated_at: '2025-12-16T12:13:21+09:00'
id: fc1f563035c2e1f21c8d
organization_url_name: null
slide: false
ignorePublish: true
---
# はじめに

VPN装置はその性質からインターネットに接続していることが多いため、脆弱性が狙われやすいものです。

インターネットに接続している装置としては、DNSやReverse Proxy Serverを含めたWeb系のシステムも同様です。

しかしVPNは内部のネットワークに接続するという性質から攻撃に成功すれば確実により多くのリソースにアクセスできるというインセンティブのために常に研究の対象となっています。


