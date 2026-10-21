# Saved Looks

Phase 12a, 15 October 2026. Saved Looks is the third tab: every look she saved, as its sticker bundle, with search, piece and colour filters, and a detail screen for each look. It works offline and uses no picture allowance (RD-08.1). Since 21 October 2026 a Saved | All switch also lets her list the Style Me results she didn't save (below). The Pictures tab, picture detail and Try it on came in Phase 12b and are described in `docs/try-on-pictures.md`.

Spec: amendment RD-08 (Looks and Pictures tabs, search, "+ Make your own", no Favorites or collections in Stage A), LR-09 (piece and colour filters), LR-10 (Wear today, Last worn), LR-16.4 (a removed piece faded with Swap it) and LR-08 (Swap for every piece change, no path to the editor from a saved look). The visual references are `saved.html` and `look.html` in `closet/prototypes/RoomDirectionMockups/screens`; their Favorites, collections, star and "Add to collection" are a proposal with no Stage A screen, and their Edit button is replaced by Swap a piece (LR-08.1).

## What's where

| File | Holds |
|---|---|
| `Models/Rules/LookFilter.swift` | The pure search and filter rule |
| `Features/SavedLooks/SavedLooksModel.swift` | Loads every look, lists the saved ones newest saved first (Saved) or all of them newest made first (All), and filters them; the "N more in All" count; Save look from the grid; the lasting Undo after Delete look |
| `Features/SavedLooks/SavedLookItem.swift` | One look's bundle, name, occasion and search words, worked out once when the looks load |
| `Features/SavedLooks/SavedLooksPage.swift` | The title, Looks and Pictures, the Saved and All switch, search, filters, the grid, the "N more in All" line and the states |
| `Features/SavedLooks/SavedLooksGrid.swift` | The lazy grid of looks, and rows at the accessibility sizes; the Not saved tag and Save look on a look she didn't save |
| `Features/SavedLooks/SavedLooksFilters.swift` | The piece chips and colour swatches, folding behind Show filters at the accessibility sizes |
| `Features/SavedLooks/SavedLooksScreen.swift` | Navigation (look detail, garment detail and what it opens, Make your own look), the toasts |
| `Features/SavedLooks/LookDetail/` | `LookDetailModel`, `LookDetailPage`, `LookDetailScreen`, `RenameLookSheet` and `LookDetailText` |
| `Features/Home/Room/FramedLookArt.swift` | A saved look drawn small in a frame under the Home shelf |

## The Looks tab

Top to bottom, as in `saved.html`:

- **Saved Looks** in the serif title on the wall, and "5 looks". The bar carries "+ Make your own" (words and icon) and Profile.
- **Looks · Pictures**, the same switch as Your looks' tabs.
- **Saved | All** (Looks tab only), a second switch under it. Saved is the default.
- **Search your looks.** Typed words match the look's name, its pieces' names and other names, and the occasion, kinds, types and colours ("office", "skirt", "loafers", "navy"). Every word has to match. Search waits until she pauses, as Closet's does.
- **The filters** (LR-09): Tops, Bottoms, Dresses, Layers, Shoes, Bags (and Accessories if a look has one), then a named swatch for each colour in her saved looks. A chip and a swatch match one piece together, so Bottoms and Black finds black bottoms, not a look with a bottom and black shoes. Ideas count as pieces.
- **"2 of 5 looks"** (out of the looks in the scope) with **Clear**, while anything is set. Clear sits on this line rather than at the end of a chip row, so it never scrolls out of sight.
- **The grid.** Each look is its bundle on a soft cream mat, with its name and "Office · Last worn 5 days ago" under it. Two or more columns of at least 150 points; one look per row with the bundle beside its name at the accessibility sizes. A piece that has left her closet is faded in the bundle (LR-16.4).

**Saved and All (LR-06.4, decided 21 October 2026).** Style Me keeps every result she didn't save as background history. Phase 21c first let typed search pull those up in a separate group on Saved, which Jose found unclear. The two scopes are now explicit, with a switch at the top of the Looks tab (`SavedLooksModel.Scope`):

- **Saved** lists her saved looks, newest saved first. Search and every filter narrow within them.
- **All** lists her saved looks and every Style Me result she kept but didn't save, in one list, newest made first. Search and the filters apply exactly as on Saved. A look she didn't save has a small "Not saved" tag, a made date ("Casual · Made Oct 11", since several can share a name) and a **Save look** button under it. Save look names it as Your looks would ("Pink & navy", "Casual look"), saves it with today's date, and shows "Saved to Saved Looks" with Undo. The look changes where it is: the tag and button go and nothing else moves, because All's order is by when a look was made, which saving doesn't change. It then also sits at the top of Saved.
- **The nudge.** On Saved, when the search and filters match looks she didn't save too, one line, pinned above the tab bar, says "3 more in All" with an arrow (21 October 2026: it was the last item of the page, and on a short list the page is only a little taller than the screen, so the line sat under the floating tab bar until she scrolled; it's now in the scroll view's bottom safe area, which stops above the bar, so it always shows and the list scrolls above it). The other tab screens, Home and Closet, have no line at the end of the page that she has to see, and the bar's inset already stops their scrolling above it (measured on Saved Looks: scrolled to the end, the last item sits 32 points above the bar); they needed no change. It is a button: tapping it switches to All and keeps the search and filters, and the list scrolls to its top. It stays away when N is 0, and when nothing is typed or chosen (every unsaved look would "match", and the line would only be noise). It also shows under "No saved looks match", which is the case it matters most in.
- **No special cases.** The same search and filters work the same way in both scopes. The old rule that only typed words found earlier results is gone, and so is the "Earlier results, not saved" group.
- **Swatches follow the scope.** On All a colour that only an unsaved look has gets a swatch; on Saved it doesn't, so a swatch there always finds something. A chip or swatch that's on stays on show when she switches, so she can turn it off.
- **The scope goes back to Saved each time she leaves the screen**, like the line about a deleted look. The app keeps no screen state across launches, so there is nothing to restore. The search and filters aren't reset by that.
- An unsaved look opens on look detail from All with its facts ("Casual · Simple · Made Oct 11 · Not saved"), the note "An earlier Style Me result. Save it to keep it in Saved Looks, where you can wear it, swap pieces and try it on.", **Save look** and its pieces, and none of the buttons that change a saved look. Opened any other way, an unsaved look is still "no longer saved".
- The tour runs on Saved only, since its first look has to be one she saved.

