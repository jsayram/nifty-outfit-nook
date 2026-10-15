# iPad

Phase 15a, 15 October 2026. iPad layouts for Home and Closet, the tab bar at the bottom, and windows of any size. Phase 15b, the same day, added Style Me, Your looks, Saved Looks and every other screen; see [Style Me, Saved Looks and the other screens](#style-me-saved-looks-and-the-other-screens). Spec: amendment RD-01.6 (the wide room with bottom tabs in both orientations; rotating or resizing loses nothing and starts no request), the mockup README's decision 12 (use the space, never a phone layout centred in a tablet frame), PRD §7.2 (no state loss on resize, keyboard and pointer). Visual references: `ipad-home.html` and `css/home-wide.css` (sideways), the room in `ipad-home-portrait.html` (upright), and `ipad-closet.html`, in `closet/prototypes/RoomDirectionMockups`.

## What's where

| File | Holds |
|---|---|
| `Features/Shared/WindowLayout.swift` | Every layout choice that depends on the window, in one place: which room a window gets, the three layouts of Closet and Saved Looks and their column widths, the readable width, and when two panes sit side by side |
| `Features/Shared/BrowseColumns.swift` | The columns of Closet and Saved Looks for a layout, the note beside the grid before she picks something, and `pagedTitle` for a screen that's either pushed or beside the grid |
| `Features/Shared/WidePanes.swift` | `WidePanes` (two panes side by side, or stacked as on a phone) and `.readablePane()` |
| `Features/Shared/RootTabView.swift` | The tab bar at the bottom (see below) |
| `Features/Home/Room/RoomPlan.swift` | The three arrangements of the room: the phone's, the upright iPad's (`tall`) and the sideways iPad's (`wide`) |
| `Features/Home/Room/RoomStage.swift` | The phone room's rects, and `RoomLayout`, which scales a plan to a window |
| `Features/Closet/ClosetScreen.swift` | Closet's layout, the piece beside the grid, and keeping it across a change of layout |
| `Features/Closet/ClosetPage.swift` | The page as a whole, or split into the sidebar and the grid column |
| `Features/SavedLooks/SavedLooksScreen.swift`, `SavedLooksPage.swift` | The same for Saved Looks, with a look or a picture beside the grid (15b) |

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

This is two columns of the screen's own, not a `NavigationSplitView`. Closet's navigation stack is shared with Home (the suitcase and hamper open Suitcases and Laundry in it), and a split view inside a tab whose width class we override would bring its own column rules; the plain columns keep one stack and one set of rules, and they're drawn by the snapshot tests exactly as the screen draws them (`BrowseColumns`, shared with Saved Looks since 15b).

## Style Me, Saved Looks and the other screens

Phase 15b. Spec: the plan's "Results and Saved Looks with side-by-side detail and centered panes", the mockup README's decision 12 and its tablet notes R10 and R11 (two panes where useful, centred), and `ipad-saved.html`. `ipad-results.html` still shows Current, Earlier and Shuffle, which Lily's sign-off replaced, so Your looks follows the tablet layout of `results.html` with today's versions.

### Two panes, and a readable column

Two shared pieces, both deciding from the window like everything else here:

- **`.readablePane()`** keeps a column of rows, words or fields to 640 points in the middle of the window (`WindowLayout.readableWidth`). Every page that was a phone column now uses it instead of its own width (they were 560 to 640), so nothing runs from edge to edge. A phone is narrower, so phones don't change. Garment detail, Edit and Recently deleted keep their 560.
- **`WidePanes`** puts two panes side by side, sharing at most 1,120 points (`panesMaximumWidth`) with 40 between them, when the window is regular width, the text is below the accessibility sizes, and the page's content is at least 720 points wide (`panesMinimumWidth`). Otherwise the panes stack in one readable column, as the same views with the same spacing as before, so the phone snapshots didn't change. Each pane is told which arrangement it's in, so a look can grow beside its controls. The choice is made from the space the page is offered (`ViewThatFits`), which a still image sees the same way as the screen.

Measured content widths (the window less two 16-point margins): 1,178 on the 11-inch held sideways, 802 upright, 763 at two thirds of it sideways, 1,000 on the 13-inch upright, and 712 on the iPad mini upright, which stays one column.

| Screen | In a wide window |
|---|---|
| Your looks, Today | The version switch and the look on the left, up to 420 points wide; the notes, the pieces, Undo, the four buttons and Try a different outfit on the right. The tabs, the request line and any banner stay above both |
| Your looks, Saved | A grid of the saved looks, each bundle on a soft mat with its name and "4 pieces · Last worn …" under it, 180 to 240 points a column |
| Style Me | Your request on the left, the options and Style me on the right, from 960 points of content (`rowPanesMinimumWidth`): the option rows need more room than a look does. Upright on the 11-inch it stays one column. Short content sits in the middle of the window's height, as the mockups centre their panes |
| Swap a piece | The pieces and the look on the left, 320 points wide; the options and buttons on the right |
| Make your own look | The look on the left, 320 points wide; the lead, the name and the pieces on the right |
| States (styling, not enough pieces, didn't finish, offline, loading, errors) | One readable column |

VoiceOver reads the left pane, then the right, which is the phone's order except on Make your own look, where the look comes before the lead and the name.

### Saved Looks

Laid out like Closet, from the same widths (`WindowLayout.browse`):

- **Sideways (from 1,080 points):** the sidebar has the title and count, Looks and Pictures, search, the chips and swatches wrapped onto as many lines as they need, and the line about a deleted look or picture with Undo. The grid fills the middle. The look or picture she picks shows on the right.
- **Upright (from 760 points):** the phone page on the left, with the look or picture beside it.
- Narrower windows and the accessibility sizes keep the phone page.

The look beside the grid is look detail without a bar of its own, everything else as on a phone; a picture is picture detail. Before she picks one the right side says "Pick a look" or "Pick a picture". The look or picture beside the grid stands on a soft tint and VoiceOver reads it as selected, with the hint "Shows this look beside your looks."

**Each tab keeps its own.** The Looks tab remembers its look and the Pictures tab its picture, so what's beside the grid is always one of the grid's own. See the look on a picture switches to Looks with that look beside the grid, and a picture in a look's list switches to Pictures. Everything else (a piece's garment detail, Swap a piece, Make your own look) opens over the whole width, and Back returns to the same look.

**Keeping what's open.** A look or picture beside the grid is pushed when the window gets narrow, under anything it had opened, and a pushed one moves back beside the grid when it widens again. A frame on the Home shelf and Try it on's See the picture open their look or picture beside the grid when the window is wide.

### Sheets

In a regular-width window the system shows a sheet as a form in the middle of the screen. A sheet that can rest at half height on a phone is now only as tall as its content there (`presentationSizing(.form.fitted(…))`), so Occasion or Rename is no longer a tall card that's mostly empty. Sheets that only open full height (the piece pickers, packing, Try it on) keep the form's full height, so they don't jump as their content changes. Two things were needed: the form ignores fitting while detents are set, so detents are only set over a compact window, read from the window the sheet opens over; and a scroll view offers no height of its own, so the sheet tells the form its content's height. Over a compact window (a phone, or a narrow iPad window) sheets are bottom sheets with detents, as before.

### The segmented switch

`NookSegmentedPicker` used to change its value inside `withAnimation`, which animated everything the value changed, such as the whole of Saved Looks when she switched between Looks and Pictures. With a look beside the grid that crashed the app on the iPad simulator: SwiftUI drew the animated change on its own render thread (`com.apple.SwiftUI.AsyncRenderer`), called the switch's `ForEach` content there, and Swift 6's check that main-actor code runs on the main thread stopped the app. Now the switch changes its value plainly and animates only its own pill (`.animation(_:value:)`), so the page changes at once. The crash didn't come back in any orientation or window size.

## Pointer and keyboard

Room controls, pieces in Closet's grid, and looks and pictures in Saved Looks' grids show the system's pointer highlight (`.hoverEffect(.highlight)`). Everything else is standard buttons, fields and the system tab bar, which take the keyboard and pointer as they do anywhere.

No keyboard shortcuts yet. Command-F for search and Escape to close a sheet were tried in 15b (`.keyboardShortcut`), but neither did anything when the UI tests pressed the keys on the iPad simulator, so they were left out rather than shipped unchecked. They need a look on a real iPad with a keyboard.

## Tests

- `WindowLayoutTests`: Closet's layout for each measured width, compact and accessibility sizes, the column widths and that the grid keeps three pieces across.
- `RoomPlanTests`: the phone plan is unchanged; each iPad window gets the room for its shape without scrolling; every control is 44 points or more, between the bars and not overlapping its neighbours on six iPad windows and two Split View sizes; every plate stays on its furniture; the title is clear of the wall.
- `HomeIPadSnapshotTests`: the tall and wide rooms on the 11- and 13-inch iPads, the wide room in dark, a compact third-width window, and the large-text page at AX5 on an iPad.
- `ClosetIPadSnapshotTests`: the sidebar layout on the 11-inch and (in dark) the 13-inch held sideways, the page with the piece beside it on both upright, nothing picked yet, a compact third-width window and AX3 on an iPad.
- `WindowLayoutTests` (15b): when two panes sit side by side, for each measured width, compact windows and every text size, and that a pane has room for a look.
- Snapshots of each main screen on the 11-inch iPad sideways and upright and in a window a third of its width (`SnapshotWindow`), drawn by `assertWindowSnapshot`: `StyleMeIPadSnapshotTests` (Your looks, also in dark and at AX3, its Saved tab, Style Me, Swap a piece), `SavedLooksIPadSnapshotTests` (a look beside the grid, also in dark and at AX3, nothing picked, a picture beside the Pictures grid, Make your own look), `SuitcasesIPadSnapshotTests` (Suitcases, a suitcase, Laundry) and `ProfileIPadSnapshotTests` (Profile, Fit and measurements, Help, Privacy and terms).
- `IPadTests` (UI, iPad only): the tab bar at the bottom in both orientations, the tall and wide rooms and their furniture, turning with Style Me open (nothing sent), the Closet sidebar with a filter, search, a piece beside the grid and Edit, turning upright with the piece kept, and a window dragged to a third of the screen falling back to the phone layouts and widening back with the piece moved beside the grid.
- `IPadStyleMeAndSavedTests` (UI, iPad only, 15b): Style Me's request beside its options, Style me, the look beside its buttons in both orientations (turning sends nothing), Save look, the Saved tab's tile, then the look beside the Saved Looks grid upright and with the sidebar sideways; a picture beside the Pictures grid, See the look switching to Looks; a third-width window pushing the look, and widening moving a pushed look beside the grid. The two classes share their helpers in `IPadTestCase`.

iPad snapshots are drawn at 1x: a 2x picture of a 13-inch window is several megabytes, and 1x still catches a moved drawing or a changed plate.

### Running the iPad UI tests

Every iPad UI test skips itself on an iPhone, so the phone runs aren't slower. On an iPad simulator:

```sh
NOOK_SIM_FAMILY=iPad scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests \
  -only-testing:NiftyOutfitNookUITests/IPadStyleMeAndSavedTests
```

They take about five minutes locally. In 15a CI ran `IPadTests` in the `ui-home-and-results` part after its phone tests. That step took 12 minutes (6 of them tests, the rest the iPad simulator's boot and first launch) and made that part the slowest, so the whole check grew to 27 to 30 minutes. Since 15b both iPad classes have a part of their own, `ui-ipad`, and the parts were balanced again (see README, CI). The narrow-window tests passed on the hosted runner too, so its simulator has Windowed Apps on.

The narrow-window test drags the window's corner, which needs iPadOS 26's Windowed Apps (on by default on a new iOS 26.5 simulator). If a simulator has it off, the test skips with a message instead of failing. iPadOS 26 resizes a window about its centre, so the corner only moves half the change in width.

The phone UI tests (`HomeTests`, `ClosetTests` and the rest) are written for the phone layouts and aren't meant to run on an iPad.

## Decisions for Jose

1. **The tab bar is held at the bottom by telling the tab view it's compact.** There's no API for a bottom tab bar on iPadOS 26. The override is public SwiftUI and fails safe (the bar would move back to the top), but it's a workaround, so it's worth checking again on each new iPadOS.
2. **Closet's sidebar holds Closet's own controls, not the app's sections.** The mockup's sidebar repeats the tabs, which RD-01.6 puts at the bottom.
3. **Upright, Home is the room alone, not the mockup's room plus Style Me panel.** RD-01.6 says the wide room in both orientations, and the amendment wins over the upright mockup Lily liked. The room is the upright mockup's own arrangement, so it looks like the one she saw.
4. **The tall room's window sits lower and its suitcase a little higher** than the mockup, for the longer title and to keep the suitcase's and hamper's tap areas apart.
5. **At the accessibility text sizes Closet keeps the phone page** even on a wide window, since the columns would squeeze the words.
6. **The iPad mini upright (744 points) gets the phone page in Closet,** a little narrower than the detail needs beside the grid. Home there gets the tall room.
7. **No keyboard shortcuts yet.** Pointer highlights are in. Command-F and Escape were tried in 15b and left out (see Pointer and keyboard).
8. **Saved Looks is laid out like Closet** (15b): the mockup's sidebar repeats the tabs, so the sidebar holds Saved Looks' own controls, and the detail is a third of the window, as on Closet.
9. **Each Saved Looks tab keeps its own look or picture beside the grid** (15b), and going between a picture and its look switches tab, rather than showing a look beside the pictures.
10. **Your looks' tabs and request line stay above the two panes** (15b), with only the version switch beside the look, so switching versions or tabs doesn't move them.
11. **Style Me goes side by side only from 960 points** (15b). Upright on the 11-inch, two columns squeezed the option rows' words, so it stays one centred column there; Your looks and Swap a piece do go side by side upright.
12. **Suitcases, Laundry, Profile and the settings screens keep the wall on top** (15b), with the title, the drawing and the rows lined up in one readable column, rather than the mockups' wall beside the rows. The wall and floor read as one room, and side by side would cut it in two.
13. **The segmented switch no longer animates the page it changes** (15b), only its own pill, which fixed a crash (see The segmented switch).

## Left for later phases

- **16a, 16b:** the tours on iPad layouts.
- **Later:** keyboard shortcuts, checked on a real iPad with a keyboard.
