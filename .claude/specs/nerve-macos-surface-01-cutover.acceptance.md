---
criteria:
  - { id: A1, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A2, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A3, type: code, status: verified, last_checked: 2026-08-22 }
  - { id: A4, type: review, status: pending }
  - { id: A5, type: review, status: pending }
  - { id: A6, type: review, status: pending }
  - { id: A7, type: manual, status: pending }
  - { id: A8, type: manual, status: pending }
  - { id: A9, type: runtime, status: verified, last_checked: 2026-08-22 }
---

# nerve-macos-surface-01-cutover — Acceptance

Binding contract for `.claude/specs/nerve-macos-surface-01-cutover.md`. All items must pass before spec close.

## A1 — FrameDiffer pairs in-frame changes

**type:** unit

`scripts/test_swift_units.sh` 中:上帧 job `j1(attention=none)` + 本帧 `j1(attention=required)` →
`pairs` 恰返回 1 对且 `previous!.attention.level == .none`、`next.attention.level == .required`;
两帧完全相同时返回 0 对;首帧新 job → `previous == nil`。

## A2 — FrameDiffer emits departed terminal pairs with real previous

**type:** unit

上帧含 active `j2`、本帧 `jobs` 不含 `j2` 且 `departed` 含 `j2(lifecycle=ended, outcome=success)` →
`pairs` 含 `(previous: 上帧 j2, next: 终态 j2)`;断言 `previous != nil`
(否则 `NotificationService.swift:137-151` long_success 与 `:154-161` sticky 清除静默失效)。

## A3 — HubFrame decoding is tolerant

**type:** unit

解码缺 `departed` 键、含未知键、`jobs: []` 三种 payload 均不抛错,缺失数组按空数组处理。

## A4 — No in-app ingest server or second semantic copy remains

**type:** review

`Nerve/Nerve/Ingest/` 不存在;`rg -n "IngestServer|NWListener" Nerve/` 无命中;`project.pbxproj` 无
`IngestServer.swift` 引用;`JobStore` 中不再存在 `apply(envelope:)` / `apply(event:)` / `commit` /
`evictEnded` / `runMaintenanceTick` / `loadDemo` 本体;无任何 fallback 分支在 hub 不可达时接管状态。

## A5 — JobStore observation surface unchanged

**type:** review

`JobStore` 仍为 `@Observable`,仍暴露 `private(set) var jobs/timelines/pendingActions` 与 `revision`;
`AppModel.swift:8` 与 `StatusPanelView.swift:21` 的 `@Environment(JobStore.self)` 消费形状零改动;
`statusSections` / `sortComparator` / `ribbonSegments` / `performAction` / `focusAndOpenJob` /
`ensureLocalActions` 全部保留。

## A6 — NotificationService body untouched

**type:** review

`git diff` 对 `Nerve/Nerve/Services/NotificationService.swift` 为空。新的调用方为 `HubClient`
经 `FrameDiffer` 产出的 pair。

## A7 — Dev-mode panel renders and Clear round-trips through hub

**type:** manual

手动 `nerve-hub serve` → `./scripts/run.sh` → `./scripts/inject_demo.sh`:面板与 ribbon 出现 demo 行,
Open/Focus/Copy 可重复触发不卡死;面板 Clear 后 hub 的 `GET /v1/jobs` 为 `[]` 且面板不被下一帧回填。

## A8 — Notification parity across all three scenarios

**type:** manual

attention 升级(suggested/required)、failure 终态、long_success 终态各触发一次系统通知,内容与改造前一致;
**后两者经 `departed` 帧路径**;attention 降级后 sticky banner 被移除;同一 (job, kind) 120s 内不重复。

## A9 — Build + suites green

**type:** manual

`scripts/test_swift_units.sh` 全绿;`xcodebuild`(经 `./scripts/run.sh`)零 error;
`python3 sources/agents/tests/test_nerve_hook.py` 零改动全绿。
