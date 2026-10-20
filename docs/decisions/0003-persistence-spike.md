# 0003. Persistence spike: SwiftData with a migration journal and CKSyncEngine

Status: **recommendation, waiting for Jose** (Phase 20a checkpoint)
Date: 20 October 2026
Plan: `closet/SWIFT_BUILD_PLAN.md`, Phase 20a. Rules: PRD 11.7, `closet/SECURITY_STANDARD.md` §4 and §10, `closet/STAGE_B_DATA_OPTIONS.md` (the four gates), `closet/THREAT_MODEL.md` D8(d).

Checked with Xcode 27.1 (Swift 6.4) on macOS 27.0.1. The tests ran on an iPhone 12 simulator with iOS 26.5 (the base device); CI runs them on iOS 27.0. The kill harness ran on the Mac.

## Recommendation: GO on SwiftData, with three conditions

SwiftData passed every gate the spike could test without an iCloud account. It isn't safe on its own, though. The app has to wrap it in three things it doesn't provide:

1. **A migration journal and a recovery snapshot around every schema change.** SwiftData's custom migration stages aren't atomic. Killed halfway through, a store comes back already marked as the new version but holding only some of the migrated data, and the next launch opens it as if nothing happened. The spike's coordinator (journal, snapshot, manifest, verify, roll back) fixed this in every one of 64 real kills.
2. **`CKSyncEngine` for sync, never SwiftData's own CloudKit mirroring.** The merge rules PRD 11.7 asks for need our code to see each conflict. They're pure functions here and pass in both reconnect orders.
3. **Value types only outside the store.** Each store is a `@ModelActor` that hands out `Garment`, `Look` and `Suitcase` values, as the in-memory stores do now. Model objects never leave it.

If Jose prefers a store we control end to end, the runner-up is still GRDB (a dependency needing his written approval) or plain Core Data. Nothing the spike found requires that.

## What the spike built

All of it is test code in `Packages/NookKit/Tests/PersistenceSpikeTests`. Nothing ships, and the app's behaviour doesn't change.

