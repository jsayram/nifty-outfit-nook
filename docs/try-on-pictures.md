# Try it on and the Pictures tab

Phase 12b, 15 October 2026. Try it on makes a try-on picture of one look, only when she asks. Her pictures live on Saved Looks' Pictures tab, each linked to its look, and each look lists its pictures. In Stage A every picture is simulated: the look's pieces on a plain backdrop, with no person in it, made on the phone. Real pictures are Phase 33, behind its gates. Since 17 October 2026 the fixtures also hold six sample previews of a woman wearing a look (see "Sample previews" below).

Spec: amendment RD-06 (Try it on per look, only on tap, labelled Simulated, linked to its look), RD-08 (Pictures holds only saved try-on pictures, each linked to its look; search on each tab), RD-08.2 (each picture opens its look, and the look shows its pictures), RD-04.2 (every try-on picture says Simulated) and the mockup README's decisions 3 to 5 (no avatar; the only image of her in clothes is an optional try-on picture). PRD §7.5 and §9.2.4 (every delivered picture is kept until she deletes it, with the look as it was), §9.2.1 step 5 (keep the picture before saying it's ready), FR-56 (simulated services in development), FR-59 (offer a matching picture before making another) and §14.4 (pictures will use an allowance). DATA_MAP.md: try-on pictures are Sensitive. The visual references are `saved.html?tab=pictures`, `picture.html` and the picture row in `look.html` in `closet/prototypes/RoomDirectionMockups/screens`.

## What's where

| File | Holds |
|---|---|
| `Models/Looks/TryOnPicture.swift` | `TryOnPicture`: its look's ID, the look as it was (`CapturedLook`: pieces, name, occasion), the image (`.simulated`, or `.generated` from Phase 33) and when it was made |
| `Models/Rules/TryOnLinks.swift` | Where a picture's look is now (current, changed since, not saved), a look's pictures, the picture to reuse (FR-59) |
| `Models/Services/Stores.swift`, `Providers.swift` | `TryOnPictureStore` and `TryOnService` |
| `Fixtures/Stores/InMemoryTryOnPictureStore.swift`, `Fixtures/Providers/SimulatedTryOn.swift` | The in-memory store, and Stage A's Try it on |
| `Features/TryOn/TryOnPictureView.swift` | How a picture is drawn, and hidden while the app isn't active |
| `Features/TryOn/TryOnModel.swift`, `TryOnSheet.swift` | The Try it on sheet and its steps |
| `Features/TryOn/TryOnText.swift` | The words for pictures |
| `Features/SavedLooks/Pictures/` | `SavedPictureItem`, `SavedPicturesGrid`, `PictureDetailModel`, `PictureDetailPage`, `PictureDetailScreen` |

## The picture

A simulated picture is the look's sticker bundle on a plain studio backdrop in the room's stone and sand, portrait 4:5, with a "Simulated" badge in its corner. No person, no body, no silhouette. It's drawn on the phone each time from the pieces the look had when the picture was made, so nothing is stored but the record. Pieces that later left her closet aren't faded in it: a picture doesn't change. A piece deleted for good can't be drawn, so it's left out.

Below 120 points the badge is left off and the words next to the picture say Simulated instead (the look's list of pictures, and the Pictures tab's rows at the accessibility sizes).

**Hidden in the app switcher.** The security standard (§4) asks for try-on pictures to be hidden in the app switcher's snapshot. While the scene isn't active, a picture draws only its backdrop and an eye-slash symbol. Simulated pictures don't show her, but the real ones will, so this is in place now.

## Try it on

From Your looks (the version on screen) and from look detail. A full-height sheet titled Try it on, Simulated:

| Step | What she sees |
|---|---|
| Before | "Try it on makes one picture of this look, only now that you ask." That it's simulated here, her pieces with no person, and nothing leaves the phone. From Your looks, for a look that isn't saved: "Making a picture also saves this look, so the picture has a look to go with." The note "Simulated pictures are free in this test build." Then Make a picture |
| She already has one | The picture of exactly these pieces, "You already have a picture of this look", See the picture, and Make another (FR-59) |
| Making | "Making a picture", "Simulated. Leaving stops it, and nothing is kept.", Cancel. About a second in the demo |
| Made | The picture, "Saved to Pictures" (announced to VoiceOver), See the picture, Done |
| Offline | "Pictures need a connection", "Nothing was made or used. Try again when you're online.", Try again |
| Didn't finish | "The picture didn't finish", "Nothing was used. Try again in a moment.", Try again |
| Not kept | "The picture couldn't be kept" when the store failed after making it |

