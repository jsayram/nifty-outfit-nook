# DesignSystem

Colour, type, spacing, corner and shadow tokens for Nifty Outfit Nook (Phase 2a), and the shared components built
on them (Phase 2b, see [Components](#components) below).

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
| `stickerEdge` | `#FFFFFF` | `#EEE7DE` | `.stk` drop shadows `#fff` (Phase 8b) |

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

## Components

Phase 2b. Every component follows the soft no-box rules: no outlines or borders, separation by space, tints and
shadows that fall only below. Each one is checked at the default text size, at AX5 (the largest), and in dark mode,
keeps tap targets at 44 points or more, and turns its animation into a plain change or a fade when Reduce Motion is
on. Text that a component shows comes in already localized, as a `String`; the few words the components own
("Try again", "Close", "Clear search", "Loading", "You’re offline.", "Retry") are in
`Resources/Localizable.xcstrings`.

| Component | Mockup source | Notes |
|---|---|---|
| `NookButton`, `.buttonStyle(.nook(_:size:))` | `.btn`, `.btn.ghost`, `.btn.small`, `.shuffle`, `.lnk` | Kinds: `primary` (solid accent, radius 18), `soft` (tint), `pill` (strong tint capsule), `text`. Sizes `regular` (50 pt) and `small` (44 pt). Pressed darkens and shrinks 3% (no shrink with Reduce Motion). Disabled fades to 45% and drops its shadow. `isLoading` swaps the icon for the dots, ignores taps, keeps its colour, and adds "Loading" as the VoiceOver value. At large sizes the icon moves above the title. |
| `NookAdaptiveStack` | `.grid4` at the largest size | Side by side normally, stacked at the accessibility sizes. For pairs of buttons. |
| `NookChip`, `NookChipBar` | `.chip`, `.chip.on`, filters (Lily's L9, L11) | Tint pill, selected is a solid accent pill. 36 pt pill inside a 44 pt target. `.isSelected` trait. The bar scrolls sideways, and wraps (`NookFlowLayout`) at the accessibility sizes so no chip is hidden off screen. The bar is a VoiceOver container named by its title. A chip can carry a colour `swatch` before its name (Phase 6, colour filters); the name is always there too. |
| `NookMenuChip` | Suitcase filter (L11) | A chip that opens a menu, with a chevron after the title. Shows the choice as a selected pill once something is chosen. Draws only its label in still images. |
| `NookSegmentedPicker` | `.seg` (Looks / Pictures), `.vers` (Simple · Dressed up · Something new) | Tint track, accent pill on the chosen option, which slides (moves without sliding under Reduce Motion). Options stack when their labels don't fit side by side. Each option is a button with `.isSelected`. |
| `NookRow`, `.buttonStyle(.nookRow)` | `.item` (Profile), `.erow` | Round tinted icon, title, subtitle, value, chevron. No separators. Pressed shows a tint. At the accessibility sizes the icon goes above the title and the value under it. One VoiceOver element. |
| `NookSection`, `NookSectionHeader`, `NookDivider` | `.sec-h`, `.grp`, `.note`, `.soft-div` | Headers are VoiceOver headings. The divider fades at both ends and goes between groups, never between rows. Secondary text in headers and notes must not sit on the bare floor (see Contrast). |
| `.nookCard(_:)` | `.tile`, `.sec`, `.r` | Tint (or strong tint, or butter) with radius 22 and the small shadow. Use sparingly. |
| `NookSearchField` | `.search` | Strong tint, radius 18, magnifier, 44 pt "Clear search" button. Wraps a long query or prompt at large sizes; Return still searches. The prompt is a wrapping text behind the field, since the system's own prompt stays on one line and truncated at AX5 (Phase 6). VoiceOver and XCUITest see a search field named by the prompt. |
| `.nookSheet(isPresented:…)`, `.nookSheet(item:…)`, `NookSheetContainer` | `.sheet-w`, `.wxsheet` | System sheet with grabber, radius 28 and the wall behind it. Serif title, optional line, Close button. Content scrolls. At the accessibility sizes it opens full height. |
| `NookEmptyState`, `NookLoadingState`, `NookErrorState` | `.empty` (Closet), `.state` (Your looks) | Centred, at most 360 pt wide, title is a heading. Error has a retry button ("Try again") and room for more actions. Loading reads as one VoiceOver element. |
| `NookLoadingIndicator` | new | Three soft dots. Fades only under Reduce Motion. |
| `NookBanner`, `NookOfflineBanner` | `.banner` (Your looks) | Butter or neutral, with an optional action that moves under the text at large sizes. |
| `NookToast`, `.nookToast(_:)` | `.toast` (Closet, Laundry, Profile, Swap) | Dark pill (light in dark mode) with an optional action like Undo. VoiceOver announces it. It stays 4 s, 6 s with an action, two and a half times longer while VoiceOver runs. Slides in, or fades with Reduce Motion. |
| `NookBadge` | `.sim`, `.pill`, `.dirty` | Small capsule label in four tones. Always words, never colour alone. |
| `NookSticker`, `StickerRenderer`, `StickerCache` | `.stk` in `results.html` and `garment.html` | Phase 8b. See [Stickers](#stickers). |
| `StickerBundleLayout`, `BundleRole`, `BundlePlacement` | `spots()` in `results.html` | Phase 9. The flat-lay arrangement of a look bundle: where 2 to 6 stickers lie by what they are, their tilt from a seed, and fitting the whole inside the 300 x 356 box. Pure arithmetic, tested for every mix of pieces. The view, `LookBundle`, is in Features since it draws garments; see `docs/look-bundles.md`. |
| `NookPhotoTile` | RD-07.2 | Phase 8b. A photo in a rounded tile with the soft shadow below, no outline, the same size a sticker would take. Corners are an eighth of the short side, 8 to 24 points. |

New colour pairings these components use are in `ContrastRequirement.all`: pressed soft buttons on `track`, the
toast's wall-coloured text on `textPrimary`, and the banner's action on the strong tint over butter.

### Stickers

Phase 8b. A garment picture with transparency becomes a sticker: the piece, a thick white edge that follows its
outline, and a soft shadow that falls below it. The mockups draw the edge with eight stacked CSS drop shadows; here
it's drawn once into a picture and cached.

- **Size.** A sticker takes exactly the size it's given. The garment is cropped to what isn't transparent and fitted
  inside, centred, or resting on the bottom (`.resting`, used on garment detail so shoes sit on the contact shadow).
  The shadow falls outside that size, like a CSS shadow, so it never moves a layout.
- **Edge.** 1.8% of the long side, 1.25 to 6 points: about 4.25 points on garment detail, 1.6 on a closet-sized piece.
  The shadow's offset and blur grow the same way, and it always falls further than it spreads, so nothing shows
  above the sticker. The edge is the `stickerEdge` token: white, and a warm off-white in dark so it doesn't glare
  next to garments dimmed for dark mode. The shadow is the `shadow` token, a little lighter, as in the mockups.
- **How the edge is drawn** (`StickerRenderer`). The garment's alpha is doubled (so a half-covered pixel of a thin
  strap counts as solid) and grown with a greyscale dilation, `vImageDilate_Planar8` with a round brush whose rim
  fades over one pixel. The garment's own anti-aliased edge carries through, so the paper's edge is smooth along
  slanted sides. Thin straps get the full edge and small holes fill in, as on a die-cut sticker. Core Graphics and
  Accelerate on the CPU, so it's the same on every machine and in the snapshot tests.
- **Cost and caching** (`StickerCache`). A detail-sized sticker at 3x took about 25 ms in a Debug build on the
  simulator (an earlier pure-Swift distance transform took 1.7 s in Debug). It's still made away from the main
  actor, once, and kept by its key: what it shows plus its size,
  scale, appearance and placement. Two views asking at once share one render. The least recently used go first
  past 48 MB, and everything goes on a memory warning. Nothing is written to disk. The root screen puts one cache in
  the environment (`\.stickerCache`).
- **Still images.** With `nookStaticRendering` on, a sticker is made on the spot, since `ImageRenderer` can't wait.

The catalog's "Stickers and photo tiles" page shows three sizes, the tile fallback in the same sizes, and thin parts.

### The catalog

A debug-only catalog shows every component and state on one page (plus pages other modules pass to `NookCatalogView(extraPages:)`, such as Features' look bundles), with switches for light, dark and text sizes up
to AX5. Launch a Debug build with `-catalog` (in Xcode: scheme, Run, Arguments). The code is in `Catalog/` and is
wrapped in `#if DEBUG`, so a Release build doesn't contain it. CI checks that with `scripts/check-release.sh`.

### Snapshot tests

`ComponentSnapshotTests` draws every catalog page in light, dark and AX5 on a 390 pt canvas, and five pages on an
820 pt (iPad) canvas, and compares them with the PNGs in `Tests/DesignSystemTests/__Snapshots__`. That's 47 images,
about 4 MB at 2x.

- **How they're drawn.** With SwiftUI's `ImageRenderer`, not the library's UIKit host. The UIKit host's
  `layer.render(in:)` drops SwiftUI blurs, so the soft shadows vanished, and it measured AX5 layouts at the default
  size and cut them off. `ImageRenderer` can't draw UIKit-backed views (text fields, scroll views) and shows a
  placeholder instead, so components check `nookStaticRendering` and draw plain SwiftUI that looks the same. The
  real text field and scroll views are checked by the UI tests and on the simulator.
- **Determinism.** Colour scheme, text size, locale and scale (2x) are set on the view, not taken from the device.
  The references were recorded on the iOS 26.5 simulator, which `scripts/simulator.sh` picks by default locally and
  on CI, and a test fails with a clear message on any other runtime. The comparison allows 0.5% of pixels to differ
  and each pixel to be 98% alike, which absorbs anti-aliasing differences between Macs but still catches a changed
  colour, shadow or line of text.
- **Recording.** A missing reference is recorded and the test fails once. To re-record everything after a deliberate
  change, run `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all scripts/test.sh`, look at every changed PNG in the diff, then
  run `scripts/test.sh` again. On CI a failure uploads the new images and diffs with the test results.
