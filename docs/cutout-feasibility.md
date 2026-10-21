# Cutout feasibility

Phase 8a, 14 October 2026. Can Lily's iPhone 12 lift her garments out of their photos fast enough, without running out of memory, and cleanly enough for the sticker look (RD-07) to be the main way her clothes appear? This note describes the pipeline, what could be measured without her phone, how Jose runs the real test, and the proposed go/no-go limits.

The real answer needs her iPhone 12 and real photos of her clothes. Everything else is ready, so the test takes about 15 minutes.

**When it happens (17 October 2026).** No simulator can run the cutout (see below), and Jose doesn't have her phone during Stage A. So the go/no-go moves to Phase 22a, run on her iPhone 12 with her own photos, as described under [Running the benchmark](#running-the-benchmark-on-lilys-iphone-12). Before that, any real iPhone Jose owns can run the same benchmark as a quality-only check: whether the drawn samples and a few real garment photos come out clean enough for stickers. Its times and memory say nothing about an A14 and don't count toward the go/no-go.

**Status after Phase 22a (20 October 2026): waiting on Jose, with a real iPhone.** Real photos now come in from the camera and the photo picker (`docs/add-a-piece.md`), so there are real photos to cut out, but the go/no-go still needs an A14. Checked for 22a on an iPhone 12 simulator (iOS 26.5, Xcode 27.1): `-cutout-bench` opens on the Cutout benchmark, Choose photos opens the system picker with no permission prompt, and Use drawn samples runs all nine and reports "iPhone13,2 simulator, iOS 26.5" with no times, as Vision can't lift there. Nothing about the bench changed in 22a, and the steps below still apply. Until the go/no-go, real photos aren't cut out at all: a piece with a photo and no cutout shows its photo in a tile (`GarmentArtChoice`), which is the fallback for a failed lift too. Running the cutout when she adds a piece, and keeping the cutout next to the original, comes after the decision (22b keeps originals and cutouts side by side).

## What's where

| File | Holds |
|---|---|
| `Models/Services/Cutout.swift` | `CutoutService`, `CutoutResult`, `CutoutQuality`, `CutoutError` |
| `Models/Rules/CutoutThresholds.swift` | The proposed limits for sticker or tile, as a pure rule |
| `Services/Cutout/VisionCutoutService.swift` | The Vision implementation (new `Services` module, Apple frameworks only) |
| `Services/Cutout/ImageDownsampler.swift` | Reads the photo at the working size, with a pixel limit |
| `Services/Cutout/MaskSignals.swift` | The quality signals, read from Vision's masks |
| `Fixtures/Providers/StandInCutoutService.swift` | The stand-in for Stage A screens and tests (`NookServices.cutouts`) |
| `Fixtures/Sets/SyntheticGarmentPhotos.swift` | Garment-like pictures drawn with Core Graphics, for tests and the benchmark |
| `Features/Debug/CutoutBench/` | The benchmark screen (Debug builds only, `-cutout-bench`) |

## The pipeline

`VisionCutoutService.cutout(from:)` takes the photo's bytes (HEIC, JPEG, PNG) and returns a PNG of the subject on a transparent background, cropped to the subject, with quality signals.

1. **Read at a working size.** ImageIO checks the pixel count first and refuses anything over 100 million pixels without decoding it (`imageTooLarge`). It then makes an upright copy at most 1,536 pixels on the long side (`kCGImageSourceCreateThumbnailWithTransform`, so the EXIF orientation is applied). A 12-megapixel photo is never decoded at full size.
2. **Lift.** `VNGenerateForegroundInstanceMaskRequest` (iOS 17 and later, the same subject lifting as Photos) finds every foreground subject. A new request and handler are made for every photo: reusing a handler returns its cached result, which would make a second run look instant.
3. **Mask and crop.** `generateMaskedImage(ofInstances:from:croppedToInstancesExtent: true)` gives the subject on transparency, cropped to it. All subjects are kept, so a garment and its hanger come out together.
4. **Signals.** Read from Vision's 512 x 512 instance mask and the cutout's alpha (see below).
5. **Encode.** A PNG written from pixels only, so it carries no EXIF, GPS or camera data from the original photo. A test checks this with a photo that has a location.

