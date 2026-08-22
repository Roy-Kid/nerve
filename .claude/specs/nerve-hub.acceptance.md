---
criteria:
  - { id: A1, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A2, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A3, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A4, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A5, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A6, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A7, type: runtime, status: verified, last_checked: 2026-08-22 }
  - { id: A8, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A9, type: runtime, status: verified, last_checked: 2026-08-22 }
  - { id: A10, type: runtime, status: verified, last_checked: 2026-08-22 }
  - { id: A11, type: review, status: pending }
  - { id: A12, type: review, status: pending }
---

# nerve-hub — Acceptance

Binding contract for `.claude/specs/nerve-hub.md`. All items must pass before spec close.
Automated items run under `cargo test --workspace`.

## A1 — Route table parity

**type:** unit

对每条路由断言状态码与响应 shape:

- `GET /v1/health` 与 `GET /health` → 200 `{"ok":true,"service":"nerve","version":"0.1.0"}`
- `GET /v1/jobs` 与 `GET /v1/subjects` → 200,**顶层是 JSON 数组**(不是 object)
- `POST /v1/snapshot` / `POST /v1/events` → 200 `{"applied":N}`
- `GET /v1/actions/pending?producerId=t` 与 `?sourceId=t` → 200 `[]`
- `POST /v1/actions/result`(未命中)→ 404 `{"error":"pending action not found or producer mismatch"}`
- `POST /v1/demo` → 200 `{"ok":true,"demo":true}`;`POST /v1/clear` → 200 `{"ok":true}`
- `POST /v1/actions/invoke` → **404**(刻意不移植)
- 所有响应含 `Access-Control-Allow-Origin: *`

## A2 — Envelope 形态不对称保真

**type:** unit

保真到 `IngestServer.swift` **实际**行为(实证修正,`tests/contract_http.rs` 钉死):

- `POST /v1/events`:envelope 形态 → 200 `{"applied":N}`;裸 event 数组可解码但无 alias 载体 → 400 `{"error":"alias required"}`;单 event 对象被全 optional envelope 吞掉 → 200 `{"applied":0}`
- `POST /v1/snapshot`:仅 envelope 生效;裸数组 → 400;单 job 对象含 `alias` 键 → 200 `{"applied":0}`(静默丢弃),无 `alias` 键 → 400 alias required
- `{}` / 空 body → 400 `{"error":"alias required"}`;`{"alias":"x"}` / `{"alias":"x","jobs":[]}` → 200 `{"applied":0}`

## A3 — 两段式 alias 填充

**type:** unit

1. envelope.alias 缺失但某个 job 带 alias → 该 alias 成为 envelope alias,并回填其余空 job.alias
2. 全部为空 → 400 `{"error":"alias required"}`
3. 任意非空 alias(含 `__not_configured__`)→ 200,**无 allow-list**
4. envelope 与 job 都为空但 envelope.alias 存在时,job.alias = envelope.alias;两者皆空的 job(经 events 路径)→ 本机 alias

顺序断言:job 级本机 alias 兜底只在 envelope 级归一之后生效。

## A4 — 状态机语义

**type:** unit

以 fake clock 驱动:

- version 回退的 snapshot 被忽略;event `version < existing.version` → `applied:0`
- 相同 event `id` 重复提交 → `applied:0`(dedupe 上限 4000 / 批淘汰 500)
- 未知 `jobId` 且带 `name` 或 `job.created` → create-on-miss
- `lifecycle:"ended"` 的 snapshot/event → 不入库(`GET /v1/jobs` 不含它),且保留 `createdAt`/`startedAt` 锚点、缺失时补 `endedAt`
- legacy child(`parentJobId` / `paintRibbon:false` / id 含 ≥2 个 `:` / `role:"subagent"`)→ 丢弃且清理父 job 的残留子行
- timeline 每 job ≤ 40 条,`heartbeat` 不入 timeline

## A5 — 守卫

**type:** unit

- 非 loopback 远端 → 403 `{"error":"loopback only"}`(127.0.0.0/8 与 `::1` 放行)
- body > 1MB → 413 `{"error":"too large"}`
- 非法 JSON → 400(仅断言状态码,不断言错误正文)
- 任意畸形输入都不 panic(handler 返回 `(StatusCode, Json)`)

## A6 — SSE 帧契约

**type:** unit

`GET /v1/stream`:

