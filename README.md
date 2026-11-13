# qiqi-skills

企企 Agent 技能 · **通用仓**：公司任何角色（售前、实施、客服、客户成功、客开）都能用的 Agent Skill 集合。

目前收录两个技能：**产品怎么定义**查 `qiqi-product-knowledge`（知识库检索路由，全员适用），
**某个租户的实际数据是什么**查 `qiqi-graphql`（77hub GraphQL 只读取数，按需单装）。

> 本仓旧名 `qiqi-product-knowledge-skills`，改名后 GitHub 会自动 301 重定向到 `qiqi-skills`，旧链接可继续用。

## 仓与技能的分工

本仓只是一处，同一个生态里还有另外两个来源，装之前先看清楚该找谁：

| 来源 | 地址 | 放什么 | 谁用 |
| --- | --- | --- | --- |
| **本仓 `qiqi-skills`** | `bug-yuan/qiqi-skills`（公开） | 通用技能：产品知识检索、GraphQL 取数 | 公司**任何角色** |
| `qiqi-dev-skills` | 客开内部仓 | 客开专用技能（脚本开发、低代码扩展等） | **客开人员**专用，与本仓互补 |
| `cli-skills` | gitee `qiqihub/cli-skills` | `qiqi-cli`、`qiqi-business-foundations`、`qiqi-cli-installation` | 需要用 `qiqi` 命令干活的人 |

> 那三个 `qiqi-*` 命令类技能**不在本仓**，不要在本仓里找，也不要用本仓的安装命令装。

## 仓内两个技能

| 技能 | 回答什么问题 | 依赖 | 是否建议默认装 |
| --- | --- | --- | --- |
| `qiqi-product-knowledge` | 「产品**怎么定义**」——功能、单据、字段、枚举、业务规则、预算与报表口径、审批流、权限、模块归属、某版本新增/变更/下线 | 乐享（`lexiang`）MCP | ✅ 建议所有人都装 |
| `qiqi-graphql` | 「**某租户实际数据是什么**」——跨用户名/组织/对象自由查询、排查数据、验证字段值、取自定义对象 | 公司 VPN + 自填 `env.local.json` | ⚠️ 只在确实需要直接取数时装 |

## 安装

需要 Node.js 22.20+ 与 `npx`。

### 推荐：把这段话发给你的 AI 工具

复制整段，粘给任意有 shell 权限的 AI 工具（Claude Code、Codex、Cursor、OpenCode…）：

```text
请帮我安装企企 Agent 通用技能（注意两条命令都必须带 -s，且不要省略 -a universal）：

第 1 条（产品知识库检索，都要装）：
npx --yes skills@latest add bug-yuan/qiqi-skills -g -a universal -s qiqi-product-knowledge -y

第 2 条（GraphQL 直接取数，按需装）：
npx --yes skills@latest add bug-yuan/qiqi-skills -g -a universal -s qiqi-graphql -y

装完确认 ~/.agents/skills/ 下对应目录的 SKILL.md 存在，并提醒我重启或刷新会话。
```

### 手动执行

**第 1 条：产品知识库检索（所有人都要）**

```bash
npx --yes skills@latest add bug-yuan/qiqi-skills -g -a universal -s qiqi-product-knowledge -y
```

**第 2 条：GraphQL 只读取数（按需）**

```bash
npx --yes skills@latest add bug-yuan/qiqi-skills -g -a universal -s qiqi-graphql -y
```

其他写法：

```bash
# 先看看仓里有什么，不安装
npx --yes skills@latest add bug-yuan/qiqi-skills --list

# 只装到当前项目（不带 -g），不写全局
npx --yes skills@latest add bug-yuan/qiqi-skills -a universal -s qiqi-product-knowledge -y
```

### ⚠️ 三个必须知道的坑

1. **⚠️ 不要省略 `-s <技能名>`。** 不带 `-s` 会把仓内**全部**技能一次装上——只想要产品知识的人会被连带装上 `qiqi-graphql`，然后多出一堆 VPN、Tenant-Id 相关的困惑。想要哪个就写哪个，两条命令分开执行。
2. **⚠️ 不要省略 `-a universal`。** 不加 `-a` 时 CLI 会按 `--yes` 默认装到**所有**它认识的 Agent，在用户目录下创建几十个 `.xxx` 文件夹。只用 `-a universal` 就只落一个 `.agents`，再由 CLI 链到各 Agent 目录，因此不绑定任何具体工具（codex / claude-code / cursor / cline 都能读到）。
3. **⚠️ `qiqi-graphql` 依赖公司 VPN。** 集群域名解析到 `10.x` 私网地址，只能在 VPN 隧道内访问；**断 VPN 的表现是 TCP 超时 / 请求长时间无响应，而不是报错**，极易误判成「服务挂了」或「租户不对」。相比之下 `qiqi` CLI 的网关 `cli.77hub.com` 是公网地址，断 VPN 时照常可用——这是两者的硬分界。

装到哪：`-a universal` → `~/.agents/skills/<技能名>/`（Windows 为 `%USERPROFILE%\.agents\skills\`）。这是跨工具通用目录，也是本仓技能的落地位置。

安装完成后需要**重启或刷新 Agent 会话**，技能才会被加载。

### 验证与升级

```bash
# 看已装了什么、来源对不对
npx --yes skills@latest ls -g --json

