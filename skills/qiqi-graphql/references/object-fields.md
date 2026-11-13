# 查询对象字段元数据

**能用 GraphQL 查字段定义，而且比 `qiqi describe fields` 更完整。** 全部结论 2026-11-04 实测。

## 最快的方式：脚本内置模式

不用手写 GraphQL：

```powershell
# 列出一个对象的全部字段（含图片字段）
scripts\gql.ps1 -Env env-a -Fields Department

# 自定义对象用 -Entities（服务端 schema 里没有 Cs* 类型）
scripts\gql.ps1 -Env env-a -Entities <自定义对象>

# 列出全部对象类型
scripts\gql.ps1 -Env env-a -Objects
```

```bash
node scripts/gql.mjs -e env-a -F Department
node scripts/gql.mjs -e env-a -E <自定义对象>
node scripts/gql.mjs -e env-a -O
```

返回 195 个 `Department` 字段；`-Fields <自定义对象>` 返回 124 个并包含两个 `bizType=img` 的图片字段。

下面的手写方式仅在需要自定义字段组合时使用。

## 自定义对象用 `Entities`

自定义对象在服务端 schema 里没有类型，但 `Entities` 能直接按名字取，结果与 `ObjectField` **完全一致**（实测某自定义对象两边都是 124 个字段）：

```graphql
{ Entities(names: ["<自定义对象>"]) {
    name title type
    fields { name title type apiName isCustomizedField }
} }
```

`Entities` 支持 `names`（数组）、`versionId`、`isCustomizedOnly`，**不支持 `maxResult`/`firstResult`**。

## 为什么不直接用 `__type` 查业务对象

**注意：用对了 `SchemaType` 后缀是能查的**（见 [schema-introspection.md](schema-introspection.md)），但两者拿到的不是同一层东西：

- `__type("DepartmentSchemaType")` → **435 个**，含引用展开（`partyType`、`createdUser` 等），是 GraphQL 选取集可写的字段。
- `ObjectField` → **195 个**，是租户里真实的字段，**`criteriaStr` 只认这些**。

写查询/写脚本仍以 `ObjectField` 为准。`__type(name:"Department")` 少了 `SchemaType` 后缀时才返回空。

## 正确姿势：查 `ObjectField` 元数据表

字段定义存在于根字段 `ObjectField` 里，`id` 形如 `ObjectType.apiName`。

```graphql
{
  ObjectField(criteriaStr: "objectType = 'Department'", maxResult: 200) {
    name
    title
    type
    bizType
    isEnum
    enumType
    isCustomizedField
    isRequired
    length
  }
}
```

- `criteriaStr` 的 `objectType = 'XXX'` **过滤有效**，且 `ObjectField` 有嵌套的 `objectTypeObject { name title }`，可自证字段归属。

## 对象清单走 `ObjectType`

```graphql
{ ObjectType(criteriaStr: "name = '<自定义对象>'", maxResult: 1) {
    name title type appName isCustomizedEntity isDisabled
} }
```

返回如：`{ name: "<自定义对象>", title: "<对象标题>", type: "bill", appName: "baseapp", isCustomizedEntity: true }`。

- 不传 `criteriaStr` 则返回全部对象（分页拉）。
- `type` 取值：`document`（档案）、`bill`（单据）等。
- `isCustomizedEntity` 可区分标准对象与自定义对象。

## `ObjectField` 上可用的字段（79 个常用项）

| 分类 | 字段 |
| --- | --- |
| 标识 | `id`、`name`、`apiName`、`title`、`objectType`、`objectTypeObject` |
| 类型 | `type`、`bizType`、`length`、`isEnum`、`enumType`、`isMultiValue` |
| 结构 | `referInfo`、`lookupInfo`、`sourceInfo`、`mappings`、`domain`、`domainFieldNames` |
| 约束 | `isRequired`、`isEditable`、`isVisible`、`isListVisible`、`isCriteriaVisible`、`isRefVisible`、`minLength`、`defaultValue` |
| 归属 | `isCustomizedField`、`isSystemField`、`isDisabled`、`isFlowField`、`isOrganizationalField` |
| 审计 | `createdTime`、`modifiedTime`、`createdUser`、`modifiedUser`、`isDeleted` |

完整清单用 `__type(name:"ObjectFieldSchemaType"){ fields{ name } }` 取（实测 79 个）。

## 类型取值（实测分布）

`String`、`Timestamp`、`List`、`Boolean`、`Integer`、`Long`、`BigDecimal`、`JsonObject`、`Multiple` 等。

## 关键：补充 `bizType` 才能识别图片字段

**`qiqi describe fields` 会静默漏掉图片字段，GraphQL 能查到。** 实测对照（某自定义对象）：

| 通道 | 字段数 |
| --- | --- |
| `ObjectField`（GraphQL） | **124** |
| `qiqi describe fields` | 119 |

差的 5 个是 `customizedFields` 加两个图片字段：

```graphql
{ ObjectField(criteriaStr: "objectType = '<自定义对象>' and type = 'JsonObject'", maxResult: 50) {
    name title type bizType
} }
```

结果：

```
customizedFields              自定义属性  type=JsonObject  bizType=（空）
<图片字段A>                   <图片字段A标题>  type=JsonObject  bizType=img
<图片字段B>                   <图片字段B标题>  type=JsonObject  bizType=img
```

> **判定图片字段用 `bizType = 'img'`，不要用 `type = 'JsonObject'`** —— `customizedFields` 也是 JsonObject 但不是图片。

`bizType` 的其他实测取值：`date`、`dateTime`、`xchgRate`、`operator`、`mobile`、`email`、`img`。

## 枚举字段

```graphql
{ ObjectField(criteriaStr: "objectType = 'Department' and isEnum = true", maxResult: 20) {
    name title type isEnum enumType
} }
```

结果：

```
entrySrcSystemId  → enumType: EntrySrcSystem
natureId          → enumType: PartyNature
characterId       → enumType: DepartmentCharacter
```

拿到 `enumType` 后，枚举候选值仍需 `qiqi query values` 查询（本接口未验证到枚举值根字段）。

## 引用字段

```graphql
{ ObjectField(criteriaStr: "objectType = 'Department' and name = 'parentId'", maxResult: 1) {
    name title type referInfo
} }
```

`referInfo` 返回：

```json
{ "referEntities": [{ "listFieldName": "children", "listFieldTitle": "下级", "referEntityName": "Department" }] }
```

`referEntityName` 即被引用对象。

## 与 qiqi 的差异

| 维度 | GraphQL `ObjectField` | `qiqi describe fields` |
| --- | --- | --- |
| 字段数（Department） | **195** | 191 |
| 字段数（自定义对象） | **124** | 119 |
| 图片字段 | ✅ 有 | ❌ 漏 |
| 唯一性 | — | qiqi 的结果是 GraphQL 的**真子集**，无 qiqi 独有字段 |
| 输出 | 结构化，可只选需要的字段 | 大输出，需读 `77hub.large-output` 的 `path` |

**推荐**：需要完整字段清单（尤其涉及图片字段）时用 GraphQL；只需要「有哪些字段」的快速浏览时 qiqi 够用。

## 注意

- `keyword` / `name` 等模糊匹配未广泛验证，`criteriaStr` 建议先用精确等值，确认生效后再改。
- 单对象字段可能上百条，务必用 `firstResult` + `maxResult` 翻页，`maxResult` 给到位（200 起）。
- 元数据同样受租户隔离：`Tenant-Id` 打错会看到别的库的对象，或什么都没有。
