# 0002. Snapshot testing dependency

Status: **added** in Phase 2b, under the approval in decision 0001 item 8 (Jose, 13 October 2026)
Date: 14 October 2026
Security rules: `closet/SECURITY_STANDARD.md` section 3 (Dependencies).

Decision 0001 approved `swift-snapshot-testing` as a test-only dependency and left the exact version to this phase. These are the facts section 3 asks for, checked on 14 October 2026.

## What was added

| | |
|---|---|
| Package | `swift-snapshot-testing`, https://github.com/pointfreeco/swift-snapshot-testing |
| Version | **1.19.6** exactly (`exact: "1.19.6"` in `Packages/NookKit/Package.swift`), the latest stable release, published 21 September 2026 |
| Commit | `28e5de025e3fd98991791bfbf83023ab3708da03` (the `1.19.6` tag, a lightweight tag on that commit) |
| Product used | `SnapshotTesting` only |
| Linked into | the `DesignSystemTests` test target only |
| Lockfiles | `Packages/NookKit/Package.resolved` (SwiftPM, Dependabot) and `NiftyOutfitNook.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (Xcode, CI). Both committed; `scripts/check-package-pins.sh` fails CI if they disagree, and the build scripts pass `-onlyUsePackageVersionsFromResolvedFile` |

## Vetting

- **Maintainer.** Point-Free (Brandon Williams and Stephen Celis), who maintain a family of widely used Swift libraries. Releases come every few weeks to months; the latest fixes a crash on macOS 27. Not archived.
- **Usage.** About 4,400 stars and 680 forks on GitHub. It's the most common snapshot library for Swift and SwiftUI.
- **License.** MIT. Test-only, so nothing of it ships, and the licence has no effect on the app.
- **What it can access.** It runs only inside the test process on a simulator. It reads and writes PNG reference images in `Tests/DesignSystemTests/__Snapshots__` and, on a failure, writes the new image and a diff to `SNAPSHOT_ARTIFACTS` or the temporary folder. We checked the `SnapshotTesting` sources at this version: no networking, no process launching, no telemetry. Its `diffTool` setting only formats a command into the failure message.
- **Why not Apple.** Xcode has no reference-image comparison. The alternative was our own `ImageRenderer` comparison helper (record, compare with a tolerance, write diffs, file naming, record mode), which is more code to maintain. We do render with `ImageRenderer` ourselves (see the DesignSystem README) and use the library for storage, comparison and record mode.

## Packages resolved but not built

The library's manifest declares dependencies for its other products (inline snapshots and custom dump), so SwiftPM resolves and pins them even though our `SnapshotTesting` product doesn't use them. They are downloaded on resolve but **not compiled or linked** into anything of ours: the build products contain only `SnapshotTesting.o`.

| Package | Version | Maintainer | License |
|---|---|---|---|
| `swift-custom-dump` | 1.7.3 | Point-Free | MIT |
| `xctest-dynamic-overlay` | 1.13.1 | Point-Free | MIT |
| `swift-syntax` | 604.0.0 | Swift project (swiftlang) | Apache 2.0 |

## How we know it stays out of the app

- Only the `DesignSystemTests` target lists it in `Package.swift`. No library target does.
- `scripts/check-release.sh` runs in CI after the Release build and fails if the app binary contains any `SnapshotTesting` symbols or bundles a snapshot framework. The same script checks that the debug-only component catalog isn't in Release either.

## Updating it

Dependabot watches `Packages/NookKit`. To take a new version: read its release notes, change the exact version, resolve both lockfiles (commands in `scripts/check-package-pins.sh`), run `scripts/test.sh`, and update the version and commit above.
