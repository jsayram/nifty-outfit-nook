# Network resilience (Phase 26)

Every call the app makes to the backend has a timeout, can be cancelled, retries a bounded number of times and only when that is safe, and says plainly what went wrong. This is PRD 11.7 ("App-controlled interactive network operations have cancellation, a declared overall deadline...") and SECURITY_STANDARD 4. Her closet, looks and photos never use the network, so none of this can stop them.

24a built the client and the fake backend, and 24b added idempotency keys, App Attest and the limit errors. Phase 26 audited them against 11.7, and built what was missing. The code is in `Packages/NookKit/Sources/Networking/APIClient.swift`.

## The rules

| Rule | Value | Where |
| --- | --- | --- |
| One try is cut off after | 10 s (paid text 40 s, try-on 30 s) | `RetryPolicy.timing(for:)` |
| One call, all tries and waits together | 30 s (paid text 45 s, try-on 360 s) | same |
| Tries per call, the first included | 3 | `RetryPolicy.maxAttempts` |
| Backoff between tries | 0.4 s, 0.8 s, up to 4 s, plus up to a quarter at random | `APIClient.backoff` |
| Retried after | a timeout, a connection lost on the way, a 5xx, a 503 without Retry-After | `APIClient.send` |
| Retried after a Retry-After of 3 s or less | 429 and 503, after exactly that long; a longer one goes to the screen | same |
| Polled again, not counted as a try | 409 `action_in_progress` without an action ID, every Retry-After (1 to 10 s) until the deadline | same |
| Followed by ID, not sent again (35) | 409 `action_in_progress` with `error.actionId`: `POST /v1/actions/status` with only the ID, every 1 to 10 s (the answer says when), until the picture is there, within the paid endpoint's deadline counted from the first status ask | `APIClient.awaitAction` |
| Never retried | any other 4xx, 429 `quota_exceeded`, 503 `feature_paused`, malformed JSON | same |
| 401 | one fresh token and one more try; a second 401 ends the session | same |
| Only requests that are safe to repeat are retried | `Endpoint.idempotent`: every paid one carries its Idempotency-Key | `APIV1.swift` |

The cut-off for one try is a hard one: the request races a timer in a task group, so a server that only trickles bytes is cut off too (`URLRequest.timeoutInterval` limits silence, not slowness). Nothing is left running when the call ends, and cancelling the calling task cancels both.

A wait that can't finish before the deadline isn't started: the call gives up with the failure it already has.