It runs off the main actor (`@concurrent`), checks for cancellation between steps, and cancels Vision's request if its task is cancelled mid-run. Nothing leaves the phone and nothing is logged. Each result carries how long each step took, for the benchmark.

Errors are typed so a screen can tell them apart: `unreadableImage`, `imageTooLarge`, `noSubject`, `unsupported` (the device can't run it), `failed` and `cancelled`.

### Working size

1,536 pixels on the long side is the proposal. A sticker drawn about 500 points wide on a 3x screen needs about 1,500 pixels, and Vision's own mask is 512 pixels whatever the input. On the Mac, going from 1,536 to 2,048 more than doubled the decode time for a 12-megapixel JPEG (34 ms to 85 ms or more), because ImageIO can halve a JPEG cheaply while decoding (4,032 to 2,016) but has to decode at full size to reach 2,048. The benchmark has a switch for 1,024, 1,536 and 2,048 so this can be checked on her phone.

### Quality signals

| Signal | What it says | Proposed limit for a sticker |
|---|---|---|
| `coverage` | Share of the picture the subject covers | 5% to 90%. Below, Vision found a speck; above, it probably lifted the background |
| `instanceCount`, `largestInstanceShare` | How many subjects, and the largest one's share of everything lifted | With more than one, the largest is at least 80% (a hanger or tag is fine, two garments aren't) |
| `touchedEdges` | Which picture edges the subject touches (within 2 of 512 mask pixels) | At most one. A hook or a sleeve at one edge is fine; a garment running off two edges looks cut off |
| `softEdgeRatio` | Share of the subject's pixels with alpha between 10% and 90% | At most 25%. Fuzzy edges (white on white, fluffy knits) make a poor outline |
| `subjectBounds` | Where the subject is, as fractions | No limit; 8b can use it for framing |

These are a starting point, not a decision (`CutoutThresholds.proposed`). The benchmark shows the suggestion for each photo next to Jose's own "usable?" mark, and reports how often they agree, so Phase 8b can set the real limits from Lily's photos.

## What was measured without her phone

### The simulator can't be trusted with it

- On the iOS 26.5 and 27.0 simulators on an Apple-silicon Mac (Xcode 26.6), the request fails with Vision error 9, "Could not create inference context". The simulator offers only its GPU as a compute device for this request (`supportedComputeStageDevices`), and there's no CPU fallback to choose.
- On GitHub's `macos-26` runners the same request runs without an error but finds no subject, even in the plain drawn flat lay. That showed up in CI on this phase's first run.

- On an iPhone 12 simulator (iOS 26.5, Xcode 26.6, 17 October 2026), made to stand in for Lily's phone, the result is the same. Called directly, Vision lists one compute device for the request, "Apple iOS simulator GPU", and `perform` fails with error 9 (`com.apple.Vision`), "Could not create inference context". The service says `unsupported`, and the benchmark (`-cutout-bench`, `CutoutBenchTests`) shows "Subject lifting isn't supported here" for each sample. A simulator runs on the Mac's chip, not an A14, so even a working request there would time the Mac, not her phone.

