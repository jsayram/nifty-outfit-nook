# Private iCloud sync

Built in Phase 21b (22 October 2026) against a stand-in for CloudKit, and **off**: no build shows it until the switch below is on. The design and its reasons are in `docs/decisions/0004-backup-and-recovery.md` §5 and §6; this page is how it's built and how to turn it on.

## What she gets

An **iCloud** row on Profile and in Privacy and terms (Your data), only in a build made with `NOOK_ICLOUD = YES`:

- **Keep a copy in iCloud**, off by default. Turning it on asks first, with 0004's wording (who can read it, Advanced Data Protection, the space it takes) and the line that measurements, weight, fit notes and the try-on photo stay on the iPhone. Turning it off asks: **Keep my iCloud copy** or **Also delete my iCloud copy**. Local data always stays.
- **Status**: Saved on this iPhone; Waiting to upload, with counts; Everything here is in iCloud (only when nothing waits and nothing failed); Last confirmed by iCloud; Couldn't upload with the reason and Try again (or Open Settings when her storage is full).
- **Questions** when iCloud changed under the app, with 0004's choices: signed out, a different account, deleted in Settings, turned off on another device, Delete my data on another device.
- **Notes**: changes kept for review after a conflict, records from a newer app version waiting for an update, and the re-upload after an encrypted data reset.
- **Delete my data** deletes her iCloud copy first, then the iPhone (both Delete my data and Delete my account).

Not built yet, and why: the safety copy before the first merge with Undo iCloud merge (0004 §1; needs its own small screen), a screen to review conflicts (only a count for now, decision 7), the onboarding step and Get my closet from iCloud (decision 5). There's no switch for body data on screen: since decision 2 (Phase F1) it syncs with everything, and the fallback is a line of code.

## How it works

| Part | Where | What it does |
|---|---|---|
| `ICloudSync` | `Services/Sync/ICloudSync.swift` | The app's side of the engine: what to send, merging what arrives, account and zone events, Delete my data |
| `CloudKitSyncEngine` | `Services/Sync/CloudKitSyncEngine.swift` | A thin wrapper over `CKSyncEngine`, and the `CKRecord` mapping. Only translates |
| `SyncEngineDriving`, `SyncEngineDelegate` | `Services/Sync/SyncEngine.swift` | The protocol between them, in CloudKit's terms without CloudKit types |
| `SyncPolicy` | `Services/Sync/SyncPolicy.swift` | 0004's table of account events, as a pure state machine |
| `SyncMerge`, `SyncCodec` | `Services/Sync/SyncMerge.swift` | The conflict rules per record type |
| `SyncSchema` | `Services/Sync/SyncSchema.swift` | Which kinds sync, record names, zones, body data, `SyncGeneration` |
| Bookkeeping | `Services/Sync/SyncBookkeeping.swift` | Sync's rows in the store: ledger, per-record system fields and ancestor, held records, conflicts, pending deletion |
| The iCloud screen | `Features/Settings/ICloud` | `ICloudScreen`, `ICloudModel`, `ICloudText` |
| The switch | `NiftyOutfitNook/AppICloud.swift` | Makes and starts the engine when `NookICloudEnabled` is YES |

**Records.** Each synced store row is one CloudKit record named `<kind>.<key>` (such as `garment.<uuid>`), never anything she typed. The payload is the row's JSON exactly as stored, with its payload version, in `encryptedValues` with a tombstone flag. Nothing else is a field: no references, no plain values. Photos are `Image` records named by the photo's ID, a `CKAsset` each, written once and deleted when nothing points to them. Record types: `Garment`, `Look`, `Suitcase`, `TryOnPicture`, `Profile`, `Draft`, `AppState` (onboarding and tours), `StylistThread`, `Image`, `Body`, `SyncGeneration`.

**Zones.** `Closet` for everything she makes; `Me` for body data (measurements, weight, usual fit, pieces that fit, the try-on photo and its image), written since decision 2 was answered on 29 October 2026 (D11: sync everything; Phase F1), with `SyncSchema.syncsBodyData` as the one-line fallback if App Review 5.1.3(ii) rejects it; `Control` for one content-free `SyncGeneration` (a number, a reason, a date) that tells other devices why a zone was deleted. The profile goes to `Closet` with its body data taken out.

