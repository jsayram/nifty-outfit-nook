# Image storage and caching

Phase 22b, 21 October 2026. Where her photos, cutouts and stored try-on pictures live on the iPhone, the thumbnails made from them, the memory cache, what happens when the iPhone is nearly full, and how files nothing points to are removed. Builds on 22a's photo intake (`docs/add-a-piece.md`) and 21b's backups (`docs/decisions/0004-backup-and-recovery.md`).

Spec: PRD §9.2.4 (a delivered picture is kept until she deletes it), §15.3 (storage planning figures), §15.4 (a piece deleted for good clears covered copies), SECURITY_STANDARD.md §4 (Data Protection `complete`; caches hold no sensitive data, or are protected and cleared), DATA_MAP.md.

## What's where

| Folder | Holds | Backed up | Protection |
|---|---|---|---|
| `Application Support/Photos` | One file per image, named by its ID: originals (JPEG, metadata stripped), cutouts (PNG, next to their original), stored try-on pictures | Device backups and exports | `complete` |
| `Library/Caches/Thumbnails` | `<image id>-512` and `<image id>-1024`: JPEG, or PNG for an image with transparency | Never (cache folder, and marked excluded) | `complete` |
| `Store/RestoreSafetyCopy/Photos` | The photos as they were before a restore, for Undo restore (21b) | Never | `complete` |

| Code | Does |
|---|---|
| `Services/Photos/PhotoFileStore.swift` | Writes a new image (`add`, `addCutout`) only when 50 MB stays free afterwards; reads and removes |
| `Services/Photos/ThumbnailCache.swift` | Makes, keeps and trims thumbnails |
| `Services/Photos/StoredImageFiles.swift` | Removes files nothing points to: `release` and the launch sweep `removeUnused` |
| `Services/Photos/LocalPhotoIntake.swift` | `StoredPhotoProvider`: small sizes from thumbnails, large ones from the image itself |
| `Models/Services/ImageFiles.swift` | The `ImageFiles` protocol the screens use (`NookServices.imageFiles`); `NoImageFiles` where there are no files |
| `Features/Shared/GarmentArt/GarmentImageLoader.swift` | The memory cache of decoded pictures |

## Originals next to cutouts

A garment points to two files: `photo` (the cleaned original) and `cutout.image` (the PNG lifted out of it). Both are plain files in the photo folder, both travel in exports, both get thumbnails and both go when the piece is deleted for good. `PhotoFileStore.addCutout` keeps a `CutoutResult` and returns the `GarmentCutout` to save on the piece. Nothing calls it from Add a piece yet: running the cutout on her photos waits for the go/no-go on her iPhone 12 (`docs/cutout-feasibility.md`).

## Thumbnails

Grids ask for about 500 pixels and detail screens for up to about 1,000, while an original is 4,032. So the provider serves any size up to 512 from a 512-pixel thumbnail and any size up to 1,024 from a 1,024-pixel one; anything larger reads the image itself. A thumbnail is made the first time it's asked for, from the pixels alone (no metadata), and written atomically. The loader then shrinks those bytes to the exact size shown.

The folder holds at most 200 MB. Past that it trims to 150 MB: thumbnails not used since launch first, then the least recently used. The order is kept in memory, so no file dates are read (they would need a privacy manifest reason). A thumbnail that can't be written (a full iPhone, a failed write) is still returned to the screen; it's just made again next time.

## The memory cache

`GarmentImageLoader` keeps decoded pictures in an `NSCache` with two limits: 300 pictures and 64 MB of pixels. A 500 by 375 grid picture is about 750 KB, so the byte limit, not the count, is what holds when she scrolls a large closet. It empties under memory pressure, as before.

## When the iPhone is nearly full

- **A new photo** is only written if 50 MB stays free afterwards. Otherwise nothing is written and Add a piece shows its existing "That photo couldn't be saved. Your iPhone may be out of space. Nothing was saved."
- **Thumbnails** aren't written while less than 500 MB is free, and the folder is halved to give space back. Screens still get their thumbnail from memory.
- **A failed write** of any kind leaves nothing half written: every write is atomic, and a stray temporary file in the photo folder is removed by the next launch sweep.
- The store's own checks (migrations, the restore's safety copy, exports) are 21a's and 21b's, unchanged.

## Files nothing points to

What counts as pointed to is read from the store each time, through the reading backups use (`BackupContents.photoIDs`): pieces and their cutouts, pieces in Recently deleted, unsaved drafts and what they started from, the try-on photo, stored try-on pictures, and copies kept from a restore for review. A file two records share stays until both have gone, and nothing is removed while the store can't be read.

| When | What goes |
|---|---|
| A piece is deleted for good (Delete now, or the 30-day purge) | Its photo and cutout, its unsaved Edit's photos, and the stored images of the try-on pictures that show it, from the photo folder, the thumbnails and the restore's safety copy, so Undo restore can't bring them back (0004 decision 3) |
| Delete picture, once its Undo has gone (she leaves Saved Looks, or deletes another picture) | The picture's stored image and its thumbnails. Undo before then brings the same picture back with its file |
| A made picture whose record couldn't be kept, or Try it on cancelled after making | Its stored image |
| Each launch, away from the screens | Every file in the photo folder no record points to (a photo a saved edit replaced, a discarded draft's photo left by a kill, photos from a restore's old closet), anything there that isn't an image, and every thumbnail whose image is gone. Files written since this launch are left alone, since the draft that will point to one may not be saved yet |
| Delete my data | Every folder above |

