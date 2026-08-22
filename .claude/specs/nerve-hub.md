---
status: code-complete
slug: nerve-hub
revised: 2026-08-22
---

# nerve-hub — 跨平台状态 hub daemon(Rust · 端口即锁 · SSE refcount 生命周期)

## Summary

**Agent hooks own semantic state. Surfaces are pure frontends.** 本 spec 把今天嵌在 macOS app 里的
ingest + 状态机抽成独立的跨平台 daemon `nerve-hub`(Rust / axum + tokio),之后 macOS GUI 与 tmux 插件
降级为对等 surface(各自独立 spec)。hub 生命周期由 surface 引用计数决定:bind
`127.0.0.1:17890` 即单实例锁(端口固定,与 hook 硬编码 `INGEST_BASE` 对齐,`nerve_hook.py:77`);
一条 SSE 订阅即一个 surface 在场证明;最后一条订阅断开后 grace(默认 30s)自退,**从未有订阅者时同样计时**
(spawn 后 30s 无人连即退)。producer 永不 spawn hub。CLI 只有 `nerve-hub serve [--grace-secs N]`,前台运行,正常退出码 0。

本 spec **不碰任何 Swift 文件**:app 继续跑内嵌 server,切换在后继 spec 链 `nerve-macos-surface-*` 完成;
hub 先靠 golden 契约测试自证与现行为等价。hook 契约零改动——`test_nerve_hook.py` 保持 green 就是证明。

## Domain basis

### 已裁决决策(本 spec 的前提,不在此重开)

| # | 决策 |
|---|------|
| D1 | 拓扑 = C:独立 hub + surface refcount(非 GUI 内嵌、非 per-surface 副本) |
| D2 | 禁双写:同一时刻只有一个进程持有状态,端口 bind 即互斥 |
| D3 | SSE 连接即 refcount;30s grace;producer POST **不**续命 |
| D4 | 全量帧,无 delta 协议;断线重连 = 免费 resync |
| D5 | 本机 alias 复刻 `LocalMachine.alias` 规则(`MachineConfig.swift:92`) |
| D6 | pending 子系统整体搬迁但**休眠**(列表恒空,契约仍正确) |
| D7 | 分发:macOS bundle 内嵌(后继 spec)+ cargo/brew |
| D8 | app 一刀切(不做双栈过渡),由 `nerve-macos-surface-*` 链落实 |
| D9 | spec 切分:hub 前置,macOS 链与 tmux surface 平行 |
| D10 | 根 virtual workspace + `crates/`;未来 Rust crate 同 workspace |
| D11 | 运行时 = axum + tokio |

### 不可破坏的产品不变量(CLAUDE.md)

一 conversation 一 job(`{producer}:{session_id}`)/ fail-open hook / 状态只来自结构化字段 /
运行时状态仅内存 / **开放 alias ingest(无 allow-list)** / display-only(hub 不反控 agent)。

### 移植的事实源(逐条对照实现)

`Nerve/Nerve/Ingest/IngestServer.swift`(路由 `:166`、loopback 守卫 `:129`、alias 归一 `:263`、
envelope 三形态 `:295`/单形态 `:309`)与 `Nerve/Nerve/Store/SubjectStore.swift`
(`apply(envelope:)` `:406`、`apply(event:)` `:432`、`applySnapshot` `:520`、`applyPatch` `:782`、
`commit` `:690`、`evictEnded` `:699`、`endJobLocally` `:604`、`reapDeadLocalProducers` `:641`、
`producerPID`/`processIsAlive` `:668`/`:682`、legacy child 卫生 `:720`/`:730`/`:749`
(判定源 `Subject.swift:127`)、`rememberEventId` `:856`、timeline `:836`、pending `:934`/`:973`/`:1000`、
maintenance tick `:1021`、`loadDemo` `:1039`)。

## Design

### 模块划分(高内聚 / 低耦合;每个模块可用 fake 单测)

