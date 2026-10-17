#!/usr/bin/env bash
# Fails when a UI test taps without saying what the tap should do. On a slow CI runner a tap that
# lands while a screen is still moving does nothing, so every tap goes through a helper in
# NiftyOutfitNookUITests/UITestSupport.swift that waits for its effect and taps once more if it
# didn't come (tapUntil, tapUntilGone, tapUntilSelected, tapUntilFocused). A tap with nothing to
# wait for keeps a bare tap() with "// tap-unconfirmed: <why>" on the same line.
# scripts/format.sh runs this, so CI's swift-format job does too.
set -euo pipefail
cd "$(dirname "$0")/.."

found="$(grep -rnE --include='*.swift' '\.tap\(\)|tapWhenHittable' NiftyOutfitNookUITests \
    | grep -v '^NiftyOutfitNookUITests/UITestSupport.swift:' \
    | grep -vE '// tap-unconfirmed: [^ ]' || true)"
if [[ -n "$found" ]]; then
    echo "UI tests tap without checking what the tap did:" >&2
    echo "$found" >&2
    echo "Use a confirming helper from UITestSupport.swift, or add \"// tap-unconfirmed: <why>\"." >&2
    exit 1
fi