The longer timings are starting values from PRD 11.6 and 9.2.4 (a paid text request waits for the server's own 30 second deadline and a little more; a try-on picture gets the proposed 360 second aggregate, each try being a short call that polls). 27a and 33a confirm them against the real endpoints.

### A timeout is not a refund, and not a second charge

A try that times out, or whose connection drops, may have reached the server. A paid request is retried with the same Idempotency-Key and a fresh App Attest assertion, so the server answers from its record: it is never run or counted twice. The same holds across a cancel: if she leaves the screen, the request stops, but a request that had reached the server stays there, and asking again with the same key gets its answer back. `PaidActionAttempt` (Models) holds that key for one action; a screen makes one per action and reuses it for every Try again. A new action, or a changed request, gets a new one (the server refuses a key reused for something else). Cancelling never implies a refund.

### 401 and signing out

A 401 means the token expired or was refused. The client asks for a fresh one and tries once more (the paid request keeps its key). If the fresh token is refused too, or can't be had, the session is over: the client signs out on this phone (`APIEvent.sessionEnded`), the screen says "Sign in to use cloud styling.", and her next cloud call doesn't reach the network at all. A hiccup getting the first token of a call (the sign-in service failing) doesn't sign her out: it is reported as unavailable.

## Offline

`PathConnectivitySource` (Networking) turns `NWPathMonitor` into a stream; `ConnectionStatus` (Features) follows it for the screens. The app starts it at the root and puts it in the environment as `\.connection`. `CloudOfflineBanner` shows "You're offline. Your closet still works on this iPhone." only where a cloud feature needs the connection, and VoiceOver says it once as it appears.

The state is a hint, not a gate. A request is still sent when the state says offline, because the system's answer can lag behind a connection that just came back, and `URLSession` fails at once when there is truly none (`waitsForConnectivity` is off). The state never blocks a local feature.

**Decision: nothing is queued while offline.** A cloud request is either paid or interactive, so a queued one could run minutes or hours later, spend her allowance when she no longer wants it, and answer a question she moved on from. PRD 11.7 asks for durable queues only for background uploads and downloads, and those belong to CloudKit and StoreKit, which keep their own lifecycle. So an offline request fails with the banner and a Retry button, her input stays where it was, and she asks again when she is back. If a connection drops in the middle of a request that is safe to repeat, the client retries it itself (up to the bounds above).

## Words and VoiceOver

`CloudProblemText` has the plain words for every network and account problem, in the same voice as 24b's `CloudLimitText`: what happened, when to try again, and that her closet still works. A paid action's problems go through `CloudLimitText`, which uses the same words for the shared cases. A failure and the "taking longer than usual" note are announced to VoiceOver as they appear.

`CloudTask` (Features) is what a screen uses to run a call: one at a time, cancelled when she leaves the screen or taps Cancel (also when the screen's model is released), "taking longer than usual, you can wait or cancel" after 10 seconds (PRD 11.7 wants a useful status by then), and a failure with its words. A cancelled call ends quietly.

## Proof

The tests don't wait on real time. `APIClient` and `CloudTask` take a clock (`ContinuousClock` in the app), and the tests hand them a `ManualClock` (`NookTestSupport`) that only moves when the test advances it, so a timeout happens because the test says so, not because a busy machine was slow. The one test that still leans on real time is the trickle case, which the 15-second answer outlasts by a wide margin.

`ResilienceTests` forces each case against the fake backend (`FakeBackendMode`, with two new modes: `connectionLost` and `actionInProgress`):

| Case | Test |
| --- | --- |
| Slow, answers in time | `aSlowAnswerWithinTheLimitStillArrives` |
| Slow past the limit | `aTryIsCutOffAtItsLimitEvenWhenTheServerIsOnlySlow` |
| Never answers | `aServerThatNeverAnswersIsTriedAgainOnlyWithinTheDeadline` |
| Backoff longer than the deadline | `aBackoffThatCannotFitTheDeadlineIsNotWaited` |
| Offline at the start | `offlineAtTheStartFailsAtOnceWithoutRetrying` |
| Offline in the middle | `aConnectionLostInTheMiddleIsTriedAgainOnceItIsBack`, `aConnectionThatStaysLostIsGivenUpOnAfterTheBoundedTries`, `aRequestThatIsNotSafeToRepeatIsNotRetriedAfterAConnectionLoss`, `aPaidRequestLostInTheMiddleRunsOnceAndIsCountedOnce` |
| 401, then a fresh token | `aRefusedTokenIsRefreshedOnceAndTheCallGoesThrough`, `aPaidRequestKeepsItsKeyThroughATokenRefresh` |
| 401, the refresh fails | `aFreshTokenThatIsRefusedAgainEndsTheSessionGracefully`, `aRefreshThatFailsEndsTheSessionGracefully`, `aHiccupGettingAFirstTokenDoesNotSignHerOut` |
| Other 4xx | `otherClientErrorsAreNeverRetried` |
| 429 with Retry-After | `aShortRetryAfterIsWaitedOutExactlyAndNotSooner`, `aRateLimitThatKeepsAnsweringIsGivenUpOnAfterTheBoundedTries`, `aLongRetryAfterIsHandedToTheScreenWithoutWaiting`, `retryAfterIsReadAsSecondsOrAsADate` |
| 500 and 503 | `serverErrorsAreRetriedWithBackoffThenGivenUpOn`, `unavailableWithoutAnyHintIsRetriedWithBackoffThenGivenUpOn`, `unavailableWithAShortRetryAfterIsWaitedOutThenGivenUpOn`, `unavailableWithALongRetryAfterIsHandedToTheScreen`, `aRequestThatIsNotSafeToRepeatIsNotRetriedAfterAServerError` |
| Malformed JSON | `malformedJSONIsReportedAndNotRetried` |
| Still running | `anActionThatIsStillRunningIsAskedAboutAgainWithTheSameKey`, `anActionThatNeverFinishesIsHandedBackAsBusyAtTheDeadline` (a 409 with no action ID, the old way) |
| Still running, by ID (35) | `ActionStatusPollTests`: `thePhotosGoUpOnceAndEveryPollCarriesOnlyTheID`, `aRelaunchAsksForTheStatusAndNeverUploadsAgain`, `anActionTheServerDoesNotKnowIsAskedTheOldWayOnce`, `aFailedPictureEndsThePollAndIsNotCounted`, `aPictureThatIsNoLongerKeptSaysItDidNotFinish`, `theStatusCallsOwnLimitIsWaitedOut`, `aPictureTakingLongerThanTheDeadlineIsPickedUpAgainByItsID` |
| Cancellation | `leavingAScreenDuringABackoffWaitStopsTheCallAndSendsNothingMore`, `cancellingARequestInFlightEndsItAtOnce`, `aCancelledPaidRequestIsNotChargedTwiceWhenAskedAgainWithItsKey` |

`CloudTaskTests`, `ConnectionStatusTests` and `CloudProblemTextTests` cover what a screen sees. The debug gateway screen (`-gateway-lab`) has the new fake modes, and `GatewayLabTests.testTheOfflineBannerAndAConnectionLostInTheMiddle` (with `-connection offline`, which fixes the state in debug builds) keeps screenshots of the banner and of a call that recovers from a dropped connection.

## Not built here

- No screen uses `CloudTask` or `CloudOfflineBanner` yet beyond the debug one: the stylist (27a) and try-on (33a) are the first. Your looks still has its own stand-in offline states.
- The try-on polling endpoint came with 33a (the same request again); Phase 35 replaced it with the status call below.
- IPv6-only networks (PRD criterion 48) and a real device in airplane mode are on the device checklist below.

## Device checklist

On an iPhone, with the real backend once it is switched on: airplane mode in the middle of a request (the banner shows, nothing is charged twice, asking again works), Wi-Fi to cellular during a request, Low Data Mode, and a network that only has IPv6 (a Mac sharing its connection with NAT64).

## Following a running action (35)

Before Phase 35 a try-on was polled by sending the same POST again: the same Idempotency-Key and the same body, up to 6 MiB of photos, with a fresh App Attest assertion. That is about 8 to 10 MB uploaded per picture on cellular data at a typical 1.2 MB body and six polls (closet `LOAD_TEST_REPORT.md`). Now:

1. The first POST uploads the photos and the server answers 409 `action_in_progress` with `error.actionId`, the ID of this key's own action.
2. The app asks `POST /v1/actions/status` with `{"actionId": ...}` (a body of about 50 bytes, 1 KiB at most) until the answer is `succeeded` (with the picture and the usage), `failed` (nothing was counted) or `expired` (made, but no longer kept). `running` says how long to wait (2 seconds for the stylist, 5 for a try-on, 60 while the outcome is being checked); the client keeps that between 1 and 10 seconds.
3. The ID is kept on the job (`AIJob.actionID`, set through `ActionLink.started`), so a late answer (the 360-second deadline) or a relaunch asks for the status and never uploads again. If the server doesn't know the ID any more (404), the client sends the request once the old way with the same key.
4. A 409 without an ID (another action of hers is running, or an older backend) is still polled by sending the request again.

`PaidActionService.run(_:idempotencyKey:link:)` carries this; the old `run(_:idempotencyKey:)` is the same with no ID. The stylist's request goes through the same code, so a late stylist answer is followed by ID too; its body is small (a closet snapshot), so its ID isn't kept across a relaunch, and a resumed stylist job sends its request once more.

**App Attest on the status call: none, on purpose.** It runs nothing paid, counts nothing and writes nothing but its own rate bucket. It needs the bearer token, and an action ID (128 random bits, never listed anywhere) that must be this account's; another account's ID and an unknown one are the same 404. What it returns is only what the same account's own paid request would. An assertion on each poll would cost a Secure Enclave signature per poll on the phone and a counter write per poll on the server, which is the cost this change removes. The status call has its own limit of 30 a minute per account (rate_limited), separate from the paid limit.

**What changed for her:** a try-on that fails is final for that tap. Before, the next poll silently started a second provider attempt (PRD 11.6 allows two); now "It didn't work this time. It wasn't counted." comes straight away and Try again is a new tap with a new key.
