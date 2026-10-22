# Profile essentials

Phase 14a, 15 October 2026. Profile holds the name on her sign, Style Me's usual choices, her fit and measurements, and the try-on photo. Visual references: `settings.html` (Profile, the name sheet and the photo sheet) and `fit.html` in `closet/prototypes/RoomDirectionMockups/screens`. Where they differ from the amendment or Lily's sign-off sheet, those win.

Spec: amendment RD-03 (Name on your sign), RD-06 (the try-on photo lives in Profile), LR-03 (Preferences), LR-10 (the repeat setting), LR-13 ("Add a piece that fits you well"), LR-18 ("Saved until you change it."); PRD §9.2.1 step 1 (the try-on photo), §10.1 and §10.2 (fit and measurements); SECURITY_STANDARD §1 and §4; DATA_MAP.md (measurements, fitting pieces and the photo are Sensitive).

## What's where

| File | Holds |
|---|---|
| `Models/Profile/Profile.swift` | `Profile.units` (new), and measurements that never print their values |
| `Models/Profile/MeasurementEntry.swift` | `MeasurementUnits`, conversions, and turning typed text into stored values (`MeasurementEntry`, `EntryProblem`) |
| `Models/Rules/Validation.swift` | `MeasurementRules.fitBrand` and `fitSize` for a fitting piece |
| `Features/Profile/ProfileScreen.swift`, `ProfilePage.swift`, `ProfileHeader.swift` | Profile: the wall with her sign, the rows, where each row goes |
| `Features/Profile/ProfileModel.swift` | The one model for Profile and Fit: loading, and every change as a read-change-save |
| `Features/Profile/ProfileSheets.swift` | Name on your sign, and the Preferences and repeat sheets |
| `Features/Profile/TryOnPhotoSheet.swift` | Your try-on photo: her own from the system picker (Phase 22a), or Stage A's example |
| `Features/Profile/Fit/` | Fit and measurements: page, screen, the measurement sheet, the fitting piece sheet, formatting and words |
| `Features/Shared/HiddenWhenInactive.swift` | `.hiddenWhenInactive()`, the cover the app switcher sees |

## Where it opens from

Home's name sign and Profile button (and the same in the large-text and sideways layouts), Laundry's "Profile" link and the laundry sheet's "You can change this in Profile". It's pushed on whichever stack opened it. Home reloads when its path gets shorter, so a new name is on the sign as soon as Profile closes (RD-03.1).

## Profile

Top to bottom, as `settings.html`:

