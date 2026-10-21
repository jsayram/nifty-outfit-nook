# 0006: Limits and cost protection (Phase 24b)

Status: built against mocks on 21 October 2026, like 24a ([0005](0005-gateway-and-identity.md)). The real stylist (27a) and try-on (33a) aren't built: two placeholder paid endpoints stand in for them and go through the whole admission path. Nothing here calls a provider or costs money.

The plan's bullet: "Rate limits, the atomic usage ledger, cost reservations before any paid call, and a kill switch (PRD 11.6)." Checkpoint: "limits hold under deliberate abuse in a test."

## Where the limits live

On the server, never in the app. The private backend repo (`nifty-outfit-nook-backend`) admits each paid request in one serializable Convex mutation: the App Attest counter, the idempotency key, the kill switches, a rate limit, one paid action at a time per account, the daily and 30-day allowances, the account's monthly spending guardrail, and the provider and global spending ceilings, with the worst-case cost reserved before the provider runs. Its README has the order, the commands for the switches, and what isn't built. The app only explains what the server decided.

The proposed numbers are PRD 11.6's: 5 AI actions a minute; 10 full outfit ideas and 40 swaps and questions a day. Try-on's 3 a day and 30 a month are placeholders until 33a.

## The contract (v1, additive)

| Addition | What |
|---|---|
| `GET /v1/usage` | Each allowance (used and limit today and this month, when the next one frees up) and whether each paid feature is on. No money amounts and no provider names. |
| `POST /v1/attest/challenge`, `POST /v1/attest/key` | Registers this install's App Attest key over a one-time challenge. |
| `POST /v1/style`, `POST /v1/try-on` | **Placeholders.** Paid: they need an `Idempotency-Key` and App Attest headers, and return a placeholder result with the allowance it counted against. 27a and 33a keep the paths and the admission and replace the bodies. |
| Error codes | `quota_exceeded` (429, with `category`, `resetAt` and Retry-After), `feature_paused` (503, with `feature`), `idempotency_conflict` (409), `action_in_progress` (409, Retry-After), `attestation_required` (403). Older apps treat them by their status, as the contract says. |

The copy in `NetworkingTests/Contract` was synced from the backend repo with its manifest; the golden examples for all of the above are round-tripped by `ContractTests`, and the App Attest client data has its own golden example that both sides compute.

## In the app

| Piece | Where | What it does |
|---|---|---|
| Domain types | `Models/Services/PaidActions.swift` | `PaidActionService`, `CloudUsage`, `UsageAllowance`, `PaidActionRequest`, `PaidActionReceipt`, `CloudLimitProblem` (throttled, allowance used up until a time, paused, busy, device not verified, didn't finish, or an account problem). `NookServices.paid` carries it. |
| Client | `Networking/APIClient.swift` | Paid requests send the same `Idempotency-Key` on every try and a fresh App Attest assertion each time (`RequestSigner`). A timeout or 5xx is retried with that key, so a lost answer can't run or count twice. `quota_exceeded` and `feature_paused` are never waited out; `action_in_progress` with a short Retry-After is. |
| App Attest | `Networking/Attestation/` | `DeviceAttester` with `AppAttestDeviceAttester` (Apple's `DCAppAttestService`, part of iOS) and `FakeDeviceAttester` (CryptoKit, for the simulator and tests). `AttestationSession` registers the key the first time a paid request needs it and keeps its ID in the Keychain (`WhenUnlockedThisDeviceOnly`). If the backend refuses the key, the service registers a new one and retries once, with the same idempotency key. |
| Paid service | `Networking/GatewayPaidActionService.swift` | `PaidActionService` over the gateway. |
| Fake backend | `Networking/Fake/FakeBackend+Limits.swift` | The same checks in the same order, with the backend's policy numbers: verifies the stand-in assertions with CryptoKit, keeps idempotency records, a token bucket and allowances, and has switches per feature. New modes: `answerLost` (does the work, then the answer times out) and `attestationRejected`. It counts the jobs it really ran, so tests can prove a retry wasn't run twice. |
| Messages | `Features/Shared/CloudLimits/CloudLimitText.swift` | What she reads for each limit, localized. A throttle, a used-up allowance (with "More tomorrow at 9:15 AM"), a pause, busy and a failure each read differently, and every one says her closet still works. |
| Allowance meter | `Features/Shared/CloudLimits/AllowanceMeter.swift` | "2 of 3 left today" with when one comes back, or "Taking a break right now". One VoiceOver element with the name and the full value. For the stylist and try-on screens. |
| Limits screen | `Features/Debug/LimitsLab`, `-limits-lab` | Debug builds only. The placeholder actions, the meters, Send the last one again (same key), an action whose answer is lost on the way, the fake server's kill switches, and Start over. The 24b checkpoint. |

## Decisions made inside the brief

1. **One code per kind of limit**, so the app can tell them apart (PRD 11.6 asks to distinguish throttle, exhaustion and shutdown): 24a's plan suggested `unavailable` with a feature field for the kill switch; `feature_paused` is clearer and older apps still read it as a 503.
2. **`quota_exceeded` is a 429**, not a 402: it isn't a payment request, and clients already treat 429 as "wait".
3. **The client never waits out an allowance or a pause**, only short throttles and `action_in_progress`.
4. **A paid request's retries are automatic only for timeouts and 5xx**, always with the same key. A new tap makes a new key; the debug screen's Send again is the one place that reuses one on purpose.
5. **Simulators get no paid access on the real backend.** They can't attest, and the backend's mock mode is for local and dev deployments only. A bounded fallback for devices that can't attest (PRD 11.6) is a later decision.
6. **The meters and messages aren't on any shipping screen yet.** The stylist and try-on screens that need them come in 27a and 33a; showing allowances in Settings (PRD 11.6: disclose the limits) waits until the numbers are approved.

## Device checklist (needs a real iPhone and Jose)

1. Apple Developer: turn on **App Attest** for the App ID, and add the `com.apple.developer.devicecheck.appattest-environment` entitlement (`development` for now) to the app target. Not in this change: it needs the portal first.
2. Backend: build the Apple attestation check (the steps are in the backend README, "App Attest"), test it with a real attestation from Lily's iPhone 12 or Jose's iPhone, then set `NOOK_APP_ATTEST_MODE=apple` and `NOOK_APP_ID` on the dev deployment.
3. On the device with the real backend configured: `-limits-lab`, one paid action, then check that the assertion counter goes up on each request and that a reinstall registers a new key.
4. Confirm `DCAppAttestService.isSupported` on her iPhone 12 (A14, so expected to be true).

## Tests

- `NetworkingTests/PaidActionTests`: a paid action runs once and is counted; a lost answer is retried with the same key and the fake ran it once; the same key again is answered from the record, and with another request it's refused; a burst is throttled; a used-up allowance says when it comes back; the kill switch pauses one feature only; a refused key is registered again once; a device that can't attest gets no paid access; no assertion is refused; failures map to what the screen needs.
- `NetworkingTests/AttestationTests`: the client data matches the contract's example, the stand-in assertions are shaped like Apple's and count up, and the CBOR reader refuses what it doesn't know.
- `ContractTests`: the new golden examples round-trip, paid endpoints match the contract, limit errors carry what the app explains.
- `FeaturesTests/CloudLimitTextTests` and `LimitsLabModelTests`.
- UI test `LimitsLabTests`, with screenshots: the rate limit, the try-on allowance used up, the kill switch, the same key not counted twice, and a lost answer retried.
- The backend's own tests (60, including on a real local Convex backend) cover what the fake can't: serializable admission, reservations and settlement, ceilings and alerts, and the WebCrypto assertion check.
