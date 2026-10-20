# Sample wardrobe

AI-generated sample images for the fixture closets. They are test data only, and none of them shows a real person.

Generated on 17 October 2026 with WaveSpeed:

- Garment photos and the woman in `people/`: Seedream 5.0 Flash.
- Cutouts: Ideogram Remove Background. They stand in for what Vision's subject lifting does on a phone.
- Try-on previews: Seedream 4.5 Edit, with the woman's photo and the pieces of the look as input.

## What's here

| Folder | Holds | Format |
|---|---|---|
| `photos/` | One photo per piece, as she'd take it. 21 demo pieces (`g-<id>`) and 30 extras (`x-<name>`) | JPEG, 1024 px at most |
| `cutouts/` | The same pieces on transparency, cropped to the piece | JPEG 2000 with alpha, 640 px at most |
| `people/person.jpg` | The example try-on photo (Profile, Your try-on photo) | JPEG, 1280 px at most |
| `tryon/` | The woman wearing five looks: office, casual, date, weekend, sundress | JPEG, 1280 px at most |
| `manifest.json` | The cutout quality signals, measured from each cutout, and each cutout's size in pixels (look bundles size shoes from its shape) | |

Four generated items (a bra set, pajamas, a swimsuit and a sports set) have no category in the app, so they are not bundled.

## How they're used

`SampleWardrobe` (in `Sets/`) names each picture as a `PhotoReference.sample`, and `SampleWardrobeProvider` reads the files, so pieces use the same path as real photos (`Garment.photo`, `Garment.cutout`, `GarmentArtChoice`, the image loader). The cutout signals come from `manifest.json`, so a lace top or a tiny pair of earrings shows its photo in a tile and the rest show as stickers, as they would from Vision.

- `-fixtures demo`: the 21 demo pieces (the brick knit top and the old gray leggings stay text-only), four looks with their try-on previews, and `people/person.jpg` as her try-on photo.
- `-fixtures demo:wardrobe=full`: plus the 30 extras, and the sundress look with its preview.
- `-fixtures large`: the photos are shared by category, kind and colour across the 2,400 pieces.
- `photos=drawn` turns the pictures off and shows the drawings.

## Rebuilding

`scripts/build-sample-wardrobe.swift <originals folder>` makes everything here from the generated originals (resizing, cropping the cutouts, writing JPEG 2000 and measuring the signals). The originals are not in the repo.

Cutouts are JPEG 2000 on purpose. PNG was 16 MB for the set. HEIC with alpha is smaller still, but the iOS simulator's HEVC software decoder hung on it (decodes never returned), which froze the UI tests' accessibility queries. ImageIO decodes JPEG 2000 in software on every device and simulator.

After a rebuild, look at every cutout on a dark and a bright background before committing. The signals catch fuzzy edges and pieces that run off the photo, but not a second object attached to the piece, such as a hanger or a chair.

## Known and kept

Decided by Jose on 17 October 2026, after the real-photo audit:

- 14 hung pieces keep their hangers in the cutout, and the black canvas tote keeps the chair post through its handles. Vision on a phone will keep hangers too; Phase 22a checks that.
- The two lace tops (and the clutch, hoops and necklace) fall back to their photo in a tile, so the demo shows what happens when a cutout isn't clean.
- The office preview shows a gray blazer; the closet's blazer is taupe.
