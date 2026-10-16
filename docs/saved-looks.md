# Saved Looks

Phase 12a, 15 October 2026. Saved Looks is the third tab: every look she saved, as its sticker bundle, with search, piece and colour filters, and a detail screen for each look. It works offline and uses no picture allowance (RD-08.1). The Pictures tab, picture detail and Try it on came in Phase 12b and are described in `docs/try-on-pictures.md`.

Spec: amendment RD-08 (Looks and Pictures tabs, search, "+ Make your own", no Favorites or collections in Stage A), LR-09 (piece and colour filters), LR-10 (Wear today, Last worn), LR-16.4 (a removed piece faded with Swap it) and LR-08 (Swap for every piece change, no path to the editor from a saved look). The visual references are `saved.html` and `look.html` in `closet/prototypes/RoomDirectionMockups/screens`; their Favorites, collections, star and "Add to collection" are a proposal with no Stage A screen, and their Edit button is replaced by Swap a piece (LR-08.1).

## What's where

| File | Holds |
|---|---|
| `Models/Rules/LookFilter.swift` | The pure search and filter rule |
| `Features/SavedLooks/SavedLooksModel.swift` | Loads the saved looks, newest saved first, and filters them; the lasting Undo after Delete look |
| `Features/SavedLooks/SavedLookItem.swift` | One look's bundle, name, occasion and search words, worked out once when the looks load |
| `Features/SavedLooks/SavedLooksPage.swift` | The title, Looks and Pictures, search, filters, the grid and the states |
| `Features/SavedLooks/SavedLooksGrid.swift` | The lazy grid of looks, and rows at the accessibility sizes |
| `Features/SavedLooks/SavedLooksFilters.swift` | The piece chips and colour swatches, folding behind Show filters at the accessibility sizes |
| `Features/SavedLooks/SavedLooksScreen.swift` | Navigation (look detail, garment detail and what it opens, Make your own look), the toasts |
| `Features/SavedLooks/LookDetail/` | `LookDetailModel`, `LookDetailPage`, `LookDetailScreen`, `RenameLookSheet` and `LookDetailText` |
| `Features/Home/Room/FramedLookArt.swift` | A saved look drawn small in a frame under the Home shelf |

## The Looks tab

Top to bottom, as in `saved.html`:

- **Saved Looks** in the serif title on the wall, and "5 looks". The bar carries "+ Make your own" (words and icon) and Profile.
- **Looks · Pictures**, the same switch as Your looks' tabs.
- **Search your looks.** Typed words match the look's name, its pieces' names, and the occasion, kinds and colours ("office", "skirt", "navy"). Every word has to match. Search waits until she pauses, as Closet's does.
- **The filters** (LR-09): Tops, Bottoms, Dresses, Layers, Shoes, Bags (and Accessories if a look has one), then a named swatch for each colour in her saved looks. A chip and a swatch match one piece together, so Bottoms and Black finds black bottoms, not a look with a bottom and black shoes. Ideas count as pieces.
- **"2 of 5 looks"** with **Clear**, while anything is set. Clear sits on this line rather than at the end of a chip row, so it never scrolls out of sight.
- **The grid.** Each look is its bundle on a soft cream mat, with its name and "Office · Last worn 5 days ago" under it. Two or more columns of at least 150 points; one look per row with the bundle beside its name at the accessibility sizes. A piece that has left her closet is faded in the bundle (LR-16.4).

Nothing matches: "No saved looks match", the filters in words ("Bottoms · Black · “navy”") and Clear filters (LR-09.3). Nothing saved yet: "Nothing saved yet", three steps (Style Me from the laptop, Save look on Your looks, or Make your own) and "+ Make your own" (RD-08.4). Loading and a store failure have their own states, with Try again.

The looks reload each time the tab appears and each time a pushed screen closes, so a look saved on Your looks, built in Make your own look or changed on its detail shows at once.

## Look detail

Top to bottom, as in `look.html`:

- **The name**, big, and its facts: "Office · Saved 4 Sep · Last worn 5 days ago", with "From Weekend" for a suitcase look.
- **The bundle**, large.
- **A kind note** when pieces left her closet: "Gray blazer isn't in your closet any more. Swap it for one of your pieces, or keep the look as it is." It's on a soft tint, not the warning colour, because nothing is wrong.
- **Wear today, Swap a piece, Try it on, Rename**, two by two, one column at the accessibility sizes. "Try-on pictures are simulated." under them.
- **Pieces.** Each of her pieces opens its garment detail. A piece that left her closet is in softer text with "No longer in your closet" or "In Recently deleted" and **Swap it**. An idea has "Not in your closet" and Find one. A piece deleted for good can't be drawn, so a line says how many there were.
- **Delete look**, quiet, at the end.

| Button | Does |
|---|---|
| Wear today | Records today on the look and on its pieces still in her closet (LR-10.1). Laundry doesn't change. Toast with Undo. The button then says Worn today; tapping it takes today off again |
| Swap a piece | Swap a piece (Phase 11) on this look, with options from the look's source. Use or Remove change the saved look in place, with Undo in a toast |
| Swap it | The same, starting on the faded piece |
| Try it on | The Try it on sheet (Phase 12b, `docs/try-on-pictures.md`). A new picture shows under Pictures on the look |
| Rename | A sheet with the name. `NameRules.lookName`: trimmed, one line, 1 to 60 characters, with the problem in words |
| Find one | The stand-in (Phase 34) |
| Delete look | Back to the grid. Undo is in a toast and on a line over the looks that stays until she leaves the tab |

