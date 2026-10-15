# Suitcases and Laundry

Phase 13, 15 October 2026. Suitcases are smaller sets of her pieces, for a trip or a second home, that Style Me can style from on their own. Laundry keeps note of what's in the wash, when she turns tracking on. Visual references: `suitcases.html`, `suitcase.html`, `laundry.html`, `laundry-off.html` and the suitcase sheet in `garment.html`, in `closet/prototypes/RoomDirectionMockups/screens`. Where they differ from the amendment, the amendment wins.

Spec: amendment RD-09 (three favourites and See all), LR-17 ("+ Add a suitcase" always visible), RD-11 (laundry opt-in and the hamper), LR-11 (suitcase names), LR-16.1 (pieces she no longer has); PRD §7.3 (laundry controls and bulk cleaning), §7.7 (suitcases and the remembered source), FR-64, FR-65, FR-66, FR-67.

## What's where

| File | Holds |
|---|---|
| `Models/Rules/SourceChoice.swift` | Which source shows (the remembered one, or the main closet when its suitcase has gone), and the pieces of her closet in a source |
| `Models/Rules/LaundryRules.swift` | `HamperState` (5a) and `LaundryBasket`: what's in the wash, and what Mark clean and Undo may change |
| `Models/Profile/Profile.swift` | `RememberedChoices`: the source and occasion Style Me starts from |
| `Features/Suitcases/SuitcasesScreen.swift`, `SuitcasesPage.swift`, `SuitcasesHall.swift`, `SuitcaseRows.swift` | Suitcases and All suitcases: the hall, the rows, "+ Add a suitcase", choosing the source |
| `Features/Suitcases/SuitcasesModel.swift`, `SuitcasesText.swift` | Their model and words |
| `Features/Suitcases/SuitcaseDetailScreen.swift`, `SuitcaseDetailPage.swift`, `SuitcaseDetailModel.swift` | One suitcase, with `SuitcaseChange` for Undo after archive and delete |
| `Features/Suitcases/PackingSheet.swift`, `SuitcaseEditor.swift` | The packing sheet, and the name and picture sheet |
| `Features/Suitcases/WallHeader.swift` | The title on the wall with a drawing beside it, shared with Laundry |
| `Features/Laundry/` | Laundry: model, page, screen, the confirmation and the laundry corner drawing |
| `Features/Garment/AddToSuitcaseSheet.swift` | Add to a suitcase on garment detail |

## Where they open from

Suitcases and Laundry live in Closet (RD-13), and the mockups' screens go back to Closet. So Home's suitcase and hamper open them on the Closet tab, as the wardrobe opens Closet, through `openInCloset` from the root view. Closet's tiles push them on its own stack. One copy of each screen means a piece on a suitcase opens its detail, and that detail's suitcase names open the suitcase, wherever she started.

- Suitcases: Closet's Suitcases tile, Home's suitcase (or the Source row and tile in the large-text and sideways layouts), a garment's "Add to a suitcase" when she has none.
- A suitcase: a row's chevron, a suitcase name on garment detail (LR-11.4), Style Me's "Add pieces" for an empty or small suitcase, and the toast after choosing an empty one.
- Laundry: Closet's Laundry tile (while tracking is on), Home's hamper while tracking is on. While it's off, the hamper opens the short sheet from 5a.

## Suitcases

Top to bottom, as `suitcases.html`:

1. **"Suitcases"** on the wall, and **"+ Add a suitcase"** in the navigation bar, so it shows without scrolling with any number of suitcases (LR-17.1).
2. **The hall**: a door, hooks, a mirror and a console, with her three favourites standing on the runner, the most recently used in the middle. Each wears a luggage tag with its name and piece count in live text. The source's tag is the solid accent, with "Styling from this one" under it. Tapping a tag or a suitcase chooses it.
3. **Favourites**, "Your three most recently used.", the same three as rows. There's no star (RD-09): using a suitcase is what makes it a favourite.
4. **See all suitcases** when there are more than three, or any archived.
5. **Main closet**, every piece.
6. **"+ Add a suitcase"** again, and a line: "Style Me picks only from the suitcase you choose. Main closet uses everything."