```text
crates/nerve-hub/src
├── main.rs      bin 入口:解析 CLI → 组装 → run
├── cli.rs       serve [--grace-secs N];退出码契约
├── lib.rs       组装点(store + router + broadcaster + lifecycle),不放业务
├── clock.rs     Clock trait(SystemClock / FakeClock)
├── model/       job.rs(含 legacy-noise 谓词)· event.rs · envelope.rs(三形态解码)· time.rs(ISO8601 秒精度)
├── state/       store.rs · patch.rs · dedupe.rs · timeline.rs · pending.rs · reaper.rs · machine.rs · demo.rs
├── http/        routes.rs · ingest.rs · actions.rs · admin.rs · guard.rs
├── sse/         frame.rs · broadcaster.rs
└── lifecycle/   refcount.rs · grace.rs
```

`JobStore` 是唯一写入点(`commit` 语义),对外暴露原语方法(apply_snapshot / apply_event / evict /
expire_pending / reap),不做展示派生;HTTP handler 只做解码 → 调 store → `(StatusCode, Json)`,不 panic。
无 factory 函数、无 god context:`Clock` 与 `PidProbe` 是注入的 trait,测试用 fake 驱动时间与进程存活。

### HTTP 契约(保真复刻 + 一个新端点)

| 方法 · 路径 | 响应 | 备注 |
|---|---|---|
| `GET /v1/health`(alias `GET /health`) | `{"ok":true,"service":"nerve","version":"0.1.0"}` | 字面量保持 |
| `GET /v1/jobs`(alias `GET /v1/subjects`) | **裸 JSON 数组** | 非 object 包裹;每个 job **内嵌 hub 维护的 `timeline`(≤40 条)**,见「刻意分歧」 |
| `GET /v1/stream` | SSE 全量帧 | **新增**(`/v1/events` 已被 POST 占用,故不同路径) |
| `POST /v1/snapshot` | `{"applied":N}` | body **仅** envelope `{alias, machineKind?, jobs:[…]}` |
| `POST /v1/events` | `{"applied":N}` | 三形态解码但 alias 载体只有 envelope:裸数组 → 400 alias required;单 event 被空 envelope 吞掉 → `applied:0`(退化行为,保真保留) |
| `GET /v1/actions/pending` | 裸数组 | query `producerId` 或 legacy `sourceId`;先 expire 再过滤 |
| `POST /v1/actions/result` | `{"ok":true}` / 404 | 未命中 → `{"error":"pending action not found or producer mismatch"}` |
| `POST /v1/demo` | `{"ok":true,"demo":true}` | 注入 4 条硬编码 demo job(`SubjectStore.swift:1039`) |
| `POST /v1/clear` | `{"ok":true}` | 清空 jobs / timelines / pending / seen-ids |
| `POST /v1/actions/invoke` | **404** | 刻意不移植:副作用依赖 NSWorkspace,属 surface 能力 |

横切:非 loopback → 403 `{"error":"loopback only"}`;body > 1MB → 413 `{"error":"too large"}`;
解码失败 → 400(错误正文不稳定,golden 不断言内容);响应带 `Access-Control-Allow-Origin: *`。

**alias 两段式填充(顺序不可反)**:① envelope 级(`IngestServer.swift:263`)——envelope.alias 缺失时从首个
非空 `job.alias` 借,再回填空 job.alias;非空即合法(**无 allow-list**),全空 → 400 `{"error":"alias required"}`。
② job 级(`SubjectStore.swift:414`)——仍为空则填本机 alias。
序列化:日期 ISO8601 秒精度无小数(对齐 `nerve_hook.py:103`);`version` 为 u64 毫秒时间戳(`nerve_hook.py:107`);
`machineKind` 透传存储、**无语义**(现 Swift 全程未读)。

### SSE 帧(`GET /v1/stream`)

连接建立即推一帧;此后状态变更以 ~150ms 窗口 coalesce。帧 = `{"jobs":[…全量…],"departed":[…]}`。
`departed` 是自上一帧以来被驱逐 job 的**终态**——现行为是 SessionEnd 立即驱逐(`SubjectStore.swift:699`,
通知在移除前触发),纯相邻帧 diff 会丢终态,`departed` 保证 surface 无损。窗口内同 id 只保留最后一次终态;
**`jobs` 是权威全集,`departed` 仅供终态提示**。帧内 job(含 departed)与 `GET /v1/jobs` 同 shape,
内嵌 `timeline`。无 delta、无其他事件类型;`?surface=<label>` 仅作日志标识。

