# Swap a piece and Make your own look

Phase 11, 15 October 2026. Swap a piece changes one piece of a look on Your looks: it explains its picks, shows three at a time, ends with See all and Find one, and has Remove this piece and Undo. Make your own look builds a look from scratch, piece by piece. They're kept apart on purpose: changing a piece in any look is always Swap, and the editor is only for a new look (LR-08).

Spec: amendment LR-07 (the explanation line, Show 3 more, See all, Find one) and LR-08 (Swap for every piece change, Remove and Undo, Make your own look), Lily's sign-off items L7 and L8, PRD FR-09 (one piece changes), FR-32 (offline, free, no AI) and §7.3 (drafts, undo, save in place). The "Ask the stylist" link inside Swap was discussed and not approved, so there isn't one. The visual references are `swap.html` and `editor.html` in `closet/prototypes/RoomDirectionMockups/screens`; their "Edit the whole look" link is gone (LR-08.1).

## What's where

| File | Holds |
|---|---|
| `Models/Editing/SwapRanking.swift` | `SwapSituation`, `SwapOptions` and `SwapRanking`, the pure ranking rule |
| `Models/Editing/LookEditing.swift` | Replacing and removing one piece, keeping the version and the "Same as Simple" marks |
| `Models/Editing/LookRules.swift` | `LookProblem` and the checks for a hand-made or hand-changed look |
| `Models/Editing/EditHistory.swift` | Undo and Redo, up to 20 changes |
| `Models/Drafts/LookDraft.swift` | The unsaved Make your own look draft and `LookDraftStore` |
| `Fixtures/Stores/InMemoryLookDraftStore.swift` | The Stage A draft store, in memory |
| `Features/Swap/` | `SwapModel`, `SwapPage`, `SwapScreen` and `SwapText` |
| `Features/LookBuilder/` | `LookBuilderModel`, `LookBuilderPage`, `LookBuilderScreen` and `LookBuilderText` |
| `Features/Shared/PiecePicker/PiecePicker.swift` | See all and Add a piece: Closet's search, filters and grid over a chosen set of pieces |
| `Features/SavedLooks/SavedLooksScreen.swift` | Saved Looks, with "+ Make your own" (built in Phase 12a, `docs/saved-looks.md`) |

## Swap a piece

Your looks' Swap a piece pushes it, on the version on screen. Since 12a, look detail on Saved Looks pushes it too, and Swap it on a piece that left her closet opens it on that piece (`docs/saved-looks.md`). Top to bottom, as in `swap.html`:

- **Which piece**: a chip per piece ("Layer", "Top", "Bottom", "Shoes", and the idea's kind on Something new). It opens on the first main piece. VoiceOver reads each chip with the piece's name.
- **The look**, its bundle with the piece being changed at full strength and the others stepped back, and a line under it: "Top now: Cream knit sweater", or "Trying Brick knit top".
- **"Your tops that go with this look"** (LR-07), then three of her pieces. Tapping one tries it in the look; tapping it again goes back.
- **Show 3 more** while there are more good matches. Then "That's every top in Main closet." and **See all tops** (LR-07.3), and "Not in your closet? Find one" with Mine + one idea (LR-07.4).
- **Keep current** and **Use this top** ("Use these shoes" for shoes). Use is off until she tries something. Under them: "Only the top changes. Everything else stays."
- **Remove this piece**, quiet, at the end. When taking the piece out would leave no look, it's off and says why: "A look needs a top and a bottom, or a dress, so this one can only be swapped."

Use and Remove go back to Your looks with a toast ("Swapped in Black block heels", "Took out Tan loafers") and Undo. Under the piece list, "You changed this look. Undo goes back one change." stays while there's anything to undo, since a toast is easy to miss.

**See all** opens a sheet, "All Tops", with every top she can wear from the source: the good matches first, then the others marked "May not match", then any that would rebuild an outfit she wore lately, marked "Worn together lately". It's Closet's search field, colour and suitcase filters and grid (the piece chips are hidden, since every piece is a top). Choosing one closes the sheet and tries it in the look. The sheet is filled from what Swap already has, so it reads nothing.

**Find one** opens the stand-in that says shopping comes later and nothing was searched (Phase 34).

### Ranking

`SwapRanking.options` is a pure function in Models, so it's tested on its own and the public repo holds no styling rules. It uses stored facts only (the amendment's "plain matching"):

