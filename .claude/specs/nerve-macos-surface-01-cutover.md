---
status: code-complete
slug: nerve-macos-surface-01-cutover
depends: nerve-hub
revised: 2026-08-22
---

# nerve-macos-surface-01-cutover — 一刀切:app 数据源切换到 hub

## Summary

macOS app 一刀切改造的第一段:**原子切换数据源**。删除进程内 `IngestServer` 与 `JobStore` 全部状态语义,
新增 `Services/Hub/{NerveEndpoint, HubFrame, FrameDiffer, HubClient}`;`JobStore` 降级为 SSE 帧喂养的
只读 client cache(`@Observable` 观测面零改动);通知改由相邻帧 diff 产出的 `(previous, next)` 对驱动,
`NotificationService` 本体零改动。**不保留 Swift fallback server** —— 语义两份实现必然 drift(与「禁双写」同源)。

本段结束时的形态:app 需要手动 `nerve-hub serve` 先起(dev 模式)——自动 spawn 与 bundle 内嵌在
`nerve-macos-surface-02-launch`,端口旋钮与文档清理在 `-03-settings-docs`。

## Domain basis

前置裁决(视为既定):拓扑 C(独立 hub、`127.0.0.1:17890` 固定端口即单实例锁、SSE refcount + 30s grace)/
一刀切无 fallback、禁双写 / 通知只由 macOS surface 发 / `ensureLocalActions` 的 NSWorkspace 语义留 Swift /
pending 子系统休眠(invariant 6 display-only 不变)。

hub 契约(`nerve-hub` spec 已定):`GET /v1/stream` SSE 全量帧 `{"jobs":[…],"departed":[…]}`,
`departed` 为自上帧被驱逐 job 的**终态**;帧内 job 内嵌 hub 维护的 `timeline`(≤40 条)——
**timelines 归属已裁决**:随帧接收、只读缓存,surface 不自行追加。
读写端点:`GET /v1/jobs`、`POST /v1/clear`、`POST /v1/demo`、`POST /v1/actions/result`、`GET /v1/health`。

仓库不变量(CLAUDE.md)全部保持;仓库今日**零 Swift 测试**(`Nerve.xcodeproj` 仅 1 个 app target,
无 XCTest / swift-testing)——本 spec 自带最小 swiftc harness,不新建正式 test target。

## Design

### 数据流(改造后)

```text
hooks ──HTTP──▶ nerve-hub(状态权威:apply/commit/evict/reap/retention)
                    │  SSE 全量帧 {jobs, departed}
                    ▼
            HubClient(解析 → FrameDiffer → (previous,next))
                    ├──▶ JobStore(client cache:jobs/timelines/pendingActions/revision)
                    └──▶ NotificationService.evaluate(previous:next:)   ← 本体零改动
```

### 新增单元(`Nerve/Nerve/Services/Hub/`,先例 `Services/MachineTunnelManager.swift`)

- `NerveEndpoint` —— 值类型常量:host `127.0.0.1`、port `17890`、各路径拼接。(Settings 旋钮的移除在 -03;本段先供 `HubClient` 使用。)
- `HubFrame` —— `Decodable` 值类型(单向消费,无编码回程):`jobs: [Job]`、`departed: [Job]`、`timelines: [String: [TimelineEntry]]`(从帧内 job 内嵌 `timeline` 键提取 —— `Job` 的 Codable 会丢弃未知键,故 decode 时显式提升);未知字段容错、缺字段按空数组。**无副作用、无 Foundation 以外依赖**。
- `FrameDiffer` —— 纯 struct(非 `@MainActor`、无网络):持上一帧 `[String: Job]`,
  `func pairs(for frame: HubFrame) -> [(previous: Job?, next: Job)]`。规则:
  (1) 帧内 job 逐条与上帧同 id 配对,新 job 的 `previous = nil`;
  (2) **`departed` 逐条以 `(previous = 上帧该 job, next = departed 终态)` 产出** ——
  这是 `notifyLongSuccess`(`NotificationService.swift:137-151`,依赖 `lifecycle == .ended` + `startedAt/createdAt`)
  与 sticky banner 清除(`:154-161`)唯一的触发来源,漏掉即静默回归;
  (3) 无变化的 job 不产出对(等价旧 `commit` 只在写入时触发)。**本段唯一带单测的纯逻辑单元。**