So on any simulator the service reads the photo (bad input still gets `unreadableImage` or `imageTooLarge`) and then reports `unsupported` without asking Vision. The benchmark says "Subject lifting isn't supported here". The five tests that need a real cutout skip themselves with that reason (Swift Testing's `.enabled(_:_:)` with an async probe) and run on a device. Everything else is tested on the simulator: reading and shrinking photos, the orientation flag, the pixel limit, unreadable data, cancellation, error mapping, the signal arithmetic on hand-made masks and pixel buffers, the thresholds, the stand-in, the benchmark's report and runs, and a UI test of the benchmark screen. A build for a real device (`generic/platform=iOS`, no signing) compiles the device-only path.

### On the Mac

The same Vision request works on macOS. The pipeline's source files were compiled into a throwaway command-line harness (with `-O`) on an M1 Max running macOS 26.5.2, and run on the drawn samples at iPhone 12 photo size (4,032 x 3,024 JPEG):

| | Time |
|---|---|
| First cutout in the process (model load) | 362 ms |
| Warm cutout, 1,536 px (median of 16) | about 105 ms: decode 29 ms, lift 29 ms, mask and signals 28 ms, encode 6 ms |
| Warm cutout, 1,024 px | about 90 ms |
| Warm cutout, 2,048 px | 160 to 260 ms, mostly decode |

Every drawn garment was lifted and suggested as a sticker, with coverage 12% to 28%, one subject, and soft edges 4% to 8%. The trousers drawn running off the bottom touched the bottom edge only. The empty bed cover gave `noSubject`. Vision lifted only the tee in the tee-and-shoes picture and left the shoes out.

This shows the pipeline works and gives a floor for speed. It says little about her phone: an A14 is several times slower than an M1 Max, and flat drawn shapes on plain backgrounds are far easier than real cloth. Expect the iPhone 12 to take several hundred milliseconds per photo.

### Photos picker facts (iOS 26.5 simulator)

- `PhotosPicker` runs outside the app. It opened with no permission prompt, and the app has no `NSPhotoLibraryUsageDescription` or any other privacy key (checked in the built Info.plist). The picker itself shows "Private Access to Photos: … can only access the items you select."
- The picker says **"Location Is Included"** by default, so a picked photo's bytes can carry its GPS position unless she turns that off in the picker's options. The cutout PNG has no metadata whatever the input. Since Phase 22a the stored original has none either: `PhotoCleaner` keeps an upright copy made from the pixels alone (`docs/add-a-piece.md`).
- The benchmark asks for `preferredItemEncoding: .current`, so it gets the photo as stored (usually HEIC) without the picker converting it.

## Running the benchmark on Lily's iPhone 12

### Before you start (5 minutes)

1. **Photos.** On her phone, photograph about 20 of her real garments and put them in an album (for example "Cutout test"). Aim for a mix:
   - flat lay on the floor or a table, several;
   - on a hanger against a wall or door;
   - on the bed;
   - dark on dark (black jeans on a dark cover);
   - white or cream on white;
   - patterned or striped;
   - shiny or satin;
   - knit or fluffy;
   - shoes, a bag and an accessory;
   - one or two that run off the edge of the frame, and one with two pieces in it.
2. **Signing.** Copy `Configs/Signing.local.xcconfig.example` to `Configs/Signing.local.xcconfig` and set `DEVELOPMENT_TEAM` to your team ID. The file is ignored by git.
3. **The phone.** Connect it, trust the Mac, and turn on Developer Mode (Settings › Privacy & Security › Developer Mode). It must be on iOS 26 or later.

### Run it (10 minutes)

1. In Xcode, pick the `NiftyOutfitNook` scheme and her iPhone, then Product › Scheme › Edit Scheme › Run › Arguments, and add `-cutout-bench` under "Arguments Passed On Launch". This edits the shared scheme, so untick or remove it afterwards and don't commit it.
   From the command line instead: build to the phone with `xcodebuild -project NiftyOutfitNook.xcodeproj -scheme NiftyOutfitNook -destination 'platform=iOS,name=<phone name>' -allowProvisioningUpdates build`, install the app from `build`'s products with `xcrun devicectl device install app --device <device id> <path to NiftyOutfitNook.app>`, then launch it with `xcrun devicectl device process launch --device <device id> --terminate-existing com.jsayram.niftyoutfitnook -cutout-bench`.
2. Run. The app opens on **Cutout benchmark** instead of the room. (It's a Debug build. Vision's own work runs in system code, so this barely changes the lift time; our own steps run unoptimised, so they're a little slower than they'll be in Release.)
3. **Cold start:** with the app freshly launched, tap **Choose photos**, open the album, select all and tap the tick. Don't use the drawn samples first, or they'll take the cold start.
4. Wait for **Photos done 20 of 20**. Each photo is cut out twice in a row; the first photo's first run includes Vision loading its model.
5. Scroll through and tap **Yes** or **No** under "Usable as a sticker?" for every photo. Judge it as Lily would see it: would this look right as a sticker with a white outline? A photo with no subject counts as No.
6. **Export results** (share to Notes, Mail to yourself or AirDrop) or **Copy results**. The text has numbers only: no pictures and no photo names.
7. Optional: switch the working size to 1,024 and 2,048 and tap **Run again** for each, and export those too (warm times only).
8. Close the app. Remove `-cutout-bench` from the scheme.

If the app is closed by the system mid-run, that's a memory failure: note which photo it was on.

Optional, for the tests that skip on the simulator: with the phone connected, `xcodebuild test -project NiftyOutfitNook.xcodeproj -scheme NiftyOutfitNook -destination 'platform=iOS,name=<phone name>' -only-testing:ServicesTests` runs them for real.

## Proposed go/no-go

Cutouts become the main garment look (RD-07) if all of these hold on her iPhone 12. The benchmark checks each one and shows pass or fail.

| Check | Proposed limit | Why |
|---|---|---|
| Warm time, median | at most 1 s | Adding a piece happens once per garment and can carry on in the background, so a second is fine; the form never waits for it |
| Warm time, p90 | at most 2 s | No photo should feel stuck |
| Cold start (first after launch) | at most 4 s | Happens once per launch, while she's still on the form |
| Peak footprint while cutting out | at most 300 MB | Well under what iOS allows a foreground app on a 4 GB phone, leaving room for the rest of the app |
| Usable as a sticker | at least 70% of photos | Then the tile fallback (RD-07.2) is the exception, as the amendment intends |

Between 50% and 70% usable: go, but Phase 8b should make the tile look as good as the sticker, since it will be common. Under 50%, or any speed or memory failure: no-go for stickers as the main look. Tiles become the main look, and cutouts an option where they come out clean.

The "suggestion agrees with the mark" number is for Phase 8b, not the go/no-go: it says whether the signals can choose sticker or tile on their own.

## Results (to fill in)

Device: iPhone 12, iOS ____ . Build: Debug, `develop` at ______ . Date: ______ .

| | 1,024 px | 1,536 px | 2,048 px |
|---|---|---|---|
| Cold start | n/a | | n/a |
| Warm median | | | |
| Warm p90 | | | |
| Peak footprint | | | |
| Least headroom | | | |
| Usable (marked) | | | |
| Suggested stickers | | | |
| Suggestion agrees with mark | | | |

| Photo kind | Count | Usable | Notes |
|---|---|---|---|
| Flat lay | | | |
| Hanger | | | |
| On the bed | | | |
| Dark on dark | | | |
| White on white | | | |
| Patterned | | | |
| Shiny | | | |
| Knit or fluffy | | | |
| Shoes, bag, accessory | | | |
| Runs off the edge | | | |
| Two pieces | | | |

Decision: go / go with common tiles / no-go. Signed off by ______ on ______ .

Paste the exported text below this line.

## Decisions for Jose

1. **A new `Services` module.** Decision 0001 said later stages add Services; the Vision cutout is the first real service, so it starts now. It depends on Models only and uses Apple frameworks only (Vision, ImageIO, Core Video, Accelerate). The app links it, but in Stage A only the Debug benchmark uses it: `NookServices.cutouts` is the stand-in, as Stage A is sample data only.
2. **Every lifted subject is kept**, not just the largest. A garment on a hanger comes out with the hanger. Phase 8b can switch to the largest subject if Lily's photos show that's better; the signals already say when there's more than one.
3. **The cutout is a PNG.** It's lossless with transparency and carries no metadata. HEIC with alpha would be smaller; storage is decided in Phase 22.
4. **The benchmark is Debug only** and `scripts/check-release.sh` now checks a Release build has none of it and no `-cutout-bench` argument.
5. **No sticker outline yet.** The white outline, padding and tile fallback are Phase 8b (`docs/stickers.md`). Since 8b the benchmark shows each photo as a sticker and as a tile, so the run on her phone doubles as 8b's checkpoint.
