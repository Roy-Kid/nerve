#!/usr/bin/env bash
#
# Minimal swiftc unit harness for the pure-value units of the macOS surface.
#
# The repo deliberately has no XCTest / swift-testing target (see
# .claude/specs/nerve-macos-surface-01-cutover.md -> "Out of scope"): the units
# under test are Foundation-only value types, so swiftc compiles the model
# sources + the Hub value types + the test file into one throwaway executable
# and runs it. No Xcode, no scheme, no derived data, nothing written into the
# repo (build products live in a mktemp dir that is removed on exit).
#
# Usage: bash scripts/test_swift_units.sh
# Exit:  0 all green, 1 compile or assertion failure, 2 harness itself is broken.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Match the app target so the harness cannot drift into a different dialect:
# SWIFT_VERSION = 5.0, MACOSX_DEPLOYMENT_TARGET = 14.0 (Nerve.xcodeproj).
SWIFT_LANG_VERSION="5"
DEPLOYMENT_TARGET="14.0"
TARGET_TRIPLE="$(uname -m)-apple-macosx${DEPLOYMENT_TARGET}"

TEST_FILE="Nerve/Tests/FrameDifferTests.swift"

# Compile set, smallest that still exercises the real `Job` model:
#   Models/*.swift            -- Foundation-only, no SwiftUI/AppKit (verified);
#                                CoreTypes references Job, so the directory
#                                compiles as one unit.
#   Services/Hub/HubFrame     -- unit under test (spec task T2).
#   Services/Hub/FrameDiffer  -- unit under test (spec task T2).
#   Nerve/Tests/*.swift       -- the harness itself (never in the app target).
# Store/, UI/, Services/* beyond Hub, and Ingest/ pull in SwiftUI/AppKit/Network
# and are intentionally out of the compile set.
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Nerve/Nerve/Models -name '*.swift' | sort)
SOURCES+=(
  "Nerve/Nerve/Services/Hub/HubFrame.swift"
  "Nerve/Nerve/Services/Hub/FrameDiffer.swift"
  "$TEST_FILE"
)

if [[ ! -f "$TEST_FILE" ]]; then
  echo "harness broken: missing $TEST_FILE" >&2
  exit 2
fi

PRESENT=()
MISSING=()
for f in "${SOURCES[@]}"; do
  if [[ -f "$f" ]]; then
    PRESENT+=("$f")
  else
    MISSING+=("$f")
  fi
done

if ((${#MISSING[@]} > 0)); then
  echo "note: source(s) not implemented yet (spec task T2):" >&2
  printf '        %s\n' "${MISSING[@]}" >&2
  echo "      compiling without them so swiftc reports the exact contract gap." >&2
  echo "" >&2
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nerve-swift-units.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
BIN="$BUILD_DIR/NerveUnitTests"

echo "swiftc: ${#PRESENT[@]} source file(s) -> $BIN"
if ! swiftc \
  -parse-as-library \
  -swift-version "$SWIFT_LANG_VERSION" \
  -target "$TARGET_TRIPLE" \
  -Onone \
  -module-name NerveUnitTests \
  -o "$BIN" \
  "${PRESENT[@]}"; then
  echo "" >&2
  echo "RED: swiftc could not build the unit harness (see errors above)." >&2
  if ((${#MISSING[@]} > 0)); then
    echo "     Expected while spec task T2 is open — implement:" >&2
    printf '       %s\n' "${MISSING[@]}" >&2
  fi
  exit 1
fi

echo ""
"$BIN"