The picture is kept in the store before the sheet says it's made (PRD §9.2.1 step 5). Nothing makes a picture except Make a picture (RD-06.2). Your looks still dims Try it on when offline, as in 10b.

**From Your looks** the look may not be saved. A picture needs a saved look to link to, so making it saves the look first, under the name Save look would give it, and the picture keeps that name. If making fails, nothing is saved. See the picture switches to Saved Looks with the picture open; Back goes to the Pictures tab.

**From look detail** See the picture pushes the picture, and a new picture shows in the look's list when the sheet closes.

**Allowance (Phase 30a).** PRD §14.4 has pictures use an image allowance that comes with styling access. While pictures are simulated on the phone (`NookServices.tryOnIsSimulated`) they cost nothing and the sheet keeps the free note. Once the image service is real (33a), the sheet says "Uses 1 of the 30 try-on pictures that come with styling access each month." (30 is a placeholder, decision D12), or, without access, "Try-on pictures come with styling access. Your saved pictures stay free to open." with See styling access, and Make a picture isn't offered (`TryOnAllowance`, `docs/payments.md`). The server counts and enforces the allowance (24b); credit packs are 30b.

## The Pictures tab

Top to bottom, as in `saved.html?tab=pictures`:

- **Saved Looks** and "3 pictures".
- **Looks · Pictures.**
- **Search your pictures** and the same piece chips and colour swatches as Looks. One search and one set of chips serve both tabs, so "navy" stays set when she switches. On Pictures they match the look each picture came from: its name now (or then, if it has left), its occasion, and the pieces the picture shows.
- **The grid**, newest first: each picture with its badge, the day it was made ("Sep 6", with "Earlier version" or "Look deleted" when that applies), and under it the look's name as a link with a chevron. The picture opens picture detail; the name opens the look. Two or more columns of at least 150 points; at the accessibility sizes one picture per row beside its words.

No pictures yet: "No try-on pictures yet", "A picture shows one of your looks. Pictures are made one look at a time, only when you ask.", two steps (save a look; open it and tap Try it on), and See your looks. No matches, loading and a store failure work as on Looks. A picture store that can't be read fails only this tab.

## Picture detail

Top to bottom, as in `picture.html`:

- **Try-on picture** and "Simulated · Made Sep 6".
- **The picture**, 280 points wide.
- **From the look**: the look's small bundle as it is now, its name and See the look, opening look detail. When the look changed since (a swap): "The look has changed since. This picture shows an earlier version." When it has left Saved Looks: no link, "Look deleted", and "Its look isn't in Saved Looks any more. The picture stays until you delete it."
- **Delete picture**, quiet. Back to where she came from, with Undo in a toast and, on the Pictures tab, on a line over the pictures that stays until she leaves the tab, as Delete look does. Undo puts back the same picture, linked as before.
- A note: the picture is simulated, it shows the look's pieces and not her, a later version will show her wearing it, and pictures show the style, not the exact fit.

Going between a picture and its look goes back rather than piling up screens: See the look on a picture opened from that look is Back, and the other way round.

## Look detail

Under the four buttons, **Pictures**: one row per picture, newest first, with a small picture, "Try-on picture" and "Simulated · Made Sep 6" (plus "Earlier version"). Each opens picture detail. Nothing shows when the look has none.

## Links between pictures and looks

A picture points at its look by ID and keeps the look as it was. The look doesn't point back (12a's `Look.tryOnPictureID` is gone), so there's one link to keep right, a look can have several pictures, and deleting a picture never changes the look.

| What happens | Its pictures |
|---|---|
| Swap a piece on the look | Stay linked, now "Earlier version" |
| Rename | Show the new name |
| Delete look (a result unsaved, or her own deleted) | **Stay.** The toast says so: "Deleted Lace date night. Its picture stays in Pictures." Each shows the look as it was, under its old name, with no link |
| Undo Delete look | Linked again, since the look comes back with its ID |
| Unsave on Your looks | Same as Delete look |
| Delete picture | Only that picture goes; Undo brings it back |

