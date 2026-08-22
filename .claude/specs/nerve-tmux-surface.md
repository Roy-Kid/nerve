---
status: approved
slug: nerve-tmux-surface
depends: nerve-hub
revised: 2026-08-22
---

# nerve-tmux-surface — tmux 内的对等 surface

## Summary

**macOS 菜单栏和 tmux 是 Nerve 的两个对等 surface:互不知晓,都只消费 `nerve-hub` 契约。**
本 spec 交付 tmux 侧:TPM 插件入口 `surfaces/tmux/nerve.tmux` 在 tmux 启动时后台拉起单实例
Rust helper `nerve-tmux-surface`;helper 找到(必要时拉起)hub,持有一条
`GET /v1/stream?surface=tmux` 长连接——**这条连接就是本 surface 的 refcount 在场证明**——
把每帧聚合成一段状态文本写进 tmux user option `@nerve_status`,由 `status-right` 常驻展示;
`prefix + N` 用 `display-popup` 打开只读 job 详单。attention 仅在 tmux 内表达(段高亮),
**不发系统通知**(通知归 macOS surface,避免双响)。hub 不可得时显示离线占位,退避重连,
全程 fail-open:tmux 该怎么用还怎么用。

## Domain basis

### 已裁决决策(本 spec 的前提,不在此重开)

| 决策 | 对本 spec 的含义 |
|------|------------------|
| 拓扑 C:独立 hub daemon + SSE refcount | helper 不持久化状态,唯一职责是消费者;SSE 断开即退出 refcount |
| surfaces 对等、互不知晓 | 不读 macOS app 的任何状态/设置;不假设它在跑 |
| 全量帧 + `departed` | 每帧覆盖式重绘;`departed` 只用于移除行,不触发提醒 |
| 通知仅 macOS | tmux 侧禁止 `osascript` / `terminal-notifier` / 任何系统通知 |
| 端口固定 17890 | 无 `NERVE_*` env;远程机器经 RemoteForward 连本机 127.0.0.1:17890 即达 hub |
| 根 workspace + `crates/` | helper 作为 workspace member,不建独立 workspace |
| display-only 不变量 | popup 只读:无 approve / cancel / submit_input |
| **hub 帧不带派生 status** | Swift 的 `status` 是 computed property、从不序列化;hub 保真移植不新增该字段。`status.rs` 镜像真值表是唯一路径,golden 钉死 |

**设计红利(零代码):** 远程免费。RemoteForward 隧道下,远程机器上的 helper 连自己的
127.0.0.1:17890 就到达本机 hub;helper 完全不感知"远程"这个概念。

### tmux(1) 事实(约束实现形态)

- user option:`tmux set -g @nerve_status <text>`;`status-right` 内以 `#{@nerve_status}` 插值。
- 写完 option 必须 `refresh-client -S` 才立即重绘状态行。
- **option 值会被 tmux 再次做 format 展开** —— 因此 job 名等动态文本写入前必须把 `#` 转义为 `##`;
  而 `#[fg=…]` 样式标记是我们**故意**保留展开的部分。模板占位符因此不用 `#{}`,用 `{running}` 形态。
- `display-popup -E` 执行命令并在退出时关闭;popup 内容是纯 stdout,天然只读。
- 全链路 arg-array spawn(Rust `Command`),不过 shell(与 `nerve_hook.py` 同规矩)。

### 状态词汇(唯一真值)

沿用 `Nerve/Nerve/Models/CoreTypes.swift` 的派生 `Status` 六态与优先级顺序:
`problem > attention > waiting > running > success > inactive`。派生只用结构化字段
(`outcome` / `health` / `attention.level` / `attention.reason` / `lifecycle` / `current`),
**绝不做自由文本分类**(repo 不变量 3)。

## Design

### 模块划分(每个都能用 fake 单测,不需要真 tmux / 真 hub / 真 socket)

| 模块 | 类型与职责 |
|------|------------|
| `frame.rs` | `Frame { jobs, departed }` / `JobView` — 只做 serde 解码,未知字段容忍(含 hub 的 `timeline`,本 surface 忽略) |
| `status.rs` | `StatusClass` 六态 + `StatusClass::of(&JobView)`:镜像 `Subject.swift:38` 真值表(hub 帧不带派生 status,已与 `nerve-hub` spec 对齐);fixture golden 钉死一致性 |
| `tally.rs` | `Tally::from(&[JobView])` — 纯计数,`departed` 已在上游剔除 |
| `summary.rs` | `SummaryRenderer { template }` → `render(&Tally) -> String`;零计数省略;`#` 转义 |
| `popup.rs` | `PopupRenderer { clock }` → `render(&[JobView]) -> String`(producer / name / status / attention / age) |
| `locate.rs` | `HubLocator<P: BinaryProbe>` — 发现序列 `/opt/homebrew/bin` → `/usr/local/bin` → `~/.cargo/bin` → PATH |
| `launch.rs` | `HubLauncher<S: ProcessSpawner, C: Clock>` — health 探测失败且距上次尝试 >10s 才 spawn 一次 |
| `stream.rs` | `StreamSession<T: FrameSource>` + `Backoff`(0.5s 倍增、上限 30s、成功即重置) |
| `tmux.rs` | `TmuxWriter<R: TmuxRunner>` — `set -g @nerve_status <text>` / `refresh-client -S`;识别 `ServerGone` |
| `instance.rs` | `InstanceGuard` — 以 tmux option `@nerve_surface_pid` 做单实例(活着则新进程立即 exit 0;pid 已死则接管) |
| `main.rs` | 组合根:只做装配与信号处理,无业务逻辑 |