### 生命周期

订阅数 0→1 取消 grace 定时器;1→0(以及进程启动时刻)启动 `--grace-secs`(默认 30,`0` = 立即)定时器,
到期 graceful shutdown 退出码 0。bind 冲突 = 已有 hub 在服务 → stderr 一行提示 + 退出码 0
(surface 可 spawn-and-forget;后置条件"17890 上有 hub"成立)。真实故障退出码 1。
**不提供 `--port`**:端口是锁且被 hook 硬编码;集成测试改为在 `127.0.0.1:0` 上直接装配 router/broadcaster,
不经 `serve`,从而与正在运行的 Nerve.app 互不冲突。
冷启动代价(已接受):hub 因 grace 退出后重启,jobs 为空直到下一次 hook 事件——状态本就是内存态;
surface 端的等待/离线占位由各 surface spec 处理。

### 与 Swift 的刻意分歧(必须在文档写明)

- `ensureLocalActions`(`:552`)不移植,hub 原样回显 producer 声明的 actions;Open/Copy 等展示动作由 surface 派生。
- ribbon 几何(`:293`–`:395`)、展示派生(`:176`–`:257`)同理,留在 surface。
- slot supersede 不在服务端——真实现在 hook 侧(`nerve_hook.py:1215`),原样保留。
- pending 入队侧(`enqueueRemote` `:934`)不复活。
- **`timeline` 内嵌进 job 的 HTTP 序列化**:旧实现 timeline 只存在于 app 进程内存、不经 HTTP 暴露;
  surfaces 现在需要它,属刻意契约新增(hub 维护,每 job ≤40 条,heartbeat 不入)。

### Reuse decision

| 候选 | 决策 | 说明 |
|---|---|---|
| `IngestServer` 路由 / 守卫 / 归一 | **reuse(语义移植)** | 逐条对照行号复刻,跨语言故非代码复用;分歧只有 invoke、actions 派生与 timeline 内嵌 |
| `JobStore` 状态机 + `init(clock:)` `:50` | **reuse(语义移植 + 模式)** | 注入时钟模式照搬,保证测试确定性 |
| `Subject.isLegacyChildNoise` `:127` | **reuse** | 谓词规则原样移植到 `model/job.rs` |
| `LocalMachine.alias` `MachineConfig.swift:92` | **reuse** | scutil LocalHostName → 短 hostname → sanitize,进程内缓存一次 |
| `fixtures/demo_snapshot.json`(孤儿文件) | **generalize** | 征用为 golden 输入;`inject_demo.sh` 改 POST 它 |
| `scripts/verify_loop.sh` | **generalize** | `NERVE_PORT` 已参数化,可指向 hub;修僵尸断言(见 Testing) |
| `nerve_hook.py` 契约 | **reuse untouched** | 零改动;证明 = hook 测试保持 green |
| `POST /v1/actions/invoke` `:232` | **out of scope(dropped)** | NSWorkspace 副作用属 surface |
| `ensureLocalActions` / ribbon / 展示派生 | **out of scope** | surface 能力 |
| pending `enqueueRemote` `:934` | **dormant port** | 移植为休眠基础设施,不复活入队 |
| 未来 Rust crates(`nerve-tmux-surface` 等) | **pattern** | 同入根 workspace,`members` 随各自 spec 落地追加 |

## Files

