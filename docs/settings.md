# Remaining settings

Phase 14b, 15 October 2026. The Track laundry switch, Accessibility, Help, Send feedback, Privacy and terms, and Delete my data, from Profile and from Home's desk drawers. Visual references: `settings.html`, `help.html`, `feedback.html` and `privacy.html` in `closet/prototypes/RoomDirectionMockups/screens`. Where they differ from the amendment or the PRD, those win.

Spec: amendment RD-10 (the desk drawers and their screens) and RD-11 (the Track laundry switch); PRD §7 (Settings, Help, Feedback rows), §7.8 (App tours), §15.4 (Delete My Data), §16 (accessibility), §22 (private issue form and diagnostics), §22.3 (help library); SECURITY_STANDARD §1, §4 and §9; App Review Guideline 5.1.1(v) (in-app account deletion once accounts exist).

## What's where

| File | Holds |
|---|---|
| `Models/Services/DataDeletion.swift` | `ErasableStore`, `DataDeletionService`, `DeletionScope`, `DataPart`, `DeletionReport` and `LocalDataDeletion` |
| `Models/Feedback/Feedback.swift` | `FeedbackKind`, `FeedbackNote`, `FeedbackDiagnostics` and `FeedbackRules` |
| `Fixtures/Stores/*` | `eraseAll()` on every in-memory store |
| `Features/Settings/SettingsPage.swift` | The header with the drawer chest, the page frame, groups, notes, info rows and the switch row |
| `Features/Settings/SettingsText.swift` | Shared titles and ledes, `AppVersion`, and reading `FeedbackDiagnostics.current` |
| `Features/Settings/Help/` | Help's topics (`HelpContent`) and the screen |
| `Features/Settings/Feedback/` | `FeedbackModel`, `FeedbackComposer` and the words, the screen, and `ShareSheet` |
| `Features/Settings/Privacy/` | Privacy and terms, and `SafariView` with `WebsiteLink` |
| `Features/Settings/DeleteData/` | `DeleteDataModel` and the screen |
| `Features/Settings/Accessibility/` | Accessibility |
| `Features/Shared/RootTabView.swift` | The fresh start after Delete my data, and the unsent feedback note |

## Where they open from

| Screen | From |
|---|---|
| Track laundry | A switch on Profile, in the Style Me group |
| Accessibility | Profile |
| Help | Profile, the top desk drawer (and its large-text row and sideways tile) |
| Send feedback | Profile, the middle drawer, and "Still stuck?" at the end of Help |
| Privacy and terms | Profile, the bottom drawer |
| Delete my data | Profile, and Your data on Privacy and terms |
| App tours (16b) | Profile, a sheet |

Each is pushed on whichever stack opened it, so Back goes where she came from. The titles sit on the wall, as on Profile, and the navigation bar keeps the name for Back and VoiceOver.

## Track laundry (RD-11)

The Profile row is now a switch (`settings.html`), with a line under it that says what it does: "Style Me skips pieces in the wash until they're clean." while it's on, and "Every piece counts as available. Your 2 dirty marks are kept." while it's off. Changing it saves at once and a toast says what happened to the marks: "Laundry tracking is on. 2 pieces are back in the wash." or "Laundry tracking is off. Your 2 dirty marks are kept." Turning it off never clears a mark (RD-11.2). If the save fails, the switch goes back and a toast says so.

Home's hamper and Closet's Laundry tile follow as soon as Profile closes, because both reload when their stack gets shorter and when their tab appears. Laundry itself still offers Turn on while tracking is off, and the hamper's sheet still points here.

## Accessibility

Neither the PRD nor the mockups list in-app accessibility options. PRD §16 asks the app to follow the system, so this screen has no switches of its own. It shows each iPhone setting as it is now, with what the app does with it:

- **Text size** (Default, Larger, Smaller or Largest): every screen grows with it; at the largest sizes Home turns into big rows.
- **VoiceOver** (On or Off): every button and everything in the room says what it is and where it goes.
- **Reduce Motion**: things fade instead of sliding, and Maya's z's stay still.
- **Dark Mode**: the room changes to evening with the lamp on.

