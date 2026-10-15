# iPad

Phase 15a, 15 October 2026. iPad layouts for Home and Closet, the tab bar at the bottom, and windows of any size. Spec: amendment RD-01.6 (the wide room with bottom tabs in both orientations; rotating or resizing loses nothing and starts no request), the mockup README's decision 12 (use the space, never a phone layout centred in a tablet frame), PRD §7.2 (no state loss on resize, keyboard and pointer). Visual references: `ipad-home.html` and `css/home-wide.css` (sideways), the room in `ipad-home-portrait.html` (upright), and `ipad-closet.html`, in `closet/prototypes/RoomDirectionMockups`.

Style Me's results and Saved Looks get their iPad layouts in 15b. Until then they show their phone pages at full width, as before.

## What's where

| File | Holds |
|---|---|
| `Features/Shared/WindowLayout.swift` | Every layout choice that depends on the window, in one place: which room a window gets, Closet's three layouts, and Closet's column widths |
| `Features/Shared/RootTabView.swift` | The tab bar at the bottom (see below) |
| `Features/Home/Room/RoomPlan.swift` | The three arrangements of the room: the phone's, the upright iPad's (`tall`) and the sideways iPad's (`wide`) |
| `Features/Home/Room/RoomStage.swift` | The phone room's rects, and `RoomLayout`, which scales a plan to a window |
| `Features/Closet/ClosetScreen.swift` | The layouts, `ClosetColumns`, the piece beside the grid, and keeping it across a change of layout |
| `Features/Closet/ClosetPage.swift` | The page as a whole, or split into the sidebar and the grid column |

## Decided by the window, not the device

Every choice reads the window: its width and height, its width class and the text size. Nothing checks whether the device is an iPad. An iPad app in a narrow Split View, Slide Over or Stage Manager window gets the phone layouts, and the iPhone never sees the iPad ones, because a phone's width class is always compact.

| Window | Home | Closet |
|---|---|---|
| Compact width (iPhone; a third or a half of an 11-inch iPad) | The phone room, or the sideways or large-text layout | The phone page |
| Regular, wider than tall (iPad sideways) | The wide room | Sidebar, grid and the piece beside them, from 1,080 points |
| Regular, taller than wide (iPad upright, 11-inch two thirds) | The tall room | The page with the piece beside it, from 760 points; the phone page below that (iPad mini upright, 744) |
| Any accessibility text size | The large-text page (640 points at most, centred) | The phone page, which wraps and folds its filters for those sizes |

A room is only used when every control keeps a 44-point target without scrolling (`RoomLayout.fitsWithFullTargets`). A regular window too short or narrow for its room tries the other one, then the phone room, which may scroll.

Measured on the iOS 26.5 simulator:

- iPad Pro 11-inch: 834 x 1210. The bars are 86 points at the top and 77 for the bottom tab bar, in both orientations. The wide room's scale sideways is 0.93; the tall room's upright is 1.33.
- Windows dragged to about two thirds, a half and a third of the 11-inch screen held sideways came out at 795, 618 and 416 points wide. 795 was regular width (tall room, page with the piece beside it); 618 and 416 were compact (phone layouts). Windows can't get narrower than 375 points there.

`WindowLayoutTests`, `RoomPlanTests` and the snapshot tests hold these to the numbers above.

## The tab bar at the bottom

RD-01.6 asks for the tabs at the bottom on iPad. iPadOS 26 puts a `TabView`'s bar at the top of a regular-width window, as a floating bar in the navigation area. `.tabViewStyle(.tabBarOnly)` only stops it turning into a sidebar; it stays at the top (checked on the iOS 26.5 simulator). `.sidebarAdaptable` would be a sidebar, which RD-01.6 rules out for Home.

