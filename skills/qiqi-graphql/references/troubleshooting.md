# 排查指南

按症状查，每条都对应实测现象。

**先看这一条**：本 Skill 的所有集群域名都是 `10.x` 私网地址，**必须连公司 VPN**。如果请求「卡住不动 / 超时」，十有八九是没连 VPN，不是查询写错。见下面「症状：请求超时 / 长时间无响应 / 连接挂起」。

## 症状：请求超时 / 长时间无响应 / 连接挂起

**几乎一定是没连公司 VPN。** 集群域名（`graphql.*.77hub.com`）全部解析到 `10.x` 私网地址，公网无法直达。

注意区分：**这不是报错**。没有 URL 拒绝、没有 TLS 失败、没有 4xx/5xx，只是 TCP 握手无响应，`Invoke-WebRequest` / `fetch` 会一直挂着直到超时。容易误判成「服务挂了」，然后跑去反复换 Tenant-Id —— 方向就错了。

判定命令（Windows / PowerShell，**按源地址**探测能立刻分清）：

```powershell
# 1) 目标是不是私网地址？（是 → 必须 VPN）
Resolve-DnsName graphql.cn-apnorthbj-0.77hub.com -Type A | Where-Object IPAddress

# 2) 隧道网卡是否 Up、拿到什么地址
[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
  Where-Object { $_.OperationalStatus -eq 'Up' -and $_.Name -match 'OpenVPN|TAP' } |
  ForEach-Object { $_.Name + ' = ' + (($_.GetIPProperties().UnicastAddresses |
    Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } |
    ForEach-Object { $_.Address.ToString() }) -join ',') }

# 3) 最直接：TCP 通不通
Test-NetConnection <集群私网IP> -Port 80 -InformationLevel Quiet
```

判据：

- `Test-NetConnection` 返回 `False` 且能 ping/DNS 成功 → **VPN 没连或没生效**，连上后重试。
- 想进一步确认是「只有隧道能通」，用 Node 按源地址分别连接（`s.connect({ host, port, localAddress })`），隧道地址 CONNECTED、WLAN 地址 TIMEOUT 即可确认。
- **能解析 IP ≠ 能连**：公网 DNS 解析出来的也是同一个私网地址（`10.x`），`Resolve-DnsName` 成功只说明有一条指向该地址的 A 记录，不代表隧道已通。

处理：连上公司 VPN 后原查询直接重试，**不要改 Tenant-Id、不要换集群域名**——那两个方向与本症状无关。

## 症状：返回 200，但数据看着像空系统

**几乎一定是没带 `Tenant-Id`，落到了默认库。**

默认库长相固定：

```
Organization = [全局, 默认集团, 总部, 默认集团公司, 默认公司]
User         = [小企 id=1]
```

排除：补 `Tenant-Id` 请求头。不要靠 `User` 判断，某些生产租户里也有「小企 id=1」。

## 症状：`400`，响应体是空的

租户 ID 在该集群不存在，或租户 ID 写错。**400 且 body 为空是本接口的固定表现**，不是服务挂了。

排除顺序：

1. 核对 Tenant-Id 是否笔误（15 位，大小写敏感）。
2. 换集群域名重试，见 [cluster-and-tenant.md](cluster-and-tenant.md)。
3. 用不带 `Tenant-Id` 的请求确认该域名服务在线（应返回 200 + 默认库）。

## 症状：`FieldUndefined: Field 'XXX' in type 'QueryType' is undefined`

二选一：

- **对象名写错**（大小写、复数、拼写）。
- 该对象在当前租户不存在（比如在默认库查自定义对象 `Cs…`，必然 undefined）。

注意：**自定义对象不在 `__schema` 内省结果里是正常的**，别拿内省结果去否定一个真实存在的对象。

## 症状：`invalid field 'xxx' (yyyId in metadata)`

`criteriaStr` 的左值用了 API 名而不是存储列名。

报错信息里括号中就是正确列名。例如：

```
invalid field 'createdAt' (createdAtId in metadata)
→ 把 createdAt 改成 createdAtId
```

## 症状：`operator does not exist: - character varying`

用了 `name: "-name"` 之类的「减号前缀」写法做倒序。本接口不支持。

改用：`sorts: [{ name: "name", isDesending: true }]`。

## 症状：`contains a field not in 'SortByInputSchemaType': 'direction'`

排序对象只接受 `name` 和 `isDesending` 两个字段。`direction`/`order`/`desc` 都不存在。

## 症状：`Schema is not configured for mutations`

正常。本接口**只读**，没有任何写入通道。需要写入请走 `qiqi` 或平台脚本。

## 症状：`__type(name:"X")` 返回空对象

**先把类型名加上 `SchemaType` 后缀再试**——这是最常见原因：

```
__type(name:"Department")              → {"data":{},"errors":[]}   ❌
__type(name:"DepartmentSchemaType")    → 435 个字段                ✅
```

类型名的确定方式：查根字段声明的返回类型

```graphql
{ __schema { queryType { fields { name type { kind name ofType { kind name } } } } } }
```

若加了后缀仍为空，则可能是**自定义对象**（`Cs…` 开头）——它们不在服务端 schema 里，用 `Entities(names:["Cs…"])` 查字段。见 [schema-introspection.md](schema-introspection.md)。

## 症状：GraphiQL 的 Docs 能显示某类型，`__type` 却查不到

这是正常现象，不是查询写错。**GraphiQL 的 schema 是前端合成的**：它除了发 introspection，还额外发一条 `Entities(isCustomizedOnly: true)`，再用 `buildCustomizedSchema()` 把自定义对象的 `XxxSchemaType` 拼进 types 数组。

所以 Docs 面板 = 服务端 schema + 租户自定义对象，而 `__type` 只能查服务端那部分。

自定义对象改用 `Entities`：

```graphql
{ Entities(names: ["<自定义对象>"]){ name fields{ name title type } } }
```

## 症状：只拿到 10 条，但业务上明显更多

`maxResult` 没传，默认约 10 条。

补 `maxResult`，并用 `firstResult` 翻页。注意本接口无 `total`，只能靠「本页条数 < maxResult」判断到底。

## 症状：报 `Method name must not be null`（`ObjectIndex`）

`ObjectIndex` 需要额外参数，当前契约无法直接使用。**改用其他方式统计**，不要在这上面耗时间。

## 症状：HTTPS 连不上

本接口只有 HTTP。`https://graphql.….77hub.com` 会 TLS 握手失败。同时 `https://cli.77hub.com`（qiqi 网关）在本机 curl/PowerShell 下也可能 TLS 失败但 Node 可用——**那是 qiqi 的通道，与本接口无关**，不要混用。

**注意与「请求超时」区分**：HTTPS 失败是 TLS 握手层的问题（改回 `http://` 即好）；而 `http://` 也超时的话，是本条之外的 VPN 问题，见上面的「症状：请求超时」。

## 症状：GraphQL 条数和 qiqi 的 `total` 对不上

正常，不是 bug：

- GraphQL 无鉴权、**不做数据权限过滤**；
- qiqi 按当前登录用户的数据权限过滤。

GraphQL 的结果通常**更多**。要「某人实际能看到多少」必须用 qiqi。两者差异本身可能是有价值的权限排查线索。

## 症状：中文乱码

请求 body 必须 UTF-8 编码后再发，不要直接把字符串塞 `-Body`（PowerShell 默认编码会坏）。

```powershell
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-WebRequest ... -Body $bytes
```

`scripts/gql.ps1` / `gql.mjs` 已处理。
