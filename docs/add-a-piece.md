# Add a piece and Edit

Phase 7b, 14 October 2026. Adding a piece to her closet, by photo or in words, and editing one from its detail. The visual reference is `closet/prototypes/RoomDirectionMockups/screens/garment-edit.html` (choose, Describe in words, details); where it differs from the amendment, the amendment wins. Spec: PRD §7.3 (drafts and recovery), FR-31 (durable drafts), the build plan's Phase 7b, and `closet/DATA_MAP.md` for data tiers.

## What's where

| File | Holds |
|---|---|
| `Features/AddPiece/GarmentEditorScreen.swift` | The screen: Back or Cancel, Save in the bar, the discard question, the photo source question, writing the draft when the app leaves the foreground |
| `Features/AddPiece/GarmentEditorPage.swift` | The title and line for each step, the step itself, the loading, gone and error states, and moving VoiceOver to the first problem |
| `Features/AddPiece/AddPieceSteps.swift` | "How would you like to add it?" and Describe in words with its suggestions |
| `Features/AddPiece/GarmentDetailsForm.swift` | The details form and its picture row |
| `Features/AddPiece/EditorFields.swift` | The text field, the chip groups and the problem note |
| `Features/AddPiece/DraftResumeCard.swift` | "Continue where you left off?" |
| `Features/AddPiece/GarmentEditorModel.swift` | Steps, the form, checks, Save, and the draft |
| `Features/AddPiece/GarmentEditorText.swift` | Field names, problems and suggestion words |
| `Models/Wardrobe/GarmentDetails.swift` | The facts she can type or pick, apart from the garment's states |
| `Models/Rules/GarmentRules.swift` | The form's checks |
| `Models/Drafts/GarmentDraft.swift` | An unsaved add or edit |
| `Models/Services/Intake.swift` | `DraftStore`, `PhotoIntake` and `GarmentDescriptionReader` |
| `Fixtures/Stores/InMemoryDraftStore.swift`, `Fixtures/Providers/StandInPhotoIntake.swift`, `Fixtures/Providers/WordMatchDescriptionReader.swift`, `Fixtures/Sets/FixtureDrafts.swift` | Stage A's stand-ins |

## The flow

Closet's Add a piece (and the empty closet's Add a piece) opens **"How would you like to add it?"**: Take photo, Choose from Photos, Paste and Describe in words. The empty closet's Describe in words goes straight to that step.

- **A photo choice** goes through `PhotoIntake`. Stage A's stand-in asks for nothing and returns a sample picture, so the form opens with "Sample photo". A line under the choices says photos aren't built yet. If the stand-in fails (`-fixtures demo:photo-fails`), the screen says "That photo couldn’t be read", that nothing was saved, and offers Try another photo or Describe in words.
- **Describe in words** takes her words and Suggest details lists what it found. She accepts or skips each one, and nothing is filled in until she accepts it. Continue fills the accepted fields and opens the form. A suggestion fills its field once, so going back and continuing again doesn't undo what she changed on the form.
- **The form** has the picture with Add a photo or Change photo, then Name, Other names, Kind, Type (once a kind is chosen), Colour with Shade name, Fit, How dressy, How warm, Seasons, Occasions, Brand, Size on the label and Notes, then Save to closet. Save is also in the bar.

**Edit** on garment detail opens the same form filled in with the piece, titled "Edit piece", with Save changes. Save changes keeps the piece's states (ownership, laundry, wear, suitcases) and only changes the facts. Back on the detail the new values show, since the detail loads again as it appears.

After Save the form closes. A new piece shows first in the grid with "Sage cardigan is in your closet"; an edit shows "Changes saved" on the detail.

## Fields and checks

The fields are the model's (`Garment`), and the checks are `GarmentRules` in Models, so the store runs the same ones on every save (`StoreError.invalidDetails`).

| Field | Required | Default for a new piece | Check |
|---|---|---|---|
| Name | Yes | empty | `NameRules.garmentName`: trimmed, 1 to 60 characters, one line |
| Other names | No | none | Up to 10, each up to 40 characters on one line. Add refuses an empty name, one it already has (ignoring case and accents, its own name included) and an eleventh |
| Kind | Yes | none chosen | One of the seven kinds |
| Type | No | None of these | One of the kind's types; changing the kind clears a type that doesn't belong to it. Dresses have none yet |
| Colour | No | none | Any of the colour families; the first one picked is the main colour |
| Shade name | No | empty | Up to 40 characters, one line |
| Fit | No | Not sure | Fitted, Regular, Relaxed or Not sure |
| How dressy | No | Smart | Casual, Smart or Dressy |
| How warm | No | Medium | Light, Medium or Warm |
| Seasons | No | all four | With none picked, a line says Style Me won't suggest it |
| Occasions | No | none | |
| Brand | No | empty | Up to 40 characters, one line |
| Size on the label | No | empty | Up to 20 characters, one line |
| Notes | No | empty | Up to 2,000 characters, several lines allowed |

