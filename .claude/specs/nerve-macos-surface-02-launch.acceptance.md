# nerve-macos-surface-02-launch — Acceptance

Binding contract for `.claude/specs/nerve-macos-surface-02-launch.md`. All items must pass before spec close.

## A1 — App spawns bundled hub

**type:** manual

无 hub 进程时 `./scripts/run.sh`:`pgrep nerve-hub` 有进程且其二进制路径位于
`Nerve.app/Contents/MacOS/`;`./scripts/inject_demo.sh` 后面板与 ribbon 出现 demo 行。

## A2 — Existing hub is reused, never double-spawned

**type:** manual

先手动 `nerve-hub serve` 再 `./scripts/run.sh`:`pgrep -c nerve-hub` 保持 1,app 面板正常显示
hub 已有 jobs,日志无反复 spawn/崩溃循环。

## A3 — Crash resilience with spawn throttle

**type:** manual

app 运行中 `pkill nerve-hub`:app 重探并重 spawn,面板在退避窗口内恢复;
连续 kill 时 10s 窗口内至多一次 spawn(无 spawn 风暴)。

## A4 — Surface refcount releases hub

**type:** manual

退出 app(无其他 surface 连接)后 45s 内 `pgrep nerve-hub` 为空;app 退出路径中不存在
向 hub 发送终止信号的代码(review:`HubProcessManager` 无 `terminate()`/`kill` 调用指向 hub)。

## A5 — Build + suites green

**type:** manual

`./scripts/run.sh` 全程零 error(含 `scripts/build-rust.sh`);
`python3 sources/agents/tests/test_nerve_hook.py` 零改动全绿。
