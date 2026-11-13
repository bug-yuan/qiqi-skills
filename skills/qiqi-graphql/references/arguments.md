# 根字段参数（ARGUMENTS）

GraphiQL 右侧 Docs 里每个根字段下方的 **ARGUMENTS** 列表，就是查询参数。**这些参数能用内省拿到**，而且系统对象和自定义对象是同一套。

## 怎么拿参数清单

```graphql
{ __type(name:"QueryType"){
    fields { name args { name description type{ kind name ofType{ kind name } } defaultValue } }
} }
```

`QueryType`（2779 个根字段）是服务端 schema 里所有根字段的容器。取某个对象的参数：

```powershell
scripts\gql.ps1 -Env env-a -Query '{ __type(name:"QueryType"){ fields{ name args{ name description } } } }'
```

## 18 个参数（实测 `Department`）

系统对象 `Department` / `Organization` / `User` **参数集完全相同**，都是 18 个：

| 参数 | 类型 | 实测 | 说明 |
| --- | --- | --- | --- |
| `maxResult` | Int | ✅ | 返回最大行数。**不传时只返回约 10 条** |
| `firstResult` | Int | ✅ | 起始行偏移（分页用） |
| `criteriaStr` | String | ✅ | SQL 风格条件串，用**存储列名** |
| `criteria` | GraphQLJSON | ✅ | 结构化条件 `{fieldName, operator, values}`。**运算符必须小写** |
| `sorts` | [SortByInput] | ✅ | 排序，`[{name, isDesending}]`（注意拼写 `isDesending`） |
| `bindVars` | [BindVariableInput] | ✅ | `criteriaStr` 里的命名参数 `:name` 绑定值 |
| `distinct` | Boolean | ✅ | 去重。**为 true 时不能查反向外键字段** |
| `resultStructure` | String | ✅ | `flat`（平铺）或 `tree`（树形） |
| `actionId` | String | ✅ | 数据权限动作：`view`/`add`/`update`/`delete`/`abort`/`unapprove` |
| `contextObject` | String | ✅ | 上下文对象名，如查 `Department` 时传 `Reimburse` |
| `contextField` | String | ✅ | 上下文字段名 |
| `contextOrgIds` | [String] | ✅ | 按组织过滤（无角色） |
| `contextRoleOrgIds` | Object | ✅ | 按组织 + 角色过滤，`{角色类型: 组织id}` |
| `contextAccountBookIds` | [String] | ✅ | 上下文账簿 |
| `contextDataScopeOrgIds` | [String] | ✅ | 数据权限组织过滤 |
| `orgScopeSpecs` | [OrgScopeSpecInput] | ✅ | 组织级字段取值定义 `{entityName, entityAlias, orgScopeFields, isDisabledOrgScope}` |
| `orgPropertyGetType` | String | ✅ | 组织字段取值方式：`allUsedOrg`/`usedOrgHadSetOrgProperty`/`createdOrg`/`notGet` |
| `isDisabledOrgScope` | Boolean | ✅ | 关闭组织范围限制 |

`SortByInputSchemaType` = `{ name: String, isDesending: Boolean }`
`BindVariableInputSchemaType` = `{ name: String, value: Object, typeName: String }`
`OrgScopeSpecInputSchemaType` = `{ entityName, entityAlias, orgScopeFields, isDisabledOrgScope }`

## 自定义对象：内省查不到，但参数一模一样

`Cs*` 根字段**不在 `QueryType` 里**（实测 `Cs*` 根字段数 = 0），所以内省拿不到它的参数定义。

但实测 **17 个参数在自定义对象上同样可用**（`firstResult`/`maxResult`/`criteriaStr`/`criteria`/`sorts`/`distinct`/`resultStructure`/`actionId`/`contextOrgIds`/`orgPropertyGetType`/…）：

```graphql
{ <自定义对象>(sorts:[{name:"code",isDesending:true}], maxResult:1){ id code } }
# → OK，{"code":"010000172026110001"}
```

原因：GraphiQL 的 `graphiql/js/schema.js` 里 `buildQueryType(entityName)` 用固定的 `queryTypeTemplate` 给自定义对象造根字段，参数就是这个模板的 18 个。**所以服务端接受它们，只是不写进静态 schema。**

## `customizedFields` 是个坑

GraphiQL 的 `queryTypeTemplate` 里确实有 `customizedFields`，但：

```graphql
{ Department(customizedFields:["x"], maxResult:1){ id } }
# → Validation error of type UnknownArgument: Unknown field argument customizedFields
```

**模板和真实 schema 不一致，不许传。** 这再次说明 Docs 面板是前端产物，不能当契约。

## `criteria` 的运算符（实测）

`CriteriaOperator` **不是 schema 里的枚举**（`__type` 查不到），是运行时校验。**运算符必须全小写**：

| 运算符 | 结果 |
| --- | --- |
| `eq` `ne` `gt` `ge` `lt` | ✅ |
| `like` `in` `notin` `isnull` `between` | ✅ |
| `Like` / `EQ` / `gtE` / `lte` / `equal` / `contains` | ❌ 报 `Exception while fetching data` |

```graphql
{ Department(criteria:{fieldName:"name", operator:"like", values:["%a%"]}, maxResult:1){ id } }
{ Department(criteria:{fieldName:"code", operator:"between", values:["01","99"]}, maxResult:1){ id } }
```

注意 `between` 要正好 2 个值，`isnull` 传 `[true]`。

## 怎么选：`criteriaStr` vs `criteria`

| | `criteriaStr` | `criteria` |
| --- | --- | --- |
| 写法 | SQL 字符串 `"name like '%a%'"` | JSON 对象 |
| 字段名 | **存储列名**（`createdAt`→`createdAtId`） | 同 |
| 报错提示 | 列名错会明确告诉你正确列名 | 运算符错只报运算符本身 |
| 适合 | 手写调试、复杂条件 | 脚本拼装、防注入 |

日常优先 `criteriaStr`；需要动态拼条件时用 `criteria` + `bindVars`。
