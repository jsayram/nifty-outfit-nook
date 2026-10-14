# Home room

Phase 4, 14 October 2026. Home is the illustrated bedroom from `closet/prototypes/RoomDirectionMockups/screens/home.html`, built in SwiftUI for phones in portrait. Spec: amendment RD-01, RD-03, RD-09 (the suitcase and its plate) and RD-10.

## What's where

All of it is in `Packages/NookKit/Sources/Features/Home`.

| File | Holds |
|---|---|
| `HomeScreen.swift` | The navigation stack, the Profile button, the error banner, and `HomeRoomView`, which sizes the room to the screen |
| `HomeModel.swift` | Loads the sign name, the piece count and the hamper state from the stores |
| `HomeRoomContent.swift` | What the plates say, and the sign's fallback |
| `HomeDestination.swift` | The screens Home pushes |
| `HomeStubScreen.swift` | The stand-in for each of those until its phase builds it |
| `Room/RoomStage.swift` | Every rect from the mockup's 390 x 844 stage, and `RoomLayout`, which scales them |
| `Room/RoomControl.swift` | The ten things that do something: where each goes, its VoiceOver label and hint, reading order |
| `Room/RoomCanvas.swift` | Draws the room and puts a button over each control |
| `Room/RoomPlates.swift`, `Room/NameSignView.swift` | The live-text plates and the name on the sign |
| `Room/RoomArt.swift` | The drawings in `Resources/Room.xcassets` (see `art/room/README.md`) |

## Where the furniture goes

| Object | Opens | How |
|---|---|---|
| Wardrobe | Closet | Switches tab |
| Shelf ("Saved Looks" plate, and the frames under it) | Saved Looks | Switches tab |
| Laptop | Style Me | Push |
| Calendar | Style Me, asking for the occasion | Push (`choosingOccasion: true` for Phase 10a) |
| Suitcase | Suitcases | Push |
| Hamper | Laundry when tracking is on, "Laundry tracking" when it's off | Push |
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

Each control is one button. The label names the object and where it goes ("Wardrobe: Closet", "Top drawer: Help"), with the live values where there are some ("Suitcase: Source, Main closet, 17 pieces, Whole closet"). The hint says what tapping does. The reading order is the title, then the wardrobe, shelf, sign, calendar, laptop, the three drawers, the suitcase and the hamper. The drawings themselves are hidden.

## States

- **Loading.** The furniture works straight away. The piece count and the hamper line show as placeholders and the sign is empty until the stores answer.
- **Empty closet.** "Empty · Whole closet" on the suitcase, and the sign's fallback if there's no name.
- **A store fails.** The room still works. Plates show what's known, the sign shows its fallback, and a banner says "Part of your room didn't load. Everything still opens." with Try again.

## Left for later phases

- **5a:** the weather line under the title and its sheet, the windows for each weather and night (`RoomArt.windowRain` is the only one now), the hamper's full, empty and faded drawings, the laundry-off sheet, and Maya on the rug (`RoomStage.maya` and `RoomStage.mayaZs` mark the spots).
- **5b:** the large-text layout and sideways phone. Dark appearance already works from the art's dark versions and the colour tokens, but hasn't had its design pass.
- **10a:** the occasion on the calendar (`HomeRoomContent.occasion`), and opening Style Me on the Occasion sheet.
- **12a:** her saved looks in the shelf frames, which are empty for now.
- **13:** the remembered source (`HomeModel.source`, FR-67). Until the source picker exists, Home shows the main closet. The suitcase plate already knows how to show a suitcase source (green, or butter when empty).
- **14a:** "Name on your sign" in Profile, and reloading Home when it changes (RD-03.1).
