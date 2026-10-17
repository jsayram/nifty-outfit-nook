#!/usr/bin/env bash
# Checks formatting with swift-format, using the checked-in .swift-format config, that every
# String Catalog key is still used (scripts/check-strings.py), and that every UI test tap checks
# its effect (scripts/check-ui-taps.sh). CI's swift-format job runs this.
# Usage: scripts/format.sh          lint only, fails on any finding
#        scripts/format.sh --fix    rewrite files in place, then lint
set -euo pipefail
cd "$(dirname "$0")/.."

paths=(
    NiftyOutfitNook
    NiftyOutfitNookUITests
    Packages/NookKit/Package.swift
    Packages/NookKit/Sources
    Packages/NookKit/Tests
)

if [[ "${1:-}" == "--fix" ]]; then
    xcrun swift-format format --in-place --recursive --parallel "${paths[@]}"
fi
xcrun swift-format lint --strict --recursive --parallel "${paths[@]}"
scripts/check-strings.py
scripts/check-ui-taps.sh
