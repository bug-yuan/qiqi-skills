# 用 GraphQL Schema 获取字段

**能。** `__type` 完全可用，只是业务对象的类型名要加 `SchemaType` 后缀。2026-11-04 实测。

## 一句话结论

```graphql
# ❌ 错误：业务对象名直接查，恒返回空
{ __type(name:"Department"){ name fields{ name } } }
# → {"data":{},"errors":[]}

# ✅ 正确：加 SchemaType 后缀
{ __type(name:"DepartmentSchemaType"){ name fields{ name type{ kind name } } } }
# → 435 个字段
```

根字段声明了它返回什么类型，照着查即可：

```graphql
{ __schema { queryType { fields { name type { kind name ofType { kind name } } } } } }
# Department → LIST of OBJECT/DepartmentSchemaType
```

## 命名规律

| 根字段 | 返回类型 |
| --- | --- |
| `Department` | `DepartmentSchemaType` |
| `Organization` | `OrganizationSchemaType` |
| `User` | `UserSchemaType` |
| `ObjectField` | `ObjectFieldSchemaType` |
| `ObjectType` | `ObjectTypeSchemaType` |

统一规则：**`<对象名>SchemaType`**。实测 2793 个类型里有 2776 个是 `*SchemaType`。

## 与其他通道的对比（关键）

三个通道拿到的字段数完全不同，**不是谁对谁错，是三层不同的东西**：

| 通道 | `Department` 字段数 | 拿到的是什么 |
| --- | --- | --- |
| `__type(DepartmentSchemaType)` | **435** | GraphQL 对外暴露的全部可查字段，含引用对象的展开形态 |
| `ObjectField` 元数据表 | **195** | 租户里真实存在的字段（数据库/表单一层） |
| `qiqi describe fields` | **191** | 上述的子集，且漏图片字段 |

### 435 比 195 多出来的 247 个是什么

`DepartmentSchemaType` 的字段按类型分：

- SCALAR 84 个
- OBJECT 138 个
- LIST 213 个

多出来的主要是两类：

1. **引用对象的展开**：`partyTypeId`(scalar) 与 `partyType`(OBJECT) 成对出现；`createdUserId` / `createdUser`、`modifiedUserId` / `modifiedUser`、`srcObjectId` / `srcObject`、`srcObjectType` / `srcObjectTypeObject`，以及 `children` 这类反向关系（LIST）。
2. **虚拟/表达式字段**：如 `srcObjectObjectData`。

**数据查询只认 `ObjectField` 里那 195 个真字段**——把 `partyType` 当字段名去写 `criteriaStr` 会报 `invalid field`，但可以写在选取集里让服务端展开。

### 仅 `ObjectField` 有的 7 个

`__type` 反而查不到这 7 个字段（都是多语 / 历史版本类的 `cs*` 自定义字段）。它们的名字有明显规律，认识规律就能对上号：

```
<字段A><哈希后缀>                      <字段A><哈希后缀>Objects
<字段B><哈希后缀>                      <字段B><哈希后缀>Nbr
<字段C><哈希后缀>                      <字段D><哈希后缀>
hisVer<字段D><哈希后缀>
```

即：一组基础字段 + 其 `Objects`（多语对象）/ `Nbr`（编号）派生字段，以及一个 `hisVer` 前缀的历史版本字段。

说明 **`__type` 和 `ObjectField` 互补，不能互相替代**。

## 自定义对象：Schema 里没有

某自定义对象及其 `<自定义对象>SchemaType` **都不在服务端 schema 中**（2793 个类型里 `Cs*` 数量为 0），但数据能正常查。

原因：schema 是**编译期按标准对象生成**的，租户后建的自定义对象运行时动态解析，不走静态 schema。

→ 自定义对象字段用 `Entities(names:[...])` 或 `ObjectField` 查。

> 注意：**GraphiQL 的 Docs 面板里能看到这个 SchemaType，那是前端合成的**，见本文末尾「GraphiQL 的 Docs 是前端合成的」一节。

## 怎么选

| 你的目的 | 用哪个 |
| --- | --- |
| 想知道「这条数据能查出哪些字段」（GraphQL 选取集可写什么） | `__type(XxxSchemaType)` |
| 想知道「这个对象实际有哪些字段」（写 `criteriaStr`、回填、建脚本） | `ObjectField` |
| 找图片字段 `bizType=img` | `ObjectField`（schema 不分 bizType） |
| 自定义对象 | `ObjectField` |
| 枚举候选值 | `qiqi query values` |

