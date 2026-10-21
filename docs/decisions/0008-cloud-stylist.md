# 0008: Cloud stylist (Phase 27a)

21 October 2026. Built against the fake backend; the real provider is a server switch away.

## What the app does

- **The stylist is the server's choice.** Style Me asks `POST /v1/style` for an outfit. The app never names a provider or a model; the backend picks them from its own configuration (Haiku 5.5 today, THREAT_MODEL D5), so a model change or a backup provider needs no app release. A new recipient does need new consent text, and so an app update.
- **What leaves the phone** (`StyleCall`, `APIV1.StylistPiece`): the pieces she can use today in the chosen source, at most 150, as plain descriptors (category, kind, colours, colour note, fit, dressiness, warmth, her name and up to three other names); the occasion and an Other occasion's words; indoors or Phase 29's `WeatherSummary`; today's comfort or her usual fit; a colour wish; whether one new-piece idea is allowed; the starting piece; and main-piece combinations to avoid. Never photos, notes, brands, sizes, wear dates, measurements, weight, her name or a location. A test checks the keys.
- **Consent first.** `CloudStylist` sends nothing until she agreed to the consent text (`StylistConsent`, version `stylist-1`, version A of `closet/compliance/IN_APP_PRIVACY_TEXT.md`). Without it Your looks says "Style Me needs your OK to send your request to Anthropic. You can still make your own looks." with Review, which opens the sheet. Privacy and terms gets a switch, Style Me, swaps and Ask stylist, once the cloud stylist is on; off withdraws at once. The request carries the version; the backend refuses one that doesn't cover its provider (`consent_required`). Delete my data erases the consent.
- **From your history (FR-58).** Before a paid request, Your looks looks for an earlier cloud result with the same `StyleIntent` (source, occasion, starting piece, colour wish, whether an idea is allowed, and the weather as a temperature band and wet or dry, indoors or ignored) whose every piece she can still use today and whose main pieces weren't shown already. It shows that result with "From your history: it still fits today's request, so nothing was used." and New ideas in place of Try a different outfit. Free text (an Other occasion's words) and today's comfort never make an exact match, as PRD 11.11 asks; nor does unread weather. The intent is kept on the look (`Look.intent`), never the request's words.
- **The answer.** Looks reference only the IDs that were sent (anything else is "didn't finish"), with the stylist's one-line reason as `Look.why`, shown under the look while it is as the stylist made it. An answer the server gave again from its 24-hour cache says so ("You asked for the same thing earlier today…"). Limits use 24b's words; a provider failure is 26's calm "Styling didn't finish" with Try again; each tap is a new idempotency key, and the client's own retries reuse it.

## Not tied to a screen

Jose, 21 October 2026: AI work keeps going when she leaves the screen. A cloud request runs in `StylingJobs`, an app-level owner held by the services, not by Your looks. Leaving Your looks (another tab, browsing, searching) doesn't stop it; the job keeps its looks in her history (the look store, unsaved, like every result) and marks a suitcase used, whether or not a screen still waits. If she comes back to the same Your looks, it shows them; a new Style me with the same choices finds them through From your history. Only her Cancel stops a request. Stage A's stylist on the phone keeps the old rule (leaving stops it), since it costs nothing and its UI tests depend on it. Not built yet, for the background AI jobs phase: a persisted job list, resuming after a relaunch, an in-app "your looks are ready" banner and local notifications. Phase 26's screen-scoped `CloudTask` is deliberately not used for stylist calls.

## Switching it on

The cloud stylist runs whenever the real services are configured (`docs/backend-switch.md`). In debug builds, `-cloud-stylist` (or `-cloud-stylist fails`) runs it against the in-process fake backend, signed in with the fake Apple sign-in. Otherwise Style Me keeps Stage A's stylist on the phone, which sends nothing, and none of the above shows.

## Not built

- **Ask stylist's screen.** The contract, the backend and `StyleCall.question` support a question about a look with up to six earlier turns, but the sheet on Your looks is still the stand-in.
- **Ideas for an empty closet** (PRD 8.1): still Add a piece, pending Jose's decision.
- **Swaps** stay on the phone with stored facts (Phase 11); the contract has no swap mode.

## Tests

`CloudStylistTests` (Networking, with the fake backend), `CloudStylingTests` (Models: the request, the answer, history), `YourLooksCloudTests` (Features), contract round trips for the new examples, and the UI test `CloudStylistTests` (consent, looks with a why line, the same request from history, Not now, a failing provider).
