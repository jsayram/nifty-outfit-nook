# Payments: the styling subscription, the complimentary unlock and picture credits (Phases 30a to 30c)

Status: built 22 October 2026 against Xcode's local StoreKit testing. The real products need App Store Connect, which is Jose's job (steps below). 30b added the complimentary unlock (an offer code) and picture packs. 30c made the server the authority: it verifies Apple's signature on every purchase, follows App Store Server Notifications (renewals, expiry, grace periods, refunds, revocations), and decides styling access and picture credits itself.

Spec: PRD §14 (one monthly auto-renewable subscription, a free first month for eligible users, Restore, Manage subscription, terms and privacy links, closet always free), the paywall and access mockups (`paywall.html`, `access.html`), `closet/compliance/IN_APP_PRIVACY_TEXT.md` "Phase 30a: before paying", and App Review Guideline 3.1.2.

## What's where

| File | Holds |
|---|---|
| `Models/Services/Subscriptions.swift` | `SubscriptionStatus` (none, trial, active, grace period, billing retry, expired, revoked) and its access rules, `SubscriptionOffer`, `SubscriptionService`, the cache protocol, `TryOnAllowance`, `StylingAllowances` (placeholder numbers), `EntitlementHint` |
| `Services/Store/StoreKitSubscriptionService.swift` | StoreKit 2: status, `Transaction.updates` listener, purchase, restore, offer |
| `Services/Store/DefaultsSubscriptionStatusCache.swift` | The last status in `UserDefaults` (state, product ID, dates; no transaction IDs) |
| `Fixtures/Providers/ScriptedSubscriptionService.swift` | A scripted subscription for tests and `-subscription <state>` debug launches |
| `Features/Subscription/` | Styling access: the paywall and status screen, its model and words |
| `Networking/EntitlementHint.swift` | The `X-Nook-Entitlement-Hint` header on paid requests |
| `NiftyOutfitNook/AppSubscriptions.swift` | The one service for the app, started at launch |
| `NiftyOutfitNookTests/` | The hosted unit tests (`SKTestSession`) and `NiftyOutfitNook.storekit` |
| `Models/Services/Credits.swift` | 30b: `CreditPacks` (product IDs, PLACEHOLDER sizes), `CreditsService`, `CreditClaiming`, `TryOnFunding` (the month's pictures first, then credits) |
| `Services/Store/StoreKitCreditsService.swift` | 30b: packs through StoreKit: purchase, claim, then `finish()`; recovery of unfinished packs; its own `Transaction.updates` listener |
| `Networking/GatewayCreditClaimer.swift`, `APIV1+Credits.swift`, `Fake/FakeBackend+Credits.swift` | 30b: POST /v1/credits/claim, its bodies, and the fake backend's side |
| `Fixtures/Providers/ScriptedCreditsService.swift` | 30b: scripted packs for tests and `-subscription` debug launches |
| `Models/Services/PurchaseClaims.swift` | 30c: `StylingAccessClaiming` (POST /v1/entitlements/claim) and `PurchaseAccountToken` (the account's `appAccountToken`) |
| `Networking/GatewayCreditClaimer.swift`, `Fake/FakeBackend+Credits.swift` | 30c: also the styling-access claim, and the fake's side of it |

## Products

| What | Value | Decided by |
|---|---|---|
| Subscription group | Styling | 30a (PLACEHOLDER name, Jose can rename) |
| Product ID | `com.jsayram.niftyoutfitnook.styling.monthly` | 30a. Must match App Store Connect exactly. Can't be reused once created |
| Period | 1 month, auto-renewing | PRD §14 |
| Price | US$9.99 a month | **PLACEHOLDER**: PRD §14 calls US$9.99 "a candidate, not a final price" |
| Introductory offer | Free trial, 1 month, new subscribers only | PRD §14.1 |
| Allowances shown | Style Me 10 a day, swaps and Ask stylist 40 a day, try-on pictures 30 a month | **PLACEHOLDER**: 24b's development values (decision D12). The server enforces its own numbers |
| Family Sharing | Off | **PLACEHOLDER**, a question for Jose |
| Billing grace period | The app handles it on or off | Set in App Store Connect (step 8) |
| Complimentary unlock | Non-consumable `com.jsayram.niftyoutfitnook.styling.complimentary`, styling access with no end and no renewal, given only with free one-time offer codes | PRD 14.2. **PLACEHOLDER** price US$49.99 (App Store Connect needs one; nobody buys it in the app) |
| Picture packs | Consumables `com.jsayram.niftyoutfitnook.pictures.small` (10 pictures, US$2.99) and `.pictures.large` (30 pictures, US$6.99) | PRD 14.4. **PLACEHOLDER** sizes and prices. The sizes also live in the backend's `convex/credits.ts`, which is what credits them |

The app never types a price or a date: the price, period and trial come from StoreKit (`Product.displayPrice`, `subscriptionPeriod`, `introductoryOffer`), and the free month shows only when `isEligibleForIntroOffer` is true. Someone who had the free month before sees "$9.99 a month. Charged today..." instead.

## Access rules

- **Access** (`hasStylingAccess(at:)`): a verified trial or paid month until its expiry date, and Apple's billing grace period until it ends. Billing retry without grace, expired, revoked and none give nothing. PRD §14.3.
- **Stale data**: the cache only lets the app show something before StoreKit answers. A cached status never grants past the dates Apple gave: a free month that has ended reads as expired until StoreKit says it renewed. Unverified transactions are finished and never granted.
- **After a purchase** StoreKit's status can lag a few hundred milliseconds. The status comes from the purchased transaction itself, and an empty answer from StoreKit within 60 seconds of a purchase doesn't erase it (still bounded by its own dates).
- **Not proof**: the server is the authority (SECURITY_STANDARD §8). Paid requests carry `X-Nook-Entitlement-Hint` (none, trial, active, grace, billing-retry, expired, revoked), worked out when each request is sent. The contract says it's a hint; neither the fake nor the real backend admits or refuses anything because of it.

## The server's record (30c)

- **Verified on the server**: every signed transaction the app sends, and every App Store Server Notification, is checked against Apple's certificate chain up to the pinned Apple Root CA - G3, then for this app's bundle ID and the deployment's environment (production takes production purchases, dev takes sandbox ones). The backend uses no library for it (backend README, "App Store purchases").
- **Linking purchases to her account**: the server gives each account a random `appAccountToken` (in `POST /v1/session` and `GET /v1/me`). `GatewayAccountService` hands it to `PurchaseAccountToken`, and every StoreKit purchase (the subscription and the packs) carries it, so Apple's notifications name the account. Sign-out and deletion clear it. Offer codes can't carry it, so every status read sends the subscription's and the unlock's current signed transactions to `POST /v1/entitlements/claim`, once per launch each. That's also how a purchase made signed out reaches the account. A purchase another account already claimed is refused.
- **Access on the server**: from Apple's dates when asked: the unlock until refunded or revoked, the subscription (free month included) until it expires, then through Apple's billing grace period. A refund, a Family Sharing revocation, the end of grace or expiry ends it even if a notification is late. Style Me and try-on without access get `entitlement_required` (403); this app reads it as "This account can't do that." for now, since Style Me doesn't check styling access itself yet (a question below).
- **Credits on the server**: a ledger that only grows: a grant per pack (from the app's claim, or from Apple's ONE_TIME_CHARGE notification), one spend per try-on picture (never twice for the same request), the picture back when it fails, and a refund taking the pack back. If some were already spent, the balance stops at zero and the rest is recorded as owing, never charged and never taken from a later pack. Try-on uses the month's included pictures first (with styling access), then a credit; credits work without a subscription.
- **Listener**: `AppSubscriptions.service` starts `Transaction.updates` at launch, finishes every transaction, reads the status again and tells every screen that's listening (refunds, renewals, approved Ask to Buy, purchases on another device).

## The complimentary unlock (30b)

- **What it is** (PRD 14.2): a separate non-consumable that gives styling access with no end date and no billing. Jose gives it with one-time free offer codes from App Store Connect. A code is a bearer credential until it's redeemed, so send each one privately. No family password, no code system of our own.
- **Redeeming**: Styling access → Redeem a code opens Apple's own sheet (`offerCodeRedemption`; Apple doesn't allow a custom one). On iOS 27 the sheet returns the transaction; on iOS 26 it arrives through `Transaction.updates`. Either way `redeemedOfferCode()` finishes it and reads the status again, and the screen says "Your code is redeemed. Styling access is on." when the unlock shows up, even if it comes a moment later.
- **The status**: `SubscriptionStatus.complimentarySince`, read from `Transaction.currentEntitlements(for:)`, which leaves out anything Apple refunded or revoked. It gives access on top of whatever the subscription says, never stretches a subscription's dates, and the hint on paid requests says `complimentary`.
- **With a subscription**: redeeming doesn't cancel a subscription that still renews or refund it. The screen says so and keeps Manage subscription (PRD 14.2).
- **Lily's sponsored policy** (PRD 14.4: no public allowances for her, an owner-funded budget): 30c built a server-side plan override that only an admin can set, and gave it to nobody. It waits on Jose's confirmation of her account and budget; until then the unlock gives her the public allowances.

## Picture credits (30b)

- **Buying**: Styling access shows "Extra try-on pictures" with one button per pack ("10 pictures, $2.99", price from StoreKit) only once try-on pictures cost something (`tryOnIsSimulated` false, Phase 33) and the server has said her balance. Until then the packs stay hidden, so Lily's TestFlight doesn't change.
- **Crediting**: after Apple's sheet, the app sends the transaction's signed JWS to `POST /v1/credits/claim` and calls `finish()` only after the server answers 200. The server reads the transaction ID and product from the JWS (never from the app), credits the pack size from its own list, and credits each transaction ID once: a repeat from the same account gets the first grant back (`replayed`), another account gets `forbidden`.
- **Never lost**: if the claim fails for any reason (offline, signed out, server busy or refusing), the transaction stays unfinished. The app claims it again at launch (`recoverUnfinished()` in `AppSubscriptions.follow()`), when Styling access opens, and when StoreKit re-sends it through `Transaction.updates`. The subscription's listener leaves consumables alone for this. An unverified transaction is never claimed or finished.
- **Verified since 30c**: the backend checks Apple's signature before crediting (`NOOK_APPSTORE_MODE=apple`, or `test` with a test root on local and test deployments). With the checks off the endpoint answers `unavailable` and the app keeps the purchase open. A purchase Apple refunded is `forbidden`.
- **Balance**: `GET /v1/usage` carries `credits.pictures`. Styling access shows "Picture credits: 12 left" next to the try-on allowance. Credits don't expire and work without a subscription (PRD 14.4, Guideline 3.1.1).
- **Spending order** (PRD 14.4): a try-on picture uses the month's included pictures first, then a credit (`TryOnFunding`). The try-on sheet says which before she taps, and offers nothing once both are used. The gateway enforces it in 30c; until Phase 33 pictures are simulated and free.
- **Recovery across devices**: the balance belongs to her signed-in account on the server, so a reinstall or a new iPhone shows the same balance after sign-in. Restore purchases can't rebuild consumables (Apple doesn't restore them), which is why the server keeps the ledger.

