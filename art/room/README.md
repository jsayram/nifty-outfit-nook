# Room art

The drawings for the Home bedroom. Phase 4, 14 October 2026.

## Where it comes from

`source/` holds the SVGs exactly as they are in the planning repo, `closet/prototypes/RoomDirectionMockups/art`. They were drawn for this project in October 2026, by Claude working for Jose to the style contract in that folder's `ART_DIRECTION.md`, from Jose's reference picture. No stock art, icon set or third-party illustration is in them, so there is no outside licence to track; they are covered by this repo's all-rights-reserved notice.

Three files are exceptions to "exactly as in the mockups":

- `source/wardrobe-rail.svg` is the four hanging garments on the Home wardrobe rail, exported from the mockups' `js/garments.js` (low detail, with hangers) and laid out as `screens/home.html` places them. The garments were drawn for this project too.
- `source/window-plain.svg` (Phase 5a) is `window-sun.svg` without the sun and clouds and with a paler sky. The room shows it while the weather loads or when it can't be read, so the window never claims a weather it doesn't know.
- `source/home-hamper-full.svg` (Phase 5a) is `home-hamper-dirty.svg` with a taller heap (a sage cardigan and a sand tee behind the two pieces already there) and a black sleeve hanging over the rim. Its viewBox starts 14 units higher, so the room draws it 14 units higher and the basket lands where the other hampers' does.

Phase 6 added Closet's small drawings from the same folder: `closet-armoire.svg` (the open armoire in Closet's header), `closet-suitcase.svg`, `closet-basket.svg` and `closet-basket-empty.svg` (the Suitcases and Laundry tiles), and `closet-empty-hangers.svg` (over the empty closet's message). One more is exported rather than copied:

- `source/closet-armoire-clothes.svg` is the clothes inside that armoire, exported from the mockups' `js/garments.js` (low detail, hangers on the hanging pieces) and laid out as `screens/closet.html` places them, in the armoire's own coordinates so the app draws it over the armoire at the same size. Each pair of shoes is placed twice with one shoe hidden each time, as the mockup does, and each copy has its own clip path IDs. It's a garment drawing, so it keeps its colours like the wardrobe rail.

Phase 13 added Suitcases and Laundry:

- **Copied as they are** from the mockups: the entry hall behind the favourites (`travel-hall-door.svg`, `travel-hall-hooks.svg`, `travel-hall-peg.svg`, `travel-hall-mirror.svg`, `travel-hall-console.svg`, `travel-hall-runner.svg`) and Laundry's corner (`travel-laundry-shelf.svg`, `travel-washer.svg`, `plant-floor.svg`). The corner's hamper is Home's, so its states match the room. The camel trench the mockup hangs on the hooks comes from `js/garments.js` and isn't exported.
- **The five suitcase pictures.** `source/suitcase-rolling.svg` is the mockups' `travel-suitcase-pink.svg` with nothing changed but its name. `suitcase-weekender.svg`, `suitcase-duffel.svg`, `suitcase-backpack.svg` and `suitcase-tote.svg` were drawn for this project in Phase 13, in the spinner's style: the same 104 x 182 box, line weights, contact shadow and luggage-tag strap, and the same plain face at y 30 to 124, where the hall's tags and Home's plates sit. They're drawn in mockup pastels (tan, sage, butter, blue) and the script warms them like everything else, so they come out oak, sage, butter and stone beside the sand rolling case.

Phase 14b added the desk's drawers as a small chest, copied as they are: `acct-drawers-help.svg`, `acct-drawers-feedback.svg` and `acct-drawers-privacy.svg`, one with each drawer pulled open, for the headers of Help, Send feedback and Privacy and terms.

`source/maya.svg` is Maya as the mockups draw her, from Jose's own illustration. It's heavy (about 1,300 small shapes of fur), but it's drawn once into the asset cache and only her z's move, so it stays as it is.

## How it gets into the app

```bash
scripts/room-art.py
```

The script writes one image set per drawing to `Packages/NookKit/Sources/Features/Resources/Room.xcassets`, each with a light SVG, a dark SVG, a single scale and "Preserves Vector Data" on. It also writes `palette-map.json`, which lists every source colour and what it became. Run it again whenever a source drawing changes, and commit the image sets with it.

What it changes:

- **Colours.** The mockups drew the room in the first pastel palette and only toned it down with a CSS filter for Lily's palette study. Here every colour is recoloured for real into her warm neutral palette (LR-02.3). Colours that are mockup palette values with a design token become exactly that token: sage, sage-2 and sage-line become `artSage`, `artSageDeep` and `artSageLine`; pink becomes `artSand`; lilac `artStone`; butter and butter-line `artButter` and `artButterLine`; cream `signPanel`; plum (the laptop screen) `accent`. Every other colour keeps its lightness while its colourfulness drops and its hue moves toward the warm neutrals: greens stay a little green (olive), yellows and woods soften to sand and oak, and pinks, purples and blues become warm stone. The numbers were fitted to the pairs Lily approved (room.css colour to palette-warm colour).
- **Dark.** The dark SVG is the light one in lamplight: red and green times 0.66, blue times 0.62, the same rule the dark art tokens use (`DesignSystem/README.md`).
- **Windows keep a little sky.** In the six window drawings, blues (the sky, the rain, the night) keep their hue with 40% of their colourfulness instead of turning to warm stone, so sun, cloud, rain, snow and night still read at a glance. Everything else in a window is warmed as usual. `palette-map.json` lists these as `sky`.
- **Garments keep their colours** (the wardrobe rail and the Closet armoire's clothes), because they stand for her real clothes. In dark they're dimmed to 92%, as the mockups' `dark.css` does.
- **Maya keeps her apricot colours**, because she's a real dog. In dark she gets the same lamplight as the room (red and green times 0.66, blue times 0.62), so she sits in it rather than glowing.
- **The faded hamper is made, not drawn.** `home-hamper-faded` is `home-hamper` with the mockup's `saturate(.4) brightness(1.1) contrast(.8)` filter baked into each colour, for when laundry tracking is off. `palette-map.json` lists these as `faded`. Its dark version doesn't follow the lamplight rule (Phase 5b): lamplight on the pale light colours made it the brightest thing on the dark floor, the opposite of quiet. It follows the mockups' darker "off" filter instead (`brightness(.6) saturate(.4) contrast(.85)`, where the rest of the art gets `.74`): greyed, put in lamplight, then a further 0.81 dimmer than the lit hamper. `palette-map.json` lists these as `fadedDark`.
- **`<use>` references are replaced by copies**, and comments are dropped, so the system SVG renderer only sees plain shapes.

`RoomArtTests` checks that every drawing loads in light and dark, that each dark SVG is its light SVG dimmed by the rule (the faded hamper instead stays darker and greyer than the lit one), that the token colours match `Palette.swift`, that no colour skipped the map, that Maya keeps her source colours, and that the faded hamper is the empty one with the same shapes in greyer colours.

Maya's z's aren't in the catalog. They're three strokes drawn in SwiftUI (`MayaView.swift`, copied from the mockups' `maya-zzz.svg`) in the accent colour, so they show on the rug in dark appearance and each can drift on its own.