- 连接建立立即收到一帧,`jobs` 为当前全量
- 帧结构恰为 `{"jobs":[…],"departed":[…]}`,无其他键、无 delta 事件类型
- 帧内 job(含 departed)与 `GET /v1/jobs` 同 shape,内嵌 hub 维护的 `timeline` 数组
- ~150ms 窗口内的多次变更合并为一帧
- 某 job 被驱逐(SessionEnd / ended snapshot)后,下一帧 `departed` 含其**终态**(`lifecycle:"ended"` + `endedAt` + `outcome`),且 `jobs` 不再含它;窗口内同 id 只保留最后一次终态
- 断线重连 → 首帧再次为全量(免费 resync)
- `?surface=label` 不改变帧内容

## A7 — 生命周期与单实例

**type:** unit + manual

- 订阅数 1→0 后经过 `--grace-secs`(默认 30)→ 进程退出,退出码 0
- grace 未到期时新订阅接入 → 定时器取消,进程存活
- 启动后从未有订阅者 → 同样在 grace 后退出
- `--grace-secs 0` → 订阅归零立即退出
- producer 的 POST **不**续命(仅 POST 流量时仍按时退出)
- 手动:`nerve-hub serve` 已在跑时再起一个 → 第二实例立即退出、退出码 0、stderr 提示已有 hub;第一实例不受影响

## A8 — Reaper 与本机 alias

**type:** unit

- 注入 fake `PidProbe`:`extensions.pid` 为 number 或 string 均可解析;`pid <= 1` 忽略
- 进程不存在 → job 以 `endReason:"process_gone"` 结束并离场;`EPERM` 视为存活,不结束
- `createdAt` 距今 < 3s 的 job 不被 reap
- 仅 `alias == 本机 alias` 的 job 参与 reap;远程 alias 永不 reap
- 本机 alias 解析:macOS 走 `scutil --get LocalHostName`,否则短 hostname;进程内只解析一次

## A9 — verify_loop 平移 + 僵尸断言修正

**type:** unit + manual

`tests/golden_parity.rs` 复现 `scripts/verify_loop.sh` 全部断言:health / clear /
snapshot `"applied":5` / event `"applied":1` / 幂等 `"applied":0` / 旧 version `"applied":0` /
`a1.attention.level == "urgent"` / `a2.kind == "custom.foo"` / `a1.alias` 非空 /
pending 为数组 / `actions/result` 404。并且:

- `GET /v1/jobs` 长度 = **4**(`a5` 为 ended,立即驱逐),`active` 也 = 4
- 任意 alias 的 snapshot → **200**(不是 403/400)
- `scripts/verify_loop.sh` 中对应的两处断言已同步改为 4 与 200;手动对 hub 跑 `bash scripts/verify_loop.sh` 输出 `ALL OK`

## A10 — Fixture golden 回放

**type:** unit + manual

`POST /v1/snapshot` 提交 `fixtures/demo_snapshot.json` 后 `GET /v1/jobs` 断言硬编码值:

- 2 条 job:`demo-agent-1`(`kind:"session"`,`current.type:"editing"`,`version:3`,`actions` 为 `open`+`copy` **原样回显**)与 `demo-build-1`(`kind:"build"`,`progress.kind:"indeterminate"`,`version:2`,`actions` 仍为 `[]` —— hub 不派生展示动作)
- 两条 `alias` 均为 `"local"`(fixture 自带,不被本机 alias 覆盖)
- 日期字段回读为秒精度、无小数、以 `Z` 结尾
- 手动:`bash scripts/inject_demo.sh` 对 hub 运行成功,且其 POST 的是该 fixture(不再是 `/v1/demo`)

## A11 — 零 Swift / 零 hook 改动

**type:** review + unit

- 本 spec 的 diff 不含 `Nerve/**`、`plugins/**`、`sources/agents/**` 任何文件
- `python3 sources/agents/tests/test_nerve_hook.py` 保持 green
- hub 端口固定 `127.0.0.1:17890`,未引入任何 `NERVE_*` 运行时开关,未新增 `--port` 标志

## A12 — Docs

**type:** review

`index-page/src/docs/content.ts` 的 `/docs/ingest`:

- 路由表新增 `GET /v1/stream`,含帧 shape `{"jobs":[…],"departed":[…]}`、job 内嵌 `timeline` 与"重连即全量"说明
- 移除 `POST /v1/actions/invoke` 行,并说明其为 surface 能力、hub 返回 404
- 写明契约由 `nerve-hub` 提供、展示动作(Open/Copy)由 surface 派生、alias 无 allow-list 不变