The defaults are `Garment`'s own, so a piece saved with only a name and a kind can still be styled. Empty optional text is stored as unknown, not as an empty string.

Save with problems saves nothing. Each problem shows under its field in words that say how to fix it ("Give it a name.", "Choose what kind of piece it is.", "Keep this to 40 characters."), on the error tint with an icon. VoiceOver says "Not saved yet. Check Name and Kind.", moves to the first field with a problem, and the page scrolls there. After the first Save the problems update as she types.

If the store can't save, a note says "That didn’t save. Your words are still here, so you can try again." and nothing is lost.

### Other names and Type (Phase 21c)

PRD §7.6 and the mockup's "Other names" and second row of kinds. **Other names** sits under Name: a field ("Like “Date-night top”"), **Add name**, and the names she added as chips, each of which removes itself ("Remove Date-night top" to VoiceOver). Return ends editing, as in every one-line field. A name typed but not added is added on Save, so it isn't lost; if it can't be added, Save stops with the reason under the field. The line under them says "Search finds the piece by any of its names." **Type** sits under Kind, with the kind's types and **None of these**: Tops have Blouse, Tee, Shirt, Sweater, Knit top and Tank top; Layers have Cardigan, Jacket, Blazer, Coat and Vest; Bottoms have Trousers, Jeans, Skirt, Shorts and Leggings; Shoes have Flats, Heels, Sneakers, Loafers, Boots and Sandals; Bags have Handbag, Tote, Crossbody bag, Clutch and Backpack; Accessories have Scarf, Belt, Hat and Jewellery.

