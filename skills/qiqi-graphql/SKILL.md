---
name: qiqi-graphql
description: 通过 77hub GraphQL 只读接口直接查询企企租户数据。当需要跨用户名/组织/对象做自由查询、排查数据、验证字段值、取自定义对象数据，或 qiqi CLI 覆盖不到时使用。按集群域名 + Tenant-Id 定位租户，用 GraphQL 查询语句取数。
---

# 企企 GraphQL 只读查询

## 适用边界

本 Skill 用于**已经知道租户集群域名和 Tenant-Id 时的直接取数**。常规业务查询仍优先用 `qiqi` CLI（`--profile <环境名>`）；本 Skill 是补充通道，用于 CLI 表达不了的自由查询、自定义对象排查和字段值核验。

- 接口**只读**，`mutation` 一律报 `Schema is not configured for mutations`，不存在写入通道。
- 接口**无需鉴权**，租户完全由 `Tenant-Id` 请求头决定。正因如此，**必须显式指定租户**，绝不能让请求落到默认库。
- ⚠️ **集群域名全部解析到 `10.x` 私网地址，只能在公司 VPN 隧道内访问**。未连 VPN 时的表现是 **TCP 超时 / 请求长时间无响应**，而**不是**报错——极易与「租户不对」「服务挂了」混淆，排查见 [troubleshooting.md](references/troubleshooting.md) 的「症状：请求超时 / 长时间无响应 / 连接挂起」。
- 与之相对，**`qiqi` CLI 的网关 `cli.77hub.com` 是公网地址，网络层不需要 VPN**。断 VPN 时 `qiqi` 照常可用、本 Skill 必然不通，这是两者分工之外的另一条硬分界。

## 三条铁律

1. **必须带 `Tenant-Id`**。不带时服务会静默落到默认库（`Organization` 只有「全局/默认集团/总部/默认集团公司/默认公司」，`User` 只有「小企 id=1」），返回 200 但数据是错的。这是本接口最常见的误判来源。
2. **确认返回的「小企」是哪一个**。某些生产租户里也有一个叫「小企」的用户（`id=1`），和默认库的同名用户极易混淆。判断是否命中正确租户，看 `Organization` 是否出现**该租户特有**的组织名，而不是看 `User`。
3. **先读 [cluster-and-tenant.md](references/cluster-and-tenant.md) 解析域名与 TID**。租户 ID ≠ 集群域名，打错集群会返回 `400`，且响应体为空，看上去像「服务不可用」。

## 最小可用调用

```powershell
$body = '{"query":"{ Organization(maxResult:10){ id name } }"}'
Invoke-WebRequest -Uri 'http://graphql.cn-apnorthbj-0.77hub.com/graphql' -Method Post `
  -ContentType 'application/json' -Headers @{ 'Tenant-Id' = '<TENANT_ID>' } `
  -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20
```

> `-TimeoutSec` 不是可选项：VPN 未连时 TCP 握手会一直挂着，不设超时要等几十秒才失败，且失败信息与「服务不可用」无从区分。

```bash
curl -s http://graphql.cn-apnorthbj-0.77hub.com/graphql \
  -H 'Content-Type: application/json' -H 'Tenant-Id: <TENANT_ID>' \
  -d '{"query":"{ Organization(maxResult:10){ id name } }"}'
```

现成的跨平台调用脚本见 [scripts/gql.ps1](scripts/gql.ps1) 与 [scripts/gql.mjs](scripts/gql.mjs)，两者都已处理 UTF-8 编码、分页和错误分类。**优先直接用脚本**，不要每次手写 Invoke-WebRequest。

```powershell
# 单次查询
scripts\gql.ps1 -Env env-a -Query '{ Organization(maxResult:10){ id name } }'

# 拉全量（自动翻页）
scripts\gql.ps1 -Env env-a -Query '{ Department(maxResult:200){ id name } }' -CollectAll
```

```bash
node scripts/gql.mjs -e env-a -q '{ Organization(maxResult:10){ id name } }'
node scripts/gql.mjs -e env-a -q '{ Department(maxResult:200){ id name } }' --all
```

环境别名由使用者在 `scripts/env.local.json` 里配置（参考 `scripts/env.example.json`，别名键可自定），脚本不内置任何环境；也可用 `-Server`/`-Tid`（或 `-h`/`-t`）显式传入，或走 `QI_GQL_HOST`/`QI_GQL_TID` 环境变量。全部命令与结论均已实测跑通。

## 按需读取

| 场景 | 读取 |
| --- | --- |
| 不知道域名或 Tenant-Id，或要新增环境 | [cluster-and-tenant.md](references/cluster-and-tenant.md) |
| **要查对象有哪些字段、字段类型/枚举/引用/必填，或找图片字段** | [object-fields.md](references/object-fields.md) |
| **要用 `__type` 内省、确认字段能否被选、搞清 435/195/191 差异** | [schema-introspection.md](references/schema-introspection.md) |
| **要查根字段有哪些参数（ARGUMENTS）、`criteria` 运算符、`sorts`/`bindVars` 写法** | [arguments.md](references/arguments.md) |
| 要知道某个参数怎么传、返回结构是什么、报错怎么读 | [query-contract.md](references/query-contract.md) |
| 需要常见查询配方（组织树、用户、自定义对象、按条件筛、分页拉全量） | [recipes.md](references/recipes.md) |
| 排查「查得到但数据不对」「400」「字段不存在」 | [troubleshooting.md](references/troubleshooting.md) |

只读当前任务需要的那一个。

## 查对象字段（核心能力）

**字段元数据可以直接用 GraphQL 查，而且比 `qiqi describe fields` 更全（能查到图片字段）。**

