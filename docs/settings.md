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
- **Dark appearance**: the room changes to evening with the lamp on. The Stage A audit renamed it from "Dark Mode", so no user-facing words say "Mode" (Lily's sign-off renamed Mode to Preferences).

**Open Settings** opens the app's own page in Settings (`UIApplication.openSettingsURLString`), and a note says where Text size, VoiceOver and Reduce Motion live, including Per-App Settings for this app only. Each line only claims what earlier phases checked.

Since the Stage A audit Accessibility and Delete my data have quick tours of their own (`docs/tours.md`, The Stage A audit's six).

## App tours

Since Phase 16b, a row under Help ("Replay the tips for any screen") opens App tours: every screen's quick tour with its tip count, the "Show tips on new screens" switch and Reset all tips. See `docs/tours.md`, App tours.

## Help (`help.html`)

The chest with its top drawer open, then "Everyday" (Get outfit ideas, Swap save and try on a look, Add a piece, Suitcases, Laundry) and "Good to know" (What needs a connection, Try-on pictures and real fit, Your data). Each topic opens and closes on a tap, with its answer and a quieter line; the first is open to start. VoiceOver hears each as a button with "Open" or "Closed" and a hint. Then "Still stuck?", which opens Send feedback, and the version line ("Nifty Outfit Nook · 0.1 (1) · test build with sample data").

The words are in the String Catalog, so they work offline. They describe this build as it is: the sample photos, Something new's one idea, that nothing is sent, and since the Stage A audit (under Your data) that it keeps her name and Style Me settings when it closes and forgets her fit and the pieces and looks she adds. The mockup's "Free and paid" topic waits for the subscription phase, and "What changed" (§22.2) for the first public release. There's no search: eight short topics don't need it, and neither the mockup nor §22.3 asks for one.

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

**The unsent note** lives at the root while the app runs, so leaving and coming back from the drawer or Profile finds it where she left it. Since Phase 21a it's also kept in the real store (`FeedbackDraftStore`), as she types: what it's about, her words and the details switch. After a relaunch it's there again, unless she has started typing a new one by the time it's read. Sending it, or emptying the words, removes it; closing the share sheet without sending keeps it. Delete my data erases it (it counts as one of the drafts on that screen). `-onboarding skip` keeps it in memory.

## Privacy and terms (`privacy.html`)

Since 27a, once Style Me uses the cloud stylist, a Style Me group sits above Weather with the switch **Style Me, swaps and Ask stylist** ("Piece descriptions, the occasion and the weather go to Anthropic when you ask. Never your photos, name, measurements or location."). Turning it on shows the consent sheet first; off withdraws at once and says what still works. The later-features list then drops its Style Me line. Delete my data erases the consent ([decision 0008](decisions/0008-cloud-stylist.md)).

1. A butter note: a test build with no account, nothing sent by the app, and no tracking or analytics.
2. **Stays on this iPhone**: pieces with their pictures and details; suitcases and laundry marks; saved looks and try-on pictures; her name, measurements, weight and fit; Preferences and what Style Me remembers. Then: Fit and measurements and try-on pictures are hidden in the app switcher, and what's kept when the app closes. For her own closet (Phase 21a): "Everything you add or change is kept on this iPhone when the app closes, until you delete it. Delete my data removes all of it." For the debug sample closet, as before: the name on her sign, Preferences, Avoid repeating outfits for and Track laundry, that she set it up, which closet she chose and which tips she has seen, with everything else back to how it started (Phase 17, Stage A audit). The screen picks from `NookServices.keepsChanges`; Help's "Your data" does the same.
3. **Later, sent only if you allow it**: Style Me and swaps, Try-on pictures, Weather, each with what it would send and what it never sends, from DATA_MAP. "None of these is in this test build. Each will ask first, and allowing one never allows another."
4. **Your data**: Backups (Phase 21b, only where her closet is in the store: her own closet and every Release build, not the debug sample closet), then Delete my data. The iCloud row joins them once sync is allowed (`docs/decisions/0004-backup-and-recovery.md`).
5. **Policies**: Privacy policy and Terms of use, "On the website", opened in the system's in-app Safari view at `https://niftyoutfitnook.pages.dev/privacy` and `/terms`, with "The full privacy policy and terms are still being written." Those pages don't exist yet, and the site currently answers both addresses with its coming-soon page. Phase 19b writes them.

**Not built from the mockup:** the six permission switches (nothing is sent, so a switch would control nothing; each comes with its feature in 19b, 24a, 27a, 29, 31 and 33). Export a copy is on its own Backups screen (21b).

## Backups and iCloud (designed in 20b, Backups built in 21b)

The full design is `docs/decisions/0004-backup-and-recovery.md`; its "Built in Phase 21b" section says what was built and what waits.

- **Backups** (built), under Privacy and terms (Your data) and on Profile (`Settings/Backups`): **Export a copy** (what goes in it with counts, measurements and the try-on photo on their own lines, and the estimated size; a passphrase the app makes, 24 letters and digits in groups of four with Copy passphrase, which copies it to this iPhone only for 2 minutes, or her own of at least 12 characters typed twice; then the Files sheet saves it wherever she picks, and Check this copy), **Check a copy** (the Files picker, her passphrase, every restore check, "This copy works", changing nothing), **Restore from a copy** (the same checks, then the copy's date and counts against her closet now, then Replace my closet with this copy, asked once more when the phone isn't empty, or Add what's missing), and **Undo restore** for 7 days. After a restore or an undo the app builds every screen again on the restored closet. The file is a `.nookbackup` Apple Encrypted Archive; the app never stores the passphrase and can't recover it. A wrong passphrase says "That passphrase doesn't open this copy." with no attempt limit.
- **Recovery screen** (built): when the store can't be opened, Export a copy saves the raw store and photos, encrypted the same way, for a later version to restore. Try again and Send feedback aren't there yet (the coordinator already retries at each launch, and feedback needs services the screen can't open).
- **iCloud** (not built), on Profile and in Privacy and terms: off by default, and not shown at all until the restore and two-device tests pass. The iCloud container and test accounts are Jose's setup, still to do. The on sheet is the 19b wording with the Advanced Data Protection line; the status shows Saved on this iPhone, Waiting to upload (with counts), Couldn't upload and Last confirmed by iCloud. Turning it off keeps everything on the phone and asks whether to keep or delete the iCloud copy. Measurements, weight, fit notes and the try-on photo stay on the phone until Jose decides how App Review 5.1.3(ii) applies.
- **Onboarding:** the welcome has **Restore from a backup file** under "I already use Nifty Outfit Nook" (built in 21b; the restore finishes onboarding on her own closet). Get my closet from iCloud comes with sync. Whether onboarding also gets an iCloud step is a Jose decision in 0004.

## Delete my data

Two steps. The screen says exactly what goes, with counts read from the stores: Your closet (21 pieces, with pictures, details and Recently deleted), Looks (6 looks), Try-on pictures (3 pictures), Suitcases (6 suitcases), Your profile (name on the sign, Preferences, fit, measurements, try-on photo, since 16b the app tours she has seen, and since 17 the closet she started with) and Unsaved work (drafts). "Afterwards" says the app starts fresh, as if just installed, opening on the welcome so she can choose a starting closet again (Phase 17), and that nothing about her is kept anywhere else. Then a solid button in the error colour with a trash icon, and "You'll be asked once more. Deleting can't be undone."

The button asks once more: "Delete everything?" with Delete everything and Cancel. Delete everything erases every store through `DataDeletionService`, then the root goes back to onboarding (`DataDeletedAction`, Phase 17, `docs/onboarding.md`): the welcome, with a toast that says "Your data is deleted. The app is starting fresh." Every tab, every cache and the unsent feedback note are gone, and finishing onboarding builds them new on the closet she chooses. Nothing from before can show on a screen that was already open, because no screen from before is left.

If a part fails (`-fixtures demo:stores-fail`), the screen stays and a note names what's left ("Most of your data is deleted, but not: Looks and Try-on pictures. Try again to finish.", or "Nothing was deleted. Try again in a moment."), and the button becomes Try again. Deleting is safe to repeat.

**Since Phase 21a deleting lasts:** the stores are in the real store on the iPhone, and Delete my data erases their records, so a relaunch opens on the welcome with nothing of hers left. Only a content-free note that the old `UserDefaults` suite was moved in stays. On the debug sample closet, which comes back as it ships, deleting also erases the store's records, so nothing from an earlier closet comes back. The store file itself, its journal and a migration snapshot (at most seven days old) stay; 21b adds erasing safety copies, as 0004 designs.

### The service, built for Phase 24c

```swift
protocol ErasableStore: Sendable { func eraseAll() async throws(StoreError) }   // every store protocol refines it

protocol DataDeletionService: Sendable {
    var scopes: [DeletionScope] { get }               // Stage A: [.thisDevice]
    func parts(in scope: DeletionScope) -> [DataPart]
    func delete(_ scope: DeletionScope) async -> DeletionReport   // part by part: deleted, pending or failed
}
```

`LocalDataDeletion` erases unsaved work, pictures, looks, suitcases, the closet and then the profile, keeps going past a failure, and reports each part. `NookServices` builds it from its own stores unless it's given another.

### Delete my account (Phase 24c, built against the fakes)

App Review Guideline 5.1.1(v) needs account deletion inside the app. **Delete my account** is a row in Privacy and terms, under Delete my data, shown only while she's signed in. It opens the same screen with the `account` scope: the parts held elsewhere first (what the server keeps, the account, the Sign in with Apple link, her iCloud copy when sync was ever on), then the six on this iPhone; the subscription note ("Deleting your account doesn't cancel a subscription..."); then one question, then Apple's sign-in sheet again.

`AccountDataDeletion` (Models) runs it: Apple's sheet and the backend's `POST /v1/account/deletion` first, so nothing is deleted anywhere if either says no; then it reads the backend's steps (a few times while they're pending); deletes the iCloud copy through `ICloudCopyDeletion` (a hook: `NoICloudCopy` until sync exists); erases this iPhone as Delete my data does; and signs out and forgets the App Attest key ID. Trying again after a local failure doesn't ask the backend again. The screen ends one of four ways: nothing deleted, with why; a fresh app; "Everything on this iPhone is deleted... Still being deleted on the server" with Done; or Try again for a local part. Payments (30) add the Manage subscription link and the active-subscription check.

Debug builds: `-fake-signed-in` signs in with the fake at launch and runs one paid action, so the row shows; the fake backend's counts go to `tmp/fake-backend-deletions.json` after each deletion request. Decision 0007 has the rest.

Since Phase 16a the tours she has seen and the "Show tips on new screens" switch are erased with her profile (PRD §7.8: Delete My Data resets them), so Home's tour starts again when she's back on Home (`docs/tours.md`). Since 16b the words under Your profile name them. Since 21b it also deletes what Backups keeps on the phone: her photo files, a checked copy waiting in staging, unsaved exports, the restore's safety copy and journal, deletion markers and the copies' versions kept for review. Exports she saved elsewhere stay where she put them. Phase 20b designed the iCloud part (below and `docs/decisions/0004-backup-and-recovery.md` §6); it comes with sync.

### Her iCloud copy (designed in 20b, not built yet)

Once iCloud sync exists, Delete my data also deletes her private iCloud copy. In order: stop sync, save a content-free pending deletion, delete the `Closet` and `Me` zones and wait for iCloud to confirm, erase everything on the phone (stores, images, safety copies, restore and export staging, the sync state), then clear the pending deletion. A third zone, `Control`, keeps one record with a generation number, a reason and a date, so a device that was offline learns not to upload its old closet.

- **iCloud unreachable:** the phone is erased anyway and the screen says "This iPhone: deleted. Your iCloud copy: waiting to be deleted." The deletion runs first at the next launch with a connection, and iCloud can't be turned on again until it has. Signed in to a different account by then, she's told which account holds the copy and where to delete it in Settings.
- **Her other devices** ask before erasing: "Your data was deleted from iCloud on another device. Delete it from this iPad too?" with Delete it here too and Keep it on this iPad (sync off). That's a Jose decision in 0004.
- **The list** gains "Your iCloud copy", shown only if sync was ever on, and "Afterwards" adds that exported copies stay wherever she saved them and are deleted in Files (PRD 15.2).
- **Deleting the app** is different: it removes this iPhone's copy and leaves iCloud's, so a reinstall can get it back. Help says so.

`DeletionScope` doesn't change: the iCloud copy is one more `DataPart` in `.thisDevice`, reported as deleted, pending or failed like the others.

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
- `FeedbackDraftKeepingTests` (Features, 21a): the note back after a relaunch, sending or clearing it forgetting it, a cancelled share keeping it, a late read never replacing her typing, and a failing store leaving it on screen. `StoragePersistenceTests.deleteMyDataLeavesNothing` (Services): no record of hers left in the store file.
- `TrackLaundryTests`, `FeedbackModelTests`, `DeleteDataModelTests` (Features): the kept marks and their words, on bringing them back on Home and Closet, off keeping them and making every piece eligible, a failed save; the note holding only her words by default with the demo profile loaded, the details' exact lines, sending exactly the preview, the problem; counts, deleting leaving a fresh Home, Closet and Profile, and the words for what's left.
- `SettingsSnapshotTests` (16 images): Help light, dark and AX5; Send feedback empty, filled with details in dark, with the problem, sent and AX5; Privacy light, dark and AX5; Accessibility default and AX5 dark; Delete my data, incomplete in dark, and AX5. `ProfileSnapshotTests` re-recorded for the switch and the new rows.
- UI, `SettingsTests`: every Profile row opens its real screen or sheet; the switch turns tracking on and off with the hamper and the Laundry tile following; the drawers, Help's topics and Still stuck, Send feedback's problem, preview, details and share sheet, the note waiting after leaving, Privacy and terms to Delete my data; Delete my data with Cancel, then Delete everything to a fresh Home and an empty Closet.

## Decisions for Jose

1. **App tours was hidden until 16b**, not shown as "coming soon". It's on Profile now.
2. **Accessibility has no in-app options**, only the system's settings with what the app does and Open Settings, since nothing in the spec lists any.
3. **Send feedback goes through the share sheet**, with no reply email field, until a support queue exists. The app details are three lines, off by default.
4. **Privacy and terms has no permission switches**, since nothing is sent. Export is on Backups (21b).
5. **Delete my data is two steps** (the explaining screen, then one question), not type-to-confirm, which is a lot of typing for something already explained and asked.
6. **Delete my data is on Profile as well as Privacy and terms.** The mockup has it only under Privacy and terms; 14a put the row on Profile, and Apple wants deletion easy to find.
7. **Deleting resets to a fresh Home**, the same as `-fixtures empty`. Since Phase 17 it goes back to onboarding instead.
8. **The policy links open the website's addresses now**, which show the coming-soon page until 19b writes the pages.

## Left for later phases

- **16a (done):** tour progress erased by Delete my data, with the profile (`docs/tours.md`).
- **16b (done):** App tours on Profile, and Delete my data naming the tours.
- **19b:** the privacy policy and terms pages on the website, and the real wording of Privacy and terms.
- **20b (designed), 21b (built):** Backups (Export a copy, Check a copy, Restore from a copy, Undo restore). Still to come: the iCloud switch and status, and the iCloud copy in Delete my data. The design, flows and test plan are in `docs/decisions/0004-backup-and-recovery.md`. Export is encrypted with a passphrase (an Apple Encrypted Archive); PRD 15.4's unencrypted archive is superseded (decision D10).
- **21a (done):** stores on disk, so deletion lasts across launches, and the feedback note is kept.
- **24c (built against the fakes):** Delete my account, with pending parts and the Apple link. The real Clerk and Apple calls wait on Jose (`docs/backend-switch.md`).
- **A backend phase not yet placed:** the private support queue Send feedback should reach.
- **19b, 24a, 27a, 29, 31, 33:** the permission switches on Privacy and terms, each with its feature.