The tab view draws its bottom bar whenever its own width class is compact. So `RootTabs` gives the tab view `.environment(\.horizontalSizeClass, .compact)`, and gives each tab's content the window's real class back. The result is the same Liquid Glass bar as on iPhone, at the bottom, with the system's own behaviour (selection, VoiceOver, the tab bar's accessibility, keyboard focus). The screens inside still see the real width class, so the iPad layouts work. This uses only public SwiftUI and doesn't touch UIKit. It's the closest supported match to RD-01.6 we found; if a later iPadOS changes how the tab view reads its width class, the bar goes back to the top and nothing else breaks.

## The wide and tall rooms

`RoomPlan` holds every rect of one arrangement in stage units, and `RoomCanvas` draws whichever plan its layout carries, so the art, the plates and the tap areas stay together. The phone plan is `RoomStage` as before.

The iPad plans move whole pieces of furniture, never parts of one: the wardrobe with its rail, flats and plate, the shelf with its frames and plate, the desk with its laptop, lamp, chair and drawers, the suitcase with its two plates, and so on. Each group moves to a new top-left corner and grows around it, as the mockups' CSS does with `transform: scale(...)`. The numbers are copied from the mockups:

- **Wide** (`home-wide.css` at 1,194 x 834): wardrobe at 7% of the width (1.2x), window at 35% (1.3x), suitcase at 30% (1.2x), desk at 58% less 30 (1.2x) with the calendar above it, the shelf and the sign at 74% (1.3x), the hamper at 10% (1.1x), a wider rug, and the bed in the corner.
- **Tall** (the room in `ipad-home-portrait.html`, 594 wide): the phone's arrangement spread across a wider wall at about 1.15x. Two changes from the mockup: the window sits 32 units lower so the app's longer title ("Nifty Outfit Nook", where the mockup says "Home") doesn't run into it, and the suitcase sits 10 units higher so its tap area doesn't overlap the hamper's.

No new art was needed. The room scales to fit between the bars and sits in the middle of any spare height. The wall, the floor and the bed run to the window's edges.

The plates keep their text styles, so on iPad they're roomier rather than bigger. The large-text and sideways layouts are unchanged; the large-text page already stops at 640 points and centres.

## Closet

`ipad-closet.html` has an app-wide sidebar with Home, Closet and Saved Looks in it. With the tabs at the bottom (RD-01.6) that sidebar would repeat the tab bar, so Closet's sidebar holds what's Closet's own instead:

- **Sideways (from 1,080 points):** the sidebar has the wall with the armoire and the count, "Continue where you left off?", search, every filter chip wrapped onto as many lines as it needs (so none hide off the edge of a narrow column), Suitcases and Laundry one above the other, and Recently deleted. The grid fills the middle. The piece she picks shows on the right.
- **Upright (from 760 points):** the phone page on the left, with the piece beside it, as the upright mockup has it.

The sidebar is about a quarter of the window (280 to 340 points) and the detail about a third (340 to 420). The grid always keeps room for three pieces across.

