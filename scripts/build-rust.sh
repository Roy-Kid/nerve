#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cargo build --workspace --release
echo "Built: $ROOT/target/release/nerve-hub"
