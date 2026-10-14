# DesignSystem tokens

Colour, type, spacing, corner and shadow tokens for Nifty Outfit Nook (Phase 2a). Components come in Phase 2b.

The source is the room-direction mockups in the planning repo (`closet/prototypes/RoomDirectionMockups`):
`css/palette.css` (`html.palette-warm`, Lily's pick on 13 October 2026), `css/soft.css` (the soft no-box style),
`css/room.css` (shared sizes and fonts) and the screens' own styles. Where they differ, the warm palette wins over
the old pink and plum values in `room.css`. Requirements: PRD section 7.1, amendment RD-05 and LR-02, decision note
0001 item 15.

## Using them

```swift
Text("Your looks")
    .nookTextStyle(.display)
    .foregroundStyle(.nook.textPrimary)

Text("Work")
    .nookTextStyle(.chip)
    .foregroundStyle(.nook.onAccent)
    .padding(.horizontal, NookSpacing.medium)
    .frame(minHeight: NookSpacing.minimumTapTarget)
    .background(.nook.accent, in: Capsule())
    .softShadow(.drop, in: Capsule())
```

- Colours: `Color.nook.<token>`, or `.nook.<token>` where a style is expected. `Color(token:)` takes a `ColorToken`.
- Type: `.nookTextStyle(_:)` sets the font and letter spacing. `Font.nook.<role>` gives the font alone.
- Spacing and radii: `NookSpacing`, `NookRadius`. Draw rounded corners with `NookRadius.shape(_:)` so they're continuous.
- Shadows: `.softShadow(.drop, in: shape)` or `.dropLarge`.

There are no border or outline tokens. Cards, rows, tiles, chips and plates have no stroke. Things are separated by
space, the `tint` washes, the fading `softDivider` and shadows that fall only below. A control that needs a visible
edge for contrast gets it from its fill (RD-05).

## Colours

`Palette.swift` is the one source of truth. `Resources/Colors.xcassets` holds the same values as colour sets with
an Any and a Dark appearance. To change a colour, change both. `PaletteAssetCatalogTests` checks the catalog files
against `Palette.swift`, and checks that the compiled catalog resolves to the same values through `Color.nook` in
light and dark. It names the colour set that's wrong.

### Interface

| Token | Light | Dark | CSS source |
|---|---|---|---|
| `background` | `#F4EEE6` | `#211B16` | `--wall` |
| `backgroundLow` | `#EBE2D6` | `#1B1612` | `--wall-2` |
| `surface` | `#FFFDF9` | `#2E2620` | `--plate` |
| `tint` | `#FFFFFF` at 0.55 | `#FFF0E1` at 0.07 | `--soft-tint` (soft.css) |
| `tintStrong` | `#FFFFFF` at 0.82 | `#3A3028` at 0.94 | `--soft-tint-strong` (soft.css) |
| `textPrimary` | `#2A211B` | `#F4EEE6` | `--ink` |
| `textSecondary` | `#6B5E54` | `#C7B8AA` | `--ink-soft` |
| `accent` | `#4B3628` | `#DCC3A8` | `--plum`, espresso in palette-warm |
| `accentPressed` | `#35261B` | `#C4A98D` | `--plum-2` |
| `onAccent` | `#FFFFFF` | `#211B16` | `#fff` on `.chip.on` and `.btn` |
| `accentSoft` | `#EFE6DB` | `#3B3027` | `--plum-soft` |
| `chevron` | `#8A7B6E` | `#9C8C7E` | `--soft-chev`, darkened from `#9A8B7E` |
| `track` | `#E6DCCD` | `#4A3F36` | `--plate-line` (meter track) |
| `divider` | `#967D64` at 0.3 | `#E6D2BE` at 0.2 | `--soft-divider` colour |
| `shadow` | `#3C2A1C` at 0.26 | `#000000` at 0.55 | `--soft-drop` colour |
| `shadowLarge` | `#3C2A1C` at 0.32 | `#000000` at 0.6 | `--soft-drop-lg` colour |

### Status

The warm palette has no status colours, so these are new. They start from PRD 7.1's success and error values,
shifted warmer, and from the mockups' butter banner. They stay clearly apart from the espresso accent, and are never
the only signal: there's always text or an icon too (LR-02).

| Token | Light | Dark | Source |
|---|---|---|---|
| `success` | `#46613F` | `#B9CDA6` | PRD 7.1 success, warmed |
| `successSurface` | `#E5E9D6` | `#2C3424` | PRD 7.1 success surface, warmed |
| `warning` | `#7A5B14` | `#E6C98A` | banner icon `#8A6A12`, darkened for text |
| `warningSurface` | `#F5EACB` | `#433A22` | butter banner `#FCF0C6`, warmed |
| `error` | `#A3352B` | `#F2A596` | PRD 7.1 error, warmed (brick, not pink) |
| `errorSurface` | `#F7E2DA` | `#4A2924` | new |

### Room and art

The drawn room is recoloured into these for real (LR-02.3), instead of the mockups' preview filter. The art itself
is redrawn in a later phase; these are the values it uses.

| Token | Light | Dark | CSS source |
|---|---|---|---|
| `floor` | `#E5D7C5` | `#362C24` | `--floor` |
| `floorLow` | `#DACAB4` | `#30271F` | `--floor-2` |
| `floorLine` | `#C6B097` | `#1A1410` | `--floor-line` |
| `artSage` | `#C9CDB4` | `#858770` | `--sage` |
| `artSageDeep` | `#B6BB9E` | `#787B62` | `--sage-2` |
| `artSageLine` | `#959A7C` | `#62664D` | `--sage-line` |
| `artSand` | `#E3D3C6` | `#968B7B` | `--pink`, sand in palette-warm |
| `artStone` | `#DCD3CA` | `#918B7D` | `--lilac`, stone in palette-warm |
| `artButter` | `#EFE3C8` | `#9E967C` | `--butter` |
| `artButterLine` | `#CDB98F` | `#877A59` | `--butter-line` |
| `signPanel` | `#FFF7EA` | `#A8A391` | `name-sign.svg` panel |
| `signText` | `#4B3628` | `#3A2A1E` | `.sign .name` (`--plum`) |

### How dark appearance was derived

Lily only chose the light palette, so the dark values are ours. The aim: the same room at night, warm charcoal and
espresso, never grey-blue. A test checks that no dark value leans blue (red is at least blue in every token but the
black shadows).

- **Wall and floor.** The wall goes to a warm charcoal on the espresso hue, `#211B16` to `#1B1612`. It's darker than
  the mockups' dark wall (`#3A2A33`) because the PRD's dark background is a near-black warm charcoal (`#1C191B`), and
  a darker wall makes the plates and text stand out more. The floor is a step lighter than the wall (`#362C24`), as in
  the mockups' `dark.css`, so the room still reads as wall and floor. The floor line goes darker, not lighter.
- **Text.** Primary text is the light wall colour, `#F4EEE6`, so light and dark mirror each other. Secondary text is
  a warm taupe, `#C7B8AA`.
- **Accent.** Espresso on a dark wall would be about 1.5:1, so in dark the accent becomes a light latte, `#DCC3A8`,
  with dark text on it (`onAccent` `#211B16`). That's the same move as the PRD's dark plum (`#D9AFCB` with charcoal
  text). One token then works for selected chips, buttons, links and icons, and the selected chip stays a solid pill
  that stands out from the quiet ones (10:1 against the wall).
- **Tints and shadows.** White glass doesn't work on a dark wall, so `tint` is a faint warm cream wash (7%) and
  `tintStrong` a near-solid raised espresso, following `dark.css`. Shadows go to black at 55 to 60%, as in `dark.css`,
  because a brown shadow disappears on a brown wall.
- **Art.** Drawn art is dimmed, not inverted, so things keep their identity: each light value times 0.66 in red and
  green and 0.62 in blue, which reads as lamplight. `dark.css` dimmed art to 74% brightness with a filter, but our
  wall is darker, so the art comes down further too. The name sign keeps dark text on its dimmed panel, as the
  mockups do.
- **Status.** Light text on deep tinted surfaces, the usual dark-mode pattern, each checked for contrast.

### Contrast

`ContrastRequirement.all` lists every pairing the design relies on, and `ContrastTests` checks each one in light and
dark: 4.5:1 for text, 3:1 for large text, icons and control boundaries (PRD 7.1, LR-02.2). See-through tints are
blended onto the wall (both ends of its gradient) and onto the floor before measuring.

Changes from the CSS:

- **Chevron, light:** `--soft-chev` `#9A8B7E` was 2.9:1 on the wall and 2.6:1 on `--wall-2`, under the 3:1 needed
  for icons. It's now `#8A7B6E`: 3.6:1 and 3.2:1.
- **Secondary text on the bare floor:** `--ink-soft` on `--floor` is 4.4:1, just under 4.5:1. Rather than change
  Lily's ink colour, secondary text never sits straight on the floor. On the floor it goes on a `tint` (5.4:1), which
  is what the mockups already do with their plates.

Tightest pairs that pass: secondary text on `backgroundLow` (4.9:1 light), chevron on `backgroundLow` (3.2:1 light),
the warning note (5.3:1 light) and her name on the dimmed sign (5.4:1 dark).

`divider` is decorative and has no minimum. It's never the only edge of a control.

## Type

All text uses Dynamic Type text styles, so it grows with her text size setting. There are no fixed sizes. Both
fonts are Apple system fonts, so nothing is bundled and there's no licence to check: the rounded design
(SF Pro Rounded, the mockups' `ui-rounded`) for the interface, and the serif design (New York, the mockups'
`--font-display`) for titles and the name sign.

| Role | Text style | Design, weight | Mockup source |
|---|---|---|---|
| `display` | `.largeTitle` | serif, heavy, tracking -0.6 | `.title-display`, 33 px 800 |
| `title` | `.title2` | serif, heavy, tracking -0.3 | `.state h1`, 24 px 800 |
| `lookTitle` | `.title3` | serif, heavy, tracking -0.2 | `.look-title`, 20 px 800 |
| `nameSign` | `.title3` | serif, bold italic, tracking 0.2 | `.sign .name`, 21 px 700 italic |
| `headline` | `.headline` | rounded, bold | `.nav`, 17 px 700 |
| `body` | `.body` | rounded, regular | PRD 7.1: body starts at `.body` |
| `button` | `.callout` | rounded, bold | `.btn`, 16 px 700 |
| `label` | `.subheadline` | rounded, bold | `.erow b`, `.grid4 .btn`, 15 px 700 |
| `chip` | `.footnote` | rounded, semibold | `.chip`, 13 px 600 |
| `note` | `.footnote` | rounded, regular | `.ask`, `.req`, `.say`, 13 px |
| `caption` | `.caption` | rounded, semibold | `.tabbar`, `.mk`, 12 px 600 |
| `finePrint` | `.caption2` | rounded, medium | `.fine`, 11 px 500 |

At the default text size each style is within 2 points of the mockup size, which a test checks. The mockups' body
text is 14 to 15 px; the PRD's `.body` (17 pt) wins. The name sign sits on a fixed-size drawing, so the component that
draws it (Phase 4) has to let the name shrink to fit at large text sizes.

## Spacing, corners and shadows

`NookSpacing`: an 8 point rhythm with 4 point half steps (2, 4, 8, 12, 16, 20, 24, 32). Screen margin 16, group
padding 16, gap between groups 24, gap between chips 8, minimum tap target 44.

`NookRadius`, from `soft.css`:

| Token | Points | Source |
|---|---|---|
| `small` | 10 | `.sim` |
| `plateSlim` | 14 | `.tag.slim` |
| `buttonSmall` | 16 | `.btn.small`, `.grid4 .btn` |
| `button` | 18 | `.btn`, `.tag` |
| `group` | 22 | `.vers`, `.pcs`, `.erow` |
| `tile` | 24 | `.tile` |
| `sheet` | 28 | `.wxsheet`, large-text rows |
| chips and pills | `Capsule()` | `border-radius: 999px` |

`SoftShadow`, from palette-warm's `--soft-drop` and `--soft-drop-lg`:

| Token | CSS | Colour |
|---|---|---|
| `.drop` | `0 10px 16px -12px` | `shadow` |
| `.dropLarge` | `0 16px 22px -16px` | `shadowLarge` |

SwiftUI's `.shadow` has no spread, so it would put a halo on every side. `.softShadow(_:in:)` draws what the CSS
draws: the shape shrunk by the spread, moved down, blurred by half the CSS blur radius, and cut away under the shape so
a see-through tint on top stays clean. A test checks that both shadows start below the shape's top edge.

Contact shadows under garments (the radial ellipse in Closet) belong to the garment component in a later phase.
