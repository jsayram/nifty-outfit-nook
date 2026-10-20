# Garment detail

Phase 7a, 14 October 2026. Garment detail shows one piece and what she can do with it. The visual reference is `closet/prototypes/RoomDirectionMockups/screens/garment.html`; where it differs from the amendment, the amendment wins. Spec: LR-10 (Last worn and the recent-wear note), LR-11 (suitcase names near the title), LR-16 (Remove from closet and Recently deleted), RD-11 (laundry only while tracking is on), LR-08 and the amendment's drafting decision 2 (Style with this), and PRD §7.4 (No longer own, Trash).

## What's where

| File | Holds |
|---|---|
| `Features/Garment/GarmentDetailScreen.swift` | The screen: Edit in the bar, the two sheets, the toasts, and handing a removal back to Closet |
| `Features/Garment/GarmentDetailPage.swift` | The page top to bottom, the picture, and the loading, gone and error states |
| `Features/Garment/GarmentFacts.swift` | The facts and one fact's row |
| `Features/Garment/GarmentSheets.swift` | The Style with this choices and the Remove from closet sheet |
| `Features/Garment/GarmentDetailModel.swift` | Loading, the changes it makes through the store, and `GarmentRemoval` with its Undo |
| `Features/Garment/GarmentDetailText.swift` | Every line of words, from stored facts with a given clock, calendar and locale |
| `Features/Closet/RecentlyDeleted/` | Recently deleted: its model, screen and rows |

Closet pushes the detail (`ClosetDestination.garment`) and Recently deleted. On a wide iPad window it shows the detail beside the grid instead, with Edit on the page rather than in a bar (Phase 15a, `docs/ipad.md`). Edit opens the Add a piece form filled in with the piece (Phase 7b, see `docs/add-a-piece.md`). Style Me (10a), Make your own look (11) and each suitcase's detail (13) are built. Saved Looks pushes the same screens from a look's piece, through the shared `ClosetDestinationScreen`.

## The page

1. **Her name for it**, in the display style, read as a heading.
2. **Last worn** (LR-10): "Last worn today", "yesterday", "5 days ago", then a date ("Oct 7", with the year when it isn't this year's). With no wear recorded it says "Not marked as worn yet", since wear is only what she records.
3. **The recent-wear note**, only for a top, bottom or dress worn inside her repeat window: "Style Me won’t repeat an outfit you wore it in during the last week" (or "last 2 weeks"). Shoes, layers, bags and accessories can repeat freely, and "I don't mind" has no note. This is the same `WearRules.isRecent` the mock stylist uses.
4. **"In suitcases:"** (LR-11), a chip per active suitcase, by name. Each opens that suitcase (a stand-in until 13). Archived suitcases don't count.
5. **The piece** on a soft glow with its contact shadow, tilted 3 degrees, as a sticker with a white edge (Phase 8b, `docs/stickers.md`): the drawing or the clean cutout, resting on the bottom of its space, or the photo in a rounded tile when there's no clean cutout. "In the wash" sits on it while tracking is on.
6. **Style with this**, and **Mark as dirty** or **Mark as clean** while tracking is on (RD-11). Laundry changes show a toast with Undo. Since Phase 11 the toast sits on a clear layer that keeps to the safe area, so it stays above iOS 26's floating tab bar (the fix Your looks got in 10b).
7. **Details**: Kind, Colour (swatches, names, and her note for the shade), Fit, Seasons ("All year" for all four), Occasions, Brand, Size, Status, Saved looks ("In 2 saved looks") and her Notes. Unknown facts are left out.
8. **Remove from closet**, quiet, at the end (LR-16).

Status reads "Available" when nothing is in the way, as in the mockup. Otherwise it says "Bought, not here yet", "Away until Oct 23" or "Away for now", and "Clean" or "Dirty" while tracking is on.

A piece she no longer has can still be shown (saved looks will link to it in 12a), with no actions.

## Style with this

A sheet with two choices (amendment, drafting decision 2):

- **Style me with it**: Style Me with the piece as the starting piece. Since 10a it opens the Style Me request with the piece set (`docs/style-me.md`).
- **Make my own look**: Make your own look starting from it (LR-08.3). Built in Phase 11 (`docs/swap-and-editor.md`).

## Remove from closet (LR-16)

A sheet with two choices. Both ask first, inside the sheet, and VoiceOver moves to each step's heading.

| Choice | Asks | Then |
|---|---|---|
| I don’t have it any more | "Take it out of your closet?" and what happens | Ownership becomes `noLongerOwned`. It leaves Closet and styling (`Eligibility` says `noLongerOwned`), keeps its suitcase and look links, and Closet shows "… is out of your closet" with Undo, which puts back the ownership it had (a bought piece stays bought) |
| Delete it | "Delete Navy dress pants?", the day it goes for good (30 days on), and the saved looks that use it, or "No saved looks use it." | It goes to Recently deleted. Closet shows "… is in Recently deleted" with Undo, which restores it |

After either one the screen goes back to the grid, which reloads. Archive isn't offered. If the save fails, nothing changes and a toast says so.

**Recently deleted** lists deleted pieces, most recent first, each with "Kept until Nov 13", Restore and Delete now. Restore brings back the same piece with its links (LR-16.3) and shows a toast. Opening it first removes pieces whose 30 days are up (`purgeExpired`), as PRD §7.4 asks when the app next runs.