**The piece beside the grid.** Tapping a piece shows it on the right instead of pushing it: the same garment detail, with Edit on the page (there's no bar of its own there) and everything else as on a phone. The piece stands on a soft tint in the grid and VoiceOver reads it as selected; its hint says "Shows the piece beside your closet." Before she picks one, the right side says "Pick a piece". Every other screen (Suitcases, Laundry, Edit, Style Me, a suitcase) still opens over the whole width, and Back returns to the same piece.

**Keeping what's open.** Turning the iPad or resizing the window keeps the piece: when the layout changes to the phone page, the piece beside the grid is pushed, and when it widens again a pushed piece moves back beside the grid. The search and the filters live in the model, so they survive too. The grid's scroll position goes back to the top when the columns change.

This is two columns of the screen's own, not a `NavigationSplitView`. Closet's navigation stack is shared with Home (the suitcase and hamper open Suitcases and Laundry in it), and a split view inside a tab whose width class we override would bring its own column rules; the plain columns keep one stack and one set of rules, and they're drawn by the snapshot tests exactly as the screen draws them (`ClosetColumns`).

## Pointer and keyboard

Room controls and pieces in the grid show the system's pointer highlight (`.hoverEffect(.highlight)`). Everything else is standard buttons, fields and the system tab bar, which take the keyboard and pointer as they do anywhere. No keyboard shortcuts are added yet.

## Tests

- `WindowLayoutTests`: Closet's layout for each measured width, compact and accessibility sizes, the column widths and that the grid keeps three pieces across.
- `RoomPlanTests`: the phone plan is unchanged; each iPad window gets the room for its shape without scrolling; every control is 44 points or more, between the bars and not overlapping its neighbours on six iPad windows and two Split View sizes; every plate stays on its furniture; the title is clear of the wall.
- `HomeIPadSnapshotTests`: the tall and wide rooms on the 11- and 13-inch iPads, the wide room in dark, a compact third-width window, and the large-text page at AX5 on an iPad.
- `ClosetIPadSnapshotTests`: the sidebar layout on the 11-inch and (in dark) the 13-inch held sideways, the page with the piece beside it on both upright, nothing picked yet, a compact third-width window and AX3 on an iPad.
- `IPadTests` (UI, iPad only): the tab bar at the bottom in both orientations, the tall and wide rooms and their furniture, turning with Style Me open (nothing sent), the Closet sidebar with a filter, search, a piece beside the grid and Edit, turning upright with the piece kept, and a window dragged to a third of the screen falling back to the phone layouts and widening back with the piece moved beside the grid.

iPad snapshots are drawn at 1x: a 2x picture of a 13-inch window is several megabytes, and 1x still catches a moved drawing or a changed plate.

### Running the iPad UI tests

Every `IPadTests` test skips itself on an iPhone, so the phone runs aren't slower. On an iPad simulator:

```sh
NOOK_SIM_FAMILY=iPad scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests
```

They take about three minutes locally. CI runs them in the `ui-home-and-results` part after its phone tests, on the iPad Pro 11-inch (M5) simulator. On the first run that step took 12 minutes (6 of them tests, the rest the iPad simulator's boot and first launch), which brought the part to about 30 minutes, level with `ui-variants-and-style-me`, so the check takes no longer than before. The narrow-window test passed there too, so the hosted runner's simulator has Windowed Apps on.

The narrow-window test drags the window's corner, which needs iPadOS 26's Windowed Apps (on by default on a new iOS 26.5 simulator). If a simulator has it off, the test skips with a message instead of failing. iPadOS 26 resizes a window about its centre, so the corner only moves half the change in width.

The phone UI tests (`HomeTests`, `ClosetTests` and the rest) are written for the phone layouts and aren't meant to run on an iPad.

## Decisions for Jose

1. **The tab bar is held at the bottom by telling the tab view it's compact.** There's no API for a bottom tab bar on iPadOS 26. The override is public SwiftUI and fails safe (the bar would move back to the top), but it's a workaround, so it's worth checking again on each new iPadOS.
2. **Closet's sidebar holds Closet's own controls, not the app's sections.** The mockup's sidebar repeats the tabs, which RD-01.6 puts at the bottom.
3. **Upright, Home is the room alone, not the mockup's room plus Style Me panel.** RD-01.6 says the wide room in both orientations, and the amendment wins over the upright mockup Lily liked. The room is the upright mockup's own arrangement, so it looks like the one she saw.
4. **The tall room's window sits lower and its suitcase a little higher** than the mockup, for the longer title and to keep the suitcase's and hamper's tap areas apart.
5. **At the accessibility text sizes Closet keeps the phone page** even on a wide window, since the columns would squeeze the words.
6. **The iPad mini upright (744 points) gets the phone page in Closet,** a little narrower than the detail needs beside the grid. Home there gets the tall room.
7. **No keyboard shortcuts yet.** Pointer highlights are in; shortcuts (for example Command-F for search) can come with 15b.

## Left for later phases

- **15b:** Style Me's results and Saved Looks on iPad, with side-by-side detail.
- **16a, 16b:** the tours on iPad layouts.
