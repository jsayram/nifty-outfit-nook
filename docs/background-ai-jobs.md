# Background AI jobs (Phase 27c)

Jose, 21 October 2026: "She will be able to navigate away if she clicks try on and just have her notify when it's done... any AI calls or AI stylist conversations persist if she navigates away, that way she can look and search within the app while background processes keep working."

Every paid AI action is a job in `AIJobs` (Models), one per app, held by the services, never by a screen. Style Me's outfit ideas use it now; Ask stylist's job and conversation model are ready for its screen; try-on (33a) plugs in as a third kind. Phase 27a's `StylingJobs` became this.

## A job

`AIJob` keeps: an ID, its kind (`styling`, `askStylist`, `tryOn`), its own Idempotency-Key, its state, when it was made, changed and finished, what it asked for, and a reference to its result.

| State | Means |
|---|---|
| `queued` | Waiting its turn. The server runs one paid action at a time per account, so the app does too. |
| `running` | Sent, waiting for the answer. |
| `stillRunning` | The answer didn't come back in time (Phase 26's 45-second deadline for paid text, or "still running"). The job asks again with the same key every 20 seconds. |
| `done` | The result is kept: the looks in her history (the look store, as before) and the outcome on the job. |
| `failed` | Said with the screens' words: offline, didn't finish, needs consent, a limit. |
| `cancelled` | Her Cancel. Nothing else cancels a job. |

The key is made once, when she taps, and goes with every try: the client's own retries (Phase 26), the job's later asks, and the ask after a relaunch. The server answers a repeat from its record and never runs or charges it twice (24b). What the job asked for is kept with it (the styling context and the consent version, or the Ask stylist question), and the request is built from it the same way every time, so the body matches and the server's fingerprint check passes (`aKeptJobBuildsExactlyTheSameRequest`).

A job that says `stillRunning` gives up 10 minutes after she asked and says it didn't finish. Asking again later would still be free (the server's record answers), but she gets an answer instead of a spinner.

## Where it's kept

Jobs are records of a new kind, `aiJob`, in the store on the iPhone (Phase 21a), so the schema doesn't change and older stores open as before (`thePhase21bStoreMigratesThenKeepsJobsAndConversations`). They're this iPhone's work in progress, tied to its sign-in, so an export never carries them and a restore leaves them alone (`anOlderBackupRestoresAndLeavesTheJobsAlone` with the 21b and a 21c backup, `anExportCarriesConversationsButNeverJobs`). A finished job is kept for a day, so the banner, the dot and the result survive a relaunch; its looks stay in her history for good. Delete my data stops every job first, then erases them.

The debug sample closet keeps its jobs in memory, like everything else in it.

## Relaunch

At launch and each time the app comes back to the front, `AIJobs.resume`:

- asks again, with its key, for every job that was sent (once, however long ago; the server answers a finished one from its record for free);
- sends a job that was never sent, unless she asked more than 10 minutes ago, when it says it didn't finish instead (Phase 26's rule: nothing she asked for long ago is charged by surprise);
- writes looks again that couldn't be written when the job finished (the store is locked with the iPhone, `FileProtectionType.complete`);
- tidies away finished jobs older than a day.

## Telling her

| Where she is | What happens |
|---|---|
| On the result, in the app | Nothing extra: the screen shows it. |
| Elsewhere in the app | A calm banner at the top, "Your looks are ready, Tap to see them.", over every tab, and a dot on Home (where Style Me lives) until she sees them. Tapping the banner opens Your looks on Home. A failed job's banner says "Your outfit ideas didn't finish, Tap to try again." VoiceOver reads the banner out when it appears; it grows with Dynamic Type, has a Hide button, and doesn't go away on a timer. |
| App in the background | A local notification, "Your outfit ideas are ready" / "Open Outfit Nook to see them.", if she allowed them, even when she left the app on the result's screen (she isn't looking at it). Tapping it opens the result. The app's banner also waits for her return unless the result's screen is the one she comes back to. In the app, the system banner is hidden because the app's own banner shows. The delegate uses the completion-handler methods on the main actor: the `async` form crashed on a tap in the checkpoint. |
| App closed | Nothing runs on the iPhone. The job is asked again at the next launch, and the banner and dot show. A push would need APNs (below). |