无 factory 函数、无 god context、无 all-in-one façade;每个 trait 都是为注入 fake 而存在的窄接口。

### 生命周期与所有权

```text
nerve.tmux (source 时)
  └─ spawn -> nerve-tmux-surface run          (单实例;已有活实例则立即退出)
        ├─ HubLocator → HubLauncher(必要时)
        ├─ StreamSession: GET /v1/stream?surface=tmux   ← 本 surface 的 refcount
        │     每帧 → Tally → SummaryRenderer → TmuxWriter → refresh-client -S
        ├─ 断线 → Backoff 重连;首次失败即写离线占位
        └─ 退出(SIGTERM / tmux server 消失 / ServerGone)→ 断开 SSE(hub 自理 refcount)
prefix + N → display-popup -E "nerve-tmux-surface popup"  (一次性 GET /v1/jobs,只读)
```

无守护化魔法:不写 launchd / systemd;helper 崩了下次 `nerve.tmux` 触发或按键重拉。

### 用户可配置项(首版克制,共三个)

`@nerve_status_format`(默认含 `{running}` `{attention}` `{problem}` `{waiting}` `{total}` 占位符与
`#[fg=…]` 主题友好标记)、`@nerve_status_offline`(离线占位文本)、`@nerve_popup_key`(默认 `N`)。

### Reuse decision

| 候选 | 决策 | 说明 |
|------|------|------|
| hub 契约 `/v1/stream` `/v1/jobs` `/v1/health` | **reuse** | 只消费,不新增端点、不改 hub |
| `Job.status` 派生规则(`Nerve/Nerve/Models/Subject.swift:38`) | **pattern(镜像)** | Swift 无法跨语言调用;`status.rs` 抄写真值表并由 fixture 钉死一致性 |
| `scripts/verify_loop.sh` / `scripts/inject_demo.sh` | **reuse** | 集成验证复用现成注入器,新脚本只编排 |
| `fixtures/demo_snapshot.json` | **reuse** | 作为渲染 golden 输入 |
| `plugins/nerve/hooks/run.sh` 自定位 + 候选序列 + fail-open exit 0 | **pattern** | `nerve.tmux` 逐条照抄这套写法,读起来像同一个仓库的代码 |
| `plugins/nerve/`(marketplace 目录) | **new placement** | 根 `.claude-plugin/marketplace.json` 扫描 `plugins/`,放进去会被 marketplace 语义污染 → `surfaces/tmux/` |
| `nerve-tmux`(未来 tmux adapter crate) | **new — 职责不同** | surface = 渲染消费者;adapter = tmux 操作原语。故命名 `nerve-tmux-surface`,不撞名 |
| `Nerve/Nerve/Services/NotificationService.swift` | **不复用(刻意)** | 通知仅 macOS surface |

## Files

| 路径 | 变更 |
|------|------|
| `Cargo.toml` | 由 `nerve-hub` 创建;本 spec 仅向 `members` 追加 `crates/nerve-tmux-surface` |
| `crates/nerve-tmux-surface/Cargo.toml` | (new) crate 清单,bin 名 `nerve-tmux-surface` |
| `crates/nerve-tmux-surface/src/{main,frame,status,tally,summary,popup,locate,launch,stream,tmux,instance}.rs` | (new) 见 Design 模块表 |
| `crates/nerve-tmux-surface/tests/` | (new) 集成级单测:帧 → 段文本、popup 渲染 golden |
| `surfaces/tmux/nerve.tmux` | (new) TPM 入口:自定位 helper、单实例 spawn、`status-right` 幂等接入、绑定 popup 键 |
| `surfaces/tmux/README.md` | (new) 短指引:TPM `set -g @plugin` / 手动 source / 三个 option |
| `scripts/verify_tmux_surface.sh` | (new) 可复现验证:hub → 注入 → 段计数 → 退出 refcount |
| `index-page/src/docs/content.ts` | 新增 nav item + doc page `tmux`(安装、选项、popup、与 hub 关系、隧道红利、display-only) |
| `README.md` | 一行指针:tmux surface → 站点 `/docs/tmux` |
| `.claude/specs/nerve-tmux-surface.acceptance.md` | (new) 验收契约 |