## Where it shows

- **Profile → Styling access** (under the name, as in `settings.html`): the status, the offer when she has no access, what's included, what's always free, Restore purchases, Manage subscription (Apple's `manageSubscriptionsSheet`) once there's a subscription, Terms of use and Privacy policy (the website pages, placeholders until 35b).
- **Try it on**: simulated pictures stay free ("Simulated pictures are free in this test build"). When the image service is real (`NookServices.tryOnIsSimulated = false`, Phase 33), a picture says it uses 1 of the month's pictures, or, without access, "Try-on pictures come with styling access" with See styling access, and Make a picture isn't offered.
- **Help → Free and paid** (Good to know): what's always free and what uses styling access, and where to manage it; the second line changes when she has access.
- **Delete my account**: the "doesn't cancel your subscription" note and a Manage subscription row show only while a subscription may still bill her (trial, active, grace period, billing retry).

## Why a custom paywall, not `SubscriptionStoreView`

`SubscriptionStoreView` shows Apple's own layout for the product and handles the trial wording, Restore and policies. It was not used because: the PRD and mockup need the allowances, what stays free and the first charge date in the app's plain words and soft design; the try-on sheet, Profile and Help share the same status; and snapshot and UI tests must draw it from a fake, which `SubscriptionStoreView` can't (it needs StoreKit, and package tests have no app). The App Store's own sheet still confirms every purchase, and Manage subscription is Apple's sheet. Guideline 3.1.2 is followed by the page itself: price and period from StoreKit, the free month and when the first charge comes, that it renews until cancelled, how to cancel (a day before, Settings → name → Subscriptions), Restore purchases, terms and privacy links. No countdowns, no pre-ticked choices, Not now always available.

## Testing

- **Hosted unit tests** (`NiftyOutfitNookTests/SubscriptionStoreKitTests.swift`): StoreKit's test sessions refuse to run in a package test bundle, so they live in a small unit-test target hosted in the app. Eleven tests: the offer, purchase (free month), access ending at Apple's date with an injected clock, a forced renewal, expiry, a refund through the `Transaction.updates` listener, a grace period, billing retry, restore on a fresh install, Ask to Buy approved, and the checkpoint (purchase, a renewal StoreKit makes by itself with a month every 30 seconds, restore, expiry). Restore in tests skips `AppStore.sync()`, which shows Apple's sign-in prompt; a test must never sign in.
- **Not on hosted CI; on the Mac's gate since 22 October 2026.** On the iOS 27.0 simulator StoreKit's test environment serves no products to the host app (`SKInternalErrorDomain` 17 on every session call), although the app is signed with `get-task-allow` (PR #91 printed the entitlements from the running app). It does the same on the Mac, so it is the iOS 27.0 simulator, not the hosted runner. The suites are disabled when `NOOK_CI` is set, unless `NOOK_STOREKIT=1` is set too; two small checks (the host's `get-task-allow` and the configuration file in the bundle) run everywhere. When the gate runs on the self-hosted runner it runs the suites on an iOS 26.5 simulator of its own (README, "CI"). `checkpointPurchaseRenewRestoreExpire` is left out of the gate (it needs 95 seconds or more of StoreKit's sped-up clock and misses its two-minute limit on a busy Mac); run it by hand.
- **Why the suites were flaky under load (22 October 2026, found on a busy Mac, load average 300 to 900).** Three causes, all fixed except the last. (1) `Transaction.updates` was iterated inside a utility-priority task, which can start late on a busy machine, and an update that arrived before the first `next()` was never delivered. The listener test then waited forever (its `for await` had no limit) until the suite's two-minute limit killed the test host. `start()` in both services now makes the iterator before it starts the task, and the tests wait with a limit (`StoreKitWaits`) and report what they heard. (2) The app itself, hosting the tests, started its own `Transaction.updates` listener and ran `follow()` (which recovers unfinished packs against the real gateway) at launch, beside the tests' own StoreKit use. Neither runs inside hosted tests now (`AppSubscriptions`), as the packs listener already didn't. With (1) and (2) fixed, 19 of 20 tests passed in 37 seconds at a load average near 900, twice in a row, where before one to four tests a run hung for two minutes. (3) The listener test read `Transaction.unfinished` after a second or more, and the test environment drops an unfinished consumable by then (finding 1 below), so it now takes StoreKit's signed transaction right after the purchase. The checkpoint test is still sensitive to load and stays out of the gate.
- **Debug builds have `get-task-allow`** (`Configs/*-Debug.entitlements`): StoreKit's local testing on the simulator refuses an app without it ("not installed for development"). Release builds use the entitlements files without it, and `scripts/check-archive.sh` still checks them.
- **30b hosted tests** (`NiftyOutfitNookTests/CreditsStoreKitTests.swift`, nested in the 30a suite so they never run at the same time as it): the offer code redemption (`SKTestSession.buyProduct` with `.codeOffer(referenceName:)`) turning on complimentary access and surviving a reinstall, a refunded unlock giving nothing, the unlock beside a renewing subscription, the packs and prices, a pack purchase credited then finished, a pack the server couldn't credit recovered at the next launch, a pack claimed twice credited once, the subscription listener leaving packs alone, and the packs listener crediting a pack bought elsewhere. The server side is a small ledger in the test that reads StoreKit's real JWS the way the backend does. Same CI gating as 30a.
- **Two StoreKit testing findings (30b)**: (1) Xcode's StoreKit test environment on the iOS 26.5 simulator drops an unfinished consumable from `Transaction.unfinished` about a second after first listing it, though no code calls `finish()` (every call was instrumented). So the recovery tests pass StoreKit's own signed transaction through a seam (`StoreKitCreditsService(unfinished:)`). (2) Without `SKIncludeConsumableInAppPurchaseHistory` (now in `Configs/AppInfo.plist`) `Transaction.latest(for:)` loses a consumable too. Also, `.codeOffer(referenceName:)` on a non-consumable with no code offer in the configuration still buys it, but the transaction carries no `.code` offer, so the tests check the entitlement, not the offer type. And the app's own packs listener doesn't start while the hosted tests run (`XCTestConfigurationFilePath`), or it would claim the tests' purchases.
- **Package tests**: the access rules (`SubscriptionStatusTests`), the hint header (`PaidActionTests`), the screen's model, Profile, Help, try-on and Delete my account (`StylingAccessModelTests`), and the paywall snapshots (`StylingAccessSnapshotTests`).
- **UI test**: `StylingAccessTests` (scripted subscription). It runs in the `ui-audit-and-settings` part of the UI batch in `.github/workflows/ci.yml` (and `ui-rest` skips it).
- **By hand in Xcode**: Run uses `NiftyOutfitNookTests/NiftyOutfitNook.storekit` (the scheme's StoreKit configuration). Debug → StoreKit → Manage Transactions shows, refunds and expires purchases; Editor → Subscription Renewal Rate speeds up renewals.
- **Debug launches**: `-subscription none|trial|active|grace|retry|expired|revoked|used-trial|complimentary` uses a scripted subscription (and scripted packs) with no StoreKit at all. Redeem a code there always gives the unlock.
- **30b package tests**: `SubscriptionStatusTests` (the unlock's access and hint, an old cache still decoding, the spending order), `CreditClaimTests` (the fake backend credits once, refuses another account, sizes from its own list, unavailable while off), the contract's new examples, `StylingAccessModelTests` (redeeming, a late redemption, the unlock beside a subscription, packs shown only when sold, buying, Profile's value, try-on's month-then-credits) and the snapshot `complimentary-credits-packs`. Backend: `tests/credits.test.ts` plus the cross-user and deletion cases.

## App Store Connect setup (Jose)

Do these before a TestFlight build can sell anything. Sandbox and TestFlight purchases are free.

1. **Agreements**: App Store Connect → Business → accept the Paid Apps Agreement, and fill in banking and tax. Products can't be fetched until it's active.
2. **Group**: My Apps → Nifty Outfit Nook → Monetization → Subscriptions → create a subscription group named `Styling`. Add a group display name (shown in Settings → Subscriptions), for example "Nifty Outfit Nook styling".
3. **Subscription**: in the group, create a subscription with Reference Name `Styling monthly` and Product ID `com.jsayram.niftyoutfitnook.styling.monthly` (exactly; it can't be changed or reused). Duration 1 month.
4. **Price**: Subscription Prices → add the price (US$9.99 is the placeholder; pick the final one) and let App Store Connect fill other storefronts, or set them by hand.
5. **Free month**: Subscription Prices → Introductory Offers → create → all territories → Free → duration 1 month. Leave it open-ended.
6. **Localization**: Display Name "Styling, monthly" (or the final name) and a description, for example "Style Me, swaps, Ask stylist and try-on pictures".
7. **Review information**: a screenshot of Styling access (the paywall), and a review note: "Profile → Styling access. The closet is free; Style Me, swaps, Ask stylist and try-on pictures use the subscription. Restore purchases and Manage subscription are on the same screen."
8. **Billing grace period**: App → Subscriptions → Billing Grace Period → on, 16 days, for all renewals (the app handles it either way).
9. **Family Sharing**: leave off unless Jose decides otherwise (it can be turned on later, not off).
10. **App Store Server Notifications** (30c): see "30c: server notifications and switching on verification" below.
11. **Legal links**: App Information → License Agreement (Apple's standard EULA, or a custom one), and the privacy policy URL. Apple asks for a terms of use (EULA) link in the app description too, for auto-renewable subscriptions.
12. **Attach to the version**: on the first version that sells it, App Store → the version → In-App Purchases and Subscriptions → select the subscription, and submit them together.
13. **Sandbox testers**: Users and Access → Sandbox → add a tester, then on the iPhone, Settings → Developer → Sandbox Apple Account. Check: buy, restore after reinstalling, cancel in Manage subscription, and that a sandbox month renews every 5 minutes.
14. **Group ID**: the app reads it from StoreKit (`subscriptionGroupID`), so nothing needs copying into the app.

### 30b: the complimentary unlock and offer codes

15. **The unlock**: My Apps → Nifty Outfit Nook → Monetization → In-App Purchases → create a Non-Consumable with Reference Name `Styling complimentary unlock` and Product ID `com.jsayram.niftyoutfitnook.styling.complimentary` (exactly). Price: any (US$49.99 is the placeholder; nobody buys it in the app). Display name "Complimentary styling", description "Styling access with no end date". Family Sharing off.
16. **Review notes for it**: "Not sold in the app. It's given with free one-time offer codes to the owner's family. Redeem in Profile → Styling access → Redeem a code. It gives styling access with no renewal; it doesn't cancel an existing subscription." Add a screenshot of Styling access with complimentary access. Attach it to the same version as the subscription (step 12).
17. **Offer codes** (Apple may require the product to be approved first): the unlock → Offer Codes → create an offer: Free, one-time use codes, eligibility all customers, a code count (for example 5), and an expiry for redeeming (the access itself never expires). Download the codes and send each one privately; a forwarded code works for whoever redeems it first. Xcode's StoreKit testing covers the app's side (the hosted tests); for a real code, check Apple's current guidance on redeeming in the sandbox or TestFlight first.
18. **Sandbox check**: redeem a code on a device (TestFlight), see "Your code is redeemed. Styling access is on.", delete and reinstall, tap Restore purchases, and check it's still on.

### 30b: picture packs

19. **Packs**: In-App Purchases → create two Consumables: `com.jsayram.niftyoutfitnook.pictures.small` ("10 try-on pictures") and `com.jsayram.niftyoutfitnook.pictures.large` ("30 try-on pictures"), with the final prices (US$2.99 and US$6.99 are placeholders). If the sizes change, change `CREDIT_PACKS` in the backend's `convex/credits.ts` and `CreditPacks.pictures` in the app together, before release. Review note: "Extra try-on pictures; credits never expire and work without a subscription. Shown in Styling access once try-on pictures are on."
20. **Hold them back** until Phase 33 makes pictures real: the app doesn't show packs before then. (30c verifies them on the server.)

### 30c: server notifications and switching on verification

21. **The app's Apple ID**: App Information → General Information → Apple ID (a number). Set it on the production deployment: `npx convex env set NOOK_APP_APPLE_ID <number>`. Without it production verifies nothing.
22. **Dev (sandbox) first**: on the dev deployment run `npx convex env set NOOK_APPSTORE_MODE apple` and `npx convex env set NOOK_APPSTORE_ENVIRONMENT Sandbox`, then deploy (`npx convex dev --once`).
23. **Notification URLs**: App Information → App Store Server Notifications. Choose **Version 2** for both. Production Server URL: `https://<production deployment>.convex.site/appstore/v2/notifications`. Sandbox Server URL: `https://beaming-oyster-905.convex.site/appstore/v2/notifications` (dev). Save.
24. **Test it**: in App Store Connect there's no button for it; the App Store Server API's "Request a Test Notification" sends one, which needs an App Store Connect API key (In-App Purchase type). Simpler: buy the subscription in the sandbox on a device signed in to dev, then check the dev deployment's logs for `"route":"appStoreNotification","status":200,"outcome":"subscription:subscribed"`. A `400` with `rejected:environment` means the deployment's environment doesn't match the URL; `503` means `NOOK_APPSTORE_MODE` isn't set.
25. **Production**: on the production deployment set `NOOK_APPSTORE_MODE apple` and `NOOK_APP_APPLE_ID` (leave `NOOK_APPSTORE_ENVIRONMENT` unset: it defaults to Production). Never set `NOOK_APPSTORE_MODE test` or `NOOK_APPSTORE_TEST_ROOT` there (test mode refuses production purchases anyway).
26. **Refund check in the sandbox**: refund a sandbox purchase (Settings → Developer → Sandbox Apple Account → manage, or Apple's sandbox refund flow), then confirm Style Me answers `entitlement_required` on the dev deployment.

## Questions for Jose

1. Price: US$9.99 a month, or another? Any storefronts to leave out?
2. The free month is one month, as the PRD says. Should the paywall say "we'll remind you before it ends" as the mockup does? The app sends no reminder today (that needs a local notification and her permission), so the paywall doesn't promise one.
3. Allowances on the paywall: confirm 10 Style Me requests a day, 40 swaps and questions a day, 30 try-on pictures a month (D12), or give the final numbers.
4. Family Sharing on or off?
5. Terms of use: Apple's standard EULA, or a custom one? The app links to the website's `/terms` page, which isn't written yet (35b).
6. Subscription group name and the product's display name, as customers will see them in Settings.
7. May an agent look into why StoreKit's test environment gets no products on the iOS 27.0 simulator (see Testing)? Until then the suites run on iOS 26.5, locally and in the Mac's gate, and are skipped on hosted CI.
8. (30b) Pack sizes and prices: 10 pictures for US$2.99 and 30 for US$6.99 are placeholders. What should they be?
9. (30b) The unlock's App Store price (placeholder US$49.99). Any price works since nobody buys it; a high one makes accidental purchase pointless if Apple ever shows it.
10. (30b, 30c) Lily's sponsored policy: the server's plan override is built and given to nobody. Confirm her signed-in account (its `usr_` ID) and her 30-day budget (placeholder US$5), and an admin sets it.
11. (30b, 30c) After an account deletion the backend deletes her credit ledger and entitlements with everything else, so unspent paid credits are forfeited. Keep them for a time instead (they would need to survive under a keyed hash, like kept usage), or leave it?
12. (30c) Style Me doesn't check styling access in the app: once the real backend is on, someone without access gets "This account can't do that." from the server. Add a Styling access prompt to Style Me (and swaps and Ask stylist) in a small app phase?
13. (30c) Apple's CONSUMPTION_REQUEST (a refund request asking how much was used) is recorded and alerted but not answered. Answering needs an App Store Server API key and her consent to share it. Answer them, or let Apple decide without the data?
14. (30c) A refund after credits were spent leaves "owing", which is never charged or taken from a later pack. Keep it that way, or take it from the next pack?