**What iOS allows in the background.** When she leaves mid-job, the app asks for a background task (`beginBackgroundTask`). iOS decides how long it lasts, usually about 30 seconds, and doesn't promise it. A job that answers in that time lands and posts its notification. After that the app is suspended: the job's request may still finish on the server, but the app only learns about it when it comes back to the front, and then shows the banner. `BGTaskScheduler` doesn't fit: a refresh task runs when iOS chooses, often hours later, and with the iPhone locked it couldn't read the store anyway. So the honest promise is: a short job tells her in the background; a longer one tells her when she opens the app, or by push once APNs is on.

**Asking for permission.** Never at launch. The first time a cloud job starts, Your looks shows a short card while it works: "Want a note when they're ready? If you leave the app, a notification can tell you when your outfit ideas are ready. It never says what's in them." Notify me shows iOS's own alert; Not now hides the card for good (kept in a `UserDefaults` suite, erased by Delete my data). If she says no, the banner still works.

**What a notification says.** Fixed words per kind of job, never a piece, a look, an occasion or anything she wrote, because it shows on the Lock Screen. Its identifier is the job's random ID.

## Push when the app is closed (designed, not switched on)

The backend records one "job done" event per paid action when the ledger first settles it, and calls a push hook. The hook is mocked: `NOOK_PUSH_MODE` off (the default) records the event only; `mock` builds the payload and logs one line with the kind of job; `apns` fails closed. The payload carries only localization keys (`JOB_DONE_STYLE_TITLE`, `JOB_DONE_BODY`) and the kind of job. Events expire after a day and go with the account. Steps to switch it on are in the backend README, "Switching on push", and need Jose: the APNs key in Apple Developer, the Push Notifications capability, the device-token endpoint, and the app's localization keys. Once push is on, the app stops posting its own notification for jobs the server pushes about, so she never gets two.

## Ask stylist conversations

`StylistThread` keeps one conversation about one look: her questions and the stylist's answers, up to 60 turns, each turn at most 2,000 characters, in the store (kind `stylistThread`), carried by an export and erased by Delete my data. `AIJobs.ask` keeps her question in the thread at once and adds the answer when the job is done, wherever she is, including after a relaunch (`aConversationKeepsHerQuestionAtOnceAndTheAnswerWhenItComes`). Only the last six turns go with a new question (27a's contract). The screen isn't built: that's a question for Jose.

## Tests

- `AIJobsTests` (ServicesTests, on the real store, with `ManualClock`): history and banner, no banner on the result, the background notification, a late answer asked for again with the same key, giving up after 10 minutes, one at a time, only Cancel stops a job, no consent means no job, a relaunch asks again with the same key, a never-sent job, looks written again after a locked store, a day's keep, Delete my data, the same request rebuilt, and Ask stylist across a relaunch.
- `AIJobsStoreTests`: relaunch, the 21b store, 21b and 21c backups both ways, export, Delete my data.
- `AIJobsResumeTests` (NetworkingTests, against the fake backend): a job resumed after a relaunch gets the server's record: one action, one job run, one use of the allowance.
- `YourLooksCloudTests`: a screen opened later shows the finished job without asking again, no banner while she waits on the screen, the leaving note and the one-time offer.
- UI: `BackgroundJobsTests` with `-cloud-stylist slow` (the fake stylist answers after 15 seconds): Style Me, then the closet and a search, the banner, and her looks; and, on full-suite runs, the notification in the background.
- Backend `tests/jobs.test.ts`: the app killed mid-job and relaunched (409 while it runs, then the record: one provider call, one charge), one event per action with nothing of hers in it, the push hook's modes, a failed job, the payload, and expiry.
