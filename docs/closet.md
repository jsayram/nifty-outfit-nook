# Closet

Phase 6, 14 October 2026. Closet is where she browses, searches and filters her pieces. The visual reference is `closet/prototypes/RoomDirectionMockups/screens/closet.html`; where it differs from the amendment, the amendment wins. Spec: RD-13 (layout), LR-09 (piece and colour filters), LR-11 (suitcase icon, filter and search), RD-11 (Laundry only while tracking is on), LR-16 ("Recently deleted · N") and LR-10 (last worn, spoken only on the grid).

## What's where

All of it is in `Packages/NookKit/Sources/Features/Closet`, apart from the pieces other screens will share.

| File | Holds |
|---|---|
| `ClosetScreen.swift` | The navigation stack, Add a piece and Profile in the bar, and the toasts after a save or a removal |
| `ClosetPage.swift` | The page top to bottom, and the loading, error, empty and no-match states |
| `ClosetHeader.swift` | The wall with the title and count, and the small armoire |
| `ClosetFilters.swift` | The piece chips, colour swatches, the Suitcase menu, Dirty and Clear |
| `ClosetTiles.swift` | The Suitcases and Laundry tiles |
| `Grid/GarmentGrid.swift` | The lazy grid, its columns per text size, and one piece's cell |
| `ClosetModel.swift` | Loading, the filter state, the search delay and the words the page shows |
| `ClosetItem.swift` | One piece as the grid shows it, and what VoiceOver reads about it |
| `ClosetDestination.swift` | The screens Closet pushes |
| `ClosetDestinationScreen.swift` | The screen for each destination, shared with Saved Looks, which pushes the same screens from a look's piece. Its switch has no `default`, so a new destination can't open the wrong screen on one tab |
| `RecentlyDeleted/` | Recently deleted, with Restore (Phase 7a) |
| `Shared/GarmentArt/` | Garment pictures: the image loader, the placeholder drawings and garment colours |
| `Shared/GarmentWords.swift` | The words for kinds of piece and colour families |

## The page

Top to bottom, as RD-13 orders it:

1. **Header.** "Closet" in the display style on the wall, "Main closet" and the count under it ("17 pieces", "5 of 17 pieces" while filtering, "No pieces yet"), and the open armoire on the right at the mockup's size (390 x 284 at 0.535). The armoire is decoration only: hidden from VoiceOver, not tappable. Its clothes are a separate drawing, left out when the closet is empty. Add a piece and Profile sit in the navigation bar; the bar's own title is empty, since the big title is on the wall.
2. **"Continue where you left off?"**, only when a piece she started adding or editing wasn't saved (Phase 7b, see `docs/add-a-piece.md`), with Resume and Discard.
3. **Search.** "Search your closet". See [Search](#search).
4. **Filters.** Three rows of chips: the kinds of piece, a swatch for each colour in her closet, then the Suitcase menu, Dirty while laundry tracking is on, and Clear once anything is set.
5. **Suitcases and Laundry** as soft tiles with their small drawings. Laundry only shows while tracking is on (RD-11.1), and its basket is full or empty to match. They sit side by side while each tile's words fit on their lines in half the width (`ClosetTilesLayout`), and one above the other otherwise: at the accessibility sizes, and on a 375 point iPhone SE, where "Suitcases" broke as "Suitcas-es" (QA, 17 October 2026).
6. **Her pieces**, standing on the floor with a soft shadow under each and the name below.
7. **"Recently deleted · N"** at the bottom when anything is in it (LR-16).

Everything below the header sits on the floor colour. Secondary text on the bare floor is just under 4.5:1, so the states and the Recently deleted row sit on a soft tint, as the design system asks.

## Filters

| Row | Choices | Rule |
|---|---|---|
| Kind of piece | Tops, Bottoms, Dresses, Layers, Shoes, Bags (LR-09), plus Accessories when she has any | Any of the selected kinds |
| Colour | One swatch per colour family in her closet, in a fixed order, each with its name | Any of the selected colours |
| Suitcase | A menu: Any, In a suitcase, Not packed, then each suitcase that isn't archived, by name (LR-11) | One choice |
| Dirty (N) | Only while tracking is on (RD-11) | Pieces marked as in the wash |

Rows combine with each other and with search, and Clear resets everything, search included (LR-09). The rule itself is `GarmentFilter` in Models, so Saved Looks (12a) can use the same one. A suitcase that disappears after a reload, or the Dirty chip after tracking is turned off, drops out of the filter rather than leaving an empty grid.

When nothing matches, the page says "No pieces match", names the filters that are on ("Shoes · Pink · “navy”") and offers Clear filters (LR-09.3).

At the accessibility text sizes the rows wrap so no chip is hidden off screen, which makes them several screens tall at AX5. There they fold away behind a Show filters button (with "2 on" read out when filters are set), so her pieces come straight after the search field and the tiles.

## Search

Every typed word has to match somewhere: the name, the brand, her colour note, the name of a suitcase the piece is in (LR-11.3), or Closet's words for its kind and colours ("shoes", "denim"). So "navy pants" finds Navy dress pants and "weekend shoe" finds the sneakers packed for the weekend. Case and accents don't matter.

Search waits for a 250 ms pause in typing before it runs, so the large closet isn't filtered on every letter. Pressing Search, or emptying the field, applies at once.

### Possible matches (PRD §7.6)

When no piece has every word, Closet still says "No pieces match" with Clear filters, and then lists **Possible matches**: pieces that have some of her words. It's a separate, labelled section, never mixed with real results. The line under the heading says "These have some of your words, not all, so they might not be what you meant." and names any word none of them has ("None of them has “party”."). Each piece carries a small "2 of 3 words" mark, and VoiceOver reads which words it has and which aren't recorded on it ("Has “navy” and “pants”. Not recorded: “party”").

- The rule is `GarmentFilter.possibleMatches` in Models. The chips, swatches, Suitcase filter and Dirty chip still apply in full; only the typed words are loosened.
- Filler words ("my", "the", "with" and a few more, a translatable list in `ClosetModel.fillerWords`) don't count. With fewer than two other words there's nothing to loosen, so nothing is listed.
- More words first, then newest first, and at most eight.
- Closet only. Swap's See all and the piece picker share this model but don't show possible matches, since picking a piece there doesn't open its detail.
- Nothing is stored and nothing leaves the phone. There's no spelling or synonym help yet ("baggie" for "baggy").

Opening a possible match opens its detail with **Remember this name** (`docs/garment-detail.md`). Once she remembers the words, the same search finds the piece as a real result.

## The grid

`LazyVGrid`, so only the cells on screen exist. Columns follow the width and the text size:

| Text size | Layout |
|---|---|
| Up to xxxLarge | As many 104 pt columns as fit: 3 on an iPhone, 7 on an 11-inch iPad, more sideways |
| AX1, AX2 | 150 pt columns, bigger pictures |
| AX3 to AX5 | One piece per row, picture beside the name, so long names wrap between words |

Each cell was worked out when the closet loaded (`ClosetItem`): its suitcases' names, whether it's in the wash, when it was last worn. A cell does no lookups. A packed piece shows one small suitcase at its feet, however many suitcases it's in, with no words (LR-11.1). A piece in the wash shows a Dirty badge, only while tracking is on.

**VoiceOver.** Each piece is one button. Its label is the name, its value the rest: "Navy dress pants", then "In Jose's house and Weekend, Last worn 5 days ago". Last worn says today, yesterday, 2 to 6 days ago, then a date ("Oct 7"). The hint is "Opens the piece." Filter chips say "Selected" when on, and each row is a group named for what it filters. The armoire, the tile drawings and the pictures are hidden.

Tapping a piece opens its detail (Phase 7a, see `docs/garment-detail.md`). Closet reloads when she comes back, so a piece she marked dirty or removed there shows as it is now.

## Garment pictures

A piece with no photo draws a placeholder (every piece did in Stage A, and still does with `-fixtures demo:photos=drawn`; since 17 October 2026 the fixture pieces show the sample wardrobe's photos, see `docs/stickers.md`): its kind's outline (a top, trousers, a dress, a jacket, a loafer, a handbag, a hat for accessories) filled with its main colour, a detail such as a waistband or sole in its second colour, and a darker outline. Garment colours are their own, not the room's palette (LR-02), and dim to 92% in dark, as the room art's garments do. A piece with no colour recorded is a quiet stone.

Phase 8b routes every piece's picture through `GarmentPicture`, which picks the drawing, the cutout or the photo tile (`GarmentArtChoice`, see `docs/stickers.md`). The grid keeps the standing look from `closet.html`: a clean cutout stands plain on the floor, and a photo without one shows in a rounded tile the same size.

The path for real photos is already in place. `GarmentPicture` asks `GarmentImageLoader` for the picture at the size it's shown, in pixels. The loader asks the `ImageProvider` (the fixtures' `SampleWardrobeProvider` answers for the sample wardrobe's photos and cutouts and `nil` for anything else), shrinks what comes back with ImageIO's thumbnail call away from the main actor, so a full photo is never decoded, and keeps it in an in-memory cache by picture and size. Pieces with no picture are remembered too (up to 1,000, then the list starts over), while a load that fails isn't, so it's tried again next time. Two cells asking for the same picture share one load. The memory cache holds at most 300 pictures and 64 MB, and her own photos come from thumbnails on disk (Phase 22b, `docs/image-storage.md`).

## States

| State | What shows |
|---|---|
| Loading | The header, then "Opening your closet" with the soft dots |
| Error (`-fixtures demo:stores-fail`) | "Your closet didn’t load", "Nothing was lost. Try again in a moment.", Try again |
| Empty (`-fixtures empty`) | The empty armoire, a rail of empty hangers, "Your closet is empty", Add a piece and Describe in words (RD-13.2) |
| No matches | See [Filters](#filters) |

Offline doesn't apply: Closet only reads local stores.

The closet reloads each time the tab appears, so a change made elsewhere (laundry tracking turned on from the Home hamper) shows up.

## Performance

Measured on an Apple-silicon Mac, iOS 26.5 simulator, Debug, tests run one at a time, with the 2,400-piece closet:

- Preparing the grid (filtering to her closet, suitcase names per piece, chips): 48 ms, once per load.
- The slowest single chip, swatch, Suitcase or search change: 7 ms.
- Scrolling: five fast flings down the grid, measured with `XCTOSSignpostMetric.scrollingAndDecelerationMetric`, took 2.58 s on average with 0.3% spread. The simulator doesn't report hitch counts, so the hitch rate needs a run on a real phone (see Needs Jose in the PR).

`LargeClosetBrowsingTests` holds the first two to loose bounds (500 ms and 150 ms, the fastest of three runs, three times that on CI) so CI catches a big slowdown without flaking. `ClosetScrollPerformanceTests` (UI) is the scroll measurement; it's skipped unless `TEST_RUNNER_NOOK_PERFORMANCE=1` is set, because it takes about three minutes.

## Tests

- `PossibleMatchesTests` (Models) and `ClosetPossibleMatchesTests`: which pieces are possible matches, their order and limit, filler words, chips still applying, none with real results or in a picker, and the words for each piece.
- `ClosetModelTests`: what each fixture set loads, the suitcase names, laundry tracking on and off, each filter alone and together, search words, Clear, the search delay, and what VoiceOver reads.
- `LargeClosetBrowsingTests`: timing with the large closet.
- `GarmentImageLoaderTests`: downsampling, the cache, remembered misses, retrying a failed load, and the placeholder drawings.
- `ClosetSnapshotTests`: the demo closet with tracking on, the same in dark, AX5, no matches, possible matches, empty, and the error state, 402 pt wide; and the tiles alone on a 375 pt iPhone SE, stacked.
- `ClosetTests` (UI): a piece chip and its selected state, Clear, search by name, VoiceOver's value on a piece, opening a piece and coming back, and the empty closet's Add a piece. `testPossibleMatchesAndRememberThisName` searches "navy party pants", opens the possible match, remembers the words, and finds the piece by them back on Closet.
- `LaunchTests` (UI) now reads the piece count from Closet's header for the demo, offline, empty and large sets, and the error state for `stores-fail`.

## Decisions for Jose

1. **Accessories get a seventh chip** when she has any. LR-09 lists six chips, but the model has accessories as their own kind, and without a chip they could only be found by search. The demo has none, so it shows the approved six.
2. **Laundry is hidden while tracking is off.** The mockup shows a faded "Off" tile; RD-11.1 says no Laundry entry anywhere while it's off, and the amendment wins.
3. **No "Photos stay on this iPhone." line** under the empty closet. Where photos live is decided in Phases 20 to 22 (and cutouts in 8a), so the app shouldn't promise it yet.
4. **Last worn is spoken, not shown, on the grid.** LR-10 puts "Last worn" on saved looks and garment detail; the grid keeps to the approved name-only cells, and VoiceOver hears it.
5. **The filters fold away at AX sizes** behind Show filters, so her pieces aren't several screens down.
6. **The packed suitcase sits at the piece's feet**, not its top corner, so it never covers the Dirty badge and stays near shoes and bags.
7. **Not used here: LR-13's "Add a piece that fits you well".** It belongs to Profile's fit section (14a), not to adding a closet piece.

## Left for later phases

- **13 (done):** Suitcases and Laundry behind their tiles (`docs/suitcases-and-laundry.md`). The grid can also tick several pieces (the packing sheet) and show a minus on each (a suitcase's pieces).
- **15a (done):** on a wide window, the sidebar, the grid and the piece beside them, or the page with the piece beside it upright. See `docs/ipad.md`.