- `HubClient` —— `@MainActor` final class:`URLSession` 消费 `GET /v1/stream?surface=macos`,
  逐帧解析 → `FrameDiffer` → 依次 (a) 用帧覆盖 `JobStore` cache,(b) 对每个 pair 调 `notificationSink`;
  断线指数退避重连(1s→30s 上限);`clearAll()` / `loadDemo()` / `postActionResult()` 走
  `POST /v1/clear|/v1/demo|/v1/actions/result`。

单元边界(高内聚低耦合、无 factory function、无 god context):`HubFrame`/`FrameDiffer` 纯值、可脱离 app 编译;
`HubClient` 通过既有 `notificationSink` 闭包(`AppModel.swift:45-47` 已有接线形状)出栈,不反向持有 UI。

### JobStore 降级(`Store/SubjectStore.swift` —— 文件名/类名漂移是遗留,勿模仿)

- **保留**(观测面不变,消费侧 `@Environment(JobStore.self)` 零改动:`AppModel.swift:8`、`StatusPanelView.swift:21`):
  `@Observable`、`private(set) var jobs/timelines/pendingActions`(`:21-23`)、`revision`(`:41`)、
  `panelOpen/selectedJobId/focusedListIndex`、展示派生 `statusSections`(`:176`)、`sortComparator`(`:257`)、
  `ribbonSegments`(`:293`)、`performAction`(`:871`)、`focusAndOpenJob`(`:1107`)、
  `ensureLocalActions`(`:552`,改为**收帧后在 client 侧逐 job 应用**)。
- **删除**(语义已在 hub):`apply(envelope:)`(`:407`)、`apply(event:)`(`:433`)、`applySnapshot`、
  `commit`(`:690`)、`evictEnded`(`:699`)、事件去重(`seenEventIds`)、PID reap、
  pending 维护与过期(`:948-:1017`)、`runMaintenanceTick`(`:1021`)、`purgeAllLegacyChildJobs`(`:749`)、
  `loadDemo`(`:1039`)本体、`clearAll`(`:1029`)本体 —— 后两者改为 `HubClient` 打 hub 端点。
- **新增**:`func applyFrame(…)` —— 整帧覆盖(jobs / 帧内 timeline / pending)+ `bumpRevision()`;
  `notificationSink` 由 `HubClient` 直接驱动(store 不再自己判断何时通知)。

### 接线点改动

- `AppModel.swift:53-59`(IngestServer 构造 + start)→ `HubClient.connect()`(本段无 spawn);
  `:156`(`ingest?.stop()`)→ `hubClient.disconnect()`(**不杀 hub**);`:62`(`purgeAllLegacyChildJobs`)删除;
  `:67-71`(5s expireTimer)删除(语义入 hub);`:45-47` `notificationSink` 接线保留原形;
  `:76-83`(coach demo)→ `HubClient.loadDemo()`。
- `StatusPanelView.swift:265`(`runMaintenanceTick`)删除;`:352`(`store.clearAll()`)→ `HubClient.clearAll()`
  (否则本地清了、下一帧原样回填,**可见 bug**)。
- `Nerve/Nerve/Ingest/` 整目录删除 + `project.pbxproj` 引用清理(`:7`、`:32`、`:61`、`:88`),
  加入 `Services/Hub/*.swift`。

### Reuse decision

| 候选 | 裁决 | 依据 |
|---|---|---|
| `NotificationService.evaluate(previous:next:)`(`:46`) | **reuse**(零改动) | 已是纯 `(previous,next)→副作用`;只换调用方为 `FrameDiffer`。`lastFire` dedupe(`:13`)留本 surface |
| `JobStore` 观测面(`:21-23`,`:41`) | **reuse** | 保持 `@Observable` 契约,UI 零改动;仅换数据源 |
| 展示派生 `:176`/`:257`/`:293`/`:871`/`:1107` | **reuse** | 纯展示与本地动作,与状态权威无关 |
| `ensureLocalActions` `:552` | **reuse**(迁调用点) | NSWorkspace 语义留 Swift;hub 只存原始 actions,收帧后 client 侧应用 |
| `IngestServer.swift`(整目录) | **delete** | 禁双写:ingest + 语义唯一实现在 hub |
| `JobStore` 语义块(`:406`–`:1020`) | **delete** | 同上 |
| `HubFrame`/`FrameDiffer`/`HubClient`/`NerveEndpoint` | **new** | 仓库无 SSE 消费者、无帧配对逻辑,无可复用件 |