**Not synced:** the unsent feedback note, AI jobs in progress, copies kept from a restore, deletion markers (tombstones carry them), thumbnails and caches, and sync's own rows.

**What to send** is worked out from the store each time, not remembered: a row whose value differs from the version both sides last agreed on (its ancestor), a row that went (a tombstone), a photo iCloud doesn't have, a photo this device used that nothing points to now. So an engine reset (every account change), a crash between a save and its bookkeeping, or a restore all end the same way. Values are compared decoded, since JSON from sets isn't byte-stable.

**Conflicts.** Three-way: pieces field by field (removal and restriction win, wear days are a set), suitcases field by field (memberships are a set), everything else as a whole record. The server's version wins otherwise, and what lost is kept as a `syncConflict` row for review. A piece deleted for good stays deleted everywhere: its tombstone wins, an edit from a stale device is dropped and reported, the receiving device writes a deletion marker and removes the photos at once (also from the restore's safety copy, 22b).

**Versions.** A record from a newer payload version than the build reads is held as it came (`syncHeld`), never applied and never overwritten; the status says to update. After an update, the next launch applies it, and a local edit made meanwhile is kept for review. The CloudKit schema never changes for a new payload version.

**Accounts.** Nothing is sent unless sync is on and the account signed in at that moment is the one the closet belongs to (hashed in the ledger). That's checked before every batch, whatever order the engine's events come in. A different account pauses sync until she chooses Copy it to this account or Keep it on this iPhone.

**Restored devices.** A random marker sits in the Keychain (`WhenUnlockedThisDeviceOnly`) and in the ledger. A ledger whose marker the Keychain doesn't hold came from a device backup: its engine state and change tags are dropped and everything is fetched and merged by ID.

**Writes from iCloud** go through the store actor that owns the kind when that actor keeps values in memory (pieces, looks, suitcases, try-on pictures), so her edits and remote changes never interleave and the actor forgets its cache; other kinds are written in sync's own context. Local saves post `StoreSaveSignal`; the app looks for changes 3 seconds after edits settle and whenever it comes forward, and `CKSyncEngine` also syncs on its own, woken by CloudKit's silent pushes.

## Turning it on (Jose)

1. **Apple Developer** > Certificates, Identifiers & Profiles:
   - Identifiers > iCloud Containers > **+** > `iCloud.com.jsayram.niftyoutfitnook`, description "Nifty Outfit Nook". A container can't be deleted or renamed later.
   - Identifiers > App IDs > `com.jsayram.niftyoutfitnook`: tick **iCloud** (choose CloudKit support, then Configure and pick the container) and **Push Notifications**. Save. Xcode's automatic signing picks the change up at the next build.
2. Set `NOOK_ICLOUD = YES` in `Configs/Secrets.xcconfig` (ignored by git, so it applies to builds from your Mac only). That one setting signs the app with the iCloud entitlements (`Configs/NiftyOutfit-ICloud*.entitlements`: the container, CloudKit, and `aps-environment`, development for Debug and production for Release; the WeatherKit copies carry both), adds the `remote-notification` background mode (preprocessed `Configs/AppInfo.plist`), and tells the app to show the iCloud row and run `CKSyncEngine` (`NookICloudEnabled`). With `NO` (the default) none of that is in the build.
3. In Xcode, Signing & Capabilities should show iCloud (CloudKit, the container) and Push Notifications. An entitlement error means step 1 isn't finished.
4. **Two test Apple Accounts** (decision 8), made at account.apple.com, not your own: **A** with Advanced Data Protection on, and **B** with its iCloud storage nearly full (fill it with a large file in iCloud Drive). Two devices: the iPhone 12 and an iPad (or a second iPhone), both signed in to A for the main tests.
5. **Make the schema in Development.** Run a Debug build on the device signed in to A and turn sync on. CloudKit creates each record type the first time one is saved, so exercise every kind: a piece with a photo, a look, a suitcase, a try-on picture, a draft (Add a piece, then leave it), an Ask stylist conversation, the tours switch, then Turn off with **Also delete my iCloud copy** (writes `SyncGeneration`) and turn it on again.
6. **Check it in the CloudKit Console** (icloud.developer.apple.com > CloudKit Database > the container > Development > Schema > Record Types). Every type should have exactly these custom fields: `payload` (Encrypted Bytes), `payloadVersion` (Encrypted Int(64)), `tombstone` (Encrypted Int(64)); `Image` has only `asset` (Asset). Anything plain other than an asset is a bug: stop and tell the iOS agent. No indexes are needed (the engine fetches zone changes and never queries). `Body` only appears if decision 2 allows the `Me` zone.
7. **Run the two-device test plan** below in Development, with ADP on and off. Results go in `closet/DEVICE_TEST_CHECKLIST.md`.
8. **Deploy to Production**: Console > Schema > Deploy Schema Changes. This can't be undone: a production schema only grows. TestFlight and App Store builds use Production.
9. When Production is deployed and the tests passed, set `NOOK_ICLOUD = YES` in `Configs/Base.xcconfig` so every build has it. That same change has to update `scripts/check-archive.sh`, which today fails a Release archive with any background mode or any entitlement beyond Data Protection: allow `remote-notification` and check the iCloud entitlements file instead. Also add the iCloud and push lines to the App Store privacy answers and `closet/compliance/` (the data map already lists the iCloud copy).

