# Home room

Phase 4, 14 October 2026. Home is the illustrated bedroom from `closet/prototypes/RoomDirectionMockups/screens/home.html`, built in SwiftUI for phones in portrait. Spec: amendment RD-01, RD-03, RD-09 (the suitcase and its plate) and RD-10.

Phase 5a, the same day, brought the room to life: the window follows the weather, the hamper shows the laundry, and Maya sleeps on the rug (RD-01.4, RD-11, RD-12). See [Weather, laundry and Maya](#weather-laundry-and-maya).

## What's where

All of it is in `Packages/NookKit/Sources/Features/Home`.

| File | Holds |
|---|---|
| `HomeScreen.swift` | The navigation stack, the Profile button, the error banner, and `HomeRoomView`, which sizes the room to the screen |
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
| Calendar | Style Me, asking for the occasion | Push (`choosingOccasion: true` for Phase 10a) |
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

The plates, the title and the name are live text in the design system's text styles. The plates are fixed-size shapes on the drawing, so their words shrink to fit, and in the room they stop growing at the largest standard text size (xxxLarge). At the accessibility sizes Phase 5b replaces the room with the banner and large rows (`home-ax.html`, RD-01.5). Until then the room at AX5 shows capped text, with nothing cut off or overflowing.

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

`home.html` has a weather line under the title ("58°F · Rain today") with a small detail sheet. The amendment doesn't keep it: LR-04 puts the weather on Style Me, as a **Weather** row with "Your looks are picked for today's weather." under it, and a sheet with Use today's weather, I'll be indoors and Ignore the weather. So Home's part is the window, and the row and sheet are built on Style Me's stand-in screen (`StyleMeStubScreen`) until Phase 10a builds the rest of Style Me around them. The choice is for one request: the screen starts on Use today's weather every time it opens (LR-04.2). When the weather can't be read the row says "Not available" with "The weather can't be read right now, so your looks won't use it.", and the sheet still works (LR-04.3).

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

## Left for later phases

- **5b:** the large-text layout and sideways phone. Dark appearance's design pass should look at the room at night too: in dark the wall is already night, so the night window and the glow fit; in light at night only the window and the lamp change. Dark appearance already works from the art's dark versions and the colour tokens, but hasn't had its design pass.
- **10a:** the occasion on the calendar (`HomeRoomContent.occasion`), and opening Style Me on the Occasion sheet.
- **12a:** her saved looks in the shelf frames, which are empty for now.
- **13:** the remembered source (`HomeModel.source`, FR-67). Until the source picker exists, Home shows the main closet. The suitcase plate already knows how to show a suitcase source (green, or butter when empty).
- **14a:** "Name on your sign" in Profile, and reloading Home when it changes (RD-03.1).
