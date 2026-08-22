# nerve-tmux-surface — Acceptance

Binding contract for `.claude/specs/nerve-tmux-surface.md`. All items must pass before spec close.

## A1 — Status mapping parity

**type:** unit

硬编码一帧含六个 job,分别落 `problem` / `attention` / `waiting` / `running` / `success` / `inactive`:
`Tally` 每态计数为 1。另断言:

- 某 job `current.summary = "build failed!!"` 但结构化字段健康 → 仍为 `running`(禁止自由文本分类)
- 帧内 job 带未知字段(含 hub 的 `timeline`)→ 解码与计数不受影响
- `departed` 中的 job 不进入任何计数

## A2 — Segment rendering golden

**type:** unit

默认 `@nerve_status_format` + `Tally{running:2, attention:1, problem:0}` → 输出等于硬编码期望串;
零计数段整体省略;自定义模板 `{running}/{total}` 按位替换;动态文本含 `#` 时输出为 `##`,
而模板自带的 `#[fg=…]` 原样保留。

## A3 — Discovery order and spawn throttle

**type:** unit

fake probe 下:三处候选同时存在 → 选 `/opt/homebrew/bin`;仅 PATH 命中 → 选 PATH;
health 探测成功 → **零次** spawn;health 失败且二进制存在 → 注入时钟 30s 内**恰好 1 次** spawn(10s 节流);
二进制缺失 → 不 spawn,写离线占位,退出码 0。

## A4 — Backoff and offline placeholder

**type:** unit

连续失败产生延迟序列 `0.5, 1, 2, 4, 8, 16, 30, 30`(上限 30s);一次成功后重置为 `0.5`;
首次失败即写入 `@nerve_status_offline` 文本;重连成功后下一帧覆盖为正常段文本。

## A5 — Tmux command shape

**type:** unit

fake `TmuxRunner` 记录 argv:每次更新恰为 `["set","-g","@nerve_status", <text>]` 后跟
`["refresh-client","-S"]`;**任何一次调用都不是单字符串 shell 命令**;
runner 返回 `no server running` → `run` 停止重试并 exit 0(SSE 连接已 drop)。

## A6 — Single instance

**type:** unit + manual

启动时 `@nerve_surface_pid` 被认领;第二个 `run` 见到活 pid → 立即 exit 0 且**从未打开 stream**;
pid 已死 → 新进程接管并改写该 option。手动:重复 `source nerve.tmux` 三次,
`pgrep -f nerve-tmux-surface` 仅一个进程。

## A7 — Live status-line segment

**type:** manual

TPM 安装(或手动 source)后注入 `fixtures/demo_snapshot.json`:`status-right` 2s 内出现
running 计数;注入 `attention.level=required` 的 job → 该段以 attention 颜色高亮;
job 结束进入 `departed` → 计数在下一帧回落。

## A8 — Read-only popup

**type:** manual

`prefix + N` 打开 popup,列出 producer / name / status / attention / age 行;
popup 内**不存在**任何 approve / cancel / submit 交互;ESC 关闭且不影响 helper 与 hub。

## A9 — Refcount coexistence

**type:** manual

macOS surface 与 tmux surface 同时连接 hub:

- `pkill -f nerve-tmux-surface` → hub **不退**(macOS 仍持流)
- 再退出 macOS app → 约 30s grace 后 hub 自行退出
- 重新 source `nerve.tmux` → helper 重新发现并拉起 hub,段恢复

## A10 — Fail-open in tmux

**type:** manual

以下每种情况下 tmux 使用完全不受影响(不卡顿、不弹错、`nerve.tmux` 退出码 0):
hub 二进制缺失 / 17890 端口关闭 / helper 被 `kill -9` / hub 中途重启。
段文本降级为离线占位,并在 hub 恢复后自动回到实时计数。

## A11 — No system notifications

**type:** review

crate 与 `surfaces/tmux/` 全量检索:无 `osascript`、`terminal-notifier`、
`UNUserNotification`、系统铃声调用;attention 表达仅限段高亮与可选 `display-message`。
同时确认无 launchd / systemd 单元文件、无磁盘状态文件(单实例走 tmux option)。

## A12 — Docs

**type:** review

`index-page/src/docs/content.ts` 新增 `tmux` 页且入 `docNav`,覆盖:TPM 与手动安装、
三个 user option、popup 键位、与 hub 的关系(surface 对等 / SSE refcount / 自动拉起与自退)、
RemoteForward 下远程零配置红利、display-only 边界与"通知只在 macOS"。
`README.md` 与 `surfaces/tmux/README.md` 均为指向站点的短指引。
