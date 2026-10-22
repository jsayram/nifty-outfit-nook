#!/usr/bin/env bash
# Checks that a Release build carries no debug-only or test-only code: the component catalog
# (DesignSystem/Catalog, compiled only in Debug, and the look bundle page in Features/Debug/Catalog),
# the cutout benchmark (Features/Debug, Phase 8a), the device checks screen and migration kill
# helpers (Models/Debug, Services/Debug, Features/Debug/DeviceChecks), swift-snapshot-testing (test targets only) and
# the sample data (Fixtures/Sets and the sample photo providers, Phase 20a), and that the
# debug-only launch arguments (-catalog, -cutout-bench, Phase 16a's -tour, Phase 17's -onboarding,
# -toasts-stay and -animations, Phase 20a's -fixtures, the device checks' -device-checks,
# -make-old-store, -migration-kill-at and -migration-pause-at, and 33a's -seed-tryon and
# -cloud-tryon) aren't in it. 33a: nor is the drawn stand-in person the simulator uses
# (SyntheticPerson).
#
# It also fails if any sample photo is inside the built app: the SampleWardrobe folder, a Fixtures
# or test-support resource bundle, or any file with the name of one of the repo's sample photos
# (Packages/NookKit/Tests/NookTestSupport/SampleWardrobe, the one copy). The photos are for Debug
# builds and tests only, and Configs/Release.xcconfig leaves them out of Release.
# Phase 25a: it also fails if the built app holds anything that looks like a secret: an AI provider,
# Clerk secret, Convex deploy or GitHub key; a private key; a server-only setting name
# (ANTHROPIC_API_KEY, NOOK_RESULT_KEY and the like); a provider's own address (the app only ever
# calls our gateway); a URL with a password in it; plain http:// or localhost addresses; a key file
# (.env, .p8, .p12, .pem, .key, .xcconfig); or an Info.plist key named like a secret. The Clerk
# publishable key and the gateway URL are allowed in Info.plist only: both ship in the app on
# purpose. The scan reads the strings of every file in the app, so a key can't hide in a resource.
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
    DemoCloset LargeCloset SampleWardrobe SamplePhotoGarments SyntheticGarmentPhotos FixtureDrafts SamplePhotoProvider \
    MigrationDebug DeviceFileChecks DeviceChecksScreen DeviceChecksSource FileCheckRow LockProbe SyntheticPerson; do
    if grep -q "$pattern" <<<"$symbols"; then
        echo "Release binary contains $pattern symbols" >&2
        failed=1
    fi
done
for argument in -catalog -cutout-bench -tour -onboarding -toasts-stay -animations -fixtures \
    -device-checks -make-old-store -migration-kill-at -migration-pause-at -seed-tryon -cloud-tryon; do
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

# Secrets (Phase 25a, SECURITY_STANDARD.md sections 3 and 4). Nothing sensitive in the app, ever.
# Matches are masked in the output, so a real key that slipped in doesn't land in a CI log.
key_patterns='sk-ant-[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{24,}|[sr]k_(live|test)_[A-Za-z0-9]{8,}|whsec_[A-Za-z0-9]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}|(dev|prod|preview|project):[a-z0-9:-]+\|[A-Za-z0-9+/=]{20,}|[a-z][a-z0-9+.-]*://[^/[:space:]@:]+:[^/[:space:]@]+@'
publishable_pattern='pk_(live|test)_[A-Za-z0-9]{10,}'
server_only_names='ANTHROPIC_API_KEY|CLERK_SECRET_KEY|NOOK_RESULT_KEY|NOOK_SUBJECT_PEPPER|NOOK_KILL_SWITCH|CONVEX_DEPLOY_KEY|CONVEX_DEPLOYMENT|BFL_API_KEY|OPENAI_API_KEY|APNS_KEY|R2_ACCESS_KEY|R2_SECRET'
provider_hosts='api\.anthropic\.com|api(\.[a-z]+)?\.bfl\.(ai|ml)|api\.openai\.com|api\.clerk\.com|api\.cloudflare\.com|[a-z0-9.-]+\.r2\.cloudflarestorage\.com'
debug_addresses='localhost|127\.0\.0\.1|0\.0\.0\.0|ngrok|\.local[:/]|https?://10\.|https?://192\.168\.'
cleartext_http='http://[A-Za-z0-9]'

mask() { sed -E 's/^(.{0,12}).*/\1... (masked)/'; }
secret_hits=0
scan_text() { # scan_text <label> <text> <allow publishable key: yes|no>
    local label="$1" text="$2" allow_pk="$3" hits
    hits="$(grep -aoE "$key_patterns" <<<"$text" | mask || true)"
    if [[ -n "$hits" ]]; then
        echo "Release app has what looks like a secret in $label:" >&2
        echo "$hits" | sort -u | head -5 >&2
        secret_hits=1
    fi
    if [[ "$allow_pk" == no ]] && grep -qaE "$publishable_pattern" <<<"$text"; then
        echo "Release app has a Clerk publishable key outside Info.plist in $label" >&2
        secret_hits=1
    fi
    for group in "server-only setting name:$server_only_names" "provider address:$provider_hosts" "debug address:$debug_addresses"; do
        if grep -qaE "${group#*:}" <<<"$text"; then
            echo "Release app has a ${group%%:*} in $label (the app calls only our own gateway)" >&2
            grep -aoE "${group#*:}" <<<"$text" | sort -u | head -3 >&2
            secret_hits=1
        fi
    done
    # Plain http:// in the app (Apple's plist DTD and the W3C and Swift schema names are text, not requests).
    local plain
    plain="$(grep -aoE "${cleartext_http}[^[:space:]\"<>]*" <<<"$text" | grep -vE '^http://(www\.apple\.com/DTDs|www\.w3\.org|swift\.org|ns\.adobe\.com|purl\.org)' || true)"
    if [[ -n "$plain" ]]; then
        echo "Release app has a plain http:// address in $label:" >&2
        echo "$plain" | sort -u | head -3 >&2
        secret_hits=1
    fi
}

scan_text "the binary" "$text" no
while IFS= read -r -d '' file; do
    [[ "$file" == "$binary" ]] && continue
    if [[ "$(basename "$file")" == Info.plist ]]; then
        plist="$(plutil -p "$file")"
        scan_text "Info.plist" "$plist" yes
        # An Info.plist key that is named like a secret is a mistake even when its value is empty.
        if grep -qiE '^\s*"[^"]*(secret|password|private[_-]?key|api[_-]?key|credential|access[_-]?token)[^"]*" =>' <<<"$plist"; then
            echo "Release app's Info.plist has a key named like a secret" >&2
            secret_hits=1
        fi
    else
        scan_text "${file#"$app"/}" "$(strings -a "$file")" no
    fi
done < <(find "$app" -type f -print0)
key_files="$(find "$app" \( -name '.env*' -o -name '*.p8' -o -name '*.p12' -o -name '*.pem' -o -name '*.key' -o -name '*.xcconfig' -o -iname '*secret*' -o -iname '*credential*' \) 2>/dev/null)"
if [[ -n "$key_files" ]]; then
    echo "Release app contains key or config files:" >&2
    echo "$key_files" >&2
    secret_hits=1
fi
[[ $secret_hits -eq 0 ]] || failed=1

if [[ $failed -ne 0 ]]; then
    exit 1
fi
echo "Release app has no catalog, benchmark, snapshot-testing code, sample data code, sample photos or secrets"
