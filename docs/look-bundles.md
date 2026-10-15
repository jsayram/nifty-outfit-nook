# Look bundles

Phase 9, 14 October 2026. A look is shown as a sticker bundle (RD-07): her pieces cut out with a thick white edge, laid out where they're worn, slightly tilted and overlapping, with no tiles and no hangers. It's one view, used wherever a look appears: results (10b), swap and the editor (11), Saved Looks and look detail (12a). Phase 9 builds the view and its catalog page; the screens that use it come in those phases.

The visual reference is `results.html` (the open look and the other looks as small bundles), `results-versions.html` (Something new with its "Not in your closet" tag and Find one), `saved.html` and `look.html` in `closet/prototypes/RoomDirectionMockups/screens`.

## What's where

| File | Holds |
|---|---|
| `DesignSystem/Components/Bundle/StickerBundleLayout.swift` | The layout: `BundleRole`, `BundlePlacement`, `StickerBundleLayout.place(_:seed:)` |
| `Features/Shared/LookBundle/LookBundleContent.swift` | What a bundle shows, built from a `Look` and the garments loaded for it |
| `Features/Shared/LookBundle/LookBundle.swift` | The view, its sizes and the idea tag |
| `Features/Shared/LookBundle/LookPieceList.swift` | The text list of pieces under a bundle, with Find one |
| `Features/Shared/LookBundle/LookBundleText.swift` | The words, including what VoiceOver says |
| `Features/Debug/Catalog/` | The catalog page and its sample looks (Debug only) |

## The layout

`StickerBundleLayout` is pure arithmetic in DesignSystem, so it's tested without views. It works in the mockups' 300 x 356 box and the view scales the result to its width.

- **Where pieces go.** The spots come from the mockups' `spots()`: a top alone across the top, or a layer on the left and the top on the right; trousers or a skirt in the middle; shoes low on the right over the trousers' hem; the bag at the right side. A dress takes the top and middle, with a layer or top beside it on the upper right. An accessory takes the bag's place, or goes low on the left when there's a bag. With no trousers or dress, the shoes come up nearer the middle.
- **Leftovers.** A second top, a second pair of shoes and so on go to the free spot nearest where that kind usually goes that overlaps the others by at most 20%. The search spirals out past the box, so such a spot always exists. A usual spot that would cover more than 24% of a piece placed before it is treated the same way.
- **Tilt and nudges.** Each piece gets its spot's tilt (as in the mockups, -8° to 8°), plus up to 2.5° more and a nudge of up to 3 points, from a seed. The seed is the look's ID, hashed with FNV-1a and run through SplitMix64, so a look lies the same way on every screen and every launch. Swift's `Hasher` can't be used: it's seeded differently on each launch. Nudges happen before the overlap checks, so they can't push two pieces over the limit.
- **Filling the box.** The whole arrangement, tilted corners included, is scaled and centred inside a 6 point margin, growing at most 1.25 times. Nothing is clipped, and a two-piece look isn't lost in empty space.
- **Stacking.** Back to front: dress and trousers, layer, top, accessory, bag, shoes. So the top's hem lies over the trousers and the shoes over the trousers' hem.

Tests (`StickerBundleLayoutTests`) run every mix of 2 to 6 pieces, kinds repeating (1,708 mixes), with three seeds: every piece inside the box with its tilt, no two frames overlapping more than 30% of the smaller one (the worst is 24%), one placement per piece, the same placements for the same seed, a fixed first number from the seed, different tilts for different looks, worn order, stacking, and a dress look. Placing all 1,708 takes about 1.2 s in a Debug build on a Mac, about 0.1 ms for a typical six-piece look.

## The view

`LookBundle(content, size:, title:, animatesEntrance:)`.

