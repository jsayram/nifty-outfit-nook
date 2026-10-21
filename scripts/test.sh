#!/usr/bin/env bash
# Runs every test: the NookKit package tests and the UI tests, on an iPhone simulator.
# See scripts/simulator.sh for how the simulator is chosen. NOOK_SIM_FAMILY=iPad picks an iPad
# instead, for the iPad UI tests (Phase 15a, docs/ipad.md):
#   NOOK_SIM_FAMILY=iPad scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests
#
# Usage: scripts/test.sh [xcodebuild test selection...]
# With no arguments it runs the whole test plan. Arguments go to `xcodebuild test-without-building`,
# so CI can split the suite, for example:
#   scripts/test.sh -skip-testing:NiftyOutfitNookUITests          # package tests only
#   scripts/test.sh -only-testing:NiftyOutfitNookUITests/HomeTests # one UI test class
#
# NOOK_TEST_PLAN picks another test plan in the scheme. UITests.xctestplan holds only the UI tests,
# so a run that tests only them doesn't build the package test targets, which took about half of
# build-for-testing (CI uses it for the UI parts):
#   NOOK_TEST_PLAN=UITests scripts/test.sh -only-testing:NiftyOutfitNookUITests/HomeTests
#
# On CI the build and the test runs can happen on different runners:
#   NOOK_BUILD_ONLY=1 scripts/test.sh                   builds for testing, and doesn't test
#   NOOK_XCTESTRUN=<file>.xctestrun scripts/test.sh ... tests what that build made, without building
# (see .github/workflows/ci.yml).
#
# NOOK_PR_RUN=1 marks a pull request's CI run. The UI tests that a pull request doesn't need
# (their behaviour is covered by package tests, or they repeat another test's screens at another
# text size) skip themselves then, and run on merges to develop and main, nightly, and locally.
# See UITestTier in NiftyOutfitNookUITests/UITestSupport.swift.
#
# NOOK_PARALLEL_WORKERS=<n> runs the tests on <n> cloned simulators at once. Off by default.
#
# Otherwise it builds once with build-for-testing, then tests without building, and prints how
# long each step took. xcodebuild boots the simulator itself: waiting for a full boot first with
# `simctl bootstatus` took 2 to 4 minutes on CI, against about a minute for xcodebuild's own boot.
set -euo pipefail
cd "$(dirname "$0")/.."

simulator_id="$(scripts/simulator.sh)"

# On CI (GitHub Actions sets CI), tell the tests so the speed checks allow for a slower, shared
# runner. xcodebuild passes TEST_RUNNER_* variables to the tests without the prefix.
if [[ -n "${CI:-}" ]]; then
    export TEST_RUNNER_NOOK_CI=1
fi
if [[ -n "${NOOK_PR_RUN:-}" ]]; then
    export TEST_RUNNER_NOOK_PR_RUN=1
fi
result_bundle="${NOOK_RESULT_BUNDLE:-build/TestResults.xcresult}"
echo "Testing on simulator $simulator_id"

common=(
    -project NiftyOutfitNook.xcodeproj
    -scheme NiftyOutfitNook
    -destination "id=$simulator_id"
    -derivedDataPath build/DerivedData
    -onlyUsePackageVersionsFromResolvedFile
)
if [[ -n "${NOOK_TEST_PLAN:-}" ]]; then
    common+=(-testPlan "$NOOK_TEST_PLAN")
fi

if [[ -n "${NOOK_XCTESTRUN:-}" ]]; then
    # The products and the .xctestrun file describing them came from an earlier build.
    common=(-xctestrun "$NOOK_XCTESTRUN" -destination "id=$simulator_id")
else
    SECONDS=0
    xcodebuild build-for-testing "${common[@]}" -quiet
    echo "Built for testing in ${SECONDS}s"
    if [[ -n "${NOOK_BUILD_ONLY:-}" ]]; then
        exit 0
    fi
fi

extra=()
if [[ -n "${CI:-}" ]]; then
    # When a test fails, xcodebuild by default asks the simulator for a sysdiagnose, and on a
    # hosted runner that has waited the full 600 seconds before reporting the failure ("Failure
    # collecting diagnostics from simulator: Timed out after 600.0 seconds"). That was 9 of 9
    # failed test jobs in the 11 runs before 21 October 2026. The result bundle still has the
    # screenshots and the activity of the failed test.
    extra+=(-collect-test-diagnostics never)
fi
if [[ -n "${NOOK_PARALLEL_WORKERS:-}" ]]; then
    extra+=(-parallel-testing-enabled YES -parallel-testing-worker-count "$NOOK_PARALLEL_WORKERS"
        -maximum-parallel-testing-workers "$NOOK_PARALLEL_WORKERS")
fi

# Whether the test run ended because the runner never got going, as opposed to a test failing:
# not one test case was reported, and xcodebuild named a start-up problem. The hosted simulator
# does this now and then ("Timed out waiting for AX loaded notification", "Early unexpected
# exit, operation never finished bootstrapping"). A real failure has a failed test case and
# never matches.
runner_never_started() {
    ! grep -q "Test Case '" "$1" &&
        grep -qE 'Early unexpected exit, operation never finished bootstrapping|failed to initialize for UI testing|Timed out waiting for AX loaded notification' "$1"
}

run_tests() {
    rm -rf "$result_bundle"
    xcodebuild test-without-building "${common[@]}" -resultBundlePath "$result_bundle" ${extra[@]+"${extra[@]}"} "$@"
}

SECONDS=0
status=0
log="$(mktemp)"
run_tests "$@" 2>&1 | tee "$log" || status=$?
if [[ $status -ne 0 && -n "${CI:-}" ]] && runner_never_started "$log"; then
    echo "The test runner never started (no test ran). Restarting the simulator and trying once more."
    xcrun simctl shutdown "$simulator_id" || true
    status=0
    run_tests "$@" || status=$?
fi
rm -f "$log"
echo "Tested in ${SECONDS}s"
exit $status