Both are in the draft, so closing the app keeps them. Garment detail shows the type under the kind and an "Other names" row. Search in Closet, Swap and the piece picker (which share Closet's search), Style Me's starting piece and Saved Looks finds a piece by its other names and its type. Describe in words doesn't suggest a type yet.

## Cancel

The bar shows Back while there's an earlier step, and Cancel on the first one. Cancel with nothing changed just closes. With changes, it asks first: "Discard this piece?" (or "Discard your changes?" with "Navy dress pants stays as it was."), with Discard and Keep editing. It's an alert, not a confirmation dialog: on iOS 26 a dialog from the bar opens as a popover with no visible Keep editing, and she should see both choices. Swiping back is off while the form is open, so work can't be lost by an accidental swipe.

## Drafts

Everything in the form is a draft until she saves: the step she's on, the details, and her words. The model writes the draft to a `DraftStore` half a second after she stops changing things, and straight away when the app leaves the foreground, so it never relies on a termination callback (PRD §7.3). A draft never changes her closet. Save or Discard removes it, and so does undoing every change.

Next time she opens Add a piece, or Edit on the same piece, the form asks **"Continue where you left off?"** with what's waiting ("Sage cardigan isn’t in your closet yet.", "Last changed 5 minutes ago"), Resume and Discard. Resume opens the same step with everything as she left it. The same card sits at the top of Closet, so she sees it without opening the form. A draft for a piece that's no longer in her closet isn't offered, but it's kept in case Undo brings the piece back.

### Drafts in the real store (Phase 21a)

Since Phase 21a `StoredDraftStore` keeps every draft in the real store on the iPhone, one record per target, with Data Protection `complete`, for her own closet and every Release build. Each write is saved before the call returns, so the half-second save and the save when the app leaves the foreground are durable. `closet/DATA_MAP.md` has a row for the drafts (Sensitive). Delete my data erases them, and Delete now in Recently deleted removes a piece's unsaved Edit with it. The debug sample closet keeps its drafts in memory, as below, so `-fixtures demo:draft=add` still seeds one for the UI tests.

### Why Stage A drafts lived in memory

The brief allowed a small on-disk draft (a JSON file in Application Support with complete file protection, kept out of backups) only if the security standard and the data map allow it for this data in Stage A. They don't, yet, so `DraftStore` has only an in-memory implementation, and a draft lasts until the app is closed.

- **The data is Sensitive.** A draft can hold her notes and her own description of the piece, which `DATA_MAP.md` classes as Sensitive ("private notes"). The standard asks for a data map entry, file protection and a checked deletion path before any of it is stored.
- **Stage A has no real storage on purpose.** The build plan and the brief say Stage A runs on mock data with no real persistence. Writing a file of what she types would be the app's first real storage, and it would reach her phone in Phase 18 (her first TestFlight) before the persistence spike (20a), the threat model revisit (19a) or the storage decision (21a) have looked at it.
- **Durable drafts need more than a file.** FR-31 asks for drafts that survive relaunch with an acknowledged durable write, recovery after a failed save, and the same protection as the rest of her closet. That's Phase 21a's job, and the protocol is what it plugs into.

So the draft logic is real and tested, and only the store is a stand-in. Tests stand in for "the app was closed" by building a new model on the same store. UI tests close the app and relaunch it with `-fixtures demo:draft=add` (or `draft=edit`), which puts the same draft in the store at launch.

## Describe in words

`GarmentDescriptionReader` reads her words and returns suggestions. Stage A's `WordMatchDescriptionReader` runs on the phone and is deterministic: it looks her words up in short lists of kinds, colour and shade words, and a few words for cut, warmth, dressiness, seasons and occasions. It has no style or fit rules and sends nothing anywhere. The line under the suggestions says so.

- The part of her description that names the piece runs up to the first comma, full stop, "with", "from", "by", "for", "that" or "which". The last kind word there is the kind ("dress shoes" are shoes), and its colour words are the colours ("sage green" is green with the shade Sage, "light pink" is pink with the shade Light pink).
- The suggested name is the first colour or shade she said plus the kind word ("Sage cardigan"), or no name if there's no kind word.
- "from Old Navy" or "by Uniqlo" (capitalised words) is the brand, and what follows "with" is a detail for her notes.
- Her words can be up to 1,000 characters.

A real reader, if one is added later, sits behind the same protocol and follows SECURITY_STANDARD.md §7.

## Accessibility

- Each field is named by its label ("Brand, optional"), and its problem is read after it. Chip groups are named by their heading, which VoiceOver reads as a heading, and chosen chips say "Selected".
- Each suggestion reads its field and value, then "Accept name: Sage cardigan" and "Skip name".
- Other names: the field reads "Other names, optional"; each name's chip reads "Remove Date-night top"; a refused name's reason is read after the field. Type is a chip group named "Type, optional", like the others.
- At the accessibility sizes every chip group wraps, text fields wrap their text and their prompt, the picture row stacks, the suggestion buttons move under the words, and Resume and Discard stack. Save is in the bar too, so she doesn't need to scroll to the end of a very long form.
- Dark mode uses the palette tokens; the swatches keep their garment colours as in Closet.

## Tests

- `GarmentDetailsTests`, `GarmentRulesTests`, `GarmentSuggestionTests`, `GarmentDraftTests` (Models): the checks and limits, trimming, defaults, writing details onto a garment without touching its states, each suggestion, and when a draft counts as work.
- `WordMatchDescriptionReaderTests`, `InMemoryDraftStoreTests`, `AddPieceFixtureTests` (Fixtures): description cases, the draft store, the photo stand-in, the `draft=` and `photo-fails` options, the store's new check, and every fixture garment passing it.
- `OtherNamesTests` (Models) and `OtherNamesEditorTests` (Features), Phase 21c: the rules and limits, the store's tidying, search in Closet and Saved Looks, adding and removing names, Save adding a typed name, types following the kind, Edit, the draft and garment detail.
- `GarmentEditorModelTests` (Features): steps, Back, Save's checks and live problems, add by words end to end, accept and skip, a failed save, photos, edit keeping states, dirty detection, the draft's save delay, "closing the app" and resuming, Discard, Cancel, and Closet's draft card.
- `GarmentEditorSnapshotTests`: the choices, Describe in words with suggestions, the empty form, the form with problems, the filled form in light, AX5 and dark, and "Continue where you left off?". Like every screen snapshot it is drawn at 1x (the snapshot policy in `Packages/NookKit/Sources/DesignSystem/README.md`).
- `AddPieceTests` (UI): add by words with Save's checks and see it in Closet; edit with Cancel, Keep editing and Discard changes, then save and see the detail change; abandon mid-add, close the app, relaunch and resume from Add a piece, then save.

## Decisions for Jose

1. **Drafts were in memory in Stage A** (see above). Phase 21a gave `DraftStore` a durable implementation in the real store with complete file protection, and added drafts to the data map.
2. **A kind is required as well as a name.** The mockup says "Only a name is needed", but every garment has a kind, and guessing one would quietly file her piece in the wrong place. The line now says "Only a name and the kind of piece are needed."
3. **"Other names" (aliases) and the sub-kind (Cardigan, Blazer) came in Phase 21c,** above. The type is labelled "Type" because "Kind" already names the category here; the mockup calls them Category and Kind. PRD §7.6's possible matches and Remember this name came after 21c (`docs/closet.md`, `docs/garment-detail.md`); a remembered name lands in the same other names. Alias provenance isn't built.
4. **No cleanup or "Check the photo" step.** The mockup's simulated background cleanup and original-or-cleaned-up choice are cutouts, which Phases 8a and 8b decide.
5. **"Comfort" isn't a garment field.** Today's comfort belongs to Style Me (LR-18, Phase 10a). The form has the piece's cut (Fit) and How warm.
6. **LR-13 and LR-12 aren't part of this form.** "Add a piece that fits you well" is Profile's fit section (14a), and "Thinking of buying?" is the wishlist with Find One (34). Pieces added here are always hers.
7. **Edit doesn't say "Earlier looks keep the version they were made with."** The mockup's line describes history the app doesn't keep yet, so the line is "Change anything, then save. Nothing changes until you do."
8. **Resuming an edit draft puts all its values back**, even if the piece changed elsewhere since. With one person and one device in Stage A this is rare; revisions arrive with real storage (PRD §7.3).
9. **Discard on "Continue where you left off?" doesn't ask again.** It only throws away unsaved work, and the card says what it is. The form's own Cancel does ask.