Each state names its scope. Nothing matches on Saved: "No saved looks match", the filters in words ("Bottoms · Black · “navy”") and Clear filters (LR-09.3), then "N more in All" if All has them. Nothing matches on All: "No looks match in All" with the same words. Nothing saved yet: "Nothing saved yet", three steps (Style Me from the laptop, Save look on Your looks, or Make your own) and "+ Make your own" (RD-08.4); when she has results she didn't save it adds "Results you didn’t save are in All." No looks at all on All: "No looks yet" and "Looks Style Me makes for you show up here, saved or not." The search and chips only show when the scope has looks. Loading and a store failure have their own states, with Try again.

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
- The Saved | All switch is named "Which looks to show". Each option is a button that says Selected when on, with a hint that says what it lists: "Only the looks you saved." and "Your saved looks and the Style Me results you didn’t save."
- "3 more in All" is a button, with the hint "Shows all your looks, including ones you didn’t save. Your search and filters stay on."
- A look she didn't save reads "Casual, Made Oct 11, Not saved" after its pieces. The visible tag is hidden from VoiceOver so it isn't read twice. Save look is its own button, named for the look ("Save look: Casual look"), so a list of them is told apart.
- Chips and swatches have the Selected trait, and swatches are named, so colour is never the only signal (LR-09.2). Show filters folds them away at the accessibility sizes.
- The bundle reads as one element naming its pieces, with "(No longer in your closet)" on a removed one (RD-07.3). Each piece is also a button in the list.
- Worn today has the Selected trait. Delete look and Wear today say what they do as hints.
- A frame on the Home shelf reads "Saved look: Interview navy and pink".

## Tests

- `LookFilterTests`: chips and swatches alone and together, one piece matching both, search on names, pieces and extra words, everything combined, a purged piece.
- `SavedLooksScopeTests` (21 October 2026, replacing 21c's `EarlierResultsTests`): the two lists and their order, search, chips and swatches across both scopes (fifteen cases, saved and all, with the expected looks), the scope keeping the search and filters, the nudge count and when it hides ("3 more in All", 1 and many), the empty and no-match states of both scopes, swatches following the scope, Save look in place with Undo and double taps, what VoiceOver reads, and look detail for an unsaved look.
- `SavedLooksModelTests`: saved looks only and newest saved first, the empty set, a store failure, search by name, piece and occasion, the search delay, filters with Clear and the summary, no matches, the choices, removed pieces, Delete look and the lasting Undo, the large set's speed.
- `LookDetailModelTests`: the facts, a suitcase look, missing and failed, rename checks, Wear today and Undo (the look and its pieces), Worn today taken off, a removed piece skipped by Wear today, Delete look and Undo for a result and for her own look, removed and purged pieces, Swap in place and Undo, Swap's setup from the look's source.
- `HomeFramedLooksTests`: the three newest saved looks, none, fewer than three, the pieces a frame shows.
- `SavedLooksSnapshotTests`: the grid in light, dark and AX5, filtered, no matches, empty, Pictures, and detail in light, dark, AX5 and with a removed piece; since the scope switch, Saved with "1 more in All", All in light, dark and AX5, no matches with the line, All with no matches, and the empty state of both scopes (and Saved with nothing saved but unsaved results around). `SavedLooksIPadSnapshotTests` adds All beside its sidebar. `HomeSnapshotTests` adds the room with framed looks in light and dark. Your looks' Saved tab images changed: the given-away blazer is now faded there too.
- `savedWithMoreInAllAboveTheTabBar` (snapshot): the whole 402 x 874 screen with a stand-in for the tab bar over the bottom 83 points, so a line left at the end of the page would be clipped out of it. The UI test `testTheMoreInAllLineClearsTheTabBarOnAShortList` checks the real frames against the real tab bar.
- UI, `SavedLooksTests`: a search and Bottoms on Saved find "1 more in All", which switches to All with both kept, shows the tag and Save look, and saving changes the look in place; the scope goes back to Saved after leaving the tab; an unsaved look opens from All and saves on its detail. `AccessibilityAuditTests` audits All, at the default size and at AX5. Also: Style me, Save look, then find the look by search on Saved Looks and open it; Delete look and Undo; a shelf frame opens its look, and Swap it opens Swap a piece on the faded blazer.

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

10. **Saved | All replaces 21c's separate "Earlier results" group** (Jose, 21 October 2026: "it should be unambiguous"). The nudge needs a typed search or a chip, so an unfiltered Saved never says "34 more in All". All is ordered by when a look was made, so saving one doesn't move it. All's header reads "10 looks, 1 not saved".

## Left for later phases

- **12b (done):** the Pictures tab, its search and filters, picture detail, and each look's pictures (`docs/try-on-pictures.md`).
- **15b (done):** on iPad the search and filters sit in a sidebar beside the grid, and a look opens beside it (`docs/ipad.md`).
- **Later (no Stage A screen):** Favorites, collections and Archive (RD-08, LR-16).