| Part | Files | What it does |
|---|---|---|
| Versioned schemas | `Spike/SpikeSchemas.swift` | V1 (Stage A's garment), V2 (lightweight: a revision with a default, a new date, a renamed field), V3 (custom: an image record per photo, hashed from the file on disk, saved in batches of 200) |
| Fixtures | `Spike/SpikeSeed.swift` | V1 stores of any size with real photo-sized files. The large one matches the large closet: 2,400 garments, 300 photos, 600 looks, 40 suitcases |
| Migration coordinator | `Spike/SpikeMigrationCoordinator.swift` | Reads the version from the store's metadata, checks free space, journals each step, snapshots, records a manifest (IDs, counts, image hashes), migrates, verifies, rolls back, stops after three failed tries, and deletes the snapshot seven days after a verified upgrade |
| Kill harness | `KillHarness/run.sh` | Builds the coordinator as a Mac tool and kills it with SIGKILL at every step, twice in a row, and at random moments |
| Stores | `Store/SpikeStores.swift` | SwiftData closet, look and suitcase stores behind the app's protocols |
| Files | `Store/SpikePhotoLibrary.swift`, `Store/SpikeArchive.swift` | Record and file linking, a launch-time sweep, and an export with the original photos plus a restore that checks everything first |
| Sync | `Sync/SpikeMergeRules.swift`, `Sync/SpikeSync.swift`, `Sync/SpikeCloudKitMapping.swift` | The merge rules, two offline devices against a stand-in CloudKit zone, and a garment as a `CKRecord` |

## Evidence

### The four gates from STAGE_B_DATA_OPTIONS.md

| Gate | Result |
|---|---|
| Passes every store contract suite | The SwiftData closet, look and suitcase stores pass all 28 contract checks on a real store file. Every demo garment and 300 large-closet garments round-trip field for field. These three are the stores with lists, references and unique names. The profile, drafts, pictures, tours and onboarding stores hold one record or a few flags, so they weren't built in the spike |
| A staged migration over the large fixture survives a forced kill at each step | **Passed with the coordinator, failed without it.** See below |
| 2,400 garments load off the main actor without a stall | The first read from a fresh container took 0.27 to 0.85 s and later reads about 0.26 to 0.30 s (Debug, iOS 26.5 simulator, other suites running at the same time). The load runs on the store's actor, never on the main thread (checked with `pthread_main_np`). The main actor's longest gap during the load was 3 to 43 ms when it ran alone, and up to 143 ms with the package's other suites in the same run. On CI's iPad simulator (iOS 27.0), one cold read took 4.8 s with a 5 s main-actor gap at the same moment, which looks like the whole test process stalling on a busy runner rather than the store, so the gap is recorded but not bounded. Speed on the iPhone 12 itself is still to measure |
| No crash over 1,000 rapid saves from two actors | 1,000 inserts, one save each, from two actors with their own contexts on one store, while both kept changing the same 20 pieces: 0.8 to 1.6 s, no failed saves, 1,020 records, no duplicates |

### Migrations (PRD 11.7)

- **SwiftData alone leaves a half-migrated store.** Killed with SIGKILL after six of twelve batches of the V2 to V3 stage, the store reopened as V3 with 150 of 300 image records, and opening it again didn't rerun the stage. The iOS test `swiftDataAloneLeavesAHalfMigratedStoreThatOpensAsDone` shows the same with a thrown error (100 of 113). Core Data logs "Attempting recovery" but doesn't roll the store back.
- **With the coordinator, every kill recovered.** The harness killed the 2,400-garment migration at each of its 20 checkpoints (journal, snapshot, each of 12 batches, finish, verify), four times twice in a row, and 40 times at random moments with `kill -9`. All 64 runs reopened to a store matching the manifest: every ID, count, image hash and relationship. A full migration takes about 1.8 s on the Mac.
- **A newer store is left alone.** SwiftData refuses to open a store newer than its migration plan (`loadIssueModelContainer` on iOS 26.5, `unknownDataStoreSchema` on iOS 27.0) and leaves the file as it was. The coordinator spots an unknown version from the metadata before opening anything and goes to the recovery path, never a reset.
- **Rollback works.** A photo file that disappears during a migration fails verification, the snapshot goes back, and the store is V1 again with every record. Not enough free space stops before anything changes.
- **Restore before opening anything.** On CI, putting the snapshot back in the same process that had just opened the store failed with SQLITE_BUSY: the released container still held its connection for a moment. The spike retries a few times, but the real coordinator should restore at launch, before any container exists, and after a failed verification should mark the journal and let the next launch restore.
- **A gotcha for fixtures:** once a process has opened a newer schema, SwiftData maps every model named `GarmentRecord` to the newest entity, and saving an old-version object crashes ("not key value coding-compliant for the key colorNote"). The app never makes old-version objects, so only test fixtures need to write old stores through Core Data, as `SpikeSeed` does.

### Images and export (PRD 11.7)

- A file is written whole (temporary file and rename) before the record that points to it, and removed after its record. A crash in between can only leave a file nobody points to, and the launch sweep deletes it. Tests kill at each step.
- A file lost outside the app is kept on its record as `missing`, and a file whose hash changed as `damaged`. Neither is dropped silently.
- An export holds a consistent copy of the store, every original photo and a manifest of hashes. It restores into a wiped app, including a V1 export that migrates on open. A damaged photo in the archive stops the restore before anything is copied. Encrypting the export is Phase 20b's design (SECURITY_STANDARD.md §4).

### Two offline devices (PRD 11.7)

Each scenario edits on both devices offline, then reconnects in both orders, and checks both devices and the server end up the same, with no duplicates:

- Edits to different fields both land, with no conflict.
- The same field changed on both keeps the first value to reach the server and keeps the other as a conflict to review. No device clock decides.
- Recently deleted on one device and edited on the other: it stays deleted, and the edit to another field isn't lost.
- Unavailable beats available, dirty beats clean and no longer owned beats owned, each with the other value kept for review.
- Wear days from both devices are all kept, and so are pieces added on both.
- A piece deleted for good never comes back. An edit from the other device is reported, not silently dropped.
- A crash between applying fetched records and saving the new sync state leaves the state behind the records. The next fetch delivers the same changes again, and applying them twice changes nothing.
- Suitcase membership edits from both sides merge (a pure-function test).

A garment maps to a `CKRecord` in a custom zone with only the revision in the clear. Everything else is in `encryptedValues`. `allKeys()` lists the encrypted key too, but the plain subscript can't read it, and the record's system fields carry no content.

## D8(d): no Data Protection exception for the CKSyncEngine state

**Answer: the exception isn't needed.** Keep the sync state inside the SwiftData store, as a row, and don't write a separate state file.

- `CKSyncEngine` doesn't write a state file of its own. It hands the app a `State.Serialization` in each `stateUpdate` event, and that type is `Codable` (CloudKit's Swift interface, Xcode 27.1). Where it's stored, and with which protection class, is the app's choice.
- Stored as a row in the store, the state has exactly the store's protection (`complete`) and lives in the same SQLite file. The spike checks there's no other file.
- The state must never be ahead of the records it describes, or changes get skipped for good. Saved after the records, and under the same protection, a crash or a locked phone can only leave it behind, and CloudKit sends those changes again. A separate file with weaker protection (`completeUntilFirstUserAuthentication`) would be readable while the phone is locked when the store isn't, which is the one situation where the state could run ahead.
- So the sync engine starts only when protected data is available, the same moment the store can open. A background push while the phone is locked waits for the unlock, which costs nothing because the store couldn't take the changes anyway.

