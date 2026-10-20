#!/usr/bin/env bash
# Checks that a Release build carries no debug-only or test-only code: the component catalog
# (DesignSystem/Catalog, compiled only in Debug, and the look bundle page in Features/Debug/Catalog),
# the cutout benchmark (Features/Debug, Phase 8a), swift-snapshot-testing (test targets only) and
# the sample data (Fixtures/Sets and the sample photo providers, Phase 20a), and that the
# debug-only launch arguments (-catalog, -cutout-bench, Phase 16a's -tour, Phase 17's -onboarding,
# -toasts-stay and -animations, and Phase 20a's -fixtures) aren't in it.
#
# The sample photos themselves still ship: SwiftPM copies the Fixtures resource bundle in every
# configuration, and the build-script sandbox stops a script removing it (Phase 20a, see
# docs/decisions/0003-persistence-spike.md). Nothing in Release reads them; this script says how big
# the bundle is so it isn't forgotten.
# Run after scripts/build.sh Release. scripts/check-archive.sh runs it on an archive's app
# binary instead: scripts/check-release.sh <path to the app's executable>.
set -euo pipefail
cd "$(dirname "$0")/.."

binary="${1:-build/DerivedData/Build/Products/Release-iphonesimulator/NiftyOutfitNook.app/NiftyOutfitNook}"
if [[ ! -f "$binary" ]]; then
    echo "No Release build at $binary. Run scripts/build.sh Release first." >&2
    exit 1
fi

# Read the symbols and strings once. `nm ... | grep -q` under pipefail gave false passes: grep
# stops at the first match, nm dies of SIGPIPE, and the pipeline counts as failed (Phase 20a).
symbols="$(nm "$binary")"
text="$(strings "$binary")"

failed=0
for pattern in NookCatalog CatalogDemo CutoutBench LookBundleCatalog LookBundleSamples LookBundleDemo SnapshotTesting \
    DemoCloset LargeCloset SampleWardrobe SamplePhotoGarments SyntheticGarmentPhotos FixtureDrafts SamplePhotoProvider; do
    if grep -q "$pattern" <<<"$symbols"; then
        echo "Release binary contains $pattern symbols" >&2
        failed=1
    fi
done
for argument in -catalog -cutout-bench -tour -onboarding -toasts-stay -animations -fixtures; do
    if grep -q -- "$argument" <<<"$text"; then
        echo "Release binary contains the $argument launch argument" >&2
        failed=1
    fi
done
if [[ -d "$(dirname "$binary")/Frameworks" ]] && ls "$(dirname "$binary")/Frameworks" | grep -qi snapshot; then
    echo "Release app bundles a snapshot-testing framework" >&2
    failed=1
fi

if [[ $failed -ne 0 ]]; then
    exit 1
fi
echo "Release binary has no catalog, benchmark, snapshot-testing code or sample data code"
samples="$(dirname "$binary")/NookKit_Fixtures.bundle/SampleWardrobe"
if [[ -d "$samples" ]]; then
    echo "Note: the unused sample photos still ship ($(du -sh "$samples" | cut -f1 | tr -d " ")), see docs/decisions/0003-persistence-spike.md"
fi
