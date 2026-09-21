# nerve — Tether plugin

A Tether extension that paints the same `nerve-hub` stream as the macOS menu
bar. It never starts a second hub when Nerve.app (or another surface) already
owns `127.0.0.1:17890`.

## Docs

→ Website `/docs/tether` — from repo root:

```bash
cd index && npm run dev
```

## Wire into Tether

The plugin is a compile-time Swift package. In Tether's app package:

```swift
.package(path: "../../nerve/surfaces/tether")
// …
.product(name: "NervePlugin", package: "NervePlugin")
```

```swift
registry.register(NervePlugin())
```

## Verify

```bash
swift test --package-path surfaces/tether
```
