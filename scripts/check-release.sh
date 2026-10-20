#!/usr/bin/env bash
# Checks that a Release build carries no debug-only or test-only code: the component catalog
# (DesignSystem/Catalog, compiled only in Debug, and the look bundle page in Features/Debug/Catalog),
# the cutout benchmark (Features/Debug, Phase 8a), swift-snapshot-testing (test targets only) and
# the sample data (Fixtures/Sets and the sample photo providers, Phase 20a), and that the
# debug-only launch arguments (-catalog, -cutout-bench, Phase 16a's -tour, Phase 17's -onboarding,
# -toasts-stay and -animations, and Phase 20a's -fixtures) aren't in it.
#
# It also fails if any sample photo is inside the built app: the SampleWardrobe folder, a Fixtures
# or test-support resource bundle, or any file with the name of one of the repo's sample photos
# (Packages/NookKit/Tests/NookTestSupport/SampleWardrobe, the one copy). The photos are for Debug
# builds and tests only, and Configs/Release.xcconfig leaves them out of Release.
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

# Sample photos: look at the built app itself, not at the build settings that should keep them out.
app="$(dirname "$binary")"
photos="Packages/NookKit/Tests/NookTestSupport/SampleWardrobe"
if [[ ! -d "$photos" ]]; then
    echo "The sample photos aren't at $photos, so this check can't tell if they shipped." >&2
    exit 1
fi
found="$(find "$app" \( -name SampleWardrobe -o -name NookKit_Fixtures.bundle -o -name NookKit_NookTestSupport.bundle \) 2>/dev/null)"
if [[ -n "$found" ]]; then
    echo "Release app contains sample photo folders or bundles:" >&2
    echo "$found" >&2
    failed=1
fi
# The same photos under another folder name still count: compare file names (not the README or
# manifest, whose names are too common to mean anything).
sample_names="$(find "$photos" -type f \( -name '*.jpg' -o -name '*.jp2' \) -exec basename {} \; | sort -u)"
app_names="$(find "$app" -type f -exec basename {} \; | sort -u)"
copies="$(comm -12 <(echo "$sample_names") <(echo "$app_names"))"
if [[ -n "$copies" ]]; then
    echo "Release app contains $(echo "$copies" | wc -l | tr -d " ") file(s) named like sample photos, for example $(echo "$copies" | head -1)" >&2
    failed=1
fi

if [[ $failed -ne 0 ]]; then
    exit 1
fi
echo "Release app has no catalog, benchmark, snapshot-testing code, sample data code or sample photos"
