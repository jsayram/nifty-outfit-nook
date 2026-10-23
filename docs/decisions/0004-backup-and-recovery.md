# 0004. Backup and recovery: safety copies, encrypted export, private iCloud sync

Status: **proposed, waiting for Jose** (Phase 20b checkpoint). Backups built in Phase 21b; see "Built in Phase 21b" below
Date: 20 October 2026
Plan: `closet/SWIFT_BUILD_PLAN.md`, Phase 20b. Builds on `0003-persistence-spike.md` (SwiftData with a migration journal, `CKSyncEngine`, value types only). Rules: PRD 11.7, 15.1, 15.2, 15.3 and 15.4; `closet/SECURITY_STANDARD.md` §1, §4, §9 and §10; `closet/THREAT_MODEL.md` R7, R15, F2 to F4, F12, D8 and D10; `closet/DATA_MAP.md`; `closet/compliance/` (P12 and R8 in the App Review checklist).

This is a design. Nothing here is built yet: Phase 21a builds the store and the safety copies, Phase 21b builds export, restore and sync, and runs the test plan at the end. Apple API facts were checked against Apple's documentation on 20 October 2026 (`CKRecord.encryptedValues`, "Encrypting User Data", `CKSyncEngine.Event.AccountChange`, `CKDatabase.DatabaseChange.Deletion.Reason`, AppleArchive's `ArchiveEncryptionContext`). Anything that needs a real device or an iCloud account is marked **[device]** or **[iCloud]**.

## The short version

| Layer | What it protects against | Where it lives | On by default |
|---|---|---|---|
| The store | Nothing on its own; it's the closet | Application Support, Data Protection `complete` | Yes |
| Safety copies | A failed migration, a bad restore, a bad first iCloud merge | Application Support/Recovery, `complete`, left out of device backups, 7 days at most | Yes, automatic |
| Device backup (iCloud Backup or a computer) | A lost or replaced phone, restored whole | Apple, under her own settings | Her choice in iOS |
| Export | Anything, including iCloud mistakes; a copy she controls | Wherever she saves it, encrypted with her passphrase | No, she asks for it |
| Private iCloud sync | A new or lost phone; her iPad | Two custom zones in her private CloudKit database | No, she turns it on |

Five choices carry most of the weight:

1. **The export is an Apple Encrypted Archive with a passphrase** (AppleArchive's scrypt profile). It's Apple's own framework, so there's no new dependency, it streams files of several gigabytes, and a Mac can open it with built-in tools.
2. **The export holds readable JSON records and the original photos**, not a copy of the SwiftData file. A restore goes through the same checks as any save.
3. **iCloud is off until she turns it on, and stays unavailable until 21b's restore and two-device tests pass** (R7).
4. **Every CloudKit record keeps its content in one encrypted field.** Photos are separate, unchanging image records. The only plain data is what CloudKit needs to work: the record ID (a random UUID), the record type and the system dates.
5. **Body data gets its own zone** (measurements, weight, fit notes about her body, the try-on photo), so it can stay on the phone with one switch if App Review 5.1.3(ii) or the lawyer says it must.

## 1. Safety copies on the device

A safety copy is a closed, consistent copy of the store plus a copy of the image files, taken just before something risky. It's the 20a migration snapshot, used in two more places.

| When | Why | Who restores it |
|---|---|---|
| Before every schema migration (20a) | SwiftData's custom stages aren't atomic | The migration coordinator, automatically at the next launch |
| Before a restore from an export, Replace or Merge | A bad or surprising restore | Her, with **Undo restore** in Backups, for 7 days |
| Before the first merge with an existing iCloud copy | Two closets meeting for the first time | Her, with **Undo iCloud merge** in iCloud, for 7 days |

**How it's taken.** At launch, before any `ModelContainer` exists (20a found that restoring with a container open fails with SQLITE_BUSY), or with the store's container closed. The store goes through `replacePersistentStore` as in the spike, then `PRAGMA integrity_check`, then a manifest (IDs, counts, image hashes) in the journal. Image files are copied with `FileManager.copyItem`, which on APFS makes a clone that takes no extra space until the original changes or is deleted **[device: confirm the clone and the space it uses]**. Free space is checked first (store size plus 20 percent); if it's short, the risky step doesn't start and she's told why.

**Where.** `Application Support/Recovery/<kind>-<date>/`, Data Protection `complete`, with `isExcludedFromBackup` set, so a device backup doesn't carry a second full copy of her closet.

**Retention.** At most one copy of each kind, deleted 7 days after the step it protects was verified (PRD 15.4's limit for migration snapshots), and deleted at once by Delete my data. Three failed migration attempts keep the copy until she exports or the next app version succeeds, as in 20a.

**Pieces deleted for good.** When a piece is purged (the 30-day purge or Delete permanently now), its image files are deleted from every safety copy at the same moment, and its ID goes in the copy's `purged.json`, so restoring the copy never brings it back. Its text record stays inside the copy's database until the copy expires, at most 7 days, because rewriting an older-schema database isn't safe. **Jose decides** whether that's acceptable against PRD 15.4's "clears covered personal copies immediately" (decision 3 below).

**Rejected: daily recovery points.** A rolling daily copy would catch more app bugs, but it holds deleted content for days after every purge, and it's mostly covered by export and the copies above. It can come back later if 21b's tests show a need.

## 2. Device backups

The store and photos stay in device backups, as iOS does by default. That's how a phone restored from iCloud Backup or a Mac gets her closet with no app sync at all, and the choice sits in iOS, where she already manages it. Left out: safety copies, export staging, restore staging, thumbnails, the search index and caches (rebuilt on demand).

Two rules make a restored device safe:

- **A restored device starts sync fresh.** The app keeps a marker in the Keychain with `WhenUnlockedThisDeviceOnly`, which never moves to another device. A store found without its marker came from a backup, so the app drops the `CKSyncEngine` state and the per-record sync bookkeeping, then fetches everything and merges by ID. Without this, the restored engine state could claim changes were already sent **[device + iCloud: confirm the marker doesn't survive a backup restore, and what a restored engine state does]**.
- **5.1.3(ii) may reach device backups too.** If the lawyer reads "personal health information in iCloud" to include iCloud Backup, body data would need a separate file left out of backups, and a restored phone would come back without it. Asked as part of decision 2.

## 3. Export

### What she sees

Backups, under Privacy and terms (Your data) and on Profile:

1. **Export a copy.** "A copy of everything in the app, in one file, locked with a passphrase you choose. It doesn't update itself: export again to keep it current." A preview lists what goes, with counts and the estimated size: pieces with their original photos and cutouts, looks, suitcases, try-on pictures, your profile with name, Preferences and fit, your try-on photo, measurements and weight (named on their own line because they're the most sensitive), Recently deleted, and unsaved drafts.
2. **Passphrase.** Two choices of equal weight: **Make one for me** (24 characters from an unambiguous alphabet in groups of four, about 120 bits, from `SecRandomCopyBytes`) or **Use my own** (at least 12 characters, typed twice). The screen says plainly: "We can't recover this passphrase. Without it, nobody can open the file, including you. Write it down or save it in Passwords." A generated passphrase can be copied on her tap; the copy is local only and expires after 2 minutes. The app never stores the passphrase.
3. **Save.** The system's Files sheet. She picks the place: iCloud Drive, On My iPhone, a USB drive, AirDrop to a Mac. The app sends nothing anywhere itself (standard §4: she's told where it goes).
4. **Done.** "Your copy is saved in [place] as [file name]. It holds your measurements and photos; keep the passphrase somewhere safe." With **Check this copy**, which runs the restore checks without restoring (below).

**Check a copy** opens any export file, asks for the passphrase, and runs every restore check up to the preview. It changes nothing. It's cheap, because it's the restore's first half, and it answers "will this file actually work?" before she needs it.

### The file

| Part | Choice |
|---|---|
| Name | `Nifty Outfit Nook 2026-10-20.nookbackup`. The date only; no name, no counts |
| Type | An exported UTType, `com.jsayram.niftyoutfitnook.backup`, conforming to `public.data`, so Files shows it with the app's icon and the restore picker can ask for it |
| Container | Apple Encrypted Archive (AEA), profile `hkdf_sha256_aesctr_hmac__scrypt__none`: a key derived from the passphrase with scrypt, AES in counter mode with HMAC authentication, in segments, so it streams and any change to the file is caught |
| Compression | AEA's LZFSE on the archive stream. The JSON shrinks a lot; the photos are already compressed and won't. 21b measures whether turning compression off is faster with no real size cost |
| Clear prologue (`authData`) | Only `NOOK-BACKUP` and the outer format version. Nothing about her |
| Inside | An Apple Archive (`.aar` stream) of one folder, below |

```
manifest.json          format version, kind (records or storeCopy), schema version, app version and
                       build, created at, counts per kind, the SHA-256 and size of every other file,
                       what's included (try-on photo, try-on pictures, body data)
records/garments.json  one JSON file per kind, in the app's Codable value types, with stable IDs
records/looks.json
records/suitcases.json
records/tryon-pictures.json
records/profile.json   name, Preferences, remembered choices, tour progress
records/body.json      measurements, weight, fit notes, pieces that fit well (left out if empty)
records/drafts.json    garment and look drafts
records/deletions.json IDs deleted for good, with dates; no content (PRD 15.2's deletion markers)
photos/<image id>      originals and active cutouts, try-on pictures, the try-on photo, as stored
```

**Left out on purpose:** thumbnails, the search index and caches (rebuilt), the `CKSyncEngine` state and change tags (a restore starts sync fresh), safety copies, consent receipts (each feature asks again after a restore; decision 6), Keychain items and any account token, credits and entitlements (the server is the authority, PRD 15.2), and pieces deleted for good.

**Two kinds.** `records` is the normal export. `storeCopy` holds the raw store file and images instead of JSON, and is used only from the recovery screen after a failed migration or a store from a newer version, when the app can't read the records itself. A newer app version restores it through the normal migration path, which the spike tested with an old store.

**Versions.** `formatVersion` (the outer format and manifest) and `schemaVersion` (the records) are separate integers. A restore reads every version ever shipped: older formats are upgraded by pure functions before anything is written, with a fixture file for each version in the tests, as store migrations have. A newer version than the app knows stops the restore with "This copy is from a newer version of Nifty Outfit Nook. Update the app, then try again." and changes nothing.

### Size and time

Photos are nearly all of it. Using PRD 15.3's planning figures (about 4.4 to 4.8 MB per piece for the original plus its active image), encryption adding well under 1 percent:

| Closet | Export size |
|---|---|
| 100 pieces | 0.45 to 0.5 GB |
| 300 pieces | 1.3 to 1.5 GB |
| 1,000 pieces | 4.4 to 4.9 GB |
| Each try-on picture | 1 to 5 MB more |

These are estimates. Real originals after 22a's intake may be smaller. The export is written to `tmp` (`complete`, left out of backups) and then moved by the Files sheet, so it needs about its own size free. The app checks first (`E174.1` disk-space reason) and, if space is short, says how much is needed. Saving to iCloud Drive also uses her iCloud storage, once per copy she keeps.

A long export keeps running if she leaves the app, as a `BGContinuedProcessingTask` with progress in the system UI **[device: confirm on iOS 26.5 and 27]**. If it's stopped, the partial file is deleted and nothing else changes. 21b measures time on the iPhone 12 for 300 and 1,000 pieces **[device]**.

**Consistency.** The export reads every record in one turn of each store actor and pauses the launch sweep and the purge while it runs. Files are written before the records that point to them and removed after (20a), so with cleanup paused every referenced file exists. Each file's hash is checked as it's added.

### Why this design

- **Encrypted, as the standard requires and Jose approved (D10, 19 October 2026).** PRD 15.4's unencrypted archive is superseded.
- **AEA instead of our own format.** CryptoKit has no password-based key derivation. Our own format would mean PBKDF2 from CommonCrypto plus chunked AES-GCM that we'd write, review and keep correct. AEA gives a memory-hard KDF (scrypt), authenticated streaming and a format Apple maintains, and macOS's `aea` and `aa` tools can open it for Jose or Lily on a Mac **[to verify in 21b: the exact commands]**. The cost: scrypt's parameters are fixed by Apple's profile and we can't tune them, and the file opens only on Apple systems. Fallback if 21b finds a problem: PBKDF2-HMAC-SHA256 (600,000 rounds, OWASP's current figure) through CommonCrypto, with CryptoKit AES-GCM in 1 MiB chunks bound to their index and a final-chunk flag. No dependency either way. Argon2id would need one (libsodium), so it isn't proposed.
- **JSON records instead of a store copy.** SwiftData's file layout isn't ours to promise across iOS versions, a restore through the store protocols gets the same validation as every save, Merge needs records anyway, and PRD 15.2 asks for readable records.
- **Export compliance.** The encryption is Apple's, inside the OS, so `ITSAppUsesNonExemptEncryption` = NO should still be right. **Unsure**: 21b rechecks it against Apple's export compliance page before the first build with export (App Review checklist R8).

## 4. Restore

### What she sees

From Backups (**Restore from a copy**), and in onboarding from "I already use Nifty Outfit Nook" (**Restore from a backup file**):

1. **Pick the file** in the system Files picker (`.nookbackup` only).
2. **Passphrase.** A wrong one says "That passphrase doesn't open this copy." and lets her try again. There's no attempt limit, because the file is offline and a limit protects nothing.
3. **Checks** with progress: decrypt to staging, then every check below. Nothing in the app has changed yet.
4. **Preview.** The counts in the copy against the closet now, the copy's date, and what it includes (try-on photo, body data). "This copy is from 3 October. Anything you added or changed after that isn't in it."
5. **Choose:**
   - **Replace my closet with this copy.** For a new phone, or to go back. If there's anything in the app now, she's asked once more, and a safety copy is taken first.
   - **Add what's missing.** Merge by stable ID: pieces, looks and suitcases not in the app are added; for the same ID, the merge rules below run with no common ancestor, so any difference is kept as a conflict to review. Nothing in the app is removed.
6. **Done**, with the counts restored and **Undo restore** for 7 days.

### The checks, all before anything is written

- The AEA container authenticates, so a changed or truncated file fails here.
- Bounded extraction into `Application Support/Restore/` (`complete`, left out of backups): only regular files and folders (no links), no absolute paths and no `..`, at most 200,000 entries, every size matching the manifest, and the total no larger than the free space minus a margin. An archive bomb or a crafted path stops the restore (THREAT_MODEL F4).
- Every file's SHA-256 matches the manifest; every manifest entry exists; no file is in the archive that the manifest doesn't list.
- The records decode at their format version, IDs are unique, and every reference (a look's pieces, a suitcase's members, a picture's look, an image ID) resolves or is marked missing, never dropped.
- `deletions.json` and this device's own deletion markers both apply: a piece deleted for good, in the copy or in the app, never comes back (PRD 11.7).

### Committing

Replace writes the staged records and images through the stores in one restore transaction per store, with a restore journal shaped like the migration journal (`staged`, `safetyCopyTaken`, `writing`, `written`, `verified`). Killed at any step, the next launch either finishes or puts the safety copy back, the same way a migration does. Restore staging is deleted once the restore is verified, or at the next launch if it never was.

With iCloud on, a restore is a set of local edits: restored records are saved as new revisions and records not in the copy (Replace only) as removals, and they sync to her other devices like any edit, under the same merge rules. The preview says so: "Your other devices will get this change too."

## 5. Private iCloud sync

### Off by default, and not offered until 21b passes

PRD 15.2 says onboarding offers iCloud. The design keeps that, but the switch doesn't appear in any build until 21b's restore and two-device tests pass and the CloudKit schema is promoted (R7's control). Then onboarding gets one optional step (decision 5), and the iCloud row sits on Profile and in Privacy and terms.

### Turning it on

The sheet is the 19b wording (`closet/compliance/IN_APP_PRIVACY_TEXT.md`), finished here:

> **Keep a copy in your iCloud?**
> Your closet, photos and looks go to your private iCloud, so they're on your other devices and come back if you change iPhones. Only your Apple Account can reach it; we can't.
> Apple can read most iCloud data unless you've turned on Advanced Data Protection in Settings. With it on, everything the app puts in iCloud is end-to-end encrypted, apart from the names of record types and their dates and sizes.
> It uses your iCloud storage. About [1.4 GB] now.
> [Turn on sync] [Not now]

Plus, while decision 2 is open: "Your measurements, weight, fit notes and try-on photo stay on this iPhone." (or, once allowed, a second switch, **Include my fit and try-on photo**).

If iCloud already holds a copy (another device), she's told how many pieces are there and here, a safety copy is taken, and the two merge by ID. Pieces made on different devices never collide, because IDs are UUIDs.

### What syncs and what doesn't

| Zone | Record types | Holds |
|---|---|---|
| `Closet` | `Garment`, `Look`, `Suitcase`, `TryOnPicture`, `Profile`, `Draft`, `Image` | Pieces with their states and wear days, looks (saved and unsaved results), suitcases and memberships, try-on picture records, the profile without body data (name on the sign, Preferences, remembered choices, tour progress, app state flags), drafts with their device and base revision (PRD 15.1), and every image as its own record |
| `Me` | `Body`, `Image` | Measurements and weight, fit notes about her body, pieces that fit well, the try-on photo. Synced only if decision 2 allows |
| `Control` | `SyncGeneration` | One content-free record: a generation number, a reason and a date, so other devices know a zone was deleted on purpose (below) |

Never synced: today's comfort, unless she saved it with a look as an approved neutral preference (PRD 15); thumbnails, the search index and caches; safety copies; the export passphrase; consent receipts (the server is the authority); account tokens.

### Which fields are encrypted

Every record has the same shape:

| Field | Kind | Why |
|---|---|---|
| Record name | Plain (CloudKit requires it) | A random UUID or the app's stable ID. Never a name or a word she typed |
| Record type, created and modified dates, size | Plain (CloudKit system fields) | CloudKit needs them. Record type names are generic and carry no content |
| `payload` | **Encrypted** bytes | The record's value type as JSON: everything about it, including references to other records by ID |
| `payloadVersion` | **Encrypted** integer | The JSON's format version, so an older app never overwrites a newer record |
| `tombstone` | **Encrypted** integer | 1 when the record was deleted for good; the payload is then removed. Content-free |
| `asset` (`Image` only) | `CKAsset`, encrypted by CloudKit by default | The image file. Its key is kept in an encrypted field, so it follows the same rule |

No `CKRecord.Reference` fields: references can't be encrypted, so relationships live inside the payload. No plain revision field either; the change tag does that job. The spike's mapping had one plain `revision`; it goes.

**One encrypted payload per record, not one field per property.** The spike left this open. Encrypted fields can't be queried or indexed, so per-property fields give the server nothing. A field can't be made encrypted after it exists and nothing can be removed from a production schema, so every extra field is a permanent bet. With one payload, the production schema is fixed once and all change happens in our Codable versions, which the tests cover. Field-by-field merging happens on the device anyway, against the ancestor. The cost is re-sending a few kilobytes per edit, and the 1 MB record limit, which a piece with ten years of wear days doesn't come near.

**Images are separate and never change.** An `Image` record is written once, named by the image's own ID, and deleted, never edited. A new photo is a new `Image`. So images never conflict, an edit to a piece doesn't upload its photo again, and a piece can arrive before its photo: it shows as downloading, never as missing (PRD 15.1's "Loading, not empty").

### What Lily gets, with and without Advanced Data Protection

| | Standard Data Protection | Advanced Data Protection |
|---|---|---|
| Who can read her closet, photos and body data in iCloud | Her, on her devices. **Apple holds the keys and could decrypt it** (accepted risk D8(a)) | Only her devices. Apple can't |
| What Apple sees either way | That the app stores data for her, how many records of each type, their sizes and dates | The same |
| If she loses every device | Recovered by signing in to iCloud | Only with her device passcode, recovery contact or recovery key. Without them, the iCloud copy is gone; an export is her fallback |
| If her iCloud Keychain is reset | The encrypted data in iCloud is lost (Apple: "permanently lost"); the app re-uploads what this phone has | The same |

Apple's documentation says CloudKit encrypts encrypted fields "on-device before saving them to iCloud" and, with ADP on, "the encryption keys are available exclusively to the record's owner". Assets are encrypted by default with their key in an encrypted field. **[iCloud: read back encrypted fields and assets with ADP on and off before the schema is promoted.]**

### State and bookkeeping (from 20a)

- The `CKSyncEngine.State.Serialization` is a row in the store, saved after the records it describes, with the store's `complete` protection. No separate file and no Data Protection exception (D8(d)).
- Each synced record has a sync row: its last known system fields (change tag) and its **ancestor**, the payload both sides last agreed on, for the three-way merge. The value types never see these.
- The engine starts only when protected data is available. A push while the phone is locked waits for unlock.
- The account's user record ID is stored (hashed) with the state, to catch an account switch.

### Merge rules (proven in 20a as pure functions)

- A field only one side changed takes that change. Both sides changed it the same way: fine.
- Both changed it differently: the server's value stays (whichever device got there first, never a device clock) and this device's value is kept as a conflict to review.
- Removal and restriction win, with the other value kept for review: Recently deleted, archived, no longer owned and unavailable beat their opposites, and dirty beats clean.
- Wear days and suitcase memberships are sets: both sides' additions and removals apply.
- A piece deleted for good stays deleted. An edit from a stale device is dropped and reported.
- A record with a `payloadVersion` newer than the app knows is kept as it is and never overwritten. She sees "Update the app to see 3 pieces from your other device."
- Applying the same changes twice changes nothing; a crash between the records and the state leaves the state behind, and CloudKit sends the changes again.

Conflicts to review are listed under iCloud, and the piece shows a quiet badge. Where exactly they show is a UI question for 21b (decision 7).

### Status she sees (PRD 15.1)

Under iCloud: **Saved on this iPhone** (always true once she taps Save), **Waiting to upload**: 4 changes and 12 photos, **Couldn't upload**: the reason and Try again, and **Last confirmed by iCloud**: 9:41 today. Never "Synced" while anything is still waiting. Help says once: "iCloud keeps your devices the same. It isn't a history: a piece you delete is deleted everywhere. For a copy you can go back to, export."

### Turning it off

"Turn off iCloud for this iPhone?" with two choices:

- **Keep my iCloud copy** (the default): this iPhone stops syncing and keeps everything; other devices carry on.
- **Also delete my iCloud copy**: the `Closet` and `Me` zones are deleted, and `SyncGeneration` says `syncTurnedOff`. Other devices stop syncing, keep their own data, and say "iCloud was turned off on another device. This iPad keeps its closet."

Either way the local data stays. The 19b off line stands: "Sync is off. This iPhone keeps everything. Your iCloud copy stays until you delete it in Delete my data."

### When iCloud changes under the app

| What happens | What the app does | What she sees |
|---|---|---|
| She signs out of iCloud (`signOut`) | Stops the engine. Keeps all local data and the state | "You're signed out of iCloud. Your closet stays on this iPhone and syncs again when you sign back in." |
| She signs in to a different account (`switchAccounts`), or a different account than the stored one | Pauses. Never uploads one account's data into another (PRD 15.1) | "This closet belongs to a different iCloud account. Keep it on this iPhone only, or copy it to [this account]?" |
| Her storage is full (`quotaExceeded`) | Keeps the changes pending; local saves carry on | "Your iCloud storage is full. Changes are safe on this iPhone and will upload when there's space." with a link to Settings |
| Offline or iCloud unavailable | Waits; the engine retries on its own schedule | Waiting to upload, with counts |
| She deletes the app's data in Settings > iCloud (`purged`, `userDeletedZone`) | Pauses sync. Asks, as Apple's guidance says | "Your Nifty Outfit Nook data was removed from iCloud in Settings." **Keep it on this iPhone (sync off)**, **Upload it again**, or **Delete it here too** |
| The zone was deleted by the app on another device (`deleted`) | Reads `SyncGeneration` for the reason | As in Turning it off, or Delete my data below |
| Her encrypted data was reset (`encryptedDataReset`, or `zoneNotFound` with `CKErrorUserDidResetEncryptedDataKey`) | Deletes and re-creates the zones and uploads this phone's copy, as Apple's guidance says | "Your iCloud encryption was reset, so the app uploaded this iPhone's closet again." |

**[iCloud: every row needs a real account on two devices; `encryptedDataReset` may not be possible to trigger on purpose, in which case it's tested only against a stand-in.]**

### CloudKit schema

Built in the development environment from these record types, checked in the CloudKit console, and promoted to production only after Jose approves this design and 21b's tests pass on development. Once promoted, it can only grow. The container is `iCloud.com.jsayram.niftyoutfitnook`; the iCloud capability and container are Apple setup Jose does (decision 8).

## 6. Delete my data

Delete my data now covers her private iCloud copy as well, in this order:

1. Stop the sync engine.
2. Save a pending deletion (content-free: the zone names and the hashed account ID) in the app-state store, which survives the erase.
3. Write `SyncGeneration` with `deletedEverything`, then delete the `Closet` and `Me` zones through `CKSyncEngine`'s database changes, and wait for the sent-changes event to confirm.
4. Erase every local store, image, safety copy, restore and export staging, and the sync state, as now.
5. Clear the pending deletion once iCloud confirmed it.

If iCloud is unreachable or slow, step 4 still runs and the screen says so plainly, as PRD 15.1 asks: **This iPhone: deleted. Your iCloud copy: waiting to be deleted.** The pending deletion runs at the next launch with a connection, before anything can sync, and iCloud can't be turned on again until it's done. If she's signed in to a different account by then: "Sign in to iCloud as [the account that held the copy], or delete it in Settings > [your name] > iCloud > Storage." The account is named as iOS names it, never from our records.

Her other devices see the zone deletion with `deletedEverything` and ask: "Your data was deleted from iCloud on another device. Delete it from this iPad too?" **Delete it here too** / **Keep it on this iPad (sync off)**. Asking, rather than erasing, means a bug or a mistake on one device can't wipe every device (decision 4).

The screen's list gains a line: **Your iCloud copy** (shown only if sync was ever on). "Afterwards" adds: "Copies you exported stay wherever you saved them. Delete those in Files." (PRD 15.2.) Deleting the app is different: it removes this iPhone's copy and leaves iCloud's, so a reinstall can get it back. Help says so.

`SyncGeneration` stays in the `Control` zone after Delete my data: a number, a reason and a date, nothing about her (PRD 15.1's content-free markers). It's how a device that was offline for months learns not to upload its old closet.

## 7. Recovery after a failed migration

From 20a, unchanged: the coordinator journals, snapshots, migrates and verifies; a kill or a failure restores the snapshot at the next launch; after three failed tries it stops. What she sees then:

> **Your closet couldn't be updated**
> Nothing is lost. The copy from before the update is safe on this iPhone.
> [Try again] [Export a copy] [Send feedback]

Export a copy here makes a `storeCopy` export (raw store and images, encrypted the same way), because this app version can't read the records. A later version restores it through its migration. Send feedback carries no closet data, as always. iCloud sync stays paused until the store opens, so a half-migrated store can never upload.

A store from a newer app version (a TestFlight build rolled back, or a device backup from a newer phone) is never opened or reset (20a): "This closet was saved by a newer version of Nifty Outfit Nook. Update the app to open it." with an App Store link, plus Export a copy (`storeCopy`).

## 8. New phone and lost phone

| Situation | What she does | What comes back |
|---|---|---|
| New phone, old phone in hand | Quick Start or device backup, as iOS offers | Everything. The app sees it's a restored device and starts sync fresh |
| New phone, iCloud sync was on | Install, then "I already use Nifty Outfit Nook" > **Get my closet from iCloud** | Everything that finished uploading. Progress: "Getting your closet: 312 of 540 pieces, 120 of 300 photos." Pieces she can already use show at once. Changes that never uploaded can't come back, and the app says so rather than claiming it's complete |
| New phone, an export file | Install, then "I already use Nifty Outfit Nook" > **Restore from a backup file** | The closet as of the export's date |
| Lost phone, sync on or an export | As above, on the new phone | As above. The lost phone's store is protected by its passcode (`complete`); Find My can erase it. If it's ever found and turned on, `SyncGeneration` and the merge rules stop it undoing anything |
| Lost phone, no sync, no export, no device backup | Nothing to restore | Nothing. Onboarding's privacy step and Help say this before it happens: "Without iCloud or an exported copy, your closet lives only on this iPhone." |

## 9. What this changes in the data map and threat model

- **DATA_MAP:** the iCloud row gets the zones, the field table and the ADP table; the `CKSyncEngine` state becomes a row in the store (20a, D8(d)); the export row gets AEA and the contents; safety copies get a row; Delete my data reaches the iCloud zones.
- **THREAT_MODEL:** R7 adds the safety copies, the restore journal, newer-version records never overwritten, and the restored-device marker. F2's line about a `completeUntilFirstUserAuthentication` state file goes, since D8(d) needs no exception. D7 is about server backups (R2) and doesn't change; a note says on-device backups are designed here.
- **Privacy manifest:** the migration coordinator's free-space check needs `NSPrivacyAccessedAPICategoryDiskSpace` with `E174.1` in 21a, earlier than the 21b the manifest plan says. `85F4.1` too if a screen shows free space ("You need 1.4 GB free").

## Built in Phase 21b (20 October 2026)

Export, Check a copy, Restore, Undo restore and the recovery screen's export are app code (`Services/Backup`, `Features/Settings/Backups`). iCloud sync isn't built: the iCloud container and the two test Apple Accounts (decision 8) don't exist yet, so sync stays off and hidden and no entitlement was added. The open decisions use the defaults suggested above; each is noted where it applies.

**As designed:**

- An Apple Encrypted Archive, profile `hkdf_sha256_aesctr_hmac__scrypt__none`, LZFSE, clear prologue `NOOK-BACKUP 1` and nothing else. `manifest.json` goes first, with the size and SHA-256 of every other file; records are readable JSON in the app's value types; photos go in as stored. The archive is encrypted as it's written, so no unencrypted copy is ever on disk. Every photo is hashed before the manifest is written and again as it's added.
- Every restore check runs before anything is written: the prologue (a newer format is refused before the passphrase is tried), the passphrase, AEA's authentication, the manifest first and bounded, at most 200,000 entries, only regular files and folders, safe relative paths only, every size and hash against the manifest, no file missing or extra, free space, then each record decoded and checked as a save checks it (`StoreValidation`) with its key matching its ID, and the counts against the manifest.
- Replace and Add what's missing both ship (decision 7's default). Deletion markers from both sides apply. A safety copy is taken first, and Undo restore works for 7 days. A journal (`staged`, `safetyCopyTaken`, `writing`, `verified`, `undoing`) lets the next launch finish or tidy up.
- Passphrases: generated (24 symbols from a 32-letter alphabet, `SecRandomCopyBytes`, groups of four, about 120 bits) or her own of at least 12 characters typed twice (decision 9's default). Copy passphrase is local only and expires after 2 minutes. No consent receipts are in the export, so each feature asks again after a restore (decision 6's default).
- The recovery screen's Export a copy makes a `storeCopy`; a restore opens it through the migration coordinator in staging.

**Changed from the design, and why:**

- **One records file per kind of record** (`records/garment.json`, `records/profile.json`...), not `garments.json` and a separate `body.json`. Measurements live in the profile record, so splitting them would mean a second shape to keep in step; the manifest's `includesBodyData` and the preview name them instead.
- **The restore writes in the running app, in one save,** rather than at the next launch. A SwiftData save is one SQLite transaction, so the store holds the old closet or the whole new one; a kill at any step (tested at each one) ends as one or the other. Afterwards the app makes fresh store actors (`NookStorage.reload()`), since the old ones remember what they read. Changed records are deleted and inserted again rather than edited, so no other context keeps a stale value.
- **The restore's safety copy sits in `Store/RestoreSafetyCopy`,** not `Recovery/<kind>-<date>`: the migration coordinator clears `Recovery` before each snapshot. Undo reads the copy's rows with SQLite and writes them back in one save, so it doesn't need the store closed either.
- **Deletion markers are a record kind** (`deletion`, key the piece's ID, content its date only), written in the same save as the purge. Pieces only so far; Jose's 20 October decision also deletes the try-on pictures that show a purged piece, and a restore leaves those out.
- **Add what's missing keeps the copy's differing version as a `restoreConflict` record.** There's no review screen yet; conflicts to review come with sync (decision 7's "where conflicts show").
- **Photos** are read from `Application Support/Photos/<image id>` and only those the records point to go in. Nothing writes there until Phases 22a and 22b; the round trip is tested with real files.

**Found on the way:**

- AEA ignores bytes after its end, so the reader checks the file size against `containerSize` after decrypting. A changed byte anywhere, a cut file and swapped blocks all fail AEA's authentication. A wrong passphrase fails when the decryption stream is made; one under AEA's own minimum length fails at `setPassword`. The key derivation took about 50 ms on a Mac.
- `NSPersistentStoreCoordinator.replacePersistentStore` copies a live store's data into the copy's own `-wal`, so a single-file store copy lost most of its records until the copy was checkpointed (`PRAGMA wal_checkpoint(TRUNCATE)`, then `journal_mode=DELETE`).
- A Mac opens an export: `aea decrypt -i "<file>.nookbackup" -o copy.aar -password <file holding the passphrase>`, then `aa extract -i copy.aar -d <folder>` (macOS 27.0.1). `aea` has no prompt; `-password-value` puts the passphrase in the shell's history, so the file is better.
- Export compliance (R8): Apple's "Complying with Encryption Export Regulations" (checked 20 October 2026) says encryption built into the operating system is typically exempt from the documentation upload, but that exempt encryption may still need a year-end self-classification report. `ITSAppUsesNonExemptEncryption` stays NO; the report is a question for Jose.

**Built in Phase 22b:** a piece deleted for good loses its images from the restore's safety copy at once (no `purged.json` is needed: Undo restore already leaves out pieces with a deletion marker, and now their try-on pictures too); thumbnails sit in `Library/Caches/Thumbnails`, outside every backup (`docs/image-storage.md`).

**Not built yet:** export carrying on in the background (`BGContinuedProcessingTask`) and progress counts, since closets have no photos until 22a; Try again and Send feedback on the recovery screen.

**The test plan, where it stands.** Automated and passing: round trips of the demo (every kind of record, three photos), the 2,400-piece closet and an empty closet; a wrong passphrase; one changed byte in five places, a cut file, an extra byte and swapped blocks; a file that isn't a copy, a newer prologue, manifest and payload version; crafted archives with `..`, an absolute path, a link, too many entries, a file bigger than the manifest says, an unlisted file, a missing file, a changed file, too little space, and records that fail their checks; the format 1 fixture file; nothing about her in the clear; what's left out; the passphrase never written; Replace into a full closet with Undo bringing back every record and photo; Add what's missing; deletion markers both ways; a kill at each of six restore steps for both modes, and during Undo; the safety copy left out of backups, expired after 7 days and removed by Delete my data; too little space for the safety copy or the export. Parked, waiting on Jose: every **[device]** and **[iCloud]** item above, the sync tests, and a store copy from an older schema (it can only run once the app has a real second schema, since a test-only version 2 in the same process makes SwiftData map the shared model to it, as 20a found).

## Built in Phase 21b: iCloud sync, against a stand-in (22 October 2026)

Section 5 and the iCloud part of section 6 are app code (`Services/Sync`, `Features/Settings/ICloud`), tested against an in-memory stand-in for CloudKit and `CKSyncEngine`, and **off**: no row and no CloudKit call in any build until `NOOK_ICLOUD = YES` (`docs/icloud.md`, with Jose's steps for the container, the schema and the device tests). No entitlement is in a default build. Decision 2 keeps the `Me` zone off; the other open decisions use the defaults suggested above.

**As designed:** `CKSyncEngine`, wrapped behind a protocol; one encrypted payload per record (`payload`, `payloadVersion`, `tombstone` in `encryptedValues`, nothing else plain but the record name, type and system fields); images as separate `Image` records with a `CKAsset`, written once; `Closet`, `Me` and `Control` zones; three-way merges with the 20a rules, removal and restriction winning, what lost kept for review; newer payload versions held and never overwritten; every account event in the table above with its response, and nothing ever sent unless the account signed in is the closet's; the restored-device marker in the Keychain; the engine state saved in the store after the records; Delete my data deleting the zones first after writing `SyncGeneration`, pending and run first at the next connected launch when offline, and other devices asking before they erase.

**Changed from the design, and why:**

- **What's pending is worked out from the store, not tracked.** Each look compares every synced row with the version both sides last agreed on, so an engine reset, a crash or a restore can't lose a change. Compared as values, since JSON from sets isn't byte-stable.
- **Record names are `<kind>.<key>`** (the row's stable ID with its kind), and two record types were added for kinds that came later: `AppState` (onboarding and tours) and `StylistThread` (27c).
- **Every content record gets a tombstone** when it goes, not only pieces, so a stale device can't bring back a look or a suitcase either. They're content-free and stay.
- **Her usual fit counts as body data** and stays on the phone with the measurements, the more careful reading of "fit notes about her body".
- **Conflicts are `syncConflict` records** (`StoredSyncConflict`), the sync counterpart of 21b's copies kept for review, with the fields that clashed. A deletion that beat an edit keeps no content.
- **Writes from iCloud go through the store actor that owns the kind** when it keeps values in memory, so her edits and remote changes never interleave.
- **Delete my data on this iPhone** (not only Delete my account) now lists and deletes the iCloud copy first, as section 6 says.

**Not built yet:** the safety copy before the first merge and Undo iCloud merge (section 1), a screen to review conflicts (a count only, decision 7), the onboarding step and Get my closet from iCloud (decision 5), and a body data switch (decision 2). Every **[iCloud]** and **[device]** item above waits on the container and the test accounts.

## Decisions for Jose

1. **Approve the design**, in particular AEA with a passphrase for exports, JSON records in the export, one encrypted payload per CloudKit record, and iCloud hidden until 21b's tests pass.
2. **Body data and iCloud (App Review 5.1.3(ii), checklist P12).** Until the lawyer answers: (a) keep the `Me` zone off, so measurements, weight, fit notes and the try-on photo stay on the phone (suggested); (b) sync it with a second switch, off by default; or (c) sync it with everything. And whether device backups (iCloud Backup) need the same treatment.
3. **Safety copies after a purge.** Accept that a purged piece's text stays inside a safety copy for at most 7 days (its images go at once), or delete every safety copy whenever a purge touches it (stricter, but the 30-day purge would often remove the migration snapshot during its 7 days).
4. **Delete my data on other devices.** Ask on each other device (suggested), or erase them automatically.
5. **Onboarding step for iCloud** once 21b passes (PRD 15.2 asks for it): add the step, or keep iCloud only in Profile and Privacy and terms. A new onboarding step may want Lily's look first.
6. **Permissions after a restore.** Each feature asks again (suggested), rather than the export carrying consent receipts.
7. **Merge on restore.** Ship Replace and "Add what's missing" together in 21b (PRD 15.2 asks for both), or Replace first and merge later if 21b runs long. And where conflicts to review live (iCloud screen plus a badge, suggested).
8. **Apple setup (Jose only):** the iCloud capability, the container `iCloud.com.jsayram.niftyoutfitnook`, and two test Apple Accounts for the two-device tests (one with ADP on, one nearly full).
9. **Passphrase rules:** at least 12 characters for her own, or a generated one. Fine as suggested, or different.

## Test plan for Phase 21b

Automated, in CI, unless marked.

**Export format**
- Round trip: the demo, large (2,400 pieces) and empty closets export and restore field for field, with every image hash.
- A wrong passphrase fails without writing anything. The right one with one changed byte anywhere, a truncated file, an extra byte at the end and a reordered segment each fail at authentication.
- The manifest lists a file the archive doesn't hold, the archive holds a file the manifest doesn't list, a size or hash differs: each stops before the preview.
- Crafted archives: `..` in a path, an absolute path, a symlink, 200,001 entries, a size larger than the manifest says, and a total larger than free space. Each stops with nothing written outside staging.
- Every shipped `formatVersion` has a fixture file that restores; a newer one is refused with the update message.
- `authData` holds only the format marker; nothing personal is in the clear prologue (scan the bytes for the demo's names).
- Left out: no sync state, consent receipt, token, thumbnail, cache or purged piece in the archive.
- A generated passphrase has the stated length and alphabet; the app never writes a passphrase to disk, defaults or the Keychain (search the container after an export).
- Export with the purge and the sweep paused: a piece deleted mid-export is either wholly in the archive or wholly out.

**Restore**
- Replace into an empty app (a new phone) and into a full one, with the safety copy taken and Undo restore bringing back the exact prior closet.
- Add what's missing: new IDs added, same IDs merged with conflicts kept, nothing removed.
- Deletion markers: a piece deleted for good in the app, or listed in the copy's deletions, never comes back by either path.
- Killed at each restore journal step (the 20a kill harness): every run ends as the old closet or the fully restored one, never a mix.
- A `storeCopy` export of an old schema restores through migration.

**Safety copies**
- Taken before a migration, a restore and a first iCloud merge; excluded from backup; `complete` protection set in code; deleted after 7 days and by Delete my data.
- A purge removes the piece's images from every safety copy and lists it in `purged.json`; restoring that copy leaves it out.
- Short of space: the risky step doesn't start, and the message names the space needed.

**Sync (against the spike's stand-in zone, plus the real engine where it can run without an account)**
- The merge rules from 20a, both reconnect orders, repeated delivery.
- A record with a newer `payloadVersion` is kept and never overwritten.
- `Image` records: a piece before its photo shows as downloading; an edit doesn't re-upload the image.
- The CloudKit mapping: only the record name and system fields are plain; `allKeys()` shows `payload`, `payloadVersion` and `tombstone` as encrypted; no `CKRecord.Reference`.
- The `Me` zone is never written while decision 2 keeps it off.
- Account change, quota, purge, `deleted` with each `SyncGeneration` reason, and `encryptedDataReset`, as a pure state machine fed each event: the right pause, prompt or re-upload, and never an upload into a different account.
- The restored-device marker: a store without its Keychain marker drops the sync state and refetches.

**Delete my data**
- Online: zones deleted, then local, then the pending deletion cleared. Offline: local deleted, iCloud shown as waiting, the deletion runs first at the next connected launch, and iCloud can't be turned on until it has.
- Every store, image, safety copy, staging folder and the sync state are gone (extends `DataDeletionFixtureTests`).

**UI and snapshot tests**
- Export, Check a copy, Restore (wrong passphrase, newer version, damaged, preview, Replace, Add what's missing, Undo restore), iCloud on and off sheets, the status lines, the recovery screen after a failed migration, Delete my data with iCloud waiting. Light, dark and AX5, iPhone and iPad.

**On a real device or with iCloud (manual, written up in 21b's notes)**
- **[device]** `FileProtectionType` on the store, `-wal`, `-shm`, images, journals, safety copies and staging; the store can't be read while locked.
- **[device]** APFS clones: the space a safety copy uses before and after the originals change.
- **[device]** Export and restore of 300 and 1,000 pieces on the iPhone 12: time, peak memory, temporary space, and the export carrying on in the background.
- **[device]** The Keychain marker after a restore from an encrypted Mac backup and from iCloud Backup.
- **[device]** Open an export on a Mac with `aea` and `aa`.
- **[iCloud]** Two devices on one account: edits offline on both, reconnect in both orders, deletion across devices, Delete my data with the iPad offline, turning sync off with and without deleting the copy.
- **[iCloud]** ADP on and off: encrypted fields and assets read back; the CloudKit console shows encrypted field types before promotion.
- **[iCloud]** Sign out, switch account, a nearly full account, deleting the app's data in Settings > iCloud, and push wake-ups while locked.
- **[iCloud]** New phone from iCloud with progress, and a reinstall after deleting the app.
