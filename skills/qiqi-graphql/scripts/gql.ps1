<#
.SYNOPSIS
    企企 77hub GraphQL 只读查询。

.DESCRIPTION
    按集群域名 + Tenant-Id 查询租户数据。处理 UTF-8 编码、分页、错误分类。
    接口只读，不支持 mutation。

    目标环境从外部配置读取，脚本不内置任何环境（别名与凭据都不进仓库）：
      1. 显式参数 -Server / -Tid
      2. 环境变量 QI_GQL_HOST / QI_GQL_TID
      3. env.local.json 里按 -Env 别名取
         查找顺序：$env:QI_GQL_CONFIG → 脚本所在目录 → 当前工作目录
         格式：{ "envs": { "env-a": { "host": "graphql.cn-apnorthbj-0.77hub.com", "tid": "<TENANT_ID>" } } }
      4. 都没有 → 报错并提示复制 env.example.json 为 env.local.json

.PARAMETER Server
    集群域名，如 graphql.cn-apnorthbj-0.77hub.com。可用环境别名代替（见 -Env）。

.PARAMETER Env
    环境别名，取值来自 env.local.json 的 envs 下的键（别名由使用者自定，脚本不内置任何别名）。

.PARAMETER Tid
    Tenant-Id。省略 -Env 时必填。

.PARAMETER Query
    GraphQL 语句。-All 时需包含 maxResult。

.PARAMETER Field
    -All 时从 data 里取哪个根字段。默认自动推断（查询里只有一个根字段时可用）。

.PARAMETER PageSize
    -All 时每页条数，默认 200。

.PARAMETER CollectAll
    自动翻页拉全量。-All 是别名（注意：不能用 $All 作变量名，
    PowerShell 不区分大小写，会覆盖开关参数本身）。

.PARAMETER Raw
    输出原始 JSON 字符串，不解析。

.EXAMPLE
    .\gql.ps1 -Env env-a -Query '{ Organization(maxResult: 10){ id name } }'

.EXAMPLE
    .\gql.ps1 -Env env-a -Query '{ Department(maxResult: 200) { id name } }' -CollectAll

.EXAMPLE
    .\gql.ps1 -Server graphql.cn-northwest-4.77hub.com -Tid <TENANT_ID> -Query '{ User(maxResult:5){ name } }'

.EXAMPLE
    # 查某个对象的全部字段（含图片字段），不需要写 Query
    .\gql.ps1 -Env env-a -Fields Department

.EXAMPLE
    # 先列出所有对象
    .\gql.ps1 -Env env-a -Objects
