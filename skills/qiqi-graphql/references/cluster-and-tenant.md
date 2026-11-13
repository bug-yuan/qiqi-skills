# 集群域名与租户

## 域名规律

```
http://graphql.<区域>-<序号>.77hub.com/
```

- 协议固定 **HTTP 明文**，没有 HTTPS。
- `<区域>` 目前观测到两个：`cn-apnorthbj`（北京）、`cn-northwest`（西安）。
- `<序号>` 从 `0` 开始连续分配。

## ⚠️ 网络前提：必须连公司 VPN

**这些集群域名全部解析到 `10.x` 私网地址（RFC1918），公网无法直达，必须先在 VPN 隧道内。**

实测（2026-11-13，同一台机器按源地址分别探测）：

| 出口网卡 | 目标 `<集群私网IP>:80` | 结果 |
| --- | --- | --- |
| `OpenVPN TAP-Windows6`（VPN 隧道网卡） | CONNECTED | 38–200ms |
| `WLAN`（公网出口网卡） | **TIMEOUT** | SYN 无响应，不是 refuse |

同一集群内其它几个私网 IP 探测结果相同。**公网 DNS 解析出来的也是同一个私网 IP**，所以「能解析」不代表「能连」，别用 `Resolve-DnsName` 成功就判定网络正常。

**不带 VPN 时的表现是 TCP 超时 / 请求长时间挂起，而不是报错** —— 这与「租户 ID 打错」「服务挂了」长得完全不同，不要往那两条方向排查。判定与处理见 [troubleshooting.md](troubleshooting.md) 的「症状：请求超时 / 长时间无响应 / 连接挂起」。

**对照**：`qiqi` CLI 的网关 `cli.77hub.com` 解析到公网 IP（`52.83.89.64` 等），**网络层不需要 VPN**。所以断 VPN 时 `qiqi` 照常可用、本 Skill 必然不通。（`qiqi` 另有自己的鉴权与 profile 要求，那是另一回事。）

## 已验证的域名

实测环境，2026-11-04：

> 下表 **「解析 IP」列全部是 `10.x` 私网地址**，只有在 VPN 隧道内可达（见上一节）。

| 域名 | 解析 IP | 归属集群 |
| --- | --- | --- |
| `graphql.cn-apnorthbj-0.77hub.com` | `<集群私网IP>`（北京 A 组） | 北京 A |
| `graphql.cn-apnorthbj-1.77hub.com` | `<集群私网IP>`（北京 A 组，与 `-0` 同一地址） | 北京 A |
| `graphql.cn-apnorthbj-2.77hub.com` | `<集群私网IP>`（北京 A 组，与 `-0` 同一地址） | 北京 A |
| `graphql.cn-apnorthbj-3.77hub.com` | `<集群私网IP>`（北京 B 组） | 北京 B |
| `graphql.cn-apnorthbj-4.77hub.com` | `<集群私网IP>`（北京 B 组，与 `-3` 同一地址） | 北京 B |
| `graphql.cn-northwest-1.77hub.com` | `<集群私网IP>`（西安组，同一组内多个地址轮询） | 西安 |
| `graphql.cn-northwest-4.77hub.com` | `<集群私网IP>`（西安组，同一组内多个地址轮询） | 西安 |

> 同一组内的多个域名解析到**同一个**私网 IP；西安组是两个以上私网 IP 轮询。这些都是 `10.x` RFC1918 地址，具体值随环境而定，按本节方法现场解析即可。

> `-2`、`-3`、`-4`、`cn-northwest-1` 在本次扫描中能解析、服务在线（不带租户头能返回默认库），但**没有命中已知租户**。它们是备用或未分配节点。

## 配置示例

环境别名由使用者在 `scripts/env.local.json` 里自行配置（参考提交进仓的 `scripts/env.example.json`，别名键可自定、可为中文），脚本不内置任何环境：

```json
{
  "envs": {
    "env-a": { "host": "graphql.cn-apnorthbj-0.77hub.com", "tid": "<TENANT_ID>" },
    "env-b": { "host": "graphql.cn-apnorthbj-1.77hub.com", "tid": "<TENANT_ID>" }
  }
}
```

| 别名（示例） | 集群域名 | Tenant-Id | 如何确认命中 |
| --- | --- | --- | --- |
| `env-a` | `graphql.cn-apnorthbj-0.77hub.com` | `<TENANT_ID>` | `Organization` 出现**该租户特有**的组织名 |
| `env-b` | `graphql.cn-apnorthbj-1.77hub.com` | `<TENANT_ID>` | 同上 |
| `env-c` | `graphql.cn-northwest-4.77hub.com` | `<TENANT_ID>` | 同上 |
| `env-d` | `graphql.cn-apnorthbj-0.77hub.com` | `<TENANT_ID>` | 同上 |

注意 **`env-a` 与 `env-d` 共用同一个域名**，靠 Tenant-Id 区分。同集群不同租户共享域名是常态。

> 确认命中后记下该租户特有的组织名即可，不必写进文档。默认库的组织名是固定那 5 个（见「默认库陷阱」），只要出现这 5 个之外的名字，就说明租户头生效了。

## 租户 ID 从哪来

1. **GraphiQL 页面 URL**：`?tenantId=<TENANT_ID>`，最直接。
2. **qiqi CLI**：`qiqi auth status --offline --profile <环境名>`，输出里的「租户: XXX (XXXXXXXXXXXXXXX)」，括号内即 Tenant-Id。这是批量取全量租户 ID 最快的方式：

```powershell
foreach ($p in (qiqi auth list | Select-String -Pattern '\|\s*(\S+)\s*\|') ) { }
# 更稳的做法：逐个 profile 查
qiqi auth status --offline --profile <环境名> | Select-String '租户'
```

3. **qiqi connection**：`qiqi connection show --profile <环境名>` 给的是 CLI 网关（`https://cli.77hub.com`），**不是** GraphQL 集群域名，不能直接套用。

## 如何确定一个新租户在哪个集群

租户 ID 本身不含集群信息，只能试。按下面顺序二分，通常 2–3 次就命中：

```powershell
$tid = 'XXXXXXXXXXXXXXX'
foreach ($h in @(
    'graphql.cn-apnorthbj-0.77hub.com',
    'graphql.cn-apnorthbj-1.77hub.com',
    'graphql.cn-northwest-4.77hub.com'
)) {
    $r = try {
        Invoke-WebRequest -Uri "http://$h/graphql" -Method Post -ContentType 'application/json' `
            -Headers @{ 'Tenant-Id' = $tid } -Body ([System.Text.Encoding]::UTF8.GetBytes('{"query":"{ Organization(maxResult:5){ name } }"}')) `
            -TimeoutSec 15 -UseBasicParsing
    } catch { $null }
    if ($r -and $r.StatusCode -eq 200) { Write-Output "HIT: $h"; break }
}
```

判据：**200 = 该租户在这个集群**；400 = 不在（响应体为空）。

## 默认库陷阱

**不带 `Tenant-Id` 或带 `0` 时**，服务返回 200 和一套初始化空库：

```
Organization: 全局、默认集团、总部、默认集团公司、默认公司
User:         小企 (id=1)
```

这套数据**每个集群都一样**，看起来完全是正常返回值，极易被当成目标租户。识别方法：

- `Organization` 里只有上述 5 个名字 → 一定是默认库。
- 目标租户的自定义对象（`Cs` 开头）在此处**必然查不到**（字段报 undefined）。
- 某些生产租户里也有个「小企 (id=1)」，**不要靠 User 判断**，靠 Organization 判断。