Keeping pictures follows PRD §7.5 and §9.2.4: every delivered picture is kept until she deletes it, and no other change removes it. It also suits the real thing, where a picture costs an allowance.

## Fixtures

The demo has three pictures, as in the mockups: two of Interview navy and pink (the newer of the look as it is, the older of an earlier version with the cream sweater) and one of Lace date night. The large set has one for every third saved look (165). Empty has none.

`-fixtures demo:offline` makes Try it on fail offline, `demo:picture-fails` makes it not finish, `demo:slow` takes three seconds, and `demo:stores-fail` fails the picture store too.

## Accessibility

- A picture reads as one image: "Simulated try-on picture of Interview navy and pink: Navy cardigan, Cute pink shirt, Navy dress pants, Nude pointed flats. No person is shown."
- On the Pictures tab the picture is a button with the day (and "Earlier version" or "Look deleted") as its value and "Opens the picture." as its hint; the link under it is "See the look: Interview navy and pink".
- On picture detail the look row is one button, "See the look: …". A row in the look's pictures reads "Try-on picture" with "Simulated · Made Sep 6".
- The sheet announces "Saved to Pictures". The making state's dots only fade under Reduce Motion (`NookLoadingIndicator`).
- At AX5 the grid becomes rows and the sheet opens full height.

## Performance

The large set's 165 pictures load and filter well inside the test's bounds (`SavedPicturesTests.largeSetStaysQuick`, 250 ms bounds, three times that on CI). Each picture's bundle, name and search words are worked out once when the pictures load. The grid is lazy.

## Tests

- `TryOnLinksTests`: a picture keeps its look, current, changed and not saved (deleted or unsaved), a look's pictures newest first, the picture to reuse, comparing pieces whatever their order and IDs.
- `TryOnFixtureTests`: the store's order, delete and save again, failure; the simulated picture of the look as it is, failing modes and cancelling; the demo's links, empty and large sets; behaviours reaching Try it on.
- `TryOnModelTests`: nothing made until asked, then kept; a picture she already has, and Make another; offline and not finished keep nothing; a store failure isn't shown as ready; Cancel; saving the look first from Your looks, with the picture keeping its name.
- `SavedPicturesTests`: the tab's order, empty and failure; search and chips on the look a picture came from; picture detail's facts and notes; Delete picture and Undo; a look's pictures; Delete look keeps its pictures and Undo links them again; a swap makes them earlier versions; the large set's speed.
- `SavedLooksSnapshotTests` (13 more images): the Pictures tab in light, dark and AX5 and empty; picture detail in light, dark and AX5, of an earlier version, with its look deleted, and hidden; the Try it on sheet from Your looks and with a picture she has. Look detail's images now show the Interview look's two pictures.
- UI, `SavedLooksTests`: save a look on Your looks, Try it on, See the picture, See the look, Back to the picture, Back to the Pictures tab with the new picture; and from Lace date night, open its picture, See the look goes back, Delete picture, then Undo on the Pictures tab. `YourLooksTests` checks the sheet opens and makes nothing.

## Decisions for Jose

1. **Pictures stay when their look is deleted**, with a toast that says so and a note on the picture (above). The alternative was deleting them with a confirmation; the PRD keeps every delivered picture until she deletes it.
2. **No person in the simulated picture.** The mockups and the README's 7 October exception show a generic illustrated person in placeholders; this phase's brief asked for no person, avatar or body drawing, so the picture is the look's pieces on a backdrop. The wording says "not you" and "no person is shown".
3. **Try it on from Your looks saves the look.** A picture needs a look to link to. The sheet says so before anything happens.
4. **A picture of exactly this look is offered first** (FR-59), with Make another, rather than making a duplicate.
5. **Delete picture has Undo, not the mockup's confirmation**, as Delete look does.
6. **No Favorite on a picture.** Favorites have no Stage A screen (RD-08).
7. **One search and one set of chips for both tabs.**
8. **The look row on picture detail shows the look as it is now**; the picture shows it as it was.

## Left for later phases

