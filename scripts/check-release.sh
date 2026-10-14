#!/usr/bin/env bash
# Checks that a Release build carries no debug-only or test-only code: the component catalog
# (DesignSystem/Catalog, compiled only in Debug) and swift-snapshot-testing (test targets only).
# Run after scripts/build.sh Release.
set -euo pipefail
cd "$(dirname "$0")/.."

binary="build/DerivedData/Build/Products/Release-iphonesimulator/NiftyOutfitNook.app/NiftyOutfitNook"
if [[ ! -f "$binary" ]]; then
    echo "No Release build at $binary. Run scripts/build.sh Release first." >&2
    exit 1
fi

failed=0
for pattern in NookCatalog CatalogDemo SnapshotTesting; do
    if nm "$binary" | grep -q "$pattern"; then
        echo "Release binary contains $pattern symbols" >&2
        failed=1
    fi
done
if strings "$binary" | grep -q -- "-catalog"; then
    echo "Release binary contains the -catalog launch argument" >&2
    failed=1
fi
if [[ -d "$(dirname "$binary")/Frameworks" ]] && ls "$(dirname "$binary")/Frameworks" | grep -qi snapshot; then
    echo "Release app bundles a snapshot-testing framework" >&2
    failed=1
fi

if [[ $failed -ne 0 ]]; then
    exit 1
fi
echo "Release binary has no catalog or snapshot-testing code"