# 升级：重跑对应的 add 即可（覆盖式）；也可用下面这条等价写法
npx --yes skills@latest update qiqi-product-knowledge -g -y
```

## 使用前置

### `qiqi-product-knowledge`：乐享 MCP

本技能只是检索路由，**不含任何数据、token 或凭据**。真正读知识库靠乐享 MCP（`lexiang`）连接，需要在 Agent 里配好该 MCP 服务并处于 connected 状态，否则路由表能读到、正文取不到。

### `qiqi-graphql`：`env.local.json` + VPN

脚本不内置任何环境，**必须自建** `skills/qiqi-graphql/scripts/env.local.json`：

```json
{
  "envs": {
    "env-a": { "host": "graphql.<区域>-<序号>.77hub.com", "tid": "<TENANT_ID>" }
  }
}
```

- 仓里**只提交** `env.example.json`（纯占位符），`env.local.json` 已在 `.gitignore` 中，不会被提交。
- 别名键由你自己定，可以写中文；脚本不内置任何别名。
- 解析优先级：显式参数（`-Server`/`-Tid`、`-h/--host`、`-t/--tid`）→ 环境变量 `QI_GQL_HOST` / `QI_GQL_TID` → `env.local.json` → 全无则报错并提示如何创建。
- 用法见 `skills/qiqi-graphql/SKILL.md`；**本仓不含任何真实租户 ID**，`<TENANT_ID>` 一律由使用者本地填写。

## 目录结构

```
skills/
├── qiqi-product-knowledge/
│   ├── SKILL.md                      # 六层结构、强制检索流程、引用格式、事实边界
│   └── references/
│       ├── kb-index.md               # 全量 entry_id 索引（导航台账 / 模块 / 机制 / 治理 / 变更档案）
│       ├── query-playbook.md         # 检索式模板、分层策略、坑位
│       └── routing-map.md            # 业务意图 → 域码 → 条目码段
└── qiqi-graphql/
    ├── SKILL.md                      # 适用边界、三条铁律、字段查法、关键约束速查、与 qiqi CLI 分工
    ├── references/
    │   ├── cluster-and-tenant.md     # 集群域名与 Tenant-Id 解析、新增环境
    │   ├── object-fields.md          # ObjectField 查字段（含图片字段）
    │   ├── schema-introspection.md   # __type 内省、435/195/191 三通道差异
    │   ├── arguments.md              # 根字段参数、criteria 运算符、sorts / bindVars
    │   ├── query-contract.md         # 参数怎么传、返回结构、报错怎么读
    │   ├── recipes.md                # 常见查询配方（组织树、用户、自定义对象、分页拉全量）
    │   └── troubleshooting.md        # 「查得到但数据不对」「400」「字段不存在」排查
    └── scripts/
        ├── gql.ps1                   # PowerShell 调用脚本（分页、UTF-8、错误分类）
        ├── gql.mjs                   # Node.js 跨平台调用脚本
        └── env.example.json          # 配置模板；env.local.json 需自建且不入库
```

## 事实边界（重要）

- **知识库只给产品定义**：`qiqi-product-knowledge` 回答「产品怎么设计的」，**不证明**当前租户已启用该能力、有权限使用或有数据。租户事实一律以 `qiqi` CLI 实测为准。
- **GraphQL 结果不等于用户可见数据**：`qiqi-graphql` 走的接口无鉴权、不走数据权限，结果可能比该用户在有权限的 CLI 里看到的多。涉及权限口径的结论必须回到 `qiqi` 复核。
- **检索无果 ≠ 能力不存在**：部分能力只在客开内部文档记载，判定存在性时须作为第三类来源考虑。
- 知识库内容覆盖至 **2026-09-14**；帮助文档与迭代说明冲突时取发布日期较晚者。
- 本仓只放**检索规范、脚本与文档**，不放知识库正文，也不放客户交付资料。

## 脱敏与安全

- 本仓是 **public**，已完成脱敏：**不含客户名称、真实 Tenant-Id、内网 IP、客户自定义对象/字段的真实 API 名**。
- 环境凭据（`env.local.json` 里的 `host` + `tid`）由使用者本地填写，**不入库**；示例一律用 `env-a`、`<TENANT_ID>` 这类占位符。
- ⚠️ GraphQL 接口**只读、无鉴权，`Tenant-Id` 即唯一凭据**。请勿把真实 TID 提交进仓库、贴到 Issue 或发给外部。
- GraphQL 传输为明文 HTTP，**不是安全通道**，不要在上面传敏感内容。
- 提交前自查：`git diff` 里不应出现任何真实客户名、真实 TID、`10.x` 真实地址。

## 维护

**本仓是唯一编辑入口**：改动直接在 `skills/<技能名>/` 里改 → 提交推送 → 再跑一次对应的安装命令覆盖本地 `~/.agents/skills/`。

- 安装是**复制**而非软链：改仓库后不会自动生效，**必须重新执行 `add`** 覆盖。
- 不要反向改：本地安装目录是 `npx ... add` 复制出来的产物，改了会在下次安装时被仓库内容覆盖，而且改完不推送，别人装到的仍是旧版。
- 新增技能时：放进 `skills/<技能名>/`，并在本 README 的「仓内两个技能」表、安装命令、目录结构三处同步补上（安装命令记得带 `-s <技能名>`）。

## License

**内部使用许可（Internal Use Only）**，不是开源项目。条款见 [LICENSE](LICENSE)。

本仓在 GitHub 上公开可见，**只是为了免去同事安装时的授权麻烦**；可见性不等于授权：

- ✅ 公司内部同事可以安装、使用、阅读、修改，并在内部流转
- ❌ 不得对外发布、上传到其他公共平台、或提供给公司以外的第三方
- ❌ 不适用任何开源许可（含 MIT），不授予开源许可下的权利