- **14a (done):** the try-on photo sheet in Profile (`docs/profile.md`).
- **15b (done):** on iPad a picture opens beside the Pictures grid (`docs/ipad.md`).
- **22b (done):** a generated picture's image is a stored file, removed once Delete picture's Undo has gone, or when a piece it shows is deleted for good (`docs/image-storage.md`).
- **30a (done):** the picture allowance follows styling access; credit packs are 30b.
- **33a (done):** real pictures, with her face kept on the phone ("Real pictures (33a)" above). 33b (the try-on photo setup) and 33c (the privacy walkthrough) are next.
- **21b and 22b (done):** deleting a piece for good deletes the pictures that show it, with their files.

## Real pictures (33a)

Phase 33a, 22 October 2026. Real try-on pictures with her face kept on the phone, as Jose approved on 19 October 2026 (closet `THREAT_MODEL.md` D1, `SWIFT_BUILD_PLAN.md` Phase 33a). They are on with the real backend, or with `-cloud-tryon [normal|slow|fails]` against the fake one in debug builds; otherwise pictures stay simulated, as above. The backend calls Black Forest Labs' FLUX.3 only when its key is set (backend README, "Try-on (33a)"); until then it answers with a stand-in picture.

### What happens

1. **Her OK first.** Try it on asks for try-on's own consent (`TryOnConsent`, version `tryon-1`), in the words of closet `compliance/IN_APP_PRIVACY_TEXT.md`, including the approved sentence that Black Forest Labs may keep the photos and use them to improve their models. No consent, nothing is prepared or sent. Privacy and terms gets a Try-on pictures switch; Delete my data erases the consent.
2. **On the phone** (`PhoneTryOn.prepare`, Services): her try-on photo at up to 1,280 pixels. `PersonAnalyzing` finds her outline (Vision person segmentation, accurate), her face (face rectangles and landmarks) and her neck and shoulders (body pose). `HeadMasking` builds the head shape: her outline above the chin line, near the face, joined with a padded oval around the face, so it takes in her hair; it's filled with flat grey (128). The same outline puts her on a plain studio backdrop (a soft vertical gradient), so her room never leaves the phone either.
3. **Fail closed.** It refuses, and says why kindly, when there's no person, no face, more than one face or outline, an outline too unsure (over 30% of it neither clearly in nor out), a face outside her outline, or the grey not covering every pixel of the face's box. Then the check that matters: the analyzer looks for a face in the faceless photo, both in its pixels and in the exact JPEG that would be sent, and must find none. If the checks can't run (Vision fails), nothing is sent.
4. **Sent** (`PhoneTryOn.dress`): only that JPEG and up to nine garment photos (cutout on white when there is one, otherwise the photo, at up to 768 pixels), each with its ID, category and kind. No metadata in any of them. The backend builds the prompt from those alone. POST /v1/try-on answers "still running" first (409, Retry-After 5); the client asks again with the same Idempotency-Key and body until the picture comes back, within try-on's 360-second deadline (Phase 26).
5. **Back on the phone** (`PhoneTryOn.restore`, `HeadRestore`): if the model moved her, her head follows her neck and shoulders (body pose; small moves are ignored, moves over 8% of the width aren't trusted). Only where the flat grey is still there does her original outline go back, so a hat, scarf or collar the model drew stays in front. Grey outside her outline becomes the original backdrop times the brightness change measured on nearby backdrop the model left alone. Edges are feathered.
6. **Kept** as a stored file (22b), linked to its look, with `TryOnPicture.sent`: the exact faceless JPEG and garment JPEGs that left the phone. Deleting the picture, or a piece it shows for good, removes them too (21b, 22b). The files only the phone needed (her photo with her real head on the backdrop, her outline, the head shape) go as soon as the picture is kept, or when the job fails or she cancels.

### A background job

A try-on is a 27c job (`AIJob.Kind.tryOn`): the sheet says "Dressing you" with Keep browsing and Cancel, and she can leave. The banner says "Your try-on picture is ready" (or that it didn't finish), Saved Looks gets a dot, and in the background a notification says so; tapping either opens the picture (or its look, to try again). One key from the first try to the last, so a job resumed after a relaunch is never run or charged twice. The upload's files are kept while a job points to them, so the launch sweep doesn't take them.

### See what was sent

Every real picture has See what was sent: the faceless photo and each garment photo, as the bytes that were sent, with the approved line about Black Forest Labs. They're hidden while the app isn't active, like the pictures. Real pictures aren't labelled Simulated.

### Simulator and device

Simulators can't run Vision's person segmentation, face or pose requests (iOS 26.5: "Could not create inference context", "E5RT is not supported"). So the tests and the debug checkpoint use `SyntheticPersonAnalyzer`, which reads a drawn stand-in figure (`SyntheticPerson`, never a photo of anyone) from its colours; covering its eyes with grey leaves no face to find, as Vision would. `-seed-tryon` puts that figure in her own closet as the try-on photo, with three drawn pieces and a saved look. Both are debug-only and checked out of Release by `scripts/check-release.sh`. With the real backend on a simulator the Vision checks fail and nothing is sent.

The real Vision path was checked on a Mac (22 October 2026) on the AI-generated sample person (`SampleWardrobe/people/person.jpg`): one face found, none after masking (also in the JPEG), and no grey left after restoring onto a copy moved by 14 and 9 pixels, with the move found from the body pose.

**Device checklist (Jose's iPhone 14, then Lily's iPhone 12):**

1. Set up a try-on photo of herself, standing, facing the camera. Try it on with a look of 2 to 5 pieces against the fake backend (`-cloud-tryon slow`). See what was sent: no face, no room, a plain backdrop, hair fully grey.
2. Refusals: a photo with two people, one facing away, one with her face half out of frame, one in a busy room. Each says why and sends nothing.
3. Long hair down, curly or afro hair, a ponytail, glasses, a hat or hood in the photo: the grey covers all of it.
4. Timing and memory on the iPhone 12 (Vision accurate segmentation plus the pixel work at 1,280 pixels).
5. With the real backend and BFL key (Jose's OK, about US$0.05 a picture): the 19 October hard cases redone in the app, hats ("pulled down over the top of the grey shape"), and the restore with no seam.

### Tests

- `HeadMaskingTests`: no face after masking and every face pixel grey, hair taken in, neck left, the room gone; refusals for two people, no face, no person, an unsure outline, a second face, a face outside her outline.
- `HeadRestoreTests`: no grey left and her face back; her head following a moved neck; a hat staying in front; leftover grey becoming the backdrop as the model lit it; large or missing moves ignored.
- `PhoneTryOnTests`: only the faceless photo and garment photos sent, as kept, with no metadata and within the contract's sizes; the head back on and the work files gone; a face still found after masking, two people, no face, no photo, no garment photos and checks that can't run all send nothing.
- `TryOnJobsTests` (real store, `ManualClock`): one key across a late answer, the picture kept with what was sent, the banner and dot, failure and Cancel letting go of the files, and a relaunch asking again with the same key.
- `RealTryOnModelTests`: no consent means nothing prepared or sent; Allow then a picture as a job; a refused photo explained with nothing sent; leaving the sheet leaves the job running.
- `TryOnGatewayTests` and `ContractTests`: still running then the picture, counted once, replayed with the same key; only the contract's fields on the wire; a failed picture not counted; consent to another text refused; the try-on limits match the contract.
- UI, `TryOnTests` (skipped on pull requests): the checkpoint below.

## Sample previews

The fixtures carry six AI-generated pictures of the sample woman wearing a look (`Tests/NookTestSupport/SampleWardrobe/tryon`, no real person). They are `.generated` pictures with a `PhotoReference.sample`, shown through the image loader.

- `TryOnPictureView` draws the photo whole on the backdrop (the previews are 9:16, the frame stays 4:5) with the Simulated badge. Until the photo has loaded, or if the provider has none, it draws the look's bundle as for any simulated picture. A still image uses only a photo that is already cached.
- The demo set has four of the looks and previews (office, casual, date night, weekend), so the Pictures tab has seven pictures. `wardrobe=full` adds the sundress and cool-weather looks, which use pieces only the full wardrobe has (a straw bag, black jeans, ankle boots).
- `SimulatedTryOn` gives a look that matches a preview exactly (the same garments, no piece ideas) that preview instead of the drawing. Any other look keeps the drawing. `photos=drawn` turns this off.
- Tests: `SampleWardrobeTests` (the previews, their looks and the matching), `SampleWardrobeSnapshotTests.tryOnPictures`.
