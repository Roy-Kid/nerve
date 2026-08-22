---
status: approved
slug: nerve-macos-surface-03-settings-docs
depends: nerve-macos-surface-02-launch
revised: 2026-08-22
---

# nerve-macos-surface-03-settings-docs — 固定端点、文档与回归矩阵

## Summary

macOS 一刀切改造的收尾段:移除 `settings.ingestPort` 旋钮(可变端口与「bind 17890 即单实例锁」矛盾,
hook 侧本就硬编码),全部引用改 `NerveEndpoint` 常量;公开文档写明 hub daemon 架构;
`scripts/verify_surface.sh` 固化回归矩阵并跑全量套件。

## Domain basis

前置(既定):端口固定 17890;`MachineConfig.remoteIngestPort` 是**独立的远端字段**
(RemoteForward 远端口),隧道语义无损平移、**保持不变**;历史 Settings 文件含旧 `ingestPort`
字段,解码时忽略(向后兼容,不迁移)。

`settings.ingestPort` 实测影响面(比表面大):`SettingsStore.swift:135`(存储属性)、`:330`(默认值)、
`:381`/`:420`(持久化解码)、`:539`/`:563`(remoteIngestPort 入参)、`:601`/`:634`(两个持久化 struct 的
`var ingestPort` 字段);`SettingsView.swift:318`/`:757`(UI 文案);`StatusPanelView.swift:498`(端口文案);
`MachineTunnelManager.swift:22`(private 默认值)与 `:26/61/87/145/276`(五处引用)。

## Design

- `SettingsStore`:删 `ingestPort` 属性与默认值;解码忽略历史字段;`:539`/`:563` 的
  `remoteIngestPort` 入参改用 `NerveEndpoint.port`(仅本机侧;远端字段不动)。
- UI:Settings 不再出现端口输入项,文案显示 `127.0.0.1:17890`(取自 `NerveEndpoint`);
  `StatusPanelView.swift:498` 同理。
- `MachineTunnelManager` 五处 `settings.ingestPort` → `NerveEndpoint.port`;
  managed block 输出保持 `RemoteForward 17890 127.0.0.1:17890` + `ExitOnForwardFailure` 逐字不变。
- 文档:`index-page/src/docs/content.ts` 的 `/docs/ingest` 与 `/docs/status` 写明:
  状态权威是 `nerve-hub` daemon、固定端口、SSE refcount 生命周期、app 为纯 surface、无端口设置项。
- `scripts/verify_surface.sh`:自动化可自动的回归断言(hub 存活/退出、jobs 往返),
  人工矩阵在注释中列明。

### Reuse decision

| 候选 | 裁决 | 依据 |
|---|---|---|
| `NerveEndpoint`(-01) | **reuse** | 唯一端点真值源 |
| `SSHConfigWriter` / `MachineConfig.remoteIngestPort` | **reuse**(零改动) | 隧道目标端口仍 17890 |
| `scripts/verify_loop.sh` / `test_nerve_hook.py` | **reuse**(零改动) | 契约不变,由 hub 服务 |

## Files

- `Nerve/Nerve/Store/SettingsStore.swift`
- `Nerve/Nerve/App/SettingsView.swift`
- `Nerve/Nerve/UI/Panel/StatusPanelView.swift`
- `Nerve/Nerve/Services/MachineTunnelManager.swift`
- `scripts/verify_surface.sh`(new)
- `index-page/src/docs/content.ts`

## Tasks

- [ ] **T1** Replace `settings.ingestPort` with `NerveEndpoint`(`SettingsStore.swift:135/330/381/420/539/563/601/634`、
      `SettingsView.swift:318/757`、`StatusPanelView.swift:498`、`MachineTunnelManager.swift:22/26/61/87/145/276`);
      历史 Settings 文件解码兼容(持久化 struct 字段删除、解码忽略)。
- [ ] **T2** Update public docs in `index-page/src/docs/content.ts`(`/docs/ingest`、`/docs/status`:
      hub daemon、固定端口、surface 架构、无端口设置项)。
- [ ] **T3** Add `scripts/verify_surface.sh` and run the manual regression matrix
      (通知三场景含 departed 路径、hub 生命周期、bind 冲突、隧道逐字回归)。
- [ ] **T4** Run full check + test suite(`scripts/test_swift_units.sh`、`./scripts/run.sh` 构建、
      `python3 sources/agents/tests/test_nerve_hook.py`、hub 运行时 `scripts/verify_loop.sh`、
      `cd index-page && npm test && npm run build`)。

## Testing

**Manual**:Settings 无端口输入项且文案为 `127.0.0.1:17890`;带旧 `ingestPort` 字段的历史 Settings
文件加载不报错;Settings → Machines 连接后 `~/.ssh/config` managed block 与改造前逐字一致,
连接/断开行为不变。

**Review**:`rg -n "ingestPort" Nerve/` 仅命中 `remoteIngestPort`。

**Suite**:T4 全绿;`/docs/ingest`、`/docs/status` 内容审阅通过。

## Out of scope

- brew / 公证 / 发布工程;tmux surface(sibling);pending 复活;任何 reverse-control。