**Open Settings** opens the app's own page in Settings (`UIApplication.openSettingsURLString`), and a note says where Text size, VoiceOver and Reduce Motion live, including Per-App Settings for this app only. Each line only claims what earlier phases checked.

## App tours

Since Phase 16b, a row under Help ("Replay the tips for any screen") opens App tours: every screen's quick tour with its tip count, the "Show tips on new screens" switch and Reset all tips. See `docs/tours.md`, App tours.

## Help (`help.html`)

The chest with its top drawer open, then "Everyday" (Get outfit ideas, Swap save and try on a look, Add a piece, Suitcases, Laundry) and "Good to know" (What needs a connection, Try-on pictures and real fit, Your data). Each topic opens and closes on a tap, with its answer and a quieter line; the first is open to start. VoiceOver hears each as a button with "Open" or "Closed" and a hint. Then "Still stuck?", which opens Send feedback, and the version line ("Nifty Outfit Nook · 0.1 (1) · test build with sample data").

The words are in the String Catalog, so they work offline. They describe this build as it is: the sample photos, Something new's one idea, that nothing is sent, and since Phase 17 (under Your data) that it forgets her changes when it closes. The mockup's "Free and paid" topic waits for the subscription phase, and "What changed" (§22.2) for the first public release. There's no search: eight short topics don't need it, and neither the mockup nor §22.3 asks for one.

## Send feedback (`feedback.html`, PRD §22)

1. **What is it about?** Something's wrong, An idea, Other (chips; the field's name follows: "What happened?", "What's your idea?", "What would you like to say?").
2. **Her note**, with "Keep it about the app. There's no need to add your measurements, photos or closet details." At most 1,000 characters.
3. **Include app details**, off until she turns it on. On, it adds three lines: the app version and build, the iOS version and the model identifier ("iPhone13,2").
4. **What's sent**: the exact text, updated as she types, and "Never your closet, photos, measurements, looks or name."
5. **Send privately**, and "The app doesn't send anything itself. Send opens the share sheet, and you choose where the note goes, like Messages or Mail."

The text is built by `FeedbackComposer` from the note alone, so nothing else can get into it:

```
Nifty Outfit Nook feedback
About: An idea

Could the hamper show what's in the wash?

App version: 0.1 (14)
iOS: 26.5
Device: iPhone13,2
```

Send with nothing written shows "Write a few words to send the note." under the field and moves VoiceOver to it. Otherwise it opens the system share sheet (`UIActivityViewController`, wrapped so the app learns whether she sent it) with that text and the subject "Nifty Outfit Nook feedback". Closing the sheet keeps the note. Sending it shows "Thank you" with what went, then Done or Write another.

**Why the share sheet.** PRD §22's channel is a private support queue on the backend, and no phase builds it yet (DATA_MAP open points). There's no support email address either. So in Stage A she picks the app and the person; the app makes no request. The mockup's "Reply email (optional)" field is left out for the same reason: the app she sends from already carries her address, and the app shouldn't ask for one it can't use.

**The unsent note** lives at the root while the app runs, so leaving and coming back from the drawer or Profile finds it where she left it. In memory only, like every Stage A draft; Delete my data starts a new one.

## Privacy and terms (`privacy.html`)

1. A butter note: a test build with no account, nothing sent by the app, and no tracking or analytics.
2. **Stays on this iPhone**: pieces with their pictures and details; suitcases and laundry marks; saved looks and try-on pictures; her name, measurements, weight and fit; Preferences and what Style Me remembers. Then: Fit and measurements and try-on pictures are hidden in the app switcher, and this build forgets her changes when it closes: the closet she started with comes back as it was, and it only remembers that she set it up, which closet she chose and which tips she has seen (Phase 17).
3. **Later, sent only if you allow it**: Style Me and swaps, Try-on pictures, Weather, each with what it would send and what it never sends, from DATA_MAP. "None of these is in this test build. Each will ask first, and allowing one never allows another."
4. **Your data**: Delete my data.
5. **Policies**: Privacy policy and Terms of use, "On the website", opened in the system's in-app Safari view at `https://niftyoutfitnook.pages.dev/privacy` and `/terms`, with "The full privacy policy and terms are still being written." Those pages don't exist yet, and the site currently answers both addresses with its coming-soon page. Phase 19b writes them.

