#!/usr/bin/env node
/**
 * 企企 77hub GraphQL 只读查询（Node 版，无需安装依赖）。
 *
 * 目标环境从外部配置读取，脚本不内置任何环境（别名与凭据都不进仓库）：
 *   1. 显式参数 -h/--host、-t/--tid
 *   2. 环境变量 QI_GQL_HOST / QI_GQL_TID
 *   3. env.local.json 里按 -e/--env 别名取
 *      查找顺序：$QI_GQL_CONFIG → 脚本所在目录 → 当前工作目录
 *      格式：{ "envs": { "env-a": { "host": "graphql.cn-apnorthbj-0.77hub.com", "tid": "<TENANT_ID>" } } }
 *   4. 都没有 → 报错并提示复制 env.example.json 为 env.local.json
 *
 * 用法：
 *   node gql.mjs -e env-a -q '{ Organization(maxResult:10){ id name } }'
 *   node gql.mjs -h graphql.cn-apnorthbj-0.77hub.com -t <TENANT_ID> -q '{ User(maxResult:5){ name } }'
 *   node gql.mjs -e env-a -q '{ Department(maxResult:200){ id name } }' --all -f Department
 *
 * 选项：
 *   -e, --env <name>     环境别名，取自 env.local.json 的 envs 下的键（别名由使用者自定）
 *   -h, --host <host>    集群域名（与 -e 二选一）
 *   -t, --tid <id>       Tenant-Id（与 -e 二选一；不带会静默落到默认库）
 *   -q, --query <gql>    GraphQL 语句
 *   -f, --field <name>   --all 时取哪个根字段（默认自动推断）
 *       --all            自动翻页拉全量
 *       --page-size <n>  每页条数，默认 200
 *       --raw            输出原始 JSON
 *       --jsonl          每行输出一条记录
 *   -F, --fields <type>  查该对象的全部字段（含图片字段），无需写 -q
 *   -E, --entities <type> 查自定义对象字段（走 Entities，服务端 schema 无 Cs* 类型）
 *   -O, --objects        列出全部对象类型
 */

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve as resolvePath } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const EXAMPLE_PATH = join(SCRIPT_DIR, 'env.example.json');

function findConfigPath() {
  const candidates = [];
  if (process.env.QI_GQL_CONFIG) candidates.push(process.env.QI_GQL_CONFIG);
  candidates.push(join(SCRIPT_DIR, 'env.local.json'));
  candidates.push(join(process.cwd(), 'env.local.json'));
  for (const c of candidates) {
    if (c && existsSync(c)) return resolvePath(c);
  }
  return null;
}

function readEnvConfig(path) {
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (e) {
    throw new Error(`读取配置文件 '${path}' 失败：${e.message}`);
  }
  if (!raw.trim()) throw new Error(`配置文件 '${path}' 是空的。请参照 ${EXAMPLE_PATH} 填写。`);
  let obj;
  try {
    obj = JSON.parse(raw);
  } catch (e) {
    throw new Error(`配置文件 '${path}' 不是合法 JSON：${e.message}`);
  }
  const envs = {};
  const src = obj && typeof obj === 'object' ? obj.envs : null;
  if (src && typeof src === 'object') {
    for (const [k, v] of Object.entries(src)) {
      envs[k] = {
        host: v && typeof v === 'object' && v.host ? String(v.host) : '',
        tid: v && typeof v === 'object' && v.tid ? String(v.tid) : '',
      };
    }
  }
  return { path, envs };
}

function noConfigMessage() {
  const target = join(SCRIPT_DIR, 'env.local.json');
  return [
    '未找到配置文件 env.local.json（查找顺序：$QI_GQL_CONFIG → 脚本所在目录 → 当前工作目录）。',
    `请复制 '${EXAMPLE_PATH}' 为 '${target}'，把 host / tid 填成自己的值后重试。`,
    '也可以用 -h/--host、-t/--tid 直接指定，或设置环境变量 QI_GQL_HOST/QI_GQL_TID。',
  ].join('\n');
}

function availableAliases(envs) {
  const names = Object.keys(envs).sort();
  if (!names.length) return '（空，envs 下还没有任何别名）';
  return names.join(' / ');
}