**写查询/写脚本一律以 `ObjectField` 为准**；`__type` 用于确认某个字段名在 GraphQL 层到底能不能选、以及它的标量类型是什么。

## 常用内省查询

```graphql
# 字段名 + 类型
{ __type(name:"OrganizationSchemaType"){ fields{ name type{ kind name ofType{ kind name } } } } }

# 只列字段名
{ __type(name:"UserSchemaType"){ fields{ name } } }

# 类型间关系
{ __type(name:"DepartmentSchemaType"){ fields{ name type{ name kind ofType{ name } } } } }

# 单个字段的详情
{ __type(name:"DepartmentSchemaType"){ fields{ name description isDeprecated } } }
```

## 已知限制

- `isDeprecated` 恒为 `false`（实测 0 个废弃字段），依赖它判断字段废弃不可行。
- `description` 多为空，业务含义仍要看 `ObjectField.title`。
- `ObjectField` 元数据表本身也有 `__type`：`ObjectFieldSchemaType`（79 个字段），可用于发现元数据有哪些属性。

## ⚠️ GraphiQL 的 Docs 是前端合成的，别拿它当服务端 schema

**这是最容易踩的坑。** 在 GraphiQL 里点右上角 `Docs` → 点 `<自定义对象>SchemaType`，能看到完整的自定义对象字段列表，会让人以为服务端 schema 里真有这个类型。**但服务端没有。**

验证：

```graphql
{ __type(name:"<自定义对象>SchemaType"){ name } }   # → {"data":{},"errors":[]}
{ __schema { types { name } } }                     # → 2793 个类型，Cs* 数量 = 0
```

### 原理（读 `graphiql/js/graphiql.js` 源码确认）

GraphiQL 加载 schema 时发**两个**请求，然后在浏览器里合并：

```js
Promise.all([
  fetcher({ query: introspectionQuery }),              // ① 服务端真实 schema
  fetcher({ query: '{
      Entities(isCustomizedOnly: true) {               // ② 自定义对象元数据
        name isCustomizedEntity
        fields { name apiName type title ... }
      }
    }' })
]).then(arr => buildCustomizedSchema(arr))             // ③ 前端拼进 types 数组
```

`buildCustomizedSchema` 做两件事：

- 对每个自定义对象，`buildQueryType(entityName)` + `buildSchemaType(entityName)` 造出 `XxxSchemaType`，**push 进前端 types 数组**；
- 对系统对象，把租户自定义字段 **concat 进已有字段**。

所以 Docs 面板里看到的是 **① + ② 的并集**，而 `__type` 只查 ①。

### 这意味着什么

| 问题 | 答案 |
| --- | --- |
| 自定义对象能用 `__type` 查吗 | **不能**，服务端 schema 里根本没有 |
| 那怎么查自定义对象字段 | `Entities(names:[...])` 或 `ObjectField`，两条通道结果完全一致 |
| 能在 GraphQL 里查自定义对象数据吗 | **能**，运行时按名字动态解析，不受静态 schema 限制 |
| Docs 里显示的字段可信吗 | 可信（来源于 ②），但它不等于 `__type` 能查到 |

## `Entities` 根字段（自定义对象的正确入口）

```graphql
{ Entities(names: ["<自定义对象>"]) {
    name title type
    fields { name title type apiName isCustomizedField enumType
             referInfo { referEntityName }
             sourceInfo { sourceEntityName } }
} }
```

- 参数：`names`（数组）、`versionId`、`isCustomizedOnly`。**没有 `maxResult`/`firstResult`**，传了会报 `Unknown argument`。
- 返回类型 `EntitySchemaType`（41 个字段）。
- 实测：`Entities(names:["<自定义对象>"])` → 124 个字段，含图片字段；`Entities(names:["Department"])` → 195 个字段，和 `ObjectField` 完全一致。
- `isCustomizedOnly: true` 返回 295 个，其中只有 60 个 `isCustomizedEntity=true`——**别把 295 当成"自定义对象数"**，它更像「可定制的实体」范围。

### 三通道最终对照

某自定义对象：

| 通道 | 字段数 |
| --- | --- |
| `Entities(names:[...])` | 124 |
| `ObjectField` | 124 |
| `__type` | **0（服务端无此类型）** |

`Department`：

| 通道 | 字段数 |
| --- | --- |
| `__type("DepartmentSchemaType")` | 435（含引用展开） |
| `Entities` / `ObjectField` | 195 |