**Delete now** (Phase 21a, PRD §7.4) deletes one piece for good before its 30 days are up. It asks first, in an alert titled "Delete Navy dress pants for good?", with the preview the PRD asks for, one sentence each (`PermanentDeletion` in Models works it out from the stores):

- "Its photo and details are deleted from this iPhone. This can't be undone." ("Its details" for a piece with no photo.)
- "Your unsaved changes to it go too.", when she left an Edit of it unsaved. The draft is discarded first, then the piece.
- "Saved looks that use it keep their other pieces: Office navy and Rainy Monday." Saved looks then say a piece was deleted for good, as after the 30-day purge (`LookDetailModel.goneCount`).
- "It comes out of Weekend.", for the suitcases it's packed in. Suitcases only show pieces that exist, as after the 30-day purge.
- "Try-on pictures with it in are deleted too.", when any picture shows it. Since Phase 21b the pictures that show a piece go when it's deleted for good, by Delete now or the 30-day purge, as PRD §7.4 says (Jose, 20 October 2026). Pictures of a look she deletes still stay (`docs/try-on-pictures.md`).

Delete for good removes it and shows "Navy dress pants is deleted for good". Only a piece in Recently deleted can go this way (`ClosetStore.deletePermanently` says not found for any other). A failed save leaves it in the list with the usual toast. The button is a quiet text button under Restore, or under it full width at the accessibility sizes, and reads "Delete Navy dress pants now" to VoiceOver.

## States

| State | What shows |
|---|---|
| Loading | "Opening this piece" with the soft dots |
| Gone (deleted elsewhere, or purged) | "This piece isn’t in your closet any more", where deleted pieces go, and Back to Closet |
| Error (`-fixtures demo:stores-fail`) | "This piece didn’t load", "Nothing was lost. Try again in a moment.", Try again |

Recently deleted has loading, empty ("Nothing here") and error states too.

## Accessibility

- Reading order follows the page: name (a heading), Last worn, the note, the suitcases, the buttons, the Details heading and each fact, then Remove from closet. The picture is hidden, since Status says the same in words.
- Each fact is one element, "Fit, Regular". Each suitcase chip reads "In suitcase Weekend" with the hint "Opens the suitcase."
- At the accessibility sizes the picture shrinks a little, each fact's value moves under its label, the suitcase chips wrap, and the sheets open full height. Buttons fill the width and wrap their words.
- The sheet step change fades under Reduce Motion instead of animating. Dark mode uses the palette tokens; the garment keeps its own colours, dimmed as in Closet.

## Tests

- `GarmentDetailTextTests`: Last worn with a fixed clock and calendar (today, yesterday, a late night, days, dates, another year), the recent-wear rule for each window and kind of piece, status in every case, the facts, the saved-look count and the deletion deadline.
- `GarmentDetailModelTests`: what loads for each kind of piece, gone and failing stores, mark dirty and Undo, "I don't have it any more" and Undo, Delete it then Restore from Recently deleted, a failed save, the 30-day purge, and Delete now: the preview, the piece and its unsaved Edit gone with looks unchanged, the question's words, and a failed delete keeping the piece. `PermanentDeletionTests` (Models): what the preview lists.
- `GarmentDetailSnapshotTests`: navy trousers (light and AX5), the lace top in the wash in dark, the tan loafers (never worn, no picture), the blue dress (away, two colours), the gone and error states, both sheets and Recently deleted.
- `GarmentDetailTests` (UI): open a piece from Closet, Delete it, find it in Recently deleted and restore it, then Delete now on the leggings, confirm, and Recently deleted is empty; mark it dirty, Style with this to Style Me, and "I don't have it any more" with Undo.

## Decisions for Jose

1. **LR-18's two lines aren't on garment detail.** "Saved until you change it." belongs to her fit profile (14a) and "Just for this outfit." to Style Me's Comfort (10a), as the amendment's phase table says. Detail shows the piece's own cut (Fitted, Regular, Relaxed) as a fact.
2. **The recent-wear note names the setting** rather than repeating "You wore this last week", which LR-10 puts on Your looks. Last worn already says when.
3. **"Add to a suitcase"** came in Phase 13: a soft button under Style with this opens a sheet of her suitcases with a tick each (`docs/suitcases-and-laundry.md`). The suitcase names open the real suitcase.
4. **Undo after Delete it** as well as after "I don't have it any more". LR-16 only asks for the first, but both ask first and Undo is cheap and safe.
5. **"Delete permanently now" came with real storage (Phase 21a),** as Delete now on each row, asking in an alert with the preview. Both parts of PRD §7.4's purge that waited came in 21b: the try-on pictures that show the piece go with it (Jose decided on 20 October 2026), and the piece leaves a content-free deletion marker, so a restore never brings the piece or those pictures back.
6. **"I don't have it any more" keeps suitcase membership** in the data. The piece no longer shows in Closet or styling, and Undo needs nothing else. Suitcases (13) must filter with `isInCloset`.
7. **Style me with it is offered for any piece in her closet**, even one in the wash or away. Style Me then says why it can't start a look ("In the wash") and offers another (Phase 10a, `docs/style-me.md`).