1. **Who's in.** Her pieces of the same kind, not already in the look, that `Eligibility` allows from the look's source today: hers or arrived, not deleted, archived or away, not in the wash while laundry tracking is on, and inside the suitcase for a suitcase look (LR-07.2).
2. **Worn lately.** A top, bottom or dress that would make a main-piece combination she wore inside her repeat window (`WearRules`, LR-10) is set aside for See all.
3. **Good or weaker.** A piece is a good match when it's tagged for the look's occasion, its warmth suits the day's weather (when the look used the weather), and its main colour sits with every other piece. Otherwise it's weaker ("May not match").
4. **Order.** A score: occasion 2, colours 2, then one each for warmth, season, her fit (today's comfort or her usual fit) and the same dressiness as the piece it replaces. Ties go to the piece worn longest ago, then by name.

**Colours that sit together** (`colorsGo`): either colour is unknown, either main colour is a neutral (black, white, cream, beige, tan, brown, gray, navy, denim, olive) or multicolour, or they share a colour family. That's a paint-chart lookup, not taste. Better ranking would need the private rules and would become a server call later.

Ranking runs once when she picks a piece. Show 3 more only shows more of the same list, so it sends nothing (LR-07.1) and is instant with the large closet (LR-07.5: ranking every piece of a look over 2,400 garments is checked under 250 ms, paging under 150 ms).

### The changed look

`LookEditing` makes the changed look a new look with its own ID. It keeps the result and version it came from (it's still Simple, Dressed up or Something new), the occasion, the source and every other piece in its place (FR-09). It starts unsaved, unnamed and never worn. It has no try-on pictures: those point at the earlier look's ID (Phase 12b). The stylist's look stays as it was in background history.

`YourLooksModel` keeps the changed look per version and an `EditHistory` per version. Undo gives back exactly the look before (LR-08.2), one change at a time, back to the stylist's look. Try a different outfit starts clean. The bundle keeps the first look's layout seed, so a swap doesn't toss the other pieces around.

On Today, a piece she swapped in is marked "Swapped" (or "Added" if the stylist's look had no piece of that kind), as well as the version's own marks against Simple. Save look saves the changed look as its own saved look, named from its colours as before.

## Make your own look

It opens from a garment's Style with this, Make my own look (starting with that piece, if she can wear it today), and from "+ Make your own" on Saved Looks (RD-08), in its toolbar and on its empty state since 12a. No path leads to it from a result or a saved look (LR-08.1). Top to bottom, as in `editor.html`:

- "Build an outfit yourself, piece by piece." (LR-08's tour line).
- **Continue your look?** when a half-built look is waiting, with Resume and Start over.
- **Name** ("Name this look"), optional. An empty name is filled in from the colours on save ("Pink & navy"), or "My look".
- Where the pieces come from: Main closet, what she can wear today, nothing sent.
- **The bundle**, live, or "Your look shows here as you add pieces." Under it **Undo** and **Redo**.
- **A row per piece**: its sticker, kind and name, **Change** (opens the picker on that kind) and a remove button.
- **Add a piece**: the picker sheet with every piece she can wear from the main closet, piece chips for each kind it holds, colour and suitcase filters and search. Pieces in the look are marked "In the look". A piece of a kind the look already has takes its place: one of each kind.
- What still stops Save, in words, then **Save look** and a fine-print line.

`LookRules` checks the look: 2 to 6 pieces (RD-07.1), a dress or a top and a bottom (the same shape the mock stylist builds from; shoes aren't required), one of each kind, and every piece one she can wear today. The name follows `NameRules.lookName`. Save puts a named look (`isMadeByHer`, no version) in the look store and drops the draft; saving again after more changes updates the same look (PRD §7.3). It works offline and sends nothing (FR-32).

**Drafts (LR-08.4).** Every change writes a `LookDraft` (name, source, pieces, the starting piece) to `NookServices.lookDrafts`, in order. Opening Make your own look again offers a draft with work in it. While it's offered, the old draft is kept even if she changes the new look; Resume replaces the screen with it, Start over drops it and keeps what's on screen. Stage A keeps the draft in memory, so a UI test seeds one at launch with `-fixtures demo:draft=look` ("Pink for Friday": the pink shirt and the navy dress pants).

## Accessibility

- Swap's piece chips and options have the Selected trait, so the choice isn't shown by colour alone. Options read as one button each with "Shows it in the look." Show 3 more says nothing is sent.
- The bundle is one element naming its pieces (RD-07.3). The stepped-back pieces are only a visual cue.
- Remove this piece, when it's off, gives the reason as its hint and in words under it.
- At the accessibility sizes Swap's options become one column with the name beside the piece, the buttons stack, and Make your own look's rows put Change and remove under the name. Sheets open full height.
- Dark appearance uses the tokens throughout. Nothing animates beyond the bundle's own entrance, which already follows Reduce Motion.

## Tests

- Models: `SwapRankingTests` (kind, eligibility, suitcase, order, weaker matches, weather, worn lately, an idea's kind, colours), `LookEditingTests`, `LookRulesTests`, `EditHistoryTests`.
- `SwapModelTests`: nothing sent, the first piece and the words, options from the source, worn lately in See all only, See all's marks, Find one by Preferences and source, Show 3 more paging, the large closet's speed, trying and keeping, Use, swapping an idea, Remove and its reason, Undo back to the exact look, versions kept apart, a new result starts clean, and saving the changed look.
- `LookBuilderModelTests`: starting from Style with this, empty from Saved Looks, a piece in the wash, add, replace, remove, Undo and Redo, the checks, the picker, saving and saving again, the automatic name, offline, a store failure, and drafts across a relaunch.
- `PiecePickerTests`: the scope's pieces, order and marks, chips by kind, and Closet unchanged.
- `SwapSnapshotTests` (7 images) and `LookBuilderSnapshotTests` (9 images).
- UI: `SwapTests` (swap the shoes in Simple, See all, save the changed look; Remove and Undo), `MakeYourOwnLookTests` (from garment detail, add from the picker, name and save; a draft offered after a relaunch).

## Decisions for Jose

1. **Swap is a pushed screen, and Use or Remove go back to Your looks**, as in `swap.html`, with the Undo toast there. Undo also stays under the pieces while there's a change to undo.
2. **A changed look is a new look.** The stylist's version stays in history unchanged, and a look she already saved stays saved; Undo shows it again. Saving the changed look adds it to Saved Looks next to the original.
3. **Weaker matches only appear in See all.** In the demo's Office look most tops are weaker (not tagged for the office, or a light top on a cool day), so Swap shows one and See all shows the rest marked. The rule follows the amendment's wording ("suit the occasion, weather … and go with the rest of the look"); it can be loosened if Lily finds the list too short.
4. **Olive counts as a neutral** with navy and denim. Without it, olive trousers made almost every colour "May not match".
5. **Find one at the end of Swap follows Something new's rule**: Mine + one idea and not from a suitcase (LR-05b), not only Preferences.
6. **Remove this piece is off** when the rest wouldn't be a look (fewer than 2 pieces, or no dress and no top-and-bottom), and says why.
7. **Make your own look uses the main closet only.** Choosing a suitcase as its source can come later.
8. **Shoes aren't required** in a look she makes. The shape rule is a dress, or a top and a bottom, as the mockup said ("A look needs at least a top and a bottom").
9. **One piece of each kind** in Make your own look; adding another top replaces the first.
10. **"+ Make your own" sat on the Saved Looks stand-in** until 12a built that screen; it's now in the toolbar.

## Left for later phases

- **12a (done):** Swap it on a saved look's faded piece (LR-16) and Swap a piece from look detail, which change the saved look in place; the saved looks list and renaming.
- **16a, 16b:** the Make your own look tour, starting "Build an outfit yourself, piece by piece."
- **21a:** durable storage behind `LookDraftStore`.
- **34:** Find one.