```powershell
scripts\gql.ps1 -Env env-a -Fields Department     # 该对象全部字段，含 bizType=img
scripts\gql.ps1 -Env env-a -Entities <自定义对象>   # 自定义对象
scripts\gql.ps1 -Env env-a -Objects               # 全部对象类型
```

```bash
node scripts/gql.mjs -e env-a -F Department
node scripts/gql.mjs -e env-a -E <自定义对象>
node scripts/gql.mjs -e env-a -O
```

手写等价查询：

```graphql
{ ObjectField(criteriaStr: "objectType = 'Department'", maxResult: 200) {
    name title type bizType isEnum enumType isRequired isCustomizedField
} }
```

- 对象清单查 `ObjectType`，字段清单查 `ObjectField`（`id` 形如 `ObjectType.apiName`）。
- **图片字段用 `bizType = 'img'` 判定**；`qiqi describe fields` 会静默漏掉这类字段（实测自定义对象漏 5 个：124 vs 119）。
- 细节、类型取值与实测对照见 [object-fields.md](references/object-fields.md)。

## 用 Schema 取字段（另一条通道）

`__type` 也可用，只是**业务对象名要加 `SchemaType` 后缀**：

```graphql
{ __type(name:"DepartmentSchemaType"){ fields{ name type{ kind name } } } }   # 435 个
{ __type(name:"Department"){ fields{ name } } }                              # ❌ 恒返回空
```

三条通道字段数不同，**是三层不同的东西，不能互相替代**（`Department` 为例）：

| 通道 | 字段数 | 含义 |
| --- | --- | --- |
| `__type(DepartmentSchemaType)` | 435 | GraphQL 暴露的可选字段，含引用展开（`partyType`、`createdUser`…） |
| `ObjectField` | 195 | 租户真实字段，**写 `criteriaStr` 只认这个** |
| `qiqi describe fields` | 191 | 上面的子集，漏图片字段 |

- **写查询/写脚本以 `ObjectField` 为准**；`__type` 用来确认字段名能否被选、标量类型是什么。
- **自定义对象不在服务端 schema 里**，用 `Entities(names:["Cs…"])` 或 `ObjectField` 查字段。
- ⚠️ **GraphiQL 的 Docs 面板能显示自定义对象的 SchemaType，那是前端把 `Entities` 结果拼进 introspection 的产物**，不要据此认为 `__type` 能查到它。
- 详见 [schema-introspection.md](references/schema-introspection.md)。

## 关键约束速查

| 约束 | 说明 |
| --- | --- |
| 分页 | `firstResult`（起始偏移）+ `maxResult`（条数）。**不传 `maxResult` 时只返回约 10 条**，拉全量必须显式翻页 |
| 无总数 | 返回体**没有 total**。判断拉完：本页条数 < `maxResult` 即到底 |
| 排序 | `sorts:[{ name:"<字段名>", isDesending:true }]`。⚠️ 是 `isDesending`（官方拼写错误），传 `direction`/`order` 会报字段不存在 |
| 筛选 | `criteriaStr` 用类 SQL 表达式，**左值用存储列名**（如 `createdAt` → 实为 `createdAtId`），写错会报 `invalid field` |
| 参数 | 根字段共 **18 个**参数（`maxResult`/`firstResult`/`criteriaStr`/`criteria`/`sorts`/`distinct`/`bindVars`/`actionId`/`resultStructure`/`context*`…），用 `__type(name:"QueryType")` 内省。**`customizedFields` 在 GraphiQL 模板里有但真实 schema 不认，禁止传** |
| `criteria` | 结构化条件的运算符**必须全小写**：`eq ne gt ge lt like in notin isnull between`；大写会报 `Exception while fetching data` |
| 内省 | `__schema` 只含系统对象，**自定义对象（`Cs…` 开头）不在内省结果里，但能正常查询**。不要用内省结果判断对象是否存在 |
| `__type` | **可用**，但业务对象要写 `<对象名>SchemaType`；不带后缀恒返回 `{"data":{},"errors":[]}`。自定义对象服务端无类型，改用 `Entities(names:[...])` |
| 传输 | 明文 HTTP，数据可读。不要把它当安全通道 |
| 协议 | `/graphql` 与 `/graphql/withoutAuth` 行为完全一致；`Cookie`、`Access-Token` 都不影响结果 |

## 与 qiqi CLI 的分工

| 需求 | 用哪个 |
| --- | --- |
| 常规取数、有 profile 的环境 | `qiqi query list --profile <环境>`（有字段元数据、有 total、带数据权限） |
| 已知精确条件、要自由拼查询 | 本 Skill |
| 查对象/字段元数据（尤其要图片字段） | 本 Skill 的 `ObjectType` / `ObjectField`，比 qiqi 更全 |
| 需要枚举候选值 | `qiqi query values` |
| 需要写入 | 只能走 `qiqi` / 平台脚本，本 Skill 无写入能力 |

⚠️ 本接口**不走数据权限**（无鉴权），结果可能比当前用户在有权限的 CLI 里看到的多。**不要把这里的结果当作「该用户能看到的数据」**；涉及权限口径的结论必须回到 `qiqi` 复核。

## 读取与输出纪律

- 结果必须标注来源：集群域名 + Tenant-Id + 查询语句，缺一不可，否则无法复现。
- 未命中时报告「当前租户 + 当前条件未查到」，不要下「数据不存在」的结论——可能是租户打错、字段名错或条件写错，先按 [troubleshooting.md](references/troubleshooting.md) 排除。
- 不要臆测字段名。拿不准就先按 [object-fields.md](references/object-fields.md) 用 `ObjectField` 查真实字段名（比 `qiqi describe fields` 全），再拼数据查询。
