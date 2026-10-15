# Home room

Phase 4, 14 October 2026. Home is the illustrated bedroom from `closet/prototypes/RoomDirectionMockups/screens/home.html`, built in SwiftUI for phones in portrait. Spec: amendment RD-01, RD-03, RD-09 (the suitcase and its plate) and RD-10.

Phase 5a, the same day, brought the room to life: the window follows the weather, the hamper shows the laundry, and Maya sleeps on the rug (RD-01.4, RD-11, RD-12). See [Weather, laundry and Maya](#weather-laundry-and-maya).

Phase 5b, also the same day, added the two other layouts, large text and a phone held sideways, and the design pass on dark appearance. See [Large text, sideways and dark](#large-text-sideways-and-dark).

## What's where

All of it is in `Packages/NookKit/Sources/Features/Home`.

| File | Holds |
|---|---|
| `HomeScreen.swift` | The navigation stack, the Profile button, the error banner, the choice of layout, and `HomeRoomView`, which sizes the room to the screen |
| `HomeLayout.swift` | Which layout shows (room, large text, sideways), and the words rows and tiles say to VoiceOver |
| `LargeText/HomeLargeTextView.swift`, `LargeText/HomeBanner.swift` | The large-text layout: the banner and the large rows |
| `Sideways/SidewaysStage.swift`, `Sideways/HomeSidewaysView.swift` | The sideways layout: the closer scene's rects, its scaling, and the tiles beside it |
| `HomeModel.swift` | Loads the sign name, the piece count and the hamper state from the stores, and the weather from the weather service; turns laundry tracking on |
| `HomeRoomContent.swift` | What the plates say, and the sign's fallback |
| `HomeDestination.swift` | The screens Home pushes |
| `HomeStubScreen.swift` | The stand-in for each of those until its phase builds it |
| `LaundryTrackingSheet.swift` | The short sheet the hamper opens while laundry tracking is off |
| `Room/RoomStage.swift` | Every rect from the mockup's 390 x 844 stage, and `RoomLayout`, which scales them |
| `Room/RoomControl.swift` | The ten things that do something: where each goes, its VoiceOver label and hint, reading order |
| `Room/RoomCanvas.swift` | Draws the room and puts a button over each control |
| `Room/RoomPlates.swift`, `Room/NameSignView.swift` | The live-text plates and the name on the sign |
| `Room/RoomArt.swift` | The drawings in `Resources/Room.xcassets` (see `art/room/README.md`) |
| `Room/RoomWindow.swift` | Which window the weather gives, and the lamp's glow at night |
| `Room/HamperLook.swift` | Which hamper drawing the laundry gives |
| `Room/MayaView.swift` | Maya's z's and how they drift |

Style Me's Weather row and its sheet live in `Features/StyleMe` (see below).

## Where the furniture goes

| Object | Opens | How |
|---|---|---|
| Wardrobe | Closet | Switches tab |
| Shelf ("Saved Looks" plate, and the frames under it) | Saved Looks | Switches tab |
| Laptop | Style Me | Push |
| Calendar | Style Me, on the Occasion sheet | Push (`choosingOccasion: true`) |
| Suitcase | Suitcases | Push |
| Hamper | Laundry when tracking is on (or before the closet has loaded); the laundry tracking sheet when it's off | Push, or a sheet |
| Top, middle and bottom drawers | Help, Send feedback, Privacy and terms | Push |
| Name sign, and the top-right button | Profile | Push |

Closet and Saved Looks are tabs in the mockup (the wardrobe link lands on the Closet tab), so the room switches tabs for them rather than pushing a second copy.

## Sizing

The room keeps the mockup's proportions and scales to fit between the navigation bar and the tab bar, centred, with the wall and floor running to both edges. The stage from the title (y 40) to just below the hamper (y 740) must show; the floor, the rug and the bed carry on under the tab bar.

It never shrinks below the scale that gives each desk drawer a 44 pt target (the drawers are 46 stage units apart, so 0.957). On an iPhone 17 or Pro Max the whole room fits. On an iPhone SE it doesn't at that scale, so the room scrolls by about 160 pt instead of shrinking the drawers. Every tap area is grown to at least 44 x 44 around its object.

Measured bar heights on the iOS 26.5 simulator, used by the tests: 116 pt at the top and 83 pt at the bottom on iPhone 17 and 17 Pro Max, 74 and 83 on iPhone SE (3rd generation).

## Text

The plates, the title and the name are live text in the design system's text styles. The plates are fixed-size shapes on the drawing, so their words shrink to fit, and in the room they stop growing at the largest standard text size (xxxLarge). The room never shows past that: at the accessibility sizes Home switches to the large-text layout, where nothing is capped (see below).

The sign shows her name from the profile. A long name wraps onto two lines and then shrinks. An empty name shows "Hello" (RD-03.2), and VoiceOver says "Name sign, no name yet". While the profile loads the panel stays empty, so the fallback never flashes up before her name.

## VoiceOver

Each control is one button. The label names the object and where it goes ("Wardrobe: Closet", "Top drawer: Help"), with the live values where there are some ("Suitcase: Source, Main closet, 17 pieces, Whole closet"). The hint says what tapping does. The reading order is the title, then the window, the wardrobe, shelf, sign, calendar, laptop, the three drawers, the suitcase and the hamper. The window isn't a control, but it's read as an image with the weather it shows ("Window: Rain"), so the weather in the room isn't only visual; the plain window is skipped. The other drawings, Maya and her z's included, are hidden.

## States

- **Loading.** The furniture works straight away. The piece count and the hamper line show as placeholders and the sign is empty until the stores answer.
- **Empty closet.** "Empty · Whole closet" on the suitcase, and the sign's fallback if there's no name.
- **A store fails.** The room still works. Plates show what's known, the sign shows its fallback, and a banner says "Part of your room didn't load. Everything still opens." with Try again.

## Weather, laundry and Maya

Phase 5a.

### The window

`RoomWindow` turns the weather service's answer into one of six drawings: sun, cloudy, rain, snow, night, and plain. Night wins over the condition, as in the mockups. The plain window (a pale sky, no sun or clouds) shows while the weather loads and when it can't be read, so the window never guesses. Weather that can't be read isn't a failure: the room shows no banner and everything else works (LR-04.3). The window cross-fades when the weather arrives.

At night the desk lamp glows (`.glow` in the mockups). In dark appearance it always glows a little, as the mockups' `dark.css` does.

The weather loads alongside the stores, not after them, because from Phase 29 it comes from WeatherKit and can be slow.

### The weather line: on Style Me, not on Home

`home.html` has a weather line under the title ("58°F · Rain today") with a small detail sheet. The amendment doesn't keep it: LR-04 puts the weather on Style Me, as a **Weather** row with "Your looks are picked for today's weather." under it, and a sheet with Use today's weather, I'll be indoors and Ignore the weather. So Home's part is the window, and the row and sheet are on Style Me (`docs/style-me.md`). The choice is for one request: the screen starts on Use today's weather every time it opens (LR-04.2). When the weather can't be read the row says "Not available" with "The weather can't be read right now, so your looks won't use it.", and the sheet still works (LR-04.3).

The temperature is in her locale's unit ("58°" in the US, "15°" in the UK).

### The hamper

`HamperLook` picks the drawing from the hamper state (RD-11):

| State | Drawing | Plate |
|---|---|---|
| Tracking off | the empty hamper, faded | "Laundry · Off", quiet, no shadow |
| On, nothing dirty | the empty hamper | "Laundry · All clean" |
| On, 1 to 5 dirty | a low heap just above the rim | "Laundry · 2 to wash" |
| On, 6 or more dirty | a taller heap with a sleeve over the rim | "Laundry · 8 to wash" |
| Loading | the empty hamper, not faded | placeholder |

While tracking is off, tapping the hamper opens a short sheet (`laundry-off.html`, as a sheet per RD-11): what tracking does, that every piece counts while it's off, and that her old "in the wash" marks are kept, with **Turn on**, **Not now** and "You can change this in Profile". Turn on saves the setting, closes the sheet, reloads the room so the hamper fills straight away (RD-11.4), and shows a "Laundry tracking is on." toast. If saving fails the sheet stays open and says so.

### Maya

Maya, Lily's apricot toy poodle, sleeps curled on the rug (RD-12), drawn from Jose's illustration in her own colours. She's decoration only: hidden from VoiceOver, and taps go through her. Her three z's float up a few points and fade a little, one after another, on a seven-second cycle. With Reduce Motion on they stay still in their resting places and still show. They're drawn in the accent colour so they read on the rug in dark appearance too.

### Forcing each state

The fixture launch argument takes `weather=` and `laundry=` options after the set (see the README):

```
-fixtures demo:weather=snow:laundry=full
-fixtures demo:weather=night
-fixtures empty:weather=unavailable:laundry=off
```

Weather: `sun`, `cloudy`, `rain` (the default), `snow`, `night`, `unavailable`. Laundry: `off`, `clean`, `some` (2 dirty), `full` (8 dirty). Without them each set keeps its own weather and laundry; the demo has tracking off with two pieces still marked dirty.

### Tests

`HomeLifeTests` covers the window and hamper mapping, the z's drift, and the model (weather, unreadable weather, each laundry state, Turn on). `WeatherRowContentTests` covers what the row and sheet say. `HomeSnapshotTests` has one image of all six windows and one of all four hampers, each in light and dark, plus a snowy night with a full hamper. The UI tests check the hamper sheet's Not now and Turn on, and the window and Weather row with each sheet choice.

## Large text, sideways and dark

Phase 5b. `HomeLayout` picks one of three layouts from the text size and the vertical size class:

| Layout | When | Mockup |
|---|---|---|
| Room | Upright phone, and iPad, at the standard text sizes | `home.html` |
| Large text | Any accessibility text size (AX1 to AX5), in any orientation | `home-ax.html` |
| Sideways | A phone held sideways (compact height) at the standard sizes | `home-landscape.html` |

Only the view inside `HomeScreen` changes, so turning the phone or changing the text size keeps the model, a pushed screen and an open sheet. Every control keeps the same accessibility identifier (`home.suitcase` and so on) in every layout.

### Large text

The room shrinks to a banner 186 points tall, drawn at the mockup's sizes: the right edge of the wardrobe with two pieces on its rail (opens Closet), her name sign in the middle of the wall (opens Profile), and the window on the right, still following the weather. Under it, every other control is a large row in the room's order: Source (with the piece count and scope as a pill, green for a suitcase, butter for an empty one), Occasion on butter, the Style Me button, Laundry, and then "In the desk drawers" with Help, Send feedback, and Privacy and terms. Text uses the normal text styles with no cap, wraps instead of truncating, and the page scrolls. At AX4 and AX5 each row's icon moves above its words, so a word like "Occasion" keeps the full width and never breaks. On a wide screen the page stays at most 640 points wide and centres.

Two things in the mockup aren't here:

- **The weather plate on the banner.** LR-04 moved the weather to Style Me, as on the upright room; the window still says the weather to VoiceOver.
- **A shelf row.** The mockup has none either. Saved Looks is the tab right under the rows.

Rows read as they look ("Source: Main closet, 17 pieces, Whole closet", "Laundry: Off"), so VoiceOver and Voice Control use the words on screen (`RoomControl.rowLabel(for:)`). Hints are the room's.

### Sideways

The mockups have a sideways phone screen, so Home follows it rather than inventing one. Squashing the upright room into a 402-point-tall screen would need about 40% scale and drawers far below 44 points. Instead:

- **The scene.** On the left, the mockup's closer view of the room (`SidewaysStage`, 430 x 390 units, the upright drawings at 0.72): wardrobe, window, sign, calendar, desk, suitcase, hamper, the rug and Maya. It scales to the height between the top of the screen and the tab bar, keeping its proportions, and gives way in width so the controls column keeps at least 340 points. On iPhone 17 that's a scale of 0.91 (62 points of safe area each side, 64 for the tab bar, measured on iOS 26.5). There's no shelf and no bed.
- **The controls.** Beside it, the same controls as soft tiles in the room's order: Source and Occasion side by side (stacked above the Large text size), Style Me, Laundry, then Help, Feedback and Privacy as small soft buttons. The navigation bar would take a third of the height, so it's hidden on Home and the title and the Profile button sit at the top of the column. Pushed screens keep their bar. The column scrolls above the tab bar if the text is too big to fit.
- **Who does what.** The drawings still open what they open upright, for a quick tap, but they're hidden from VoiceOver and the sideways drawers are smaller than 44 points. The tiles are the real controls: full-size targets, read once, with the words on screen. "Feedback" and "Privacy" are read as "Send feedback" and "Privacy and terms", and Voice Control answers to both names.

### Dark

The dark room already came from the art's dark versions and the colour tokens. Checking every element in dark (plates, sign, Maya, windows, hamper, the sheets) found two things to fix:

- **The faded hamper glowed.** With tracking off, the faded hamper's dark version was the pale light one in lamplight, which made it the brightest thing on the floor. It now follows the mockups' darker "off" filter and sits greyer and dimmer than the lit hamper (`art/room/README.md`).
- **The lamp at night.** In dark the lamp always glows a little; at night it now glows fully, as it does in light, and the glow fades to nothing at its edge at any size instead of being cut off in a circle.

Everything else held up: the plates use the strong tint with light text, the sign keeps dark text on its dimmed panel, Maya's z's are in the latte accent and show on the rug, the windows keep their faint sky, and the laundry sheet and the error banner use the dark tokens.

### Tests

`HomeLayoutTests` checks which layout each text size and size class gets, the row labels, the banner's rail, and that the sideways scene fits above the tab bar and keeps every control inside it. `HomeSnapshotTests.darkRoom` is the dark room on iPhone 17. `HomeLayoutSnapshotTests` draws the large-text page at AX3 (light) and AX5 (dark, a snowy night in a suitcase), and the sideways layout at 874 x 402 in light and in dark at night. `HomeVariantTests` (UI) launches at AX5 (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`) and opens every Home action from its row, the banner, the Profile button and the tabs, then turns the phone sideways, checks every control is there, opens Help and turns back upright with Help still open.

## Left for later phases

- **13:** the occasion on the calendar (`HomeRoomContent.occasion`) and under "Occasion" on the large-text row and the sideways tile, with the remembered source. Phase 10a opens Style Me on the Occasion sheet; remembering her last occasion waits for remembered request defaults (`docs/style-me.md`).
- **12a:** her saved looks in the shelf frames, which are empty for now.
- **13:** the remembered source (`HomeModel.source`, FR-67). Until the source picker exists, Home shows the main closet. The suitcase plate already knows how to show a suitcase source (green, or butter when empty).
- **14a:** "Name on your sign" in Profile, and reloading Home when it changes (RD-03.1).
- **15a:** iPad's wide room (RD-01.6). Until then iPad shows the upright room, and the large-text layout at the accessibility sizes.