**Not built from the mockup:** the six permission switches (nothing is sent, so a switch would control nothing; each comes with its feature in 19b, 24a, 27a, 29, 31 and 33), and Export a copy (20b, 21b).

## Delete my data

Two steps. The screen says exactly what goes, with counts read from the stores: Your closet (21 pieces, with pictures, details and Recently deleted), Looks (6 looks), Try-on pictures (3 pictures), Suitcases (6 suitcases), Your profile (name on the sign, Preferences, fit, measurements, try-on photo, since 16b the app tours she has seen, and since 17 the closet she started with) and Unsaved work (drafts). "Afterwards" says the app starts fresh, as if just installed, opening on the welcome so she can choose a starting closet again (Phase 17), and that nothing about her is kept anywhere else. Then a solid button in the error colour with a trash icon, and "You'll be asked once more. Deleting can't be undone."

The button asks once more: "Delete everything?" with Delete everything and Cancel. Delete everything erases every store through `DataDeletionService`, then the root goes back to onboarding (`DataDeletedAction`, Phase 17, `docs/onboarding.md`): the welcome, with a toast that says "Your data is deleted. The app is starting fresh." Every tab, every cache and the unsent feedback note are gone, and finishing onboarding builds them new on the closet she chooses. Nothing from before can show on a screen that was already open, because no screen from before is left.

If a part fails (`-fixtures demo:stores-fail`), the screen stays and a note names what's left ("Most of your data is deleted, but not: Looks and Try-on pictures. Try again to finish.", or "Nothing was deleted. Try again in a moment."), and the button becomes Try again. Deleting is safe to repeat.

**In Stage A a relaunch brings back the closet she chose in onboarding,** because the fixtures are built at launch; only the onboarding and tour flags are kept (Phase 17). Deleting erases those too, so the next launch opens on the welcome. From Phase 21a the stores are on disk and deletion lasts.

### The service, built for Phase 24c

```swift
protocol ErasableStore: Sendable { func eraseAll() async throws(StoreError) }   // every store protocol refines it

protocol DataDeletionService: Sendable {
    var scopes: [DeletionScope] { get }               // Stage A: [.thisDevice]
    func parts(in scope: DeletionScope) -> [DataPart]
    func delete(_ scope: DeletionScope) async -> DeletionReport   // part by part: deleted, pending or failed
}
```

`LocalDataDeletion` erases unsaved work, pictures, looks, suitcases, the closet and then the profile, keeps going past a failure, and reports each part. `NookServices` builds it from its own stores unless it's given another. Phase 24c adds:

- scopes for what the developer holds and for everything (PRD §15.4 asks for plainly labelled scopes), and parts for the account and server data, whose outcome can be `pending` until the server confirms;
- Sign in with Apple token revocation, and the note that deleting doesn't cancel a subscription (30a);
- the same screen, which already lists parts from the service and reports pending ones.

Since Phase 16a the tours she has seen and the "Show tips on new screens" switch are erased with her profile (PRD §7.8: Delete My Data resets them), so Home's tour starts again when she's back on Home (`docs/tours.md`). Since 16b the words under Your profile name them. Phase 20b adds her private iCloud copy.

## States

| Screen | Loading | Error | Empty |
|---|---|---|---|
| Profile's switch | As Profile | Toast, switch goes back | |
| Help, Accessibility, Privacy | Bundled, nothing loads | | |
| Send feedback | | The note's problem under the field | "Your note shows here, exactly as it will be sent." |
| Delete my data | The list without counts until read | The list without counts; a failed deletion names what's left | A fresh install lists every part with 0 |