The sweep and `release` hold the same lock as a restore and Undo restore, so they never see the photo folder and the store half way through a restore. Undo restore now also leaves out the try-on pictures that show a piece deleted for good since the restore (21b only left out the piece).

## Backups

Exports carry exactly the files the records point to (21b's rule): originals, cutouts, stored pictures and the try-on photo, now also the photos of copies kept for review. Thumbnails, the cache and the safety copy are never in an export or a device backup. A restore moves the copy's images into place and, after Replace, removes the old closet's; the next launch sweep catches anything else.

## HEIC, later

Originals and thumbnails are JPEG. HEIC would be about half the size (a 12 MP original of roughly 1.5 MB instead of 3), but a HEIC encode never finished on the iOS 26.5 simulator (22a), so the tests and the checkpoint would hang. To try it on a device:

1. Add `PhotoCleaner.Options.format` (`.jpeg` default, `.heic`), and write with `UTType.heic` when `CGImageDestinationCopyTypeIdentifiers()` lists it and the device isn't a simulator.
2. Nothing else needs to change: files have no extension and every reader goes through ImageIO, which detects the format. Exports carry the bytes as they are.
3. Measure on Lily's iPhone 12: encode time per photo (it runs off the main actor, but she waits for it in Add a piece), file size, and decode time for a 1,024 thumbnail. Keep JPEG for thumbnails either way; they're small and decode fastest.
4. Turn the HEIC cases in `PhotoCleanerTests` and `LocalPhotoIntakeTests` on for the device run (they're skipped on the simulator today).

## Checkpoint: a large closet

Measured on 21 October 2026 on the "22b iPhone 12" simulator (iOS 26.5, Xcode 27.1, Debug build), with `PhotoClosetScrollTests` (`TEST_RUNNER_NOOK_PERFORMANCE=1`). The closet is her own, in the store: 2,400 pieces from the large fixture set, each with a 3,024 by 4,032 JPEG original and a cutout PNG (`-seed-photo-closet 2400`, drawn scenes with grain so the files are about a real photo's size). The app scrolls the grid itself (`-frame-stats -auto-scroll`), 20 seconds down at 4,000 points a second and 20 back, about 1,600 pieces, and counts frames with a display link. XCUITest's swipes weren't used for the numbers, because the runner's screen queries stalled the app's main thread on their own (two 75 ms frames every 3 seconds, even with nothing scrolling).

| Run | Hitch time | Hitches in 40 s | Longest frame | Peak memory |
|---|---|---|---|---|
| Thumbnails being made (folder emptied first) | 1.3 ms/s | 3 | 34 ms | 89 MB |
| Thumbnails already made | 0.8 and 1.7 ms/s (two runs) | 2 and 4 | 33 ms | 88 to 90 MB |
| Thumbnails off (`-thumbnails off`) | 1.3 ms/s | 3 | 33 ms | 89 MB |
| First launch, straight after writing the 4.3 GB of photos | 35 ms/s | 84 | 37 ms | 89 MB |

Apple counts under 5 ms/s as good. Every steady run is well under it, and memory stays flat at about 89 MB however far she scrolls. The first launch after seeding was slow because the system was still writing 4.3 GB of new files; it isn't something she'd meet. On the Mac's CPU the simulator hides the difference thumbnails make, so the per-picture cost was measured directly with ImageIO: making a 480-pixel grid picture takes 18.5 ms from the 1.9 MB original and 2.1 ms from its 30 KB thumbnail, about 9 times less. On an A14 that's the difference that matters for battery and for fast flings.

**Storage footprint** for the 2,400 pieces: 4.1 GB of originals (about 1.8 MB each here; real iPhone 12 JPEGs are 2 to 4 MB), 190 MB of cutouts (35 to 360 KB each; the drawn cutouts are simpler than real ones, which PRD §15.3's 4.4 to 4.8 MB per piece allows for), 6 MB of store, and 45 MB of thumbnails for the 1,677 images scrolled past (about 27 KB each, so about 130 MB if she scrolled everything, inside the 200 MB limit).

**Needs a device:** the same run on Lily's iPhone 12 for hitches and memory on an A14, the Data Protection class on the thumbnail folder, and HEIC as above.

## Tests

- `ThumbnailCacheTests` (14): made once then read, also after a relaunch; one file per size and large sizes from the image; no metadata; a cutout stays PNG with transparency; left out of backups; the byte limit trims the least recently used; short of space nothing is written but the thumbnail comes; a failed write isn't an error; removing an image removes its thumbnails and strays; only thumbnail names are read; the provider serves small sizes from thumbnails; a photo isn't written when the iPhone would be too full, and the intake then saves nothing; a cutout kept next to its photo.
- `StoredImageFilesTests` (9): the launch sweep keeps everything a record points to (including Recently deleted, drafts, the try-on photo, stored pictures and review copies) and removes the rest with thumbnails and strays; a photo written since launch is left alone; a shared file is never released; deleted for good also leaves the safety copy; Delete now and the 30-day purge take every file of the piece and its pictures and nothing else; an export after Delete now carries exactly the right files and restores them byte for byte, with no thumbnails; Undo restore doesn't bring back a piece deleted since, its pictures or their files.
- `SavedPicturesTests.aDeletedPicturesFileGoesWhenItsUndoDoes`, `TryOnModelTests.aPictureThatCantBeKeptLetsGoOfItsFile`, `GarmentImageLoaderTests.theMemoryCacheKeepsToItsByteLimit`.
- `RestoreTests.replaceIntoAFullCloset…` now deletes the purged piece's pictures first, as the app does, since Undo restore leaves them out.
- UI, `PhotoClosetScrollTests`: the checkpoint above, skipped unless asked.
