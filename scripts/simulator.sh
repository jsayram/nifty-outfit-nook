#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator, or an iPad one with NOOK_SIM_FAMILY=iPad.
#
# Picks the newest iOS runtime whose version starts with NOOK_SIM_OS (default 26.5),
# preferring NOOK_SIM_NAME (default "iPhone 17", or "iPad Pro 11-inch (M5)" for an iPad) and
# falling back to any device of the family.
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
family = os.environ.get("NOOK_SIM_FAMILY", "iPhone")
if family not in ("iPhone", "iPad"):
    sys.exit("NOOK_SIM_FAMILY must be iPhone or iPad")
default_name = "iPhone 17" if family == "iPhone" else "iPad Pro 11-inch (M5)"
wanted_name = os.environ.get("NOOK_SIM_NAME", default_name)
prefix = "com.apple.CoreSimulator.SimRuntime.iOS-"

def version(runtime):
    return tuple(int(part) for part in runtime[len(prefix):].split("-"))

runtimes = [
    runtime for runtime in json.load(sys.stdin)["devices"].items()
    if runtime[0].startswith(prefix)
    and ".".join(map(str, version(runtime[0]))).startswith(wanted_os)
]
for _, devices in sorted(runtimes, key=lambda item: version(item[0]), reverse=True):
    matching = [device for device in devices if device["name"].startswith(family)]
    exact = [device for device in matching if device["name"] == wanted_name]
    if exact or matching:
        print((exact or matching)[0]["udid"])
        sys.exit(0)
sys.exit("No available " + family + " simulator for iOS " + wanted_os)
'
