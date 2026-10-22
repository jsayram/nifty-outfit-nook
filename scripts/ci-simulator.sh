#!/usr/bin/env bash
# CI on the self-hosted runner only: makes this job's own simulator, and deletes it afterwards.
# Usage: scripts/ci-simulator.sh create <iPhone|iPad>   prints the new simulator's UDID
#        scripts/ci-simulator.sh delete <udid>
#
# The self-hosted runner is Jose's Mac, and other people and agents use its simulators, so a job
# never boots or reuses one of those. It makes a simulator named nook-ci-..., and deletes only
# that one. Nothing here shuts down or deletes any other simulator, with one exception: a
# nook-ci- simulator (or a clone of one) left behind by an earlier job that was killed before its
# cleanup step ran. The runner runs one job at a time, so any other nook-ci- simulator is stale.
#
# The runtime is iOS 27.0 (NOOK_SIM_OS to change it): the snapshot test references were
# recorded on it (Packages/NookKit/Sources/DesignSystem/README.md, "Snapshot tests"). It must
# already be installed: this never downloads a runtime. The iPhone is an iPhone 12 and the iPad
# an iPad Pro 11-inch (M5); NOOK_CI_IPHONE and NOOK_CI_IPAD name other device types.
set -euo pipefail

prefix="nook-ci-"

case "${1:-}" in
create)
    family="${2:?usage: scripts/ci-simulator.sh create <iPhone|iPad>}"
    # Stale ones first (see above).
    xcrun simctl list devices -j | python3 -I -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if "'"$prefix"'" in device["name"]:  # also "Clone 1 of nook-ci-..."
            print(device["udid"])
' | while read -r stale; do
        echo "Deleting stale simulator $stale" >&2
        xcrun simctl shutdown "$stale" > /dev/null 2>&1 || true
        xcrun simctl delete "$stale" >&2
    done

    runtime_and_type="$(
        xcrun simctl list runtimes -j | FAMILY="$family" python3 -I -c '
import json, os, sys

family = os.environ["FAMILY"]
wanted_os = os.environ.get("NOOK_SIM_OS", "27.0")
wanted_type = os.environ.get("NOOK_CI_IPHONE", "iPhone 12") if family == "iPhone" \
    else os.environ.get("NOOK_CI_IPAD", "iPad Pro 11-inch (M5)")
if family not in ("iPhone", "iPad"):
    sys.exit("family must be iPhone or iPad")
runtimes = [
    r for r in json.load(sys.stdin)["runtimes"]
    if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
    and r["version"].startswith(wanted_os)
]
if not runtimes:
    sys.exit("iOS " + wanted_os + " is not installed. Install the runtime in Xcode; CI never downloads one.")
runtime = sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])[-1]
types = [t for t in runtime["supportedDeviceTypes"] if t["name"] == wanted_type]
if not types:
    sys.exit(wanted_type + " is not a device type of " + runtime["name"])
print(runtime["identifier"], types[0]["identifier"])
'
    )"
    read -r runtime device_type <<< "$runtime_and_type"
    name="${prefix}${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-${GITHUB_JOB:-job}-$$"
    udid="$(xcrun simctl create "$name" "$device_type" "$runtime")"
    echo "Created simulator $name ($udid) on $runtime" >&2
    echo "$udid"
    ;;
delete)
    udid="${2:?usage: scripts/ci-simulator.sh delete <udid>}"
    name="$(xcrun simctl list devices -j | UDID="$udid" python3 -I -c '
import json, os, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["udid"] == os.environ["UDID"]:
            print(device["name"])
')"
    if [[ -z "$name" ]]; then
        echo "Simulator $udid is already gone."
        exit 0
    fi
    if [[ "$name" != "$prefix"* ]]; then
        echo "Refusing to delete $udid: its name is \"$name\", not one this script made." >&2
        exit 1
    fi
    xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
    xcrun simctl delete "$udid"
    echo "Deleted simulator $name ($udid)"
    ;;
*)
    echo "usage: scripts/ci-simulator.sh create <iPhone|iPad> | delete <udid>" >&2
    exit 2
    ;;
esac