Nothing here needs a connection, so offline doesn't apply. The policy pages open in Safari, which handles its own offline page.

## Accessibility

- Every screen reads its title as a heading. The chest drawings are hidden from VoiceOver.
- Switches are system switches, read as one element with their line: "Track laundry, Every piece counts as available. Your 2 dirty marks are kept., switch, off".
- Help topics say Open or Closed, with a hint. Send feedback's problem is announced and focused. Delete my data's button has a trash icon and words, not colour alone, and reads "Deleting" while it works.
- At the accessibility sizes the chest is left out and titles step down one style, so no word breaks mid-word, and rows put their icon above their words. All screens checked at AX5 in snapshots.
- Help's topics open with a short animation, or none with Reduce Motion. Dark uses the tokens; the delete button's words on the error colour are 6.8:1 in light and 8.6:1 in dark (`ContrastRequirement`).

## Tests

- `DataDeletionTests`, `FeedbackRulesTests` (Models): order, a failing part not stopping the others, a part held by two stores, pending, every part covered; trimming, details only when asked, empty and too long.
- `DataDeletionFixtureTests` (Fixtures): deletion wipes every store, including both kinds of draft, back to a fresh profile; the result matches `-fixtures empty`; twice is safe; failing stores report every part; the large closet.
- `TrackLaundryTests`, `FeedbackModelTests`, `DeleteDataModelTests` (Features): the kept marks and their words, on bringing them back on Home and Closet, off keeping them and making every piece eligible, a failed save; the note holding only her words by default with the demo profile loaded, the details' exact lines, sending exactly the preview, the problem; counts, deleting leaving a fresh Home, Closet and Profile, and the words for what's left.
- `SettingsSnapshotTests` (16 images): Help light, dark and AX5; Send feedback empty, filled with details in dark, with the problem, sent and AX5; Privacy light, dark and AX5; Accessibility default and AX5 dark; Delete my data, incomplete in dark, and AX5. `ProfileSnapshotTests` re-recorded for the switch and the new rows.
- UI, `SettingsTests`: every Profile row opens its real screen or sheet; the switch turns tracking on and off with the hamper and the Laundry tile following; the drawers, Help's topics and Still stuck, Send feedback's problem, preview, details and share sheet, the note waiting after leaving, Privacy and terms to Delete my data; Delete my data with Cancel, then Delete everything to a fresh Home and an empty Closet.

## Decisions for Jose

1. **App tours was hidden until 16b**, not shown as "coming soon". It's on Profile now.
2. **Accessibility has no in-app options**, only the system's settings with what the app does and Open Settings, since nothing in the spec lists any.
3. **Send feedback goes through the share sheet**, with no reply email field, until a support queue exists. The app details are three lines, off by default.
4. **Privacy and terms has no permission switches** and no Export, since nothing is sent and export isn't built.
5. **Delete my data is two steps** (the explaining screen, then one question), not type-to-confirm, which is a lot of typing for something already explained and asked.
6. **Delete my data is on Profile as well as Privacy and terms.** The mockup has it only under Privacy and terms; 14a put the row on Profile, and Apple wants deletion easy to find.
7. **Deleting resets to a fresh Home**, the same as `-fixtures empty`. Since Phase 17 it goes back to onboarding instead.
8. **The policy links open the website's addresses now**, which show the coming-soon page until 19b writes the pages.

## Left for later phases

- **16a (done):** tour progress erased by Delete my data, with the profile (`docs/tours.md`).
- **16b (done):** App tours on Profile, and Delete my data naming the tours.
- **19b:** the privacy policy and terms pages on the website, and the real wording of Privacy and terms.
- **20b, 21b:** Export a copy, and the iCloud copy in Delete my data.
- **21a:** stores on disk, so deletion lasts across launches and the feedback note can be kept.
- **24c:** account and server deletion, with pending parts and token revocation.
- **A backend phase not yet placed:** the private support queue Send feedback should reach.
- **19b, 24a, 27a, 29, 31, 33:** the permission switches on Privacy and terms, each with its feature.