This needs one check on a real device (below): that the store and its `-wal` and `-shm` files really get `NSFileProtectionComplete`.

## Proven here, and what still needs a real device or iCloud account

| Proven in the spike | Needs a real device or iCloud account |
|---|---|
| Migrations, journal, snapshot, rollback, real SIGKILLs (on macOS, same frameworks) | A kill during migration on an iPhone, and a migration of a large store on the iPhone 12's A14 for timing |
| Store contracts, speed, concurrent saves (simulator) | Speed on the iPhone 12 itself |
| File protection set in code (`.completeFileProtection`) | The simulator doesn't enforce Data Protection. On a device: read `FileProtectionType` on the store, `-wal`, `-shm`, image files and journal, and check the store can't be opened while locked |
| Merge rules, two devices against a stand-in zone with CloudKit's change-tag rules | A real `CKSyncEngine` on two devices signed in to one iCloud account: `serverRecordChanged` payloads, push wake-ups, batching, account sign-out and switch, zone deletion, quota errors, and what Advanced Data Protection changes |
| `CKRecord` mapping with `encryptedValues` built locally | Encrypted fields saved and read back through CloudKit, and the schema in the CloudKit console before it's promoted |
| D8(d) reasoning and the state-in-store design | That the engine started after first unlock behaves when the app is woken while the phone is locked |

## Release builds and sample data

The plan's other 20a item, done in the same PR:

- The sample sets (demo, large, the sample wardrobe, the drawn samples and the drafts) and the `-fixtures` launch argument are compiled only in Debug. `scripts/check-release.sh` now checks their symbols and the argument aren't in a Release binary.
- That check had a bug: `nm ... | grep -q` under `pipefail` passed when it should have failed, because grep stops early and nm dies of SIGPIPE. It reads the output once now, and fails on the Debug binary as it should. `scripts/check-archive.sh` had the same pattern for build-machine paths and is fixed too.
- In Release, onboarding has three steps with no closet choice, "I already use Nifty Outfit Nook" opens an empty closet, Add a piece's photo stand-in gives no photo, and every piece shows its drawing. Debug is unchanged.
- **The sample photos still ship in Release (12 MB, unused).** SwiftPM copies the Fixtures resource bundle in every configuration, an override of `EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES` didn't take, and Xcode's script sandbox (`ENABLE_USER_SCRIPT_SANDBOXING`) stops a build script deleting it. Options for Jose: turn the sandbox off for the app target only, so a three-line script removes the bundle in Release, or move the photos out of the Fixtures package.

## For Jose

1. **GO or NO-GO on SwiftData**, with the three conditions above.
2. **TestFlight before Phase 21a.** A Release archive now starts with an empty closet and keeps nothing Lily adds, until real storage lands in 21a. Some wording still assumes sample data: the Help version line ("test build with sample data"), Help's "uses sample photos" line, and the What to Test text in `docs/testflight.md`. Choose between holding uploads until 21a and keeping the sample closet in TestFlight builds until then (reverting the Release part of this PR).
3. **The 12 MB of sample photos in Release:** turn the script sandbox off for the app target, move the photos, or leave them until 21a.
4. **D8(d):** no exception, if he agrees with the reasoning above.
