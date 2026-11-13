# 常见查询配方

所有示例默认 `$Host` = 集群域名、`$Tid` = Tenant-Id。用 `scripts/gql.ps1` 时直接传参即可。

## 1. 确认租户对不对（第一件事）

```graphql
{ Organization(maxResult: 10) { id name } }
```

命中正确租户会看到**该租户特有**的组织名（每个租户都不一样，按自己目标租户的实际组织名判断）。只有「全局/默认集团/总部/默认集团公司/默认公司」= **打到了默认库**。

## 2. 组织架构

```graphql
{ Department(maxResult: 300) { id name } }
```

`Department` 是部门，`Organization` 是组织。两者不等价，取组织树时确认要哪个。

## 3. 用户清单

```graphql
{ User(maxResult: 100) { id name } }
```

某生产租户实测 961 个用户（单页 100 条需翻 10 页）。

## 4. 按名字找记录

```graphql
{ Department(criteriaStr: "name like '%部%'", maxResult: 20) { id name } }
```

## 5. 组合条件

```graphql
{ Department(criteriaStr: "name like '%部%' and name not like '%停用%'", maxResult: 20) { id name } }
```

## 6. 拉全量（脚本自动翻页）

```powershell
# PowerShell：-CollectAll（-All 是它的别名）
scripts\gql.ps1 -Env env-a -Query '{ Department(maxResult: 200){ id name } }' -CollectAll

# Node
node scripts/gql.mjs -e env-a -q '{ Department(maxResult: 200){ id name } }' --all
```

实测：某生产租户 `Department` 按每页 20 条翻页，得到 69 条、去重后仍 69 条，与 qiqi `query list Department` 的 `total: 69` 一致。

> ⚠️ 脚本内部踩过的坑：`$all` 这类变量名**不能与 `$All` 开关参数同名**——PowerShell 变量名不区分大小写，会覆盖开关参数本身，报「无法将 ArrayList 转换为 SwitchParameter」。脚本里已改用 `$collected` / `$CollectAll`。

手写时的循环骨架：

```powershell
$pageSize = 200; $offset = 0; $all = @()
while ($true) {
    $q = "{ Department(firstResult:$offset, maxResult:$pageSize) { id name } }"
    $rows = (调用).data.Department
    $all += $rows
    if ($rows.Count -lt $pageSize) { break }
    $offset += $pageSize
}
```

## 7. 自定义对象

某生产租户的自定义对象（`Cs` 开头）不在内省结果里，但可直接查：

```graphql
{ <自定义对象>(maxResult: 5) { id } }
```

字段名必须准确。先拿字段清单：

```powershell
qiqi describe fields --profile <环境名> --object <自定义对象>
```

## 8. 排序取最新

```graphql
{ Department(maxResult: 5, sorts: [{ name: "code", isDesending: true }]) { id name } }
```

## 9. 按 ID 精确取

```graphql
{ Department(criteriaStr: "id = '<记录ID>'", maxResult: 1) { id name } }
```

## 10. 交叉验证：同一条件走两条通道

结论重要时，用 GraphQL 和 qiqi CLI 各查一次对比：

```powershell
# GraphQL 通道（无数据权限过滤）
scripts\gql.ps1 -Env env-a -Query '{ Department(maxResult: 200){ id name } }' -CollectAll

# qiqi 通道（带当前用户数据权限，有 total）
qiqi query list Department --profile <环境名> --fields '["name"]' --limit 1
```

**两者条数不一致是正常的**——GraphQL 无鉴权、不过滤数据权限，qiqi 会按当前用户权限过滤。差异本身是信息，不要当成 bug。涉及「某人能看到什么」的结论必须用 qiqi 复核。

## 11. 单条记录的完整字段

GraphQL 不给字段结构，所以推荐流程：

1. `qiqi describe fields --profile <环境> --object <Type>` 拿 `apiName` 列表；
2. 用这些 `apiName` 拼 GraphQL 查询；
3. 若报 `invalid field 'x' (yId in metadata)`，把 `x` 换成报错里的 `yId` 重试。
