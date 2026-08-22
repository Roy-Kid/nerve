---
status: approved
slug: nerve-macos-surface-02-launch
depends: nerve-macos-surface-01-cutover
revised: 2026-08-22
---

# nerve-macos-surface-02-launch — hub 自动拉起与 bundle 内嵌

## Summary

macOS 一刀切改造的第二段:让「装了 app = hub 一定在」。新增 `HubProcessManager`
(二进制发现序列、health 探测、bind 冲突直连、崩溃重连),`nerve-hub` 经
`scripts/build-rust.sh` + `scripts/run.sh` 打进 `Nerve.app/Contents/MacOS/`。
本段结束后 -01 的「手动 `nerve-hub serve`」dev 模式不再必要。

## Domain basis

前置(既定):hub `serve` 在 bind 冲突时立即退出、退出码 0(spawn-and-forget 安全);
SSE refcount + 30s grace 由 hub 自理;**app 退出不杀 hub**(可能还有 tmux surface 在场);
producer 永不 spawn hub —— spawn 责任只在 surface。
分发三渠道:bundle 内嵌(本段)+ `cargo install` + brew(发布工程 out of scope)。

## Design

### HubProcessManager(`Nerve/Nerve/Services/Hub/HubProcessManager.swift`)

- **发现序列**:`Bundle.main`(`Contents/MacOS/` 优先,次 Resources)→ `/opt/homebrew/bin` →
  `/usr/local/bin` → `~/.cargo/bin` → PATH。
- **启动决策**:先探 `GET /v1/health` —— 已有 hub 则**直接连、不 spawn**;探测失败才 spawn
  `nerve-hub serve`(`Process` + arg-array,极简继承 env,永不走 shell 拼串)。
- **韧性**:`HubClient` 断连触发一次重探 + 必要时重 spawn(节流:10s 窗口内至多一次);
  app 退出仅 `disconnect()`,不向 hub 发任何终止信号。
- **模式先例**:`Services/MachineTunnelManager.swift`(407 行 Process spawn + 状态机)——
  沿用其 arg-array `Process`、重试/状态形状与命名;**不 generalize**(ssh 语义与 hub 语义无共享内核,
  强抽会造 god manager)。`HubProcessManager` 不认识 `JobStore`。

### 构建与内嵌

`scripts/build-rust.sh`(-hub spec 已建)产出 release 二进制;`scripts/run.sh` 在 xcodebuild 后
把 `target/release/nerve-hub` 拷入 `Nerve.app/Contents/MacOS/`。CI 同路径。

### Reuse decision

| 候选 | 裁决 | 依据 |
|---|---|---|
| `MachineTunnelManager` | **pattern** | spawn/重试/状态机形状照抄,不共享代码 |
| `scripts/build-rust.sh` | **reuse** | `nerve-hub` spec 产物,本段只消费 |
| `HubClient`(-01) | **reuse** | 断连信号是重探/重 spawn 的触发源 |

## Files

- `Nerve/Nerve/Services/Hub/HubProcessManager.swift`(new)
- `Nerve/Nerve.xcodeproj/project.pbxproj`(加入新文件)
- `Nerve/Nerve/App/AppModel.swift`(启动接线:`ensureRunning()` 前置于 `HubClient.connect()`)
- `scripts/run.sh`(xcodebuild 后拷贝二进制进 bundle)

## Tasks

- [ ] **T1** Implement `HubProcessManager`(发现序列、health 探测后决定 spawn、bind 冲突直连、
      崩溃重探 + 10s 节流重 spawn、退出不杀 hub)。
- [ ] **T2** Wire `AppModel` startup:`HubProcessManager.ensureRunning()` → `HubClient.connect()`;
      断连回调触发重探。
- [ ] **T3** Extend `scripts/run.sh` to embed `nerve-hub` into `Nerve.app/Contents/MacOS/`
      via `scripts/build-rust.sh`.
- [ ] **T4** Verify the manual matrix(下 Testing)and run build + hook tests.

## Testing

**Manual**

- 冷启动:无 hub 进程时 `./scripts/run.sh` → `pgrep nerve-hub` 有进程且二进制路径位于
  `Nerve.app/Contents/MacOS/`;`inject_demo.sh` → 面板显示。
- bind 冲突:先手动 `nerve-hub serve` 再起 app → `pgrep -c nerve-hub` 保持 1,app 直接连,
  日志无 spawn/崩溃循环。
- 韧性:`pkill nerve-hub` → app 在退避窗口内重探并重 spawn,面板恢复;10s 内不重复 spawn。
- refcount:退出 app(无其他 surface)→ 45s 内 `pgrep nerve-hub` 归零。

**回归**:xcodebuild 零 error;`python3 sources/agents/tests/test_nerve_hook.py` green。

## Out of scope

- `settings.ingestPort` 清理、文档、完整回归矩阵 → `-03-settings-docs`。
- brew / 公证 / 发布工程;launchd 守护化(hub 生命周期就是 refcount,不注册守护)。
