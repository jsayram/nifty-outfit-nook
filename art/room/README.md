# Room art

The drawings for the Home bedroom. Phase 4, 14 October 2026.

## Where it comes from

`source/` holds the SVGs exactly as they are in the planning repo, `closet/prototypes/RoomDirectionMockups/art`. They were drawn for this project in October 2026, by Claude working for Jose to the style contract in that folder's `ART_DIRECTION.md`, from Jose's reference picture. No stock art, icon set or third-party illustration is in them, so there is no outside licence to track; they are covered by this repo's all-rights-reserved notice.

`source/wardrobe-rail.svg` is the one exception to "exactly as in the mockups": it's the four hanging garments on the Home wardrobe rail, exported from the mockups' `js/garments.js` (low detail, with hangers) and laid out as `screens/home.html` places them. The garments were drawn for this project too.

## How it gets into the app

```bash
scripts/room-art.py
```

The script writes one image set per drawing to `Packages/NookKit/Sources/Features/Resources/Room.xcassets`, each with a light SVG, a dark SVG, a single scale and "Preserves Vector Data" on. It also writes `palette-map.json`, which lists every source colour and what it became. Run it again whenever a source drawing changes, and commit the image sets with it.

What it changes:

- **Colours.** The mockups drew the room in the first pastel palette and only toned it down with a CSS filter for Lily's palette study. Here every colour is recoloured for real into her warm neutral palette (LR-02.3). Colours that are mockup palette values with a design token become exactly that token: sage, sage-2 and sage-line become `artSage`, `artSageDeep` and `artSageLine`; pink becomes `artSand`; lilac `artStone`; butter and butter-line `artButter` and `artButterLine`; cream `signPanel`; plum (the laptop screen) `accent`. Every other colour keeps its lightness while its colourfulness drops and its hue moves toward the warm neutrals: greens stay a little green (olive), yellows and woods soften to sand and oak, and pinks, purples and blues become warm stone. The numbers were fitted to the pairs Lily approved (room.css colour to palette-warm colour).
- **Dark.** The dark SVG is the light one in lamplight: red and green times 0.66, blue times 0.62, the same rule the dark art tokens use (`DesignSystem/README.md`).
- **Garments keep their colours**, because they stand for her real clothes. In dark they're dimmed to 92%, as the mockups' `dark.css` does.
- **`<use>` references are replaced by copies**, and comments are dropped, so the system SVG renderer only sees plain shapes.

`RoomArtTests` checks that every drawing loads in light and dark, that each dark SVG is its light SVG dimmed by the rule, that the token colours match `Palette.swift`, and that no colour skipped the map.

## Not here yet

Maya and her z's, the other windows (sun, cloudy, snow, night) and the hamper's full and faded states come in Phase 5a. Their sources are in the same mockup folder (`maya.svg` should be simplified first; it's 108 KB of fur).