## Tasks

> Phase 1/2 每项一律 RED → GREEN:先写会失败的单测(注入 fake runner / fake transport / fake clock),再实现。

### Phase 1 — Helper 渲染核心

- [ ] **T1** Add `crates/nerve-tmux-surface` to the root workspace `members`; scaffold the
      `run` / `popup` CLI skeleton with arg-array spawning only (no shell anywhere).
- [ ] **T2** Implement `frame.rs` + `status.rs` — frame decoding and `StatusClass::of()` mirroring
      `Subject.swift:38`; tests assert free-text fields never affect the result.
- [ ] **T3** Implement `tally.rs` + `summary.rs` — counts and `@nerve_status_format` rendering
      with `{token}` placeholders, zero-count elision, and `#` → `##` escaping of dynamic text.

### Phase 2 — Hub 附着(发现 / 流 / 写回)

- [ ] **T4** Implement `locate.rs` + `launch.rs` — discovery order
      (`/opt/homebrew/bin` → `/usr/local/bin` → `~/.cargo/bin` → PATH), health probe, and
      at-most-one spawn per 10s window under an injected clock.
- [ ] **T5** Implement `stream.rs` — SSE frame consumption over an injected transport,
      `Backoff` (0.5s doubling, 30s cap, reset on success), offline placeholder on first failure.
- [ ] **T6** Implement `tmux.rs` + `instance.rs` — `set -g @nerve_status` + `refresh-client -S`
      via fake runner, `@nerve_surface_pid` single-instance guard, `ServerGone` → clean exit 0
      that drops the SSE connection.

### Phase 3 — tmux 插件面与文档

- [ ] **T7** Add `surfaces/tmux/nerve.tmux` — self-locating helper lookup and fail-open exit 0
      following `plugins/nerve/hooks/run.sh`; idempotent `status-right` wiring of `#{@nerve_status}`.
- [ ] **T8** Implement `popup.rs` and bind `@nerve_popup_key` to
      `display-popup -E "<helper> popup"` — read-only rows (producer / name / status / attention / age).
- [ ] **T9** Add `scripts/verify_tmux_surface.sh` — reuse `scripts/inject_demo.sh`; assert the
      rendered segment counts, then assert hub survives helper exit while another surface holds a stream.
- [ ] **T10** Add docs — `index-page/src/docs/content.ts` `tmux` page + nav entry,
      `surfaces/tmux/README.md`, root `README.md` pointer.

## Testing

| 层 | 命令 / 方法 |
|----|-------------|
| 单元 | `cargo test -p nerve-tmux-surface` — 帧解析、六态映射、聚合文本 golden、`#` 转义、发现序列、退避序列、spawn 节流、tmux argv 形状、单实例接管 |
| Golden | `fixtures/demo_snapshot.json` 形态的帧 → 段文本硬编码期望值(与 Swift 派生结果一致) |
| 可复现集成 | `./scripts/verify_tmux_surface.sh`(hub → `inject_demo.sh` → 段计数 → refcount 行为) |
| 手动 · 常驻段 | TPM 安装 → 注入 demo → `status-right` 2s 内出现计数;注入 attention job → 段高亮 |
| 手动 · popup | `prefix + N` 列出 job 行;无任何按键可 approve/cancel/submit;ESC 关闭 |
| 手动 · 双 surface | macOS app + tmux 同时连:kill helper → hub 不退;再退 app → 约 30s 后 hub 自退;再开 tmux → helper 重新拉起 hub |
| 手动 · fail-open | 无 hub 二进制 / 端口关闭 / helper 崩溃 → tmux 正常使用,段显示离线占位,`nerve.tmux` 退出码 0 |

## Out of scope

- **sidebar TUI**(Ratatui 全景侧栏)—— 刻意不做:Nerve 是 conversation-centric,不是 every-pane monitor。
- **tmux pane focus / jump**(原 bridge 资产)→ 另立 spec;本 spec 不触 focus 路径。
- **pane 级 identity 上报** —— 属 producer(hook)侧,不属 surface。
- **系统通知 / 声音** —— 通知仅 macOS surface。
- **hub 本体与 macOS app** —— 前置 / sibling spec;本 spec 不改 Swift、不改 Python hook。
- 预编译二进制分发、launchd/systemd 守护化、多 hub / 非 17890 端口、popup 内搜索与筛选。

## Open questions

1. **二进制分发**:首版要求 `cargo install --path crates/nerve-tmux-surface`;
   `nerve.tmux` 找不到二进制时段内显示 `nerve: setup` 提示而非静默 —— 是否够友好,首版先这样。