function resolveTarget(opts) {
  let host = opts.host;
  let tid = opts.tid;
  let hostSource = '-h/--host';
  let tidSource = '-t/--tid';

  if (!host && process.env.QI_GQL_HOST) { host = process.env.QI_GQL_HOST; hostSource = '环境变量 QI_GQL_HOST'; }
  if (!tid && process.env.QI_GQL_TID) { tid = process.env.QI_GQL_TID; tidSource = '环境变量 QI_GQL_TID'; }

  if (!host || !tid) {
    const cfgPath = findConfigPath();
    if (!cfgPath) throw new Error(noConfigMessage());
    const cfg = readEnvConfig(cfgPath);

    if (opts.env) {
      const entry = cfg.envs[opts.env];
      if (!entry) {
        throw new Error(
          `未知环境别名 '${opts.env}'。可用别名从 '${cfgPath}' 读取，已配置：${availableAliases(cfg.envs)}。` +
          '别名由使用者自定，可在 env.local.json 的 envs 下增删。'
        );
      }
      if (!host && entry.host) { host = entry.host; hostSource = `env.local.json[${opts.env}].host`; }
      if (!tid && entry.tid) { tid = entry.tid; tidSource = `env.local.json[${opts.env}].tid`; }
      if (!host) throw new Error(`env.local.json 里别名 '${opts.env}' 缺少 host（${cfgPath}）。示例见 ${EXAMPLE_PATH}。`);
      if (!tid) throw new Error(`env.local.json 里别名 '${opts.env}' 缺少 tid（${cfgPath}）。示例见 ${EXAMPLE_PATH}。`);
    } else {
      throw new Error(
        `没有指定 -e/--env，也没有 -h/--host、-t/--tid 或 QI_GQL_HOST/QI_GQL_TID。` +
        `已在 '${cfgPath}' 找到配置，可用别名：${availableAliases(cfg.envs)}。例如：-e env-a`
      );
    }
  }

  if (/^<.+>$/.test(tid)) {
    throw new Error(`Tenant-Id 还是占位符 '${tid}'，请把它换成真实 Tenant-Id（来源：${tidSource}）。`);
  }
  if (/^<.+>$/.test(host)) {
    throw new Error(`集群域名还是占位符 '${host}'，请把它换成真实集群域名（来源：${hostSource}）。`);
  }

  return { host, tid, hostSource, tidSource };
}

function parseArgs(argv) {
  const out = { all: false, raw: false, jsonl: false, pageSize: 200 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case '-e': case '--env': out.env = next(); break;
      case '-h': case '--host': out.host = next(); break;
      case '-t': case '--tid': out.tid = next(); break;
      case '-q': case '--query': out.query = next(); break;
      case '-f': case '--field': out.field = next(); break;
      case '-F': case '--fields': out.fields = next(); break;
      case '-E': case '--entities': out.entities = next(); break;
      case '-O': case '--objects': out.objects = true; break;
      case '--page-size': out.pageSize = parseInt(next(), 10); break;
      case '--all': out.all = true; break;
      case '--raw': out.raw = true; break;
      case '--jsonl': out.jsonl = true; break;
      case '--help': case '-?': out.help = true; break;
      default: throw new Error(`未知参数: ${a}`);
    }
  }
  return out;
}

async function gql(uri, tid, query) {
  let res;
  try {
    res = await fetch(uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Tenant-Id': tid },
      body: JSON.stringify({ query, variables: null, operationName: null }),
      // 连接层超时由 undici 自己负责（约 10s 报 UND_ERR_CONNECT_TIMEOUT），
      // 这里只兜住「连上了但服务端不回」的情况，故放宽到 60s，避免大页被误截断。
      signal: AbortSignal.timeout(60000),
    });
  } catch (e) {
    const cause = e?.cause?.code || e?.name || e?.message || String(e);
    if (/TIMEOUT|ETIMEDOUT|UND_ERR_CONNECT_TIMEOUT|AbortError/i.test(String(cause))) {
      throw new Error(
        `连接 ${uri} 超时（${cause}）：该集群是 10.x 私网地址，需先连公司 VPN，连上后重试；不要改 Tenant-Id 或换集群。见 references/troubleshooting.md「请求超时」`
      );
    }
    throw new Error(`请求 ${uri} 失败（${cause}）：若为内网不可达请确认 VPN。见 references/troubleshooting.md`);
  }
  const text = await res.text();
  if (res.status === 400) {
    throw new Error(`HTTP 400（空响应体）：租户 '${tid}' 在集群 '${uri}' 不存在。请换集群域名重试。`);
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
  let obj;
  try { obj = JSON.parse(text); }
  catch { throw new Error(`响应不是合法 JSON：${text.slice(0, 300)}`); }
  if (obj.errors && obj.errors.length) {
    const msg = obj.errors[0].message;
    if (/Schema is not configured for mutations/.test(msg)) {
      throw new Error('本接口只读，不支持 mutation。写入请走 qiqi 或平台脚本。');
    }
    const m = msg.match(/invalid field '([^']+)' \(([^)]+) in metadata\)/);
    if (m) throw new Error(`criteriaStr 列名错误：'${m[1]}' 应为 '${m[2]}'`);
    throw new Error(`GraphQL 错误：${msg}`);
  }
  return obj.data;
}

