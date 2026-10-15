# Your looks

Phase 10b, 14 October 2026. Your looks is what Style me opens: one outfit in three versions, a Saved tab, and plain states for everything that can go wrong. It replaces 10a's stand-in, which showed the request in words.

Spec: amendment LR-05a (one outfit in three versions, Try a different outfit), LR-05b (Something new follows Preferences, Find one), LR-06 (Today and Saved tabs, no Shuffle), RD-06 (Save look, Try it on, Swap a piece, Ask stylist) and LR-10 (the recent-wear note). Lily's sign-off sheet (L5, L6) wins over the mockups. The visual reference is `results-versions.html` in `closet/prototypes/RoomDirectionMockups/screens` (the `?v=1|2|3` version switch), with `results.html` for the states.

## What's where

| File | Holds |
|---|---|
| `Features/StyleMe/YourLooks/YourLooksModel.swift` | Sends the request, holds the result, the tab and version, saving, Try a different outfit, retry and cancel |
| `Features/StyleMe/YourLooks/YourLooksText.swift` | Every line on the screen: the request line, version names and descriptions, notes, the partial banner, piece marks, the name a saved look gets |
| `Features/StyleMe/YourLooks/YourLooksPage.swift` | The tabs, then the result, its progress or a state |
| `Features/StyleMe/YourLooks/TodayResult.swift` | The Today tab with a result, the four buttons, and the banner for a failure over a result |
| `Features/StyleMe/YourLooks/YourLooksStates.swift` | Styling, not enough pieces, and the failure states |
| `Features/StyleMe/YourLooks/SavedLooksTab.swift` | The Saved tab, a saved look's sheet, and the stand-in sheets |
| `Features/StyleMe/YourLooks/YourLooksScreen.swift` | Navigation, sheets, the save toast with Undo, VoiceOver announcements |

## The Today tab

Top to bottom, as in `results-versions.html`:

- **Today · Saved**, a small switch.
- **The request line**, "Office · Main closet · 58° and rain". The weather is left out when she ignored it or it couldn't be read; "Indoors" when she'll be inside.
- **Simple · Dressed up · Something new** on one line, and the selected version's description under it: "Easy and safe", "The same outfit, a little classier", "The same outfit, plus one piece you don't have". When Something new has no idea piece (Only mine, or a suitcase) it says "The same outfit, another way with your own pieces". Switching sends nothing and keeps the scroll position (LR-05a.2).
- **Quiet notes** with a sparkle: "You wore this 5 days ago" (LR-10), the suitcase line on Something new ("Looks from Weekend use only what's packed, so Something new is made from your own pieces.", LR-05b), weather that couldn't be read, and "That's every outfit … can make" when Try a different outfit has nothing new.
- **The bundle**, large, with the version as its spoken title. A new result lays its pieces down; switching versions doesn't, so shared pieces stay still.
- **The piece list.** "Same as Simple" on shared pieces, and "Swapped" or "Added" on the others (LR-05a.3). Swapped means Simple has a piece of that kind; Added means it doesn't. The idea piece says "Not in your closet" with Find one (LR-05b.1).
- **Save look, Try it on, Swap a piece, Ask stylist**, two by two, one column at the accessibility sizes (RD-06.3). "Try-on pictures are simulated." under them.
- **Try a different outfit**, "Uses 1 styling request."

## What each button does

| Button | Does |
|---|---|
| Save look | Saves the version on screen and names it, then says "Saved to Saved Looks" with Undo. The button becomes Saved; tapping it takes the look out again, also with Undo. An idea piece stays an idea (LR-05b.3) |
| Try it on | A stand-in sheet labelled Simulated. Real simulated pictures are Phases 12b and 33 |
| Swap a piece | Swap a piece on the version on screen (Phase 11, `docs/swap-and-editor.md`). A swap or Remove this piece comes back here marked "Swapped", with Undo in a toast and under the pieces |
| Ask stylist | A stand-in sheet. RD-06 keeps Ask stylist on results; there's still no Ask stylist link on swap |
| Find one | A stand-in sheet: "Nothing was searched" (LR-05b.4). Phase 34 |
| Try a different outfit | One more request with the same choices and a new ID. All three versions are replaced and Simple is selected again (LR-05a.4) |

**Names.** Looks are named when saved (LR-08), from their main colours: "Cream & olive", "Blue dress", "All navy", with ", dressed up" or ", something new" for those versions. Renaming is Saved Looks' job (12a).

**History.** Every version of every result goes into the look store unsaved, as background history (LR-06). Saving sets `isSaved` and the name; unsaving clears both. Try a different outfit leaves the earlier result in the store, unsaved, so it never shows on the Saved tab (LR-06.4).

**A new base.** The model tells the stylist which main-piece combinations it has already shown for this request (`StylingContext.shownCombinations`). The mock stylist starts from one it hasn't shown; when there's none left, the best one comes round again with a note.

## The Saved tab

Looks she saved for the same source and occasion, newest first: the small bundle, the name and "4 pieces · Last worn 9 Oct". Opening one shows its bundle and pieces in a sheet. The tab sends nothing (LR-06.1), works offline, and has no Shuffle (LR-06.3). With nothing saved it says how to save a look (LR-06.2).

## States

Every state is driven by the fixture stylist and can be forced with `-fixtures demo:<flag>`:

| State | Flag | What she sees |
|---|---|---|
| Styling | `stylist-waits` (never answers), `slow` (3 s) | "Styling…" with a Simulated badge, three steps (check the pieces, send the request, choose one outfit in three versions), a progress bar and Cancel. The dots fade and the bar doesn't move under Reduce Motion |
| Complete | none | Three versions |
| Partial | `stylist-partial`, or the Jose's house suitcase | Only the versions there are, and a butter banner saying which is missing and why: "No Dressed up this time. Jose's house has no dressier piece to swap in." From a suitcase it offers Use Main closet |
| Not enough pieces | `stylist-insufficient`, or the Gym suitcase | "Not enough pieces for a look", "Nothing was charged, and nothing was made up to fill the gap.", how many pieces the source has, what a look needs, then Add a piece (or Add pieces to the suitcase) and Change your request |
| Didn't finish | `stylist-fails` | "Styling didn't finish", Try again, Back to Style Me, See saved looks. It never says the closet is too small |
| Offline | `offline`, `offline-once` | The offline banner with Retry, "Styling needs a connection", See saved looks. With `offline-once` the retry works, as if the connection came back |
| Stopped | leaving while styling | "Styling stopped", nothing used, Style again |

A failure while a result is already on screen (Try a different outfit offline, say) keeps the looks and puts the banner above them. Offline, Try it on and Ask stylist are dimmed and a line says Save and Swap still work.

Two more states guard the edges: the closet couldn't be read (nothing was sent), and the suitcase or starting piece changed since she asked (back to Style Me).

**Sending and cancelling.** The request goes when the screen first appears; coming back to it never sends again on its own. Cancel, or leaving the screen, cancels the request, and an answer that arrives later is dropped. With a result on screen, cancelling goes back to it; without one, Cancel returns to Style Me. Each result is checked with `ResultCheck` before it shows; one that fails the check is "didn't finish". Styling from a suitcase marks it used, which makes it a favourite (RD-09.2).

## Accessibility

- The version switch reads as three buttons with Selected on the chosen one, and each option's description as its hint. Switching announces the version and its description (LR-05a.6).
- The bundle is one element naming its pieces; each piece is also in the list (RD-07.3). A saved look row is one button with the look's name, pieces and detail.
- VoiceOver hears "Your looks are ready." when a result arrives, and the state's title when styling ends another way.
- At AX5 the tabs and the version switch stack, the four buttons become one column, and the styling header puts the badge under its title.
- Dark appearance uses the tokens throughout.

## Tests

- `YourLooksModelTests`: one request and three versions, starting again sends nothing, switching sends nothing, Something new by Preferences and from a suitcase, history kept unsaved, the suitcase marked used, partial, a small suitcase, insufficient (Gym and forced), a failure and its retry, offline and `offline-once`, a result that fails `ResultCheck`, a missing suitcase, failing stores (nothing sent), styling steps and Cancel, a late answer dropped, Try a different outfit (one request, a new base, history kept), offline and cancelled Try a different outfit, the Saved tab's matching, save, unsave and Undo, saving Something new, and the words.
- `MockStylistTests`: a shown base gives a different outfit, the note when none is left, the insufficient and `failingOnce` modes. `StyleRequestTests`: `again` keeps every choice; the context carries the shown bases.
- `YourLooksSnapshotTests`: each version, Something new dark and from a suitcase, Simple at AX5, styling (and at AX5), partial, insufficient, didn't finish, offline (and dark), stopped, offline over a result, and the Saved tab (with looks, dark, empty). Eighteen images.
- `YourLooksTests` (UI): a full run from the laptop through every version, Save look, the Saved tab, the stand-ins and Try a different outfit; Cancel while styling; offline then Retry; partial, insufficient and didn't finish by flag. `StyleMeTests` now checks the request line and Something new on Your looks.

## Decisions for Jose

1. **Tabs are "Today" and "Saved"**, as the amendment says (LR-06). The sign-off note said "Saved" for Earlier; the current result's tab is Today.
2. **One tap saves, with an automatic name** from the main colours. A name sheet would add a step to Save look; renaming comes with Saved Looks (12a).
3. **Tapping Saved takes the look out again**, with Undo, rather than doing nothing.
4. **A missing version is left off the switch** rather than shown greyed out, and the banner says what's missing and why.
5. **Leaving cancels styling**, as the plan asks. The mockup's "You can leave this screen. Your looks will wait here." is replaced by "Leaving this screen stops it, and nothing is used." Coming back after switching tabs mid-way shows Styling stopped with Style again; it never re-sends on its own.
6. **Offline retry is a button.** Stage A has no connection monitor, so Retry is how she says she's back; `offline-once` shows it working.
7. **No "why" line under the bundle.** The mockup's explanation text needs the stylist to write one; the mock stylist doesn't. The description and notes cover it for now.
8. **"From your history" (FR-58) isn't built.** The history check before paid inference belongs with the real stylist (27a); results are already kept for it.
9. **The recent-wear note counts days** ("You wore this 5 days ago") rather than the amendment's example "last week".
10. **The saved look sheet is read-only** (bundle and pieces). Look detail, Wear today and Swap it live on Saved Looks (Phase 12a, `docs/saved-looks.md`).

## Left for later phases

- **11 (done):** Swap a piece and Remove this piece, with Undo (`docs/swap-and-editor.md`).
- **12a (done):** Saved Looks and look detail, renaming, Wear today (`docs/saved-looks.md`). Saving now records `savedAt`, and a piece that has left her closet shows faded on the Saved tab too.
- **12b, 33:** Try it on with simulated, then real, pictures.
- **15a:** iPad results with the versions beside the look. The page keeps to 600 points and centres.
- **27a:** the real stylist contract, the history check, and the explanation line.
- **34:** Find one.
