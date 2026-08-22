#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Nerve/build/Build/Products/Debug/Nerve.app"

cd "$ROOT/Nerve"
xcodebuild -scheme Nerve -configuration Debug -derivedDataPath build -quiet build

# The app spawns its own hub, so ship one inside the bundle: HubProcessManager
# looks in Contents/MacOS first. rm-then-cp, not cp over the top, so replacing a
# copy that is currently running cannot fail with ETXTBSY.
"$ROOT/scripts/build-rust.sh"
rm -f "$APP/Contents/MacOS/nerve-hub"
cp "$ROOT/target/release/nerve-hub" "$APP/Contents/MacOS/nerve-hub"
chmod +x "$APP/Contents/MacOS/nerve-hub"
# Adding a file to Contents/MacOS breaks the bundle seal; re-sign ad-hoc,
# keeping the entitlements xcodebuild signed it with.
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags "$APP"

open "$APP"
echo "Nerve launched. Ingest: http://127.0.0.1:17890"
