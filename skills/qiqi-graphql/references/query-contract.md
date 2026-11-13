# 查询契约

以下全部经 2026-11-04 实测（某生产租户 `<TENANT_ID>` @ `cn-apnorthbj-0`），非文档推断。

## 请求

```
POST http://<集群域名>/graphql
Content-Type: application/json
Tenant-Id: <租户ID>          ← 必填，决定查哪个租户
```

Body：

```json
{ "query": "<GraphQL 语句>", "variables": null, "operationName": null }
```

- `/graphql` 与 `/graphql/withoutAuth` **行为完全一致**，随用哪个。
- `Cookie`、`Access-Token`、`From-Graphiql`、`Debug` 等头**都不影响结果**（已用伪造/空值/缺失三种情况对比，返回逐字节相同）。
- 支持 GraphQL `variables`，可以用变量传参。
- 非法租户 ID → `400`，**响应体为空**。

## 响应

```json
{ "data": { "<根字段>": [ ... ] }, "errors": [] }
```

- 成功时 `errors` 是空数组，不是缺省。
- **没有 `total`、没有 `pageInfo`、没有 `hasMore`**。分页完全靠自己算。
- 出错时 `data` 里对应字段为 `{}` 或整块缺失，错误在 `errors[0].message`。

## 分页

| 参数 | 含义 |
| --- | --- |
| `firstResult` | 起始偏移，从 0 开始 |
| `maxResult` | 本页条数 |

- **不传 `maxResult` 时只返回约 10 条**（某生产租户 `Department` 实测 10 条，而租户实际 69 条）。
- 判断拉完：`本页条数 < maxResult` 即已到底；`= maxResult` 说明可能还有下一页，`firstResult += maxResult` 继续。
- 实测 `firstResult:0, maxResult:3` → 第 1–3 条；`firstResult:3, maxResult:3` → 第 4–6 条，无重叠，行为正常。

## 排序

```graphql
Organization(sorts: [{ name: "name" }], maxResult: 3) { name }
```

- 输入类型 `SortByInputSchemaType` 只有两个字段：`name`（String，必填）和 `isDesending`（Boolean）。
- ⚠️ **是 `isDesending`，官方拼写就少一个 c**。写 `isDescending` 会报字段不存在。
- 传 `direction` / `order` 一律报 `contains a field not in 'SortByInputSchemaType'`。
- 不要用 `name: "-name"` 这类前缀写法做倒序，会直接把 `-` 拼进 SQL 报 `operator does not exist: - character varying`。倒序请用 `isDesending: true`。

## 筛选 criteriaStr

```graphql
Department(criteriaStr: "name like '%部%'", maxResult: 3) { name }
```

- 类 SQL 表达式，支持 `like`、`and`、`not like`、比较运算，字符串用**单引号**（在 GraphQL 字符串里需转义为 `''` 或 `\'`）。
- ⚠️ **左值必须用存储列名，不是 API 字段名**。实测 `createdAt` 报错：

  ```
  invalid field 'createdAt' (createdAtId in metadata) of <自定义对象>
  ```

  错误信息里括号内的 `createdAtId` 就是提示的正确列名——**报错信息本身会告诉你正确列名，这是最有效的排查手段**。
- 拿不准列名时，先用 `qiqi describe fields --profile <环境> --object <ObjectType>` 看元数据里的实际列名。

## 字段选择

- 只查需要的字段。整对象拉取会触发大响应。
- 引用字段通常返回 `{ id, name }`，可以直接在 GraphQL 里继续选子字段。
- `__typename` 可用，适合调试。

## 内省的真实边界

| 能力 | 结果 |
| --- | --- |
| `__schema { queryType { fields { name } } }` | ✅ 返回 2779 个根字段名，约 88KB |
| 自定义对象是否出现在上面 | ❌ **不出现**。`<自定义对象>` 不在内省结果里，但能正常查询 |
| `__type(name:"Department")` | ❌ 业务对象裸名恒返回 `{"data":{},"errors":[]}` |
| `__type(name:"DepartmentSchemaType")` | ✅ **正确写法，返回 435 个字段** |
| `__type(name:"ObjectFieldSchemaType")` | ✅ 元数据类型同样可用，79 个字段定义 |
| `mutationType` / `subscriptionType` | ❌ 返回空，`mutation` 报 `Schema is not configured for mutations` |

结论：**内省完全可用，但业务对象的类型名必须加 `SchemaType` 后缀**；自定义对象不在 schema 中。详见 [schema-introspection.md](schema-introspection.md)。

## 嵌套与多根字段

一次请求可以并列多个根字段，减少往返：

```graphql
{
  Organization(maxResult: 5) { name }
  User(maxResult: 2) { name }
}
```

返回 `data.Organization` 和 `data.User` 两个键。注意**任一字段出错会让整个 `data` 变空并带上 errors**，调试时建议一次只查一个根字段。