| 路径 | 变更 |
|---|---|
| `Cargo.toml` | **(new)** 根 virtual workspace,`members = ["crates/nerve-hub"]`,共享 lint/profile |
| `crates/nerve-hub/Cargo.toml` | **(new)** bin `nerve-hub`;axum / tokio / serde / serde_json / time |
| `crates/nerve-hub/src/main.rs` · `cli.rs` · `lib.rs` · `clock.rs` | **(new)** 入口、CLI + 退出码、组装点、Clock trait |
| `crates/nerve-hub/src/model/job.rs` · `event.rs` · `envelope.rs` · `time.rs` | **(new)** 类型 + legacy-noise 谓词 + 三形态解码 + ISO8601 秒精度 serde |
| `crates/nerve-hub/src/state/store.rs` · `patch.rs` · `dedupe.rs` · `timeline.rs` | **(new)** 唯一写入点、event→facet patch、seen-id LRU(4000/批淘汰 500)、每 job 40 条 + heartbeat skip |
| `crates/nerve-hub/src/state/pending.rs` · `reaper.rs` · `machine.rs` · `demo.rs` | **(new)** 上限 200 / TTL 3600s;`PidProbe` + minAge 3s + 仅本机 alias;本机 alias 解析;4 条 demo job |
| `crates/nerve-hub/src/http/routes.rs` · `ingest.rs` · `actions.rs` · `admin.rs` · `guard.rs` | **(new)** Router(含 legacy 别名)、两段式 alias、pending/result、health/jobs/demo/clear、loopback + 1MB + CORS |
| `crates/nerve-hub/src/sse/frame.rs` · `broadcaster.rs` | **(new)** 帧模型 + departed 收集;coalesce 广播 |
| `crates/nerve-hub/src/lifecycle/refcount.rs` · `grace.rs` | **(new)** 订阅计数;grace 定时器与 shutdown |
| `crates/nerve-hub/tests/contract_http.rs` · `sse_stream.rs` · `lifecycle.rs` · `golden_parity.rs` | **(new)** 契约 / 帧 / 生命周期 / golden 集成测试 |
| `scripts/build-rust.sh` | **(new)** `cargo build --workspace --release` |
| `scripts/verify_loop.sh` | 修两处僵尸断言;`NERVE_PORT` 可指向 hub |
| `scripts/inject_demo.sh` | 由 `POST /v1/demo` 改为 POST `fixtures/demo_snapshot.json` |
| `fixtures/demo_snapshot.json` | 升格为 golden 输入(内容不变,不再是孤儿) |
| `index-page/src/docs/content.ts` | `/docs/ingest`(路由表 `:326`–`:334`):新增 `/v1/stream` 帧说明、job 内嵌 timeline、移除 `invoke`、说明契约由 hub 提供、展示动作由 surface 派生 |
| `.claude/specs/nerve-hub.acceptance.md` | 验收契约(随本 spec 落盘) |

## Tasks

- [x] **T1** Add root `Cargo.toml`(virtual workspace)、`crates/nerve-hub` 骨架(bin + `serve [--grace-secs N]` + 依赖)与 `scripts/build-rust.sh`;`cargo test --workspace` 空套件绿。
- [x] **T2** Write failing unit tests for state core — serde(ISO8601 秒精度 / u64 version)、snapshot 版本回退、ended 保留 createdAt/startedAt 锚点补 endedAt、event dedupe、create-on-miss、ended 即驱逐、legacy child 丢弃、timeline 40 上限 + heartbeat skip、pending expire/complete、reaper(fake clock + fake `PidProbe`)。
- [x] **T3** Implement `model/` + `state/` + `clock.rs` — Job/Event/Envelope、`JobStore`(apply / apply_snapshot / apply_patch / commit / evict_ended / end_locally / clear)、dedupe、timeline、pending、reaper、本机 alias、demo 数据。
- [x] **T4** Write failing HTTP contract tests(`tests/contract_http.rs`)— 逐条覆盖路由表:legacy 别名、events 三形态 vs snapshot 单形态、pending `producerId|sourceId`、result 404、invoke 404、loopback 403、>1MB 413、空 alias 400、两段式 alias 填充顺序。
- [x] **T5** Implement `http/` — axum Router 与 handlers、alias 归一、loopback guard、body limit、CORS header;handler 返回 `(StatusCode, Json)`,任何输入都不 panic。
- [x] **T6** Write failing tests for SSE + lifecycle(`tests/sse_stream.rs`、`tests/lifecycle.rs`)— 首帧全量、150ms coalesce、`departed` 终态与去重、重连全量、refcount 归零 → grace 退出、grace 内重连取消退出、`--grace-secs 0` 立退。
- [x] **T7** Implement `sse/` + `lifecycle/` — broadcaster(coalesce + departed 收集)、`GET /v1/stream`(`?surface=` 日志标识)、订阅计数、grace 定时器、bind 即单实例锁与退出码契约。
- [x] **T8** Port golden parity into `tests/golden_parity.rs` — `scripts/verify_loop.sh` 断言逐条移植 + `fixtures/demo_snapshot.json` 回放(硬编码期望字段);同步修 `scripts/verify_loop.sh` 两处僵尸断言,并把 `scripts/inject_demo.sh` 改为 POST 该 fixture。
- [x] **T9** Update `index-page/src/docs/content.ts` — `/docs/ingest` 路由表加 `GET /v1/stream` 与帧 shape、job 内嵌 timeline、移除 `POST /v1/actions/invoke`、写明 hub 提供契约且展示动作由 surface 派生。
- [x] **T10** Run full check + test suite
- [x] **Hygiene** `/mol:simplify` ran clean — cargo fmt ×7 files + clippy doc fix ×3; gates green (fmt-check / clippy -D warnings / 121 tests / npm) — `cargo test --workspace`、`python3 sources/agents/tests/test_nerve_hook.py`、`cd index-page && npm test && npm run build`、`bash scripts/verify_loop.sh`(`NERVE_PORT` 指向 hub,Nerve.app 已退出)。

