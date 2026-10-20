#!/usr/bin/env bash
# Phase 20a persistence spike: real SIGKILLs during a SwiftData migration, on macOS.
#
# The iOS tests stop a migration by throwing at each checkpoint. That shows the recovery logic,
# but a thrown error lets Core Data clean up. This script kills a real process instead:
#   1. at every checkpoint, the process sends itself SIGKILL;
#   2. twice in a row, killed again while recovering from the first kill;
#   3. at random moments from outside, with kill -9, including in the middle of SQLite writes.
# After each kill it opens the store again, as the next launch would, and checks every ID, count,
# image hash and relationship against the manifest taken before the migration.
#
# Usage: Packages/NookKit/Tests/PersistenceSpikeTests/KillHarness/run.sh [garments] [random kills]
# Defaults: the large fixture's 2,400 garments (300 photos) and 40 random kills. Not run by CI.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
garments="${1:-2400}"
random_kills="${2:-40}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# -Onone: built with -O, setting the task-local checkpoint handler crashed in
# swift_task_localValuePushImpl (Xcode 26.6, macOS 26). The spike code isn't shipped, and the
# migration itself runs in the system frameworks either way.
xcrun swiftc -swift-version 6 -Onone -target arm64-apple-macos26.0 -parse-as-library -module-name SpikeKill \
    "$here"/../Spike/*.swift "$here"/*.swift -o "$work/spike-kill"
bin="$work/spike-kill"

"$bin" seed "$work/template" "$garments" >/dev/null
"$bin" manifest "$work/template" "$work/manifest.json"

passed=0
failed=0

# Opens the trial store as the next launch would, and checks it.
check() {
    local label="$1"
    local opened
    if ! opened="$("$bin" open "$work/trial" | tail -1)"; then
        echo "FAIL $label: reopening gave: $opened"
        failed=$((failed + 1))
        return
    fi
    local verdict
    verdict="$("$bin" verify "$work/trial" "$work/manifest.json" || true)"
    if [[ "$verdict" == "OK" ]]; then
        passed=$((passed + 1))
        echo "ok   $label ($opened)"
    else
        failed=$((failed + 1))
        echo "FAIL $label: $verdict"
    fi
}

fresh_trial() {
    rm -rf "$work/trial"
    cp -R "$work/template" "$work/trial"
}

# Every checkpoint the migration passes, in order, from an unkilled run.
fresh_trial
checkpoints=()
while IFS= read -r line; do
    checkpoints+=("${line#checkpoint }")
done < <("$bin" open "$work/trial" | grep '^checkpoint ')
echo "${#checkpoints[@]} checkpoints"

# 0. SwiftData alone, for comparison: killed during the custom stage, then opened again.
fresh_trial
"$bin" raw "$work/trial" didMigrate.batch.6 >/dev/null 2>&1 || true
photos="$(grep -o '"g-[0-9]*":"' "$work/manifest.json" | wc -l | tr -d ' ')"
echo "SwiftData alone, killed at didMigrate.batch.6 then reopened: $("$bin" raw "$work/trial") of $photos photos"

# 1. SIGKILL at each checkpoint.
for checkpoint in "${checkpoints[@]}"; do
    fresh_trial
    "$bin" open "$work/trial" "$checkpoint" >/dev/null 2>&1 && echo "note: $checkpoint was not reached"
    check "killed at $checkpoint"
done

# 2. Killed again while recovering: the first kill mid-migration, the second at each later
#    checkpoint of the rerun.
for second in didMigrate.batch.1 didMigrate.batch.6 migration.finished journal.migrated; do
    fresh_trial
    "$bin" open "$work/trial" didMigrate.batch.4 >/dev/null 2>&1 || true
    "$bin" open "$work/trial" "$second" >/dev/null 2>&1 || true
    check "killed at didMigrate.batch.4, then at $second"
done

# 3. kill -9 from outside at a random moment of the first second and a half, where the
#    snapshot, the migration and the hashing all happen.
for ((index = 1; index <= random_kills; index++)); do
    fresh_trial
    delay_ms=$((RANDOM % 1600))
    "$bin" open "$work/trial" >/dev/null 2>&1 &
    pid=$!
    sleep "$(awk "BEGIN { print $delay_ms / 1000 }")"
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    journal="none"
    if [[ -f "$work/trial/MigrationJournal.json" ]]; then
        journal="$(sed -E 's/.*"step":"([a-zA-Z]+)".*/\1/' "$work/trial/MigrationJournal.json")"
    fi
    check "kill -9 after ${delay_ms} ms (journal: $journal)"
done

echo "passed $passed, failed $failed"
[[ $failed -eq 0 ]]