**Swap on a saved look changes it in place.** Phase 11 makes a changed result a new look, so the stylist's version stays in history. A saved look is hers, though, so look detail keeps its ID, name, saved date and wear days and only its pieces change; it stays where it is in the grid and on the shelf. Undo saves back exactly the look before (LR-08.2). The changed pieces lose "Same as Simple", since it's no longer the stylist's version.

**Delete look** takes it out of Saved Looks. A version of a styling result goes back to background history, unsaved and unnamed, as unsaving on Your looks does (LR-06). A look she made herself has nowhere else to live, so it's deleted from the store. Undo saves the exact look again either way.

**Garment detail** from a piece is the Closet screen, pushed on Saved Looks' stack, with Edit, Style with this and Remove from closet. Removing the piece there comes back to the look, which then shows it faded, with Undo.

## The Pictures tab

Her try-on pictures, each linked to its look, with the same search and chips as Looks. See `docs/try-on-pictures.md`. Since 12b, look detail lists the look's pictures under its buttons, and Delete look keeps them, saying so in the toast.

## The Home shelf

The three frames under the shelf show her three most recently saved looks; tapping one switches to Saved Looks with that look open. See `docs/home-room.md`.

## Performance

The large set has about 480 saved looks. Each look's bundle content, name and search words are worked out once when the looks load; filtering compares those. On the iOS 26.5 simulator in Debug, loading them takes well under the test's 500 ms bound and a round of chip, swatch and search changes under its 250 ms bound (`SavedLooksModelTests.largeSetStaysQuick`, fastest of three, three times the bound on CI). The grid is lazy and each bundle is a few cached stickers or drawings.

## Accessibility

- A look in the grid is one button: its name and pieces, then the occasion, Last worn and how many pieces left her closet, with "Opens this look."
- Chips and swatches have the Selected trait, and swatches are named, so colour is never the only signal (LR-09.2). Show filters folds them away at the accessibility sizes.
- The bundle reads as one element naming its pieces, with "(No longer in your closet)" on a removed one (RD-07.3). Each piece is also a button in the list.
- Worn today has the Selected trait. Delete look and Wear today say what they do as hints.
- A frame on the Home shelf reads "Saved look: Interview navy and pink".

## Tests

- `LookFilterTests`: chips and swatches alone and together, one piece matching both, search on names, pieces and extra words, everything combined, a purged piece.
- `SavedLooksModelTests`: saved looks only and newest saved first, the empty set, a store failure, search by name, piece and occasion, the search delay, filters with Clear and the summary, no matches, the choices, removed pieces, Delete look and the lasting Undo, the large set's speed.
- `LookDetailModelTests`: the facts, a suitcase look, missing and failed, rename checks, Wear today and Undo (the look and its pieces), Worn today taken off, a removed piece skipped by Wear today, Delete look and Undo for a result and for her own look, removed and purged pieces, Swap in place and Undo, Swap's setup from the look's source.
- `HomeFramedLooksTests`: the three newest saved looks, none, fewer than three, the pieces a frame shows.
- `SavedLooksSnapshotTests` (11 images): the grid in light, dark and AX5, filtered, no matches, empty, Pictures, and detail in light, dark, AX5 and with a removed piece. `HomeSnapshotTests` adds the room with framed looks in light and dark. Your looks' Saved tab images changed: the given-away blazer is now faded there too.
- UI, `SavedLooksTests`: Style me, Save look, then find the look by search on Saved Looks and open it; Delete look and Undo; a shelf frame opens its look, and Swap it opens Swap a piece on the faded blazer.

## Decisions for Jose

1. **Swap a piece changes a saved look in place** (above), unlike results, where a changed look is a new one.
2. **Delete look unsaves a stylist's look and deletes one she made**, with Undo either way, and no question first. Undo stays on a line over the looks until she leaves the tab, since a toast is easy to miss.
3. **No Ask stylist on look detail.** `look.html` had it, but the brief and RD-06 put Ask stylist on results; the fourth button is Rename.
4. **Wear today counts her pieces still in her closet.** A piece she gave away doesn't get the wear.
5. **Archived pieces count as removed.** The demo's Lace date night has an archived black skirt, so it shows faded with "No longer in your closet". Archive has no Stage A screen, so she can't have done that herself; the demo data could change if that reads oddly.
6. **Search also finds kind and colour words** ("shoes", "navy"), as Closet's does, besides names and the occasion.
7. **Looks are ordered by when she saved them** (`Look.savedAt`, new in this phase). Looks saved before it existed use when they were made.
8. **The shelf frames' tap areas are about 36 points wide**, not 44 (`docs/home-room.md`).
9. **No "pictures" link on a look yet.** Done in 12b: a look lists its pictures, and each picture links back (RD-08.2).

## Left for later phases

- **12b (done):** the Pictures tab, its search and filters, picture detail, and each look's pictures (`docs/try-on-pictures.md`).
- **15b (done):** on iPad the search and filters sit in a sidebar beside the grid, and a look opens beside it (`docs/ipad.md`).
- **Later (no Stage A screen):** Favorites, collections and Archive (RD-08, LR-16).
