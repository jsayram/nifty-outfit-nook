# Stickers and the photo tile

Phase 8b, 14 October 2026. How a garment's picture is shown: cut out of its photo with a thick white sticker edge (RD-07), or, when there's no clean cutout, the photo itself in a soft rounded tile (RD-07.2). The 8a go/no-go on Lily's iPhone 12 is still open, so both paths are built and either outcome works without code changes.

The visual reference is `.stk` in `closet/prototypes/RoomDirectionMockups/screens/results.html` and `garment.html`: her garment, a white edge, a soft shadow below, a slight tilt, no tile and no hanger.

## What's where

| File | Holds |
|---|---|
| `Models/Wardrobe/GarmentCutout.swift` | A garment's cutout: the picture and its quality signals |
| `Models/Rules/GarmentArtChoice.swift` | The rule: drawing, cutout or photo tile. `CutoutThresholds.current` |
| `DesignSystem/Components/Sticker/` | `NookSticker`, `NookPhotoTile`, `StickerRenderer`, `StickerCache`, `StickerSpec` (see the DesignSystem README) |
| `Features/Shared/GarmentArt/GarmentPicture.swift` | The one entry point every screen uses |
| `Features/Shared/GarmentArt/GarmentDrawing.swift` | The placeholder drawing as a cutout-like picture |
| `Features/Shared/GarmentArt/TileFraming.swift` | Which part of a photo a tile shows |
| `Fixtures/Sets/SamplePhotoGarments.swift`, `Fixtures/Providers/SamplePhotoProvider.swift` | `-fixtures demo:photos=samples` |

## Choosing sticker or tile

`GarmentArtChoice` decides from the piece's photo and cutout, the same way on every screen:

| The piece has | Shown as |
|---|---|
| No photo | Its drawing (kind and colours), cut out like a photo |
| A photo, no cutout yet | The photo in a tile |
| A photo and a cutout inside `CutoutThresholds.current` | The cutout |
| A photo and a cutout with a concern (too small, too large, several subjects, runs off the photo, unsure edges) | The photo in a tile, with the concerns |

`CutoutThresholds.current` is 8a's proposal until the benchmark on Lily's phone settles it. Changing it is one line, and the tests use whatever it is.

`Garment.cutout` is new: the cutout picture's reference and its signals. Choosing a new photo on Edit drops the old cutout (`GarmentDetails.apply`), so a stale cutout never shows. A garment saved without the field still decodes. It's Personal data, like the photo (DATA_MAP.md already lists cutouts).

## Presentation

`GarmentPicture` takes the piece, a size and a presentation:

- **Sticker** (`.sticker(.centred)` or `.sticker(.resting)`): the cutout or drawing becomes a `NookSticker`. Garment detail uses it now, resting on the bottom of its space so a shoe or bag sits on the contact shadow instead of floating above it. Phase 9's look bundles will use it.
- **Standing** (`.standing`): the cutout stands plain on the floor and the drawing is the SwiftUI drawing, as before. The Closet grid, Recently deleted and the Add a piece thumbnail use it.

The photo tile is the same in both: `NookPhotoTile`, the same size the sticker would take, so a piece that falls back doesn't move anything. With quality signals, the tile frames the garment (`subjectBounds` plus 12% around it); without them it takes the middle of the photo.

Why the grid isn't stickers: `closet.html` shows her pieces standing on the floor with a contact shadow and no edge, and only the looks, garment detail (and the iPad closet's detail pane, Laundry) draw stickers. So the grid keeps that look, and real cutouts stand there plain.

## Fixture art as stickers

Stage A has no photos, so every piece shows its drawing. `GarmentDrawing` draws it with Core Graphics on transparency, cropped to the piece, at the sticker's own resolution, so it gets exactly the edge a real cutout would. Its cache name is its kind and colours, so pieces that look the same share one sticker: the 2,400-piece closet needs a few hundred, not 2,400.

## Sample photos in the app

`-fixtures demo:photos=samples` adds eight pieces with drawn sample photos (the 8a synthetic scenes) and stand-in cutouts: the same scene drawn without its background and cropped to the garment, because the simulator can't lift subjects. Coverage, edges and bounds come from the drawing; the subject count and soft-edge share come from what the Mac's Vision reported in 8a. Six come out as stickers. The white tee (unsure edges) and the green tee with shoes (two things in one photo) fall back to tiles. Without the option nothing changes.

## Loading and performance

- Photos and cutouts load through `GarmentImageLoader` at the size shown (half as big again for a tile, so a cropped tile stays sharp), off the main actor, and are cached. A sticker waits for its picture with its space empty; the grid shows the drawing while a photo loads, as before.
- The sticker is made off the main actor and cached by what it shows plus its size, scale, appearance and placement (`StickerCache`). A cutout's cache name is its picture's reference, so a new photo can't show an old sticker. Keying by garment ID plus size was the first idea; the picture's reference is one per garment for real photos and needs no clearing when a photo changes.
- Measured on an Apple-silicon Mac, iOS 26.5 simulator, Debug: a detail-sized sticker at 3x takes about 25 ms (`StickerSpeedTests`, bound 250 ms, three times that on CI). The edge is a greyscale dilation with Accelerate (`vImageDilate_Planar8`); a first version in plain Swift took 1.7 s in Debug.
- `GarmentStickerCacheTests` scrolls the large closet down and back up a row at a time: each distinct sticker is made once, scrolling back makes none, and with a small budget the rows just scrolled past are still kept.

## The benchmark

The `-cutout-bench` screen now shows each photo three ways: the photo, the cutout as a sticker, and the photo as a tile, with "(pick)" on the one the signals choose. When Jose runs it on Lily's iPhone 12, that's the Phase 8b checkpoint as well: her real garments as stickers and tiles, with the thresholds' choice beside his own "usable?" mark.

## Tests

- `GarmentArtChoiceTests` (Models): every row of the table above, each concern alone, custom thresholds, the cutout dropped on a new photo, encoding and an old record.
- `StickerSpecTests`, `StickerRendererTests`, `StickerCacheTests` (DesignSystem): edge and shadow sizes, the garment's colour and its white edge, thin parts, shadow only below, the dimmed dark edge, resting placement, empty pictures, cropping; the cache's single render, shared renders, keys, misses, least-recently-used eviction and clearing.
- `GarmentDrawingTests`, `TileFramingTests`, `GarmentStickerCacheTests`, `StickerSpeedTests` (Features).
- `SamplePhotoFixtureTests` (Fixtures): the option, six stickers and two tiles, signals read from the drawing, the provider's PNG and JPEG.
- Snapshots: `GarmentStickerSnapshotTests` (every kind of drawing as stickers at two sizes, light and dark; the eight sample photos, light and dark; garment detail with a cutout and with a tile), the catalog's stickers page in light, dark and AX5, and garment detail's five pictures re-recorded as stickers.

## Decisions for Jose

1. **The grid stays standing, not stickers**, because `closet.html` draws it that way. Stickers are on garment detail now and in looks from Phase 9.
2. **Garment detail rests the sticker on the bottom** of its space rather than centring it as the mockup does, so wide pieces (shoes, bags, hats) sit on the contact shadow.
3. **The edge is 1.8% of the sticker's long side**, a little more than the mockup's 3 px on a 216 px piece, because the single solid edge read thinner than the mockup's stacked shadows.
4. **In dark the edge is a warm off-white** (`#EEE7DE`), not pure white, to match the garments dimmed to 92%.
5. **Cache by picture, not garment ID.** See Loading above.
6. **Thresholds stay at 8a's proposal** until the benchmark on her phone.