To turn it off again, set `NOOK_ICLOUD = NO`: the row disappears and nothing talks to CloudKit. Her iCloud copy stays until she deletes it.

## Tests

**Automated, in CI** (`ServicesTests/Sync`, `FeaturesTests/Settings/ICloudModelTests`), against `FakeCloudKit`, an in-memory stand-in that keeps CloudKit's rules: one private database per account, custom zones, a new change tag per save, `serverRecordChanged` with the server's record, `unknownItem`, `zoneNotFound`, `quotaExceeded`, a 1 MB record limit with assets kept apart, change tokens, the three ways a zone goes (deleted, purged, encrypted data reset), and offline. `FakeSyncEngine` plays `CKSyncEngine` on top: pending changes in its saved state, zones sent before records, batches asked of the delegate, events in order, and its state reset (with an account change event) when the device's account changes.

Two simulated devices: create (a piece and its photo, byte for byte), edit, delete for good (tombstone, deletion marker, photos gone, a stale device can't bring it back), whole-record kinds and a deleted suitcase, a conflict (different fields both land; the same field keeps the first, the other kept for review; dirty beats clean), offline edits on both then reconnecting in both orders (wear days from both, delivered again changes nothing), an account switch (nothing written to the other account, even after a relaunch, until she copies it there; back to her own account carries on), Keep on this iPhone, sign out and back in, deleted in Settings (pauses, asks, Upload it again, the other device's Delete it here too), turned off on another device, an encrypted data reset (re-upload), storage full (waits, then uploads), an 8 MB photo (its own asset, never inside the record, not sent again on edit), a record from a newer payload version (held, never overwritten, applied after the update, the local edit kept for review), body data staying on the device and, with decision 2's switch, going only to `Me`, a restored device starting fresh, and Delete my data online, offline (pending, runs first at the next launch, blocks turning on) and with a different account signed in. Plus the `CKRecord` mapping with real records (only system fields and an image's asset are plain; `payload`, `payloadVersion` and `tombstone` encrypted; no references), the error mapping, the merge rules and every row of the account table.

**On devices with iCloud** (Jose, after step 7; also in `closet/DEVICE_TEST_CHECKLIST.md`):

- Two devices on account A: turn on with an empty and a full closet; edits offline on both, reconnect in both orders; delete for good on one; Delete my data with the iPad offline; turn off with and without deleting the copy.
- ADP on and off: encrypted fields and photos read back on the second device; the Console shows the encrypted field types.
- Sign out, switch to account B (nothing appears in B until Copy it to this account), storage nearly full on B, delete the app's data in Settings > [name] > iCloud, and a push waking the iPad while it's locked.
- A restore from a device backup (iCloud Backup and a Mac): sync starts fresh, nothing is lost or duplicated.
- A reinstall after deleting the app: turning sync on brings the closet back.
- `encryptedDataReset` probably can't be triggered on purpose; it's covered by the stand-in only.
