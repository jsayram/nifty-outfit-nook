# 0005: Gateway and identity (Phase 24a)

Status: built against mocks on 21 October 2026. Switching to the real Clerk and Convex services is configuration ([backend-switch.md](../backend-switch.md)), after the open points at the end.

Jose's direction, 21 October 2026: "build it all out with mock responses and data... then we can talk to the real deal when all is ready, it'd be just a switch."

## What was built

| Piece | Where | What it does |
|---|---|---|
| Contract types | `Networking/APIV1.swift` | Swift `Codable` types for v1 of the API: `GET /v1/health`, `POST /v1/session`, `GET /v1/me`, the error envelope and its 13 codes. |
| Network client | `Networking/APIClient.swift` | `URLSession` with an ephemeral configuration (no disk cache, no cookies, TLS 1.2 or later). Adds the bearer token, refreshes it once after any 401, retries safe calls after a timeout or 5xx with backoff (3 tries), waits out a 429 or 503 whose Retry-After is 3 seconds or less, and maps everything else to `APIFailure`. Cancellation stops a call at once. |
| Account service | `Networking/GatewayAccountService.swift` | `AccountService` (Models): sign in (Apple, then `POST /v1/session`), who am I, sign out. Screens only ever see `AccountProblem`. |
| Fake sign-in | `Networking/Fake/FakeAuthProvider.swift` | The default `AuthProvider`: a pretend Sign in with Apple and tokens that expire after 60 seconds, like Clerk's. Nothing stored, nothing sent. |
| Fake backend | `Networking/Fake/FakeBackend*.swift` | An in-process server behind a `URLProtocol`, built from the same contract types and making the real gateway's checks. Modes: normal, slow, timeout, expired token, 403, 429 with Retry-After, 500, 503, malformed JSON and offline, each for a set number of requests or until changed. |
| Clerk | `ClerkAuth/ClerkAuthProvider.swift` | `AuthProvider` over `ClerkKit`: Sign in with Apple with no name or email requested (D6), tokens from the JWT template `convex`, telemetry off. Created only when the app has a publishable key. |
| Switch | `Networking/GatewaySettings.swift`, `NiftyOutfitNook/AppGateway.swift` | Reads `NookClerkPublishableKey` and `NookAPIBaseURL` from Info.plist (build settings from the ignored `Configs/Secrets.xcconfig`). Both valid: Clerk and the real backend. Either missing: the fakes. A Clerk secret key (`sk_`) is never accepted. |
| Gateway screen | `Features/Debug/GatewayLab` | Debug builds only, `-gateway-lab`. Sign in, Who am I?, Sign out, the fake backend's modes, and what each call did. The Phase 24a checkpoint. |

`NookServices.account` carries the account service. Nothing in the app uses it yet besides the gateway screen; her closet works the same signed out, offline or with the backend down.

## The contract

One source of truth: `contract/v1/contract.json` and its golden examples in the private backend repo (`nifty-outfit-nook-backend`). `Packages/NookKit/Tests/NetworkingTests/Contract` is a byte-identical copy made by the backend's `scripts/sync-contract.mjs`, with a SHA-256 manifest. The API's shape isn't secret (anyone can watch the app's traffic), so the copy can live in this public repo; the backend's code can't.

Both sides test against the same files:

- Here, `ContractTests` checks the manifest (a hand edit fails), that the endpoints, error codes, statuses, version and body limit match `contract.json`, and that every golden example decodes and re-encodes to the same JSON. `FakeBackendContractTests` sends the contract's invalid examples to the fake and expects the same `invalid_request` the real gateway gives.
- In the backend repo, the gateway validates requests with the schemas in `contract.json`, and its tests check every response against them.

No endpoint, schema or field names an AI provider or model; a backend test enforces it. Later endpoints ask the backend to do a job (to style) and the backend picks the provider.

What later phases add to the contract (in `contract.json` under `planned`, not built): 24b rate limits on every endpoint, a quota error and kill switches; 24c `DELETE /v1/account` with a deletion status; 24d `POST /v1/feedback`; 27a `POST /v1/style` with App Attest assertions (the `X-Nook-Assertion` header is reserved).

## clerk-ios, vetted for decision D2

Approved by Jose as D2 on 19 October 2026 (closet `THREAT_MODEL.md`): `ClerkKit` only, pinned exactly, after checking its Keychain settings and what `Package.resolved` pulls in. Checked on 21 October 2026:

| Question | Answer |
|---|---|
| Version | 1.6.1 (7 October 2026), pinned with `exact:` in `Package.swift`. |
| Maintainer and use | Clerk, Inc., the sign-in provider itself. About 100 GitHub stars; last push 20 October 2026. |
| License | MIT. |
| What we use | The `ClerkKit` product only, in the `ClerkAuth` target only. Its target has no dependencies. |
| What `Package.resolved` gains | `clerk-ios` 1.6.1, plus `Nuke` 13.2.0 and `PhoneNumberKit` 5.0.12, which only `ClerkKitUI` uses. SwiftPM resolves them but never builds them: the built app has no Nuke or PhoneNumberKit code or bundles (checked in the Debug build). Clerk's test-only packages (Mocker, swift-concurrency-extras) aren't resolved. |
| What ships | ClerkKit's code and its `Clerk_ClerkKit.bundle` (translations and a privacy manifest declaring UserDefaults access, reason CA92.1, and no tracking). |
| Network | Clerk's Frontend API for the instance in the publishable key. Telemetry is on by default; we turn it off (`telemetryEnabled: false`). |
| Keychain | Clerk keeps its session in the Keychain with **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`**, set in `SystemKeychain.swift` and not configurable. SECURITY_STANDARD.md §4 asks for `WhenUnlockedThisDeviceOnly` or stricter. **Open: needs Jose's written exception, or a different approach, before the Clerk path is switched on.** |
| Inactive until | A publishable key and the backend URL are both set. Without them, `ClerkAuthProvider` is compiled in but never created, and Clerk is never configured. |

## Decisions made inside Jose's direction

1. The contract lives in the backend repo and is copied here with a checked manifest (above).
2. `POST /v1/session` creates the account and records a sign-in; `GET /v1/me` only reads, and answers `not_registered` before the first session. The client registers then, since registering is safe to repeat.
3. The app sees a pseudonymous `usr_` ID made by the backend, never the Clerk user ID, the issuer or an email.
4. Any 401 gets one fresh token and one retry, whether the code is `token_expired` or `unauthenticated`; a second 401 means signed out.
5. Retry-After of 3 seconds or less is waited out; longer is shown ("Try again in 30 seconds") and Who am I? waits.
6. The real sign-in screens aren't built: they need a design and Lily's review. The gateway screen is debug-only.

## Open points

1. The Clerk Keychain accessibility class (above).
2. 24a's plan bullets also name device attestation (App Attest) and the consent switch in Privacy and terms. Neither is built: attestation belongs with the first paid endpoint, and there's nothing for a consent switch to control yet.
3. How long a Clerk session token lives with the `convex` template (Clerk's default is 60 seconds), and whether Clerk's dashboard needs an email for Apple sign-ups, to check when Jose sets up the instance.
