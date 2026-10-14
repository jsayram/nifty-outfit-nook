#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator.
#
# Picks the newest iOS runtime whose version starts with NOOK_SIM_OS (default 26.5),
# preferring NOOK_SIM_NAME (default "iPhone 17") and falling back to any iPhone.
# The default runtime is pinned because the snapshot test references were recorded on it
# (see Packages/NookKit/Sources/DesignSystem/README.md, "Snapshot tests").
# Set NOOK_SIM_ID to skip the search and use a specific simulator.
set -euo pipefail

if [[ -n "${NOOK_SIM_ID:-}" ]]; then
    echo "$NOOK_SIM_ID"
    exit 0
fi

xcrun simctl list devices available --json | python3 -c '
import json, os, sys

wanted_os = os.environ.get("NOOK_SIM_OS", "26.5")
wanted_name = os.environ.get("NOOK_SIM_NAME", "iPhone 17")
prefix = "com.apple.CoreSimulator.SimRuntime.iOS-"

def version(runtime):
    return tuple(int(part) for part in runtime[len(prefix):].split("-"))

runtimes = [
    runtime for runtime in json.load(sys.stdin)["devices"].items()
    if runtime[0].startswith(prefix)
    and ".".join(map(str, version(runtime[0]))).startswith(wanted_os)
]
for _, devices in sorted(runtimes, key=lambda item: version(item[0]), reverse=True):
    iphones = [device for device in devices if device["name"].startswith("iPhone")]
    exact = [device for device in iphones if device["name"] == wanted_name]
    if exact or iphones:
        print((exact or iphones)[0]["udid"])
        sys.exit(0)
sys.exit("No available iPhone simulator for iOS " + wanted_os)
'