1. **The wall.** "Profile" in display type, her name sign in the middle (the Home drawing at 1.3 times, her name as live text) and a floor plant. The sign is a button that opens the name sheet. An empty name shows "Hello" (RD-03.2). At the accessibility sizes the plant goes; the row below carries the name at full size.
2. **Name on your sign** (value: the name, or Hello), **Styling access** (Phase 30a; value: Not subscribed, Free month, Subscribed, Payment problem or Ended; opens the paywall and status screen in `docs/payments.md`), **Fit and measurements**, **Your try-on photo** (Added or Not added).
3. **Style Me:** Preferences (Mine + one idea or Only mine), Avoid repeating outfits for (1 week, 2 weeks, I don't mind), and the Track laundry switch.
4. **Help and privacy:** Accessibility, Help, Send feedback, Privacy and terms, Delete my data.

Since Phase 14b, Track laundry is a switch and the fourth group opens real screens (`docs/settings.md`). App tours comes back in 16b, with tours to replay.

**Name on your sign.** One field, a small sign above it that shows what she types as she types, the note "Leave it empty and the sign says Hello", and Save. `NameRules.signName`: trimmed, one line, at most 20 characters. A problem shows under the field and Save is dimmed. Saving closes the sheet with "Your sign now says Lily."

**Preferences and Avoid repeating outfits for.** One row per value with what it does; tapping saves and closes. Style Me starts from the saved Preferences each time and can change it for one request (10a). The repeat sheet notes that single favourite pieces can still come back (LR-10). A save that fails keeps the sheet open and says so.

## Fit and measurements

Top to bottom, as `fit.html`:

1. **The wall.** The title, "Everything here is optional. It stays private, on this iPhone.", and trousers on a peg.
2. **Usual fit:** Fitted, Comfortable, Relaxed, saved on tap, with "How you like clothes to sit. Saved until you change it." and "For one outfit only, pick a Comfort on Style Me." (LR-18). Style Me's Comfort starts from it.
3. **Measurements**, with **in · lb** and **cm · kg**: Height, Waist, Hip / seat, Bust, Inseam and Weight ("Optional · approximate is fine"). Empty ones say "Not added".
4. **Pieces that fit you well** (LR-13): the line about brand and size, her pieces as "Example Denim Co. · Bottom · S · Fits well" with a remove button and Undo, "Used for fit checks when you're thinking of buying.", and **Add a piece that fits you well**. "For example: your favourite jeans or a blazer that fits perfectly." shows only while she has none (LR-13.3).
5. **The privacy line.** Saved only on this iPhone, nothing sent in this test build, and changing it never restyles a saved look.

**Units.** Until she picks, the region decides: inches and pounds in the US and the UK, centimetres and kilograms where the region is metric (`MeasurementUnits.preferred(for:)`). Her pick is saved in `Profile.units`. Values keep the unit she typed them in, so switching only changes how they're shown and never rounds what's stored.

**Showing a value.** Inches to the nearest half, height as feet and inches ("4′ 11″"), centimetres whole, pounds whole and kilograms to one decimal, in the region's number style. VoiceOver hears the long form ("4 feet 11 inches", "68 centimeters").

**The measurement sheet.** How to measure it, "Leave it empty if you don't know.", the box with its unit after it, Save, and Clear when it has a value. Height in inches has two boxes, feet and inches. The decimal keypad; a comma or a point both work as the decimal mark. Save checks with `MeasurementEntry`:

| She types | Result |
|---|---|
| Nothing | The value is cleared ("Waist cleared. Nothing is guessed in its place.") |
| Not a plain number ("abc", "-3", "1.2.3") | "Enter a number of inches between 15 and 70, or leave it empty." |
| Outside the range | The same line, with the range in her units |
| Inches of 12 or more | "Inches go from 0 to 11. Put whole feet in the first box." |
| A good number | Saved, the sheet closes, "Waist saved on this iPhone." |

The ranges are `MeasurementRules.allowedRange`, rounded inwards to whole numbers in her units, so every number the line offers is accepted. They only catch typing mistakes and say nothing about fit. The store checks again before it keeps anything. The problem is announced and VoiceOver moves to it, and it goes away as she types.

**Add a piece that fits you well.** Brand, kind (chips, none chosen to start), size as printed, and how it fits (Fits well to start, since that's what the list is for). Save names what's missing.

**Not built from the mockup:** the "Confirm" step on each measurement and the "Fit notes use…" line. See Decisions.

## Your try-on photo (Stage A)

A full-height sheet. It says what the photo is for (try-on pictures, once they're ready; styling never needs it), then four points: kept on this iPhone and hidden when she switches apps, asked first before any picture is made from it, never used to guess her size, hers to remove (pictures she saved stay). Then **Choose example photo** (Change once added), **Remove photo**, **Done**, and "This test build uses an example photo. It doesn't ask for your camera or your photos, and nothing is uploaded."

Choose shows what she'd pick in the finished app (a clear, full-length photo, standing naturally in fitted clothes, in good light) and an example, with **Use example photo**. Remove asks first: "Remove your try-on photo? Try-on pictures you saved will stay." No camera, no photo library, no Info.plist keys and no permission prompt. The example is a sample photo of a woman standing (AI-generated, not a real person and not her) from the sample wardrobe, 9:16 on the try-on backdrop with the Simulated badge and "Example photo · Simulated" under it. Without a photo to show (`-fixtures demo:photos=drawn`) it is the backdrop with a photo symbol, as in 12b.

## Your try-on photo, her own (Phase 22a)

Where real photos are on (her own closet and every Release build, `NookServices.photos.usesSystemPicker`), the sheet has **Choose from Photos** (Change photo once she has one) instead of the example. It opens the system photo picker straight away: no permission, no Info.plist key, and the app sees only the photo she picks. A line above the points says what a good photo is ("Pick a clear, full-length photo of you standing naturally in fitted clothes, in good light."), and the note at the bottom says "The app only sees the photo you pick. It keeps its own copy on this iPhone, without the location, and nothing is uploaded." The camera for the try-on photo, with its outline and pose hints, is Phase 33b.

The photo goes through the same `PhotoIntake.keep` as a garment photo (`docs/add-a-piece.md`): `PhotoCleaner` makes an upright copy with no location or other metadata, and only that is written, to `Application Support/Photos` with Data Protection `complete`. `Profile.tryOnPhoto` points to it. Her photo shows 9:16 on the sheet, covered in the app switcher like the example ("Your try-on photo" to VoiceOver).

- **Change photo** keeps the new copy, saves the profile, then deletes the old photo's file. If the profile can't be saved, the new copy is deleted and the old photo stays.
- **Remove photo** asks first, as before, then deletes the file. Saved try-on pictures stay.
- **Delete my data** deletes the whole photo folder, and an export carries the photo (Phase 21b).

`ProfileModelTests` cover keeping, replacing and removing (the old file deleted each time), a photo that can't be kept, and a profile that can't be saved.

## Sensitive data

- **App switcher.** The Fit page, the measurement and fitting piece sheets and the example photo are covered while the scene isn't active (`hiddenWhenInactive`). Checked on the iOS 26.5 simulator by reading the app's own snapshots in `Library/SplashBoard/Snapshots` after pressing Home: the cover is what iOS keeps, in light and dark. The first try left the measurements header visible through the navigation bar's blur, so the cover now runs under the bars.
- **Logs.** Nothing here logs. `BodyMeasurements` prints as "BodyMeasurements(redacted, 3 filled in)" and has no children for `dump` or a debugger, so a later log line can't leak it by accident. A test checks this.
- **Storage.** Since Phase 21a the whole profile is kept in the real store on the iPhone (`StoredProfileStore`, one record), with Data Protection `complete`: the name on the sign, Preferences, usual fit, colours, measurements and units, fitting pieces, the try-on photo and the remembered source and occasion. The values are never logged (`Length` and `Weight` print as redacted). The debug sample closet keeps its sample profile in memory and only the name and the three Style Me settings in the store, as Stage A did in `UserDefaults` (`KeptSettingsProfileStore`, `docs/onboarding.md`). The first 21a launch moves the old suite's name and settings into the store.

## States

| Screen | Loading | Error (`stores-fail`) |
|---|---|---|
| Profile, Fit | "Opening your profile" | "Your profile didn't load" with Try again |

A setting that doesn't save shows "Couldn't save that. Try again." in its sheet, or as a toast. Everything is local, so offline doesn't apply. A fresh install (`-fixtures empty`) shows Hello on the sign, the defaults, no measurements and the example line.

## Accessibility

- The sign on Profile is one button, "Name on your sign: Lily", hint "Changes the name."
- Each measurement row reads its name, its value in words ("27.5 inches", "Not added") and a hint (Add or Edit and the name).
- Number boxes are named with their unit ("Waist in inches"). Problems are announced and focused.
- At the accessibility sizes rows put their chevron beside their icon (a `NookRow` change, see the DesignSystem README), Profile's rows take a little more width, and Fit's title steps down one style, so "measurements" no longer breaks mid-word. The feet and inches boxes stack.
- No animation of its own, so Reduce Motion has nothing to change. Dark uses the tokens.

## Tests

- `MeasurementEntryTests` (Models): numbers and decimal marks, empty means no value, units kept, ranges, feet and inches, every shown bound accepted, the region's units, conversions, each field, and measurements never printing their values.
- `ProfileModelTests`: a new name reaching Home's sign (RD-03.1), an empty name and Hello (RD-03.2), a name that breaks the rules, Preferences and repeats and usual fit, Style Me starting from the saved Preferences, a setting changed elsewhere kept, units, measurements in either unit, height, the German decimal comma, problems in her units, the store checking again, clearing, fitting pieces with Undo, the photo (removing it keeps pictures), a failing store and a fresh install.
- `ProfileSnapshotTests` (17 images): Profile in light, dark (photo added), AX5 and a fresh install; Fit in inches, centimetres in dark, AX5, empty and hidden; the name sheet with a problem; measurement sheets with problems and at AX5; the fitting piece sheet with problems; the photo sheet empty, added and asking in dark, and its example step at AX5.
- UI, `ProfileTests`: change the name and see Home's sign change, then empty it and see "no name yet"; enter a waist of 270 and see the problem, fix it to 27.5 and save, enter a height in feet and inches, pick a usual fit, and find the values again; add the example photo and remove it.

## Decisions for Jose

1. **No Confirm step on measurements.** The mockup marks each value "Entered, not confirmed" with a Confirm button, since some numbers came from Jose. In the app she types them herself, so what she saves counts as hers. The PRD's confirmation state can come back if someone else ever enters values.
2. **No "Fit notes use…" line.** The mockup's line estimates a size "around M" from height and weight, which PRD §10 rules out. Fit checks belong to the private backend (Phase 34).
3. **Preferences is on Profile** as the usual choice Style Me starts from. The mockup's Profile doesn't have it, but 10a left no other place to change the default.
4. **Weight isn't promised "never shared".** The mockup says so; DATA_MAP lets the minimum relevant fact go out in a consented request. The row says optional and approximate, and the privacy line says nothing is sent in this build.
5. **Units follow the region until she picks.** The UK gets inches and pounds.
6. **Height in inches has two boxes**, feet and inches, instead of the mockup's one box of inches.
7. **The example try-on photo shows no person,** like 12b's pictures, though the README's exception allows a generic one here. (Changed on 17 October 2026: it is now an AI-generated sample photo of a woman, from `Tests/NookTestSupport/SampleWardrobe`.)
8. **Rows stood in for 14b**, which built them (`docs/settings.md`). Styling access, Closet and suitcases and Demo controls from the mockup aren't on Profile.
9. **A fitting piece's kind is required** and starts empty, as on Add a piece.

## Left for later phases

- **14b (done):** Track laundry, Accessibility, Help, Send feedback, Privacy and terms, Delete my data (`docs/settings.md`). The default wardrobe view stays with Style Me's remembered source (Phase 13).
- **16b (done):** App tours, under Help (`docs/tours.md`).
- **21a (done):** the whole profile kept across launches in the real store, with Data Protection `complete`. A device still has to confirm the protection class on the store files.
- **22a (done):** a real try-on photo through the system picker, its metadata stripped (above).
- **33:** the image service behind its gate, and the in-app camera with its outline (33b).
- **34:** fit checks that use the pieces that fit her well (LR-12).
