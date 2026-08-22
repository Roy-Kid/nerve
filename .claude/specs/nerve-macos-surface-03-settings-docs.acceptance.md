# nerve-macos-surface-03-settings-docs — Acceptance

Binding contract for `.claude/specs/nerve-macos-surface-03-settings-docs.md`. All items must pass before spec close.

## A1 — Fixed endpoint replaces the port knob without breaking tunnels

**type:** manual

Settings 不再出现 ingest 端口输入项,文案显示 `127.0.0.1:17890`;历史 Settings 文件
(含旧 `ingestPort` 字段)加载不报错;Settings → Machines 连接后 `~/.ssh/config` managed block
仍为 `RemoteForward 17890 127.0.0.1:17890` + `ExitOnForwardFailure`,连接/断开与改造前一致。

## A2 — No stray port references

**type:** review

`rg -n "ingestPort" Nerve/` 仅命中 `remoteIngestPort`(远端字段,保留);
端点字面量只存在于 `NerveEndpoint`。

## A3 — Docs describe the hub architecture

**type:** review

`index-page/src/docs/content.ts` 的 `/docs/ingest` 与 `/docs/status`:状态权威为 `nerve-hub` daemon、
固定端口 17890、SSE refcount 生命周期(最后一个 surface 断开 + 30s grace 自退)、
app 为纯 surface、Settings 无端口项。

## A4 — Full check + suite green

**type:** manual

`scripts/test_swift_units.sh` 全绿;`./scripts/run.sh` 零 error;
`python3 sources/agents/tests/test_nerve_hook.py` 零改动全绿;hub 运行时
`bash scripts/verify_loop.sh` 输出 `ALL OK`;`scripts/verify_surface.sh` 通过;
`cd index-page && npm test && npm run build` 通过。