Each row has a tick and its drawing, its name, and "8 pieces · Used 2 weeks ago" (or "Style Me source · 5 pieces"), then a chevron. The tick part chooses it as Style Me's source; the chevron opens it.

**Choosing a source** saves it at once, and a toast says "Style Me now uses Weekend." with Style me. It's remembered for next time (FR-67), Home's suitcase shows it, and the suitcase is marked as used, so it joins the favourites (RD-09.2). The rows don't move while she's on the screen; the new order shows next time, so nothing jumps under her finger. An empty suitcase isn't chosen: "Spring trip is empty. Pack something first." with Pack it, as `suitcases.html` does, and the source stays as it was.

**All suitcases** lists every suitcase with search by name: the favourites, then the others, then the archived ones only while the Archived chip is on (RD-09.3), then the main closet.

**No suitcases yet** says what a suitcase is, with "+ Add a suitcase" and the main closet.

**"+ Add a suitcase"** asks for a name (one line, 1 to 40 characters, not the same as another suitcase's) and one of five pictures, then "Add and pack" makes it and opens it on the packing sheet (LR-17.2).

**When the source goes away.** If the suitcase she chose is deleted or archived, browsing goes back to the main closet (PRD §7.7): Home's suitcase shows the main closet, and Suitcases says "The suitcase you were styling from isn't there any more, so Style Me uses Main closet." Style Me itself keeps asking her to choose ("This suitcase isn't there any more"), so a request never quietly styles from everything (FR-67). Deleting or archiving the source from its own page sets the main closet straight away, and the toast says so.

## A suitcase

Its name on the wall with "5 pieces · Used today" and its drawing beside it, then:

- **Name and picture**: the same sheet as "+ Add a suitcase", with Save.
- **The source card.** For the source: "Style Me is using this suitcase", what Suitcase only means, Style me from this suitcase and Use Main closet. For another suitcase: "Style from Weekend", what it would mean and what Style Me uses now, Style me from this suitcase and Use for Style Me. Empty: "Not ready for Style Me". Use for Style Me and Use Main closet have Undo.
- **Packed 5**, with Add or remove, then Closet's grid of its pieces. Each opens its detail, and its minus takes it out of this suitcase only, with Undo. Empty, it says how to pack it, with Add pieces.
- The menu (…) has Name and picture, Archive suitcase (or Bring it back) and Delete suitcase.

**Only pieces in her closet show.** A piece she no longer has, or one in Recently deleted, keeps its suitcase link in the data, so Undo or Restore brings it back as it was, but it isn't shown or counted anywhere (LR-16.1, garment detail decision 6). Every count of a suitcase's pieces goes through `SourceChoice.pieces`.

**The packing sheet** is Closet's search, filters and grid over her whole closet, with a tick on each piece. A tick packs it or takes it out at once, so there's nothing to confirm and closing the sheet loses nothing. The count says how many are packed. A piece already in another suitcase shows the tiny suitcase, and VoiceOver reads the names. Laundry doesn't matter here, so the Dirty badge stays off.

**Archive** keeps the suitcase and its pieces and hides it from the source choices (PRD §7.7). An archived suitcase shows a note with Bring it back, and only appears under All suitcases' Archived chip.

**Delete suitcase** asks nothing first, since Undo puts back the same suitcase with the same ID and pieces (`SuitcaseStore.restore`), as Delete look does (12a). Its pieces, saved looks and pictures stay. The page goes back to where she came from, which shows the toast.

## Add to a suitcase (garment detail)

A soft button under Style with this opens a sheet with every suitcase that isn't archived, each with its drawing and a tick. A tick packs the piece or takes it out at once. The "In suitcases" chips near the title follow. With no suitcases it offers Suitcases.

## The five pictures

A suitcase picks one of five drawings, the fixed set from Phase 3: a rolling case, a weekender, a duffel, a backpack and a tote. The rolling case is the mockups' spinner (`travel-suitcase-pink.svg`); the other four were drawn for this phase in the same style. Each is 104 x 182 with the same plain face at y 30 to 124, so the hall's tags and Home's plates sit on any of them. They go through `scripts/room-art.py` like the rest of the room, so their colours are Lily's warm palette (sand, oak, sage, butter and stone), and the shapes tell them apart, not the colours alone. `art/room/README.md` lists them.

On Home, the main closet keeps the room's own suitcase, and a suitcase source puts its own drawing there.

## Laundry

Top to bottom, as `laundry.html`:

1. **"Laundry"** on the wall with "2 pieces in the wash", and the laundry corner: a shelf, the washer, the hamper as Home draws it, and a plant.
2. **Scope chips**, only when Style Me's source is a suitcase: "Main closet · 2" and "Jose's house · 1" (PRD §7.3, This suitcase).
3. **The pieces in the wash**, each with a tick, its sticker, its name, its kind and where it is ("packed in Gym and Weekend"), and Mark clean.
4. **Clean selected** and **Mark all clean**.
5. A line: Style Me skips pieces in the wash, and a piece in two suitcases is one piece, so cleaning it cleans it everywhere.

| Action | Asks first | Then |
|---|---|---|
| Mark clean on one piece | No (PRD §7.3: no modal for one reversible change) | Toast with Undo |
| Clean selected, one ticked | No | Toast with Undo |
| Clean selected, two or more | Yes: "Mark 2 pieces clean?", the scope, the pieces | Toast with Undo |
| Mark all clean | Yes, the same | Toast with Undo |

Cleaning only changes pieces still in her closet and still in the wash; the rest are skipped (`LaundryBasket.cleanable`, FR-65). Undo only puts back pieces that are still clean, so a piece she marked dirty again in the meantime isn't touched.

**Tracking off** shows "Laundry tracking is off", that every piece counts, how many marks are kept, and Turn on. Turning it on brings the kept marks back (RD-11.2). Since 14b the switch is on Profile, where tracking also turns off, keeping every mark (`docs/settings.md`).

**Nothing in the wash** says "Every piece here counts as available to Style Me."

**The hamper follows.** Home and Closet reload when their tab appears and when a pushed screen closes, so marking a piece dirty on its detail or clean in Laundry shows on the hamper and the Laundry tile straight away. Style Me already leaves out pieces in the wash while tracking is on (`Eligibility`, Phase 3); `LaundryModelTests` checks that a piece isn't offered while it's in the wash and is once Laundry cleans it.

## The remembered source and occasion

`Profile.remembered` holds the source and occasion she chose last (FR-67). Style Me starts from them; choosing a source or an occasion there, or tapping Style me, saves them. Other isn't remembered, since its words are for one request. Comfort, colour and weather still reset each time (RD-02.4). Home's suitcase shows the source and the calendar shows the occasion ("Occasion · Office"), on the room, the large-text rows and the sideways tiles. A suitcase chosen anywhere counts as used, so it joins the favourites.

In Stage A the profile lives in memory, so "across launches" waits for real storage (Phase 21a). `-fixtures demo:source=suitcase` starts with her most recently used suitcase (Jose's house) as the source.

## States

| Screen | Loading | Error (`stores-fail`) | Empty |
|---|---|---|---|
| Suitcases, All suitcases | "Opening your suitcases" | "Your suitcases didn't load" with Try again | No suitcases yet; no matches with Clear search |
| A suitcase | "Opening this suitcase" | "This suitcase didn't load" | "Spring trip is empty"; "This suitcase isn't there any more" when it's gone |
| Laundry | "Opening your laundry" | "Your laundry didn't load" | Nothing in the wash; tracking off |

Everything here is local, so offline doesn't apply.

## Accessibility

- The hall is hidden from VoiceOver: the rows under it are the same choices with words. Each row is two buttons, the choice ("Weekend", "8 pieces · Used 2 weeks ago", selected when it's the source, hint "Makes it the source for Style Me.") and "Open Weekend".
- Packed pieces read as in Closet, plus their minus, "Remove Navy dress pants from Weekend". Packing ticks and Laundry's ticks add the selected trait; the tick isn't the only signal.
- At the accessibility sizes the hall is left out (it only repeats the rows and its tags can't grow), each row's words go under its tick and drawing, and the headers' drawings go above the title.
- Dark appearance uses the tokens; the new drawings get the room's lamplight. No new animation, so Reduce Motion has nothing to change.

## Tests

- `SourceChoiceTests`, `LaundryBasketTests` (Models): fallback, hidden pieces, cleanable and undoable pieces, kept marks.
- `SuitcaseStoreTests` (Fixtures): restore after delete, and a name taken meanwhile. `FixtureSourceTests`: `source=`.
- `SuitcasesModelTests`: favourites, 0 to 5 suitcases (RD-09.1, LR-17.2), choosing and favourites next time (RD-09.2), an empty suitcase, a source that went away, counts without pieces she no longer has, search, the words.
- `SuitcaseDetailModelTests`: pieces, packing, remove and Undo, the source, rename and picture, archive and delete with Undo, gone and failing.
- `LaundryModelTests`: listing, scopes, tracking off and on, one, selected and all clean with Undo, Undo leaving a re-dirtied piece, the hamper after cleaning, and Style Me leaving out pieces in the wash.
- `RememberedChoicesTests`: Style Me's start, what's remembered, a missing suitcase, the calendar's words, Add to a suitcase.
- `SuitcasesSnapshotTests`: Suitcases light, dark, AX5 and empty; All suitcases; a suitcase as source, in dark, empty and archived; the packing and name sheets; Laundry with a suitcase source, all clean in dark, off, and the confirmation. `HomeSnapshotTests.suitcaseSourceAndOccasion` and `GarmentDetailSnapshotTests.addToSuitcaseSheet`.
- `SuitcasesAndLaundryTests` (UI): add a suitcase, pack three pieces, remove one and Undo, Style me from it, and see it on Home's suitcase; mark a piece dirty on its detail, see the hamper fill, clean one with Undo, two selected and the rest in Laundry, and see the hamper empty.

## Decisions for Jose

1. **Suitcases and Laundry open on the Closet tab** from Home, as the mockups' back buttons and RD-13 have them. Back goes to Closet; Home is a tab away.
2. **Favourites move next time, not at once.** Choosing a suitcase marks it as used, but the rows keep their places until she comes back, so nothing jumps under her finger.
3. **Choosing an empty suitcase doesn't change the source**, as in `suitcases.html`. PRD §7.7's "a valid empty suitcase stays selected" is still true for one she already uses.
4. **Choosing a suitcase in Style Me's sheet counts as using it** (RD-09.2), as well as sending a request.
5. **Five picture shapes, not colours.** The mockups show coloured rolling cases, but Lily's warm palette turns pink, lilac and blue into nearly the same stone, so the Phase 3 set of five shapes stayed, each in its own tone.
6. **Delete suitcase has no question, only Undo**, like Delete look.
7. **No per-request "use it anyway" for a piece in the wash** (FR-64). Style Me offers another starting piece instead (10a). The line on Laundry says Style Me skips them, without "unless you allow one".
8. **The remembered occasion** shows on the calendar; Other isn't remembered.

## Left for later phases

- **14b (done):** the Track laundry switch in Profile, including turning tracking off. The source stays the remembered one from Style Me rather than a separate Settings default.
- **15a:** iPad layouts (the hall beside the list).
- **21a:** the remembered source and occasion kept across launches.
