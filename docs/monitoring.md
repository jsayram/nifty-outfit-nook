# Monitoring and crash reports (Phase 31)

No third-party crash or analytics library is in the app, and none was added. The app uses
Apple's own MetricKit, which is part of iOS.

## What the phone keeps

MetricKit hands the app crash, hang and speed reports about once a day (crashes and hangs at the
next launch). `MetricKitCollector` (Services) receives them and gives the raw JSON to
`MetricKitParser` (Models), which keeps only fixed fields and drops the rest before anything is
stored:

- Events (`DiagnosticRecord`): the kind (crash, hang, CPU exception, disk-write exception, slow
  launch), the report's date, the app version and build, the iOS version, the device model, a
  crash's exception and signal as fixed names, and a hang or launch time.
- Daily samples (`MetricSample`): a typical launch time, peak memory, and counts of memory and
  watchdog exits.

Never kept: call stacks, library or file names, addresses, the region setting, process IDs, the
bundle ID, exception text, termination reasons. Version strings must match a pattern or they are
dropped too.

`DiagnosticsLog` keeps them in `Application Support/Diagnostics/reports.json`: 30 days, at most
200 events and 60 samples, left out of device backups, file protection
`completeUntilFirstUserAuthentication` (reports can arrive while the phone is locked, and the file
holds nothing about her). Delete my data empties it (with the unsent work), and so does deleting the
app.

## Sharing, only with her approval

On Send feedback, signed in, a switch "Share crash and speed details" appears when the phone has
something to share. It is off for every note and isn't kept in the draft. Turning it on adds a few
plain lines to the preview (counts, timings and fixed names), exactly what is sent in the note's
`deviceHealth` field (contract `FeedbackDeviceHealth`). A test checks that every value in the request
is on the page. Signed out, the share sheet never carries it.

Apple's own route needs nothing from the app: with Settings, Privacy & Security, Analytics &
Improvements, Share With App Developers on, crash reports reach Xcode Organizer and TestFlight.

## Debug

Debug builds only: launch with `-diagnostics-lab` for a screen that shows the kept events and
samples, the summary a note would carry, and buttons to add sample reports (with text planted in
them that must not be kept) or clear everything. `-diagnostics-sample-reports` starts the normal app
with sample reports, for UI tests. Both keep their reports in a temporary folder.

## Not verified

No real device report has been parsed: the simulator delivers none. The parser follows the key
names of Apple's `jsonRepresentation()` output and reads loosely (unknown keys ignored, odd values
skipped). On a device, Xcode's Debug, Simulate MetricKit Payloads sends sample reports; check one
there before relying on the numbers.

`MXMetricManager` is marked "to be deprecated" in the iOS 27 SDK in favour of `MetricManager`
(iOS 27 and later). It builds with no warning and works on iOS 26 and 27. Moving to the new API
is a later change.