function printRows(rows, opts) {
  if (opts.raw) { console.log(JSON.stringify(rows, null, 2)); return; }
  if (opts.jsonl) { for (const r of rows) console.log(JSON.stringify(r)); return; }
  console.log(JSON.stringify(rows, null, 2));
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help || (!opts.query && !opts.fields && !opts.entities && !opts.objects)) {
    const src = readFileSync(fileURLToPath(import.meta.url), 'utf8');
    console.log(src.split('*/')[0].replace(/^\/\*\*?/, ''));
    process.exit(opts.help ? 0 : 1);
  }

  const target = resolveTarget(opts);
  opts.host = target.host;
  opts.tid = target.tid;

  const uri = /^https?:\/\//.test(opts.host)
    ? `${opts.host.replace(/\/$/, '')}/graphql`
    : `http://${opts.host}/graphql`;

  // ---- 元数据模式 ----
  if (opts.fields) {
    const esc = opts.fields.replace(/'/g, "''");
    opts.query = `{ ObjectField(criteriaStr: "objectType = '${esc}'", maxResult: ${opts.pageSize}) { name title type bizType isEnum enumType isRequired isCustomizedField isDisabled length } }`;
    opts.all = true;
    opts.field = 'ObjectField';
  } else if (opts.entities) {
    // 自定义对象走 Entities（服务端 schema 里没有 Cs* 类型）
    const esc = opts.entities.replace(/'/g, "''").replace(/"/g, '\\"');
    const data = await gql(uri, opts.tid,
      `{ Entities(names: ["${esc}"]) { name title type isCustomizedEntity fields { name title type apiName bizType enumType isCustomizedField isRequired } } }`);
    const ent = data.Entities || [];
    if (!ent.length) throw new Error(`未找到对象 '${opts.entities}'（检查对象名，或该租户下不存在）`);
    if (opts.raw) { console.log(JSON.stringify(ent[0], null, 2)); return; }
    return printRows(ent[0].fields || [], opts);
  } else if (opts.objects) {
    opts.query = `{ ObjectType(maxResult: ${opts.pageSize}) { name title type appName isCustomizedEntity isDisabled } }`;
    opts.all = true;
    opts.field = 'ObjectType';
  }

  if (!opts.query) throw new Error('必须指定 -q/--query、-F/--fields、-E/--entities 或 -O/--objects');

  if (!opts.all) {
    const data = await gql(uri, opts.tid, opts.query);
    if (opts.raw) { console.log(JSON.stringify(data, null, 2)); return; }
    const keys = Object.keys(data || {});
    if (keys.length === 1) return printRows(data[keys[0]], opts);
    console.log(JSON.stringify(data, null, 2));
    return;
  }

  // ---- 自动翻页 ----
  let template = opts.query;
  let field = opts.field;
  if (!field) {
    const probe = await gql(uri, opts.tid, template);
    const keys = Object.keys(probe || {});
    if (keys.length !== 1) throw new Error(`查询有 ${keys.length} 个根字段，请用 -f 指定一个`);
    field = keys[0];
  }
  if (!/maxResult/.test(template)) {
    throw new Error('--all 需要查询里包含 maxResult，例如 { Department(maxResult: 200){ id name } }');
  }
  if (!/firstResult/.test(template)) {
    template = template.replace(/maxResult\s*:\s*\d+/, `firstResult: {OFFSET}, maxResult: ${opts.pageSize}`);
  } else {
    template = template
      .replace(/firstResult\s*:\s*\d+/, 'firstResult: {OFFSET}')
      .replace(/maxResult\s*:\s*\d+/, `maxResult: ${opts.pageSize}`);
  }

  const all = [];
  let offset = 0;
  for (let page = 0; page < 500; page++) {
    const q = template.replace('{OFFSET}', String(offset));
    const data = await gql(uri, opts.tid, q);
    const rows = data[field] || [];
    all.push(...rows);
    if (rows.length < opts.pageSize) break;
    offset += opts.pageSize;
  }
  process.stderr.write(`拉到 ${all.length} 条（接口无 total，按页累加）\n`);
  printRows(all, opts);
}

main().catch((e) => {
  console.error('错误: ' + e.message);
  process.exit(1);
});