## Testing

| 层 | 方法 |
|---|---|
| 单元 | `cargo test --workspace`:model/state/http/sse/lifecycle 各模块用 fake clock + fake `PidProbe` 隔离测试 |
| 契约集成 | `tests/contract_http.rs`:在 `127.0.0.1:0` 装配 router,逐条断言路由表(状态码 + 响应 shape) |
| Golden 平移 | `tests/golden_parity.rs`:`verify_loop.sh` 全部断言(health / clear / snapshot `applied:5` / event `applied:1` / 幂等 `applied:0` / 旧 version `applied:0` / attention 升级 / `custom.foo` 透传 / pending 空数组 / result 404) |
| Golden fixture | 同文件:POST `fixtures/demo_snapshot.json`(2 job,alias `local`)后断言 `GET /v1/jobs` 关键字段硬编码值(id / kind / lifecycle / current.type / progress.kind / version / actions 原样回显) |
| 生命周期 | `tests/lifecycle.rs` 自动化 + 手动:spawn → 连 SSE → 断开 → 30s 后进程退出;第二实例 bind 冲突立退 |
| 回归(不变量) | `python3 sources/agents/tests/test_nerve_hook.py` 零改动 green;`git diff` 不含 `Nerve/**` 与 `plugins/**` |
| 站点 | `cd index-page && npm test && npm run build` |

**两处僵尸断言(实现前先确认,T8 一并修正)**:

1. `scripts/verify_loop.sh:74-77` "unknown alias rejected 403|400" —— 与开放 alias 不变量矛盾,现实现返回 200。改为断言 200。
2. `scripts/verify_loop.sh:52-53` `COUNT = 5` —— `a5` 为 `lifecycle:"ended"`,`applySnapshot`(`:530`)立即 `evictEnded`,从不入库,`GET /v1/jobs` 实为 **4**(同脚本 `:64` 的 `active == 4` 才是当前真相)。改为断言 4。

## Out of scope

- **Swift app 改造**(移除内嵌 server、改连 hub、bundle 内嵌二进制)→ spec 链 `nerve-macos-surface-01/02/03`。
- **tmux 插件 surface** → spec `nerve-tmux-surface`(其 helper crate 亦不在本 spec 内)。
- `POST /v1/actions/request` / pending 入队复活 —— 需未来 spec 显式裁决,"display-only"不变量不动。
- `POST /v1/actions/invoke`、`ensureLocalActions`、ribbon 几何、面板展示派生 —— surface 能力。
- slot supersede 服务端化(仍留在 `nerve_hook.py:1215`)、delta / 增量协议、持久化状态。
- brew formula 与发布工程、多机远程 hub / hub 间同步、鉴权(loopback 边界不变)。

## Open questions

无。前版三问已裁决:workspace 路径冲突随 `nerve-tmux-bridge` spec 删除而消失;
`verify_loop` jobs 真值以现行为为准(= 4);冷启动占位属 surface spec。
