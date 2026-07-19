#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Nerve"
xcodebuild -scheme Nerve -configuration Debug -derivedDataPath build -quiet build
open "$ROOT/Nerve/build/Build/Products/Debug/Nerve.app"
echo "Nerve launched. Ingest: http://127.0.0.1:17890"