#>
[CmdletBinding(DefaultParameterSetName = 'Query')]
param(
    [string]$Server,
    [string]$Env,
    [string]$Tid,
    [Parameter(Mandatory = $true, ParameterSetName = 'Query')][string]$Query,
    [Parameter(Mandatory = $true, ParameterSetName = 'Fields')][string]$Fields,
    [Parameter(Mandatory = $true, ParameterSetName = 'Entities')][string]$Entities,
    [Parameter(Mandatory = $true, ParameterSetName = 'Objects')][switch]$Objects,
    [string]$Field,
    [int]$PageSize = 200,
    [Alias('All')][switch]$CollectAll,
    [switch]$Raw
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------- 外部配置解析 ----------
# 兼容 Windows PowerShell 5.1 与 pwsh：不用 ?? / ??= / 三元 / -AsHashtable 等 PS7 专属语法。

$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:ExamplePath = Join-Path $script:ScriptDir 'env.example.json'

function Find-ConfigPath {
    $candidates = New-Object System.Collections.ArrayList
    if ($env:QI_GQL_CONFIG) { [void]$candidates.Add([string]$env:QI_GQL_CONFIG) }
    if ($script:ScriptDir) { [void]$candidates.Add((Join-Path $script:ScriptDir 'env.local.json')) }
    $cwd = (Get-Location).Path
    if ($cwd) { [void]$candidates.Add((Join-Path $cwd 'env.local.json')) }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

function Read-EnvConfig {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) { throw "配置文件 '$Path' 是空的。请参照 $($script:ExamplePath) 填写。" }
    try {
        $obj = $raw | ConvertFrom-Json
    }
    catch {
        throw "配置文件 '$Path' 不是合法 JSON：$($_.Exception.Message)"
    }
    $map = @{}
    if ($obj -and $obj.PSObject.Properties['envs'] -and $obj.envs) {
        foreach ($p in $obj.envs.PSObject.Properties) {
            $h = ''
            $t = ''
            if ($p.Value) {
                if ($p.Value.PSObject.Properties['host'] -and $p.Value.host) { $h = [string]$p.Value.host }
                if ($p.Value.PSObject.Properties['tid'] -and $p.Value.tid) { $t = [string]$p.Value.tid }
            }
            $map[$p.Name] = @{ Host = $h; Tid = $t }
        }
    }
    return @{ Path = $Path; Envs = $map }
}

function Get-NoConfigMessage {
    $lines = @(
        '未找到配置文件 env.local.json（查找顺序：$env:QI_GQL_CONFIG → 脚本所在目录 → 当前工作目录）。',
        "请复制 '$($script:ExamplePath)' 为 '$(Join-Path $script:ScriptDir 'env.local.json')'，把 host / tid 填成自己的值后重试。",
        '也可以用 -Server/-Tid 直接指定，或设置环境变量 QI_GQL_HOST/QI_GQL_TID。'
    )
    return ($lines -join [Environment]::NewLine)
}

function Get-AvailableAliases {
    param($Envs)
    $names = @($Envs.Keys | Sort-Object)
    if ($names.Count -eq 0) { return '（空，envs 下还没有任何别名）' }
    return ($names -join ' / ')
}

function Resolve-Target {
    param([string]$Server, [string]$Tid, [string]$EnvName)

    $hostValue = $Server
    $tidValue = $Tid
    $hostSource = '显式 -Server'
    $tidSource = '显式 -Tid'

    if (-not $hostValue -and $env:QI_GQL_HOST) { $hostValue = $env:QI_GQL_HOST; $hostSource = '环境变量 QI_GQL_HOST' }
    if (-not $tidValue -and $env:QI_GQL_TID) { $tidValue = $env:QI_GQL_TID; $tidSource = '环境变量 QI_GQL_TID' }

    if (-not $hostValue -or -not $tidValue) {
        $cfgPath = Find-ConfigPath
        if (-not $cfgPath) { throw (Get-NoConfigMessage) }
        $cfg = Read-EnvConfig -Path $cfgPath

        if ($EnvName) {
            if (-not $cfg.Envs.ContainsKey($EnvName)) {
                throw "未知环境别名 '$EnvName'。可用别名从 '$cfgPath' 读取，已配置：$(Get-AvailableAliases $cfg.Envs)。别名由使用者自定，可在 env.local.json 的 envs 下增删。"
            }
            $entry = $cfg.Envs[$EnvName]
            if (-not $hostValue -and $entry.Host) { $hostValue = $entry.Host; $hostSource = "env.local.json[$EnvName].host" }
            if (-not $tidValue -and $entry.Tid) { $tidValue = $entry.Tid; $tidSource = "env.local.json[$EnvName].tid" }
            if (-not $hostValue) { throw "env.local.json 里别名 '$EnvName' 缺少 host（$cfgPath）。示例见 $($script:ExamplePath)。" }
            if (-not $tidValue) { throw "env.local.json 里别名 '$EnvName' 缺少 tid（$cfgPath）。示例见 $($script:ExamplePath)。" }
        }
        else {
            throw "没有指定 -Env，也没有 -Server/-Tid 或 QI_GQL_HOST/QI_GQL_TID。已在 '$cfgPath' 找到配置，可用别名：$(Get-AvailableAliases $cfg.Envs)。例如：-Env env-a"
        }
    }

    if ($tidValue -match '^<.+>$') {
        throw "Tenant-Id 还是占位符 '$tidValue'，请把它换成真实 Tenant-Id（来源：$tidSource）。"
    }
    if ($hostValue -match '^<.+>$') {
        throw "集群域名还是占位符 '$hostValue'，请把它换成真实集群域名（来源：$hostSource）。"
    }

    return @{ Host = $hostValue; Tid = $tidValue; HostSource = $hostSource; TidSource = $tidSource }
}

$target = Resolve-Target -Server $Server -Tid $Tid -EnvName $Env
$Server = $target.Host
$Tid = $target.Tid
Write-Verbose "目标：host=$Server（$($target.HostSource)）tid=$Tid（$($target.TidSource)）"

if ($Server -match '^https?://') { $uri = "$($Server.TrimEnd('/'))/graphql" } else { $uri = "http://$Server/graphql" }

function Invoke-Gql {
    param([string]$Q)
    $json = @{ query = $Q; variables = $null; operationName = $null } | ConvertTo-Json -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        $resp = Invoke-WebRequest -Uri $uri -Method Post -ContentType 'application/json' `
            -Headers @{ 'Tenant-Id' = $Tid } -Body $bytes -TimeoutSec 60 -UseBasicParsing
        return ($resp.Content | ConvertFrom-Json)
    }
    catch {
        $r = $_.Exception.Response
        if ($r) {
            $code = [int]$r.StatusCode
            if ($code -eq 400) {
                throw "HTTP 400（空响应体）：租户 '$Tid' 在集群 '$Server' 不存在。请换集群域名重试，见 references/cluster-and-tenant.md"
            }
            throw "HTTP $code : $($_.Exception.Message)"
        }
        $msg = $_.Exception.Message
        # 连接层超时/不可达：Windows 中文消息形如「由于连接方在一段时间后没有正确答复…连接尝试失败」，
        # 英文版为 "The operation has timed out" / "Unable to connect to the remote server"，
        # 故同时按 WebExceptionStatus 与多种文案判定。
        $isNetTimeout = ($_.Exception.Status -eq 'Timeout') -or ($_.Exception.Status -eq 'ConnectFailure') -or
            ($msg -match 'timed out|timeout|超时|没有正确答复|连接尝试失败|无法连接到远程服务器|无法连接')
        if ($isNetTimeout) {
            throw "连接 $uri 超时/不可达：该集群是 10.x 私网地址，需先连公司 VPN，连上后重试。不要改 Tenant-Id 或换集群，见 references/troubleshooting.md「请求超时」"
        }
        throw "请求失败：$msg（若为内网不可达请确认 VPN，见 references/troubleshooting.md）"
    }
}

function Get-Payload {
    param($Obj)
    if ($Obj.errors -and $Obj.errors.Count -gt 0) {
        $msg = $Obj.errors[0].message
        if ($msg -match 'Schema is not configured for mutations') {
            throw '本接口只读，不支持 mutation。写入请走 qiqi 或平台脚本。'
        }
        if ($msg -match "invalid field '([^']+)' \(([^)]+) in metadata\)") {
            throw "criteriaStr 列名错误：'$($Matches[1])' 应为 '$($Matches[2])'"
        }
        throw "GraphQL 错误：$msg"
    }
    return $Obj.data
}

# ---------- 元数据模式 ----------
if ($PSCmdlet.ParameterSetName -eq 'Fields') {
    $esc = $Fields.Replace("'", "''")
    $Query = "{ ObjectField(criteriaStr: `"objectType = '$esc'`", maxResult: $PageSize) { name title type bizType isEnum enumType isRequired isCustomizedField isDisabled length } }"
    $CollectAll = $true
    $Field = 'ObjectField'
}
elseif ($PSCmdlet.ParameterSetName -eq 'Entities') {
    # 自定义对象走 Entities（服务端 schema 里没有 Cs* 类型）
    $esc = $Entities.Replace("'", "''").Replace('"', '\"')
    $q = "{ Entities(names: [`"$esc`"]) { name title type isCustomizedEntity fields { name title type apiName bizType enumType isCustomizedField isRequired } } }"
    $data = Get-Payload -Obj (Invoke-Gql -Q $q)
    $ent = @($data.Entities)
    if (-not $ent -or $ent.Count -eq 0) { throw "未找到对象 '$Entities'（检查对象名，或该租户下不存在）" }
    if ($Raw) { return ($ent[0] | ConvertTo-Json -Depth 20) }
    return , @($ent[0].fields)
}
elseif ($PSCmdlet.ParameterSetName -eq 'Objects') {
    $Query = "{ ObjectType(maxResult: $PageSize) { name title type appName isCustomizedEntity isDisabled } }"
    $CollectAll = $true
    $Field = 'ObjectType'
}

if (-not $CollectAll) {
    $result = Invoke-Gql -Q $Query
    $data = Get-Payload -Obj $result
    if ($Raw) { return ($result | ConvertTo-Json -Depth 20) }
    return $data
}

# ---------- 自动翻页 ----------
if (-not $Field) {
    $probeData = Get-Payload -Obj (Invoke-Gql -Q $Query)
    $names = @($probeData.PSObject.Properties.Name)
    if ($names.Count -ne 1) { throw "查询有 $($names.Count) 个根字段，请用 -Field 指定一个" }
    $Field = $names[0]
}

if ($Query -notmatch 'maxResult') {
    throw "-CollectAll 要求查询里包含 maxResult，例如 { Department(maxResult: 200){ id name } }"
}

# 把 maxResult 换成带偏移的模板
if ($Query -match 'firstResult\s*:') {
    $template = [regex]::Replace($Query, 'firstResult\s*:\s*\d+', 'firstResult: {OFFSET}')
    $template = [regex]::Replace($template, 'maxResult\s*:\s*\d+', "maxResult: $PageSize")
}
else {
    $template = [regex]::Replace($Query, 'maxResult\s*:\s*\d+', "firstResult: {OFFSET}, maxResult: $PageSize", 1)
}

$collected = New-Object System.Collections.ArrayList
$offset = 0
for ($page = 1; $page -le 500; $page++) {
    $q = $template.Replace('{OFFSET}', [string]$offset)
    $payload = Get-Payload -Obj (Invoke-Gql -Q $q)
    $rows = @($payload.$Field)
    foreach ($row in $rows) { [void]$collected.Add($row) }
    Write-Verbose "page $page offset $offset got $($rows.Count)"
    if ($rows.Count -lt $PageSize) { break }
    $offset += $PageSize
}

Write-Verbose "总计 $($collected.Count) 条（接口无 total，按页累加）"
return , $collected.ToArray()