- **Content.** `LookBundleContent(look:garments:)` takes a look and the garments a screen has loaded. Pieces come in body order (layer, top, dress, bottom, shoes, bag, accessory). A garment that's gone from the store (purged from Recently deleted) is left out. An idea piece has no photo and is drawn from its kind and colours.
- **Pictures.** Every piece goes through `GarmentPicture` with the sticker presentation, so a clean cutout is a sticker, a photo without one is a rounded tile in exactly the same space (RD-07.2), and a piece with no photo is its drawing.
- **Sizes.** `.large` (300 points, the open look on results and look detail), `.medium` (168, saved looks in a list) and `.small` (64, the other versions on results and a picture's link back to its look), or any width. The bundle keeps the 300 x 356 shape. The mockups' iPad screens keep bundles 210 to 300 points wide, so the presets don't grow on iPad. Under 120 points a bundle is a thumbnail.
- **Thumbnails stay cheap.** Each sticker is made once per picture, size, scale and appearance and kept in the shared `StickerCache`. Drawn pieces are cached by kind and colours, so the same navy trousers in a hundred thumbnails is one sticker. Thumbnails never animate, and show the idea tag as an icon.
- **The idea piece** (LR-05b). A soft tag, "Not in your closet" with a tag icon, on a plate with a shadow below and no outline, sits across the lower part of the piece and stays inside the bundle. Thumbnails show only the tag icon on a small round plate. The tag stops growing at xxLarge text so it doesn't cover the bundle; the words are in the list underneath and in what VoiceOver reads at every size.
- **Entrance.** With `animatesEntrance`, the pieces settle in back to front, a little apart, from a steeper tilt. Under Reduce Motion they only fade in, with no tilt or movement (RD-07.4). Still images never animate.
- **VoiceOver** (RD-07.3). The bundle is one element: "Look: Cream blouse, Navy trousers, Tan loafers", using the look's name or a title the screen passes ("Simple", "Look 2"). A piece she doesn't own is read with "(not in your closet)". Each piece's kind and name is also custom content, which VoiceOver users reach with the More Content rotor. A tappable thumbnail is a button around the bundle, and VoiceOver reads it as one button with the same words.

## The piece list

`LookPieceList(content:showsSameAsSimple:onFindOne:)` is the text list under a bundle (RD-07), on a soft tint with no lines between rows. A piece she doesn't own says "Not in your closet", and with `onFindOne` gets a Find one button (spoken "Find one like Camel blazer"). With `showsSameAsSimple`, pieces shared with the Simple version say "Same as Simple". An idea's tag sits under its name so Find one keeps its room. At the accessibility text sizes the marks and the button move under the name too. Swapped and Added marks wait for 10b, which knows the other versions.

## Catalog

The component catalog (`-catalog`) has a "Look bundles" page, added by the app through `NookCatalogView(extraPages:)` since DesignSystem can't see garments. It shows a large bundle with a Replay button for the entrance, 2 to 6 pieces and a dress look at medium size, Something new with its list and Find one, a row of tappable thumbnails, and her sample photos (the white tee as a tile and the satin skirt as a sticker) mixed with drawn pieces. `scripts/check-release.sh` checks the page isn't in a Release build.

## Snapshot tests

`LookBundleSnapshotTests`: 2 to 6 pieces plus Something new, each large beside its thumbnail, on a phone (402 points) and an iPad (820 points); the catalog page on a phone in light, dark and AX5; and the photo look in light and dark. Seven images, about 8 MB.

`LookBundleTests` covers the content (body order, ideas, a missing garment, Same as Simple), what VoiceOver says, where the tag goes, and the sizes. The catalog UI test `testLookBundlesReadAsOneElement` checks in the running app that a bundle is one element naming its pieces, a thumbnail is one button, and Find one names its piece. They're drawn on the wall colour with `ImageRenderer`, like the other Features snapshots.

## Decisions for Jose

1. **The tag says "Not in your closet"**, as the amendment and `results-versions.html` do, rather than a new word like "New idea".
2. **No dividers between rows in the piece list.** The mockup's `.pcs` has them, but the design system keeps dividers between groups only.
3. **The presets don't grow on iPad**, matching the iPad mockups. A screen can pass any width.
4. **Pieces whose garment is gone are left out** of the bundle rather than drawn as a blank.