## Files

- `Nerve/Nerve/Services/Hub/NerveEndpoint.swift`(new)
- `Nerve/Nerve/Services/Hub/HubFrame.swift`(new)
- `Nerve/Nerve/Services/Hub/FrameDiffer.swift`(new)
- `Nerve/Nerve/Services/Hub/HubClient.swift`(new)
- `Nerve/Tests/FrameDifferTests.swift`(new,**不加入 app target**)
- `scripts/test_swift_units.sh`(new,swiftc harness)
- `Nerve/Nerve/Ingest/IngestServer.swift` — **删除(整目录)**
- `Nerve/Nerve.xcodeproj/project.pbxproj` — 删 IngestServer 引用,加 `Services/Hub/*.swift`
- `Nerve/Nerve/App/AppModel.swift`
- `Nerve/Nerve/Store/SubjectStore.swift`
- `Nerve/Nerve/UI/Panel/StatusPanelView.swift`

## Tasks

- [x] **T1** Write failing unit harness `scripts/test_swift_units.sh` + `Nerve/Tests/FrameDifferTests.swift`(swiftc 编译 Models/*.swift + Hub 纯值文件;覆盖 departed 配对、新 job previous=nil、无变化不产对、帧解码容错)。
- [x] **T2** Implement `NerveEndpoint` + `HubFrame` + `FrameDiffer` in `Nerve/Nerve/Services/Hub/` until T1 harness green.
- [x] **T3** Reduce `JobStore` to a frame-fed cache in `Nerve/Nerve/Store/SubjectStore.swift`(删语义块,加 `applyFrame`,保留展示派生与 `ensureLocalActions`)。
- [x] **T4** Remove `Nerve/Nerve/Ingest/` and its `project.pbxproj` references; add `Services/Hub/*.swift` to the target.
- [x] **T5** Implement `HubClient`(SSE 消费、退避重连、帧→cache、pair→`notificationSink`、clear/demo/action-result 端点)。
- [x] **Hygiene** `/mol:simplify` ran clean — dead dismiss branch + orphan Event.swift + stale comment refs; gates green (harness 11/11, xcodebuild, hook)
- [x] **T6** Rewire `AppModel.swift` and `StatusPanelView.swift` to `HubClient`; run build + hook tests + unit harness.

## Testing

**Unit(`scripts/test_swift_units.sh`)**:FrameDiffer 四场景(变化对 / 新 job previous=nil / departed 真 previous /
静默帧 0 对)+ `HubFrame` 容错解码(缺 `departed`、未知字段、空数组)。

**Manual(dev 模式,hub 手动起)**:`nerve-hub serve` → `./scripts/run.sh` 起 app → `./scripts/inject_demo.sh` →
面板/ribbon 显示;面板 Clear → hub 清空且不回填;通知三场景(attention 升级、failure 终态、long_success 终态)——
后两条走 departed 路径;attention 解除后 sticky banner 清除。

**Review**:`rg -n "IngestServer|NWListener" Nerve/` 无命中;`git diff` 对 `NotificationService.swift` 为空。

**回归**:`python3 sources/agents/tests/test_nerve_hook.py` 零改动 green;xcodebuild 零 error。

## Out of scope

- hub 自动 spawn、二进制发现、bundle 内嵌 → `nerve-macos-surface-02-launch`。
- `settings.ingestPort` 移除、公开文档、完整回归矩阵 → `nerve-macos-surface-03-settings-docs`。
- hub 本体(`nerve-hub`)、tmux surface、tmux focus/identity(bridge 已删,待新 spec)。
- 正式 XCTest target 与覆盖率工程(swiftc harness 即最小基座)。
