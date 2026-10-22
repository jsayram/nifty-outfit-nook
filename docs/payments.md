# Payments: the styling subscription (Phase 30a)

Status: built 22 October 2026 against Xcode's local StoreKit testing. The real products need App Store Connect, which is Jose's job (steps below). Phases 30b (complimentary unlock, credit packs) and 30c (server checks, App Store Server Notifications, the credit ledger) come later.

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

The app never types a price or a date: the price, period and trial come from StoreKit (`Product.displayPrice`, `subscriptionPeriod`, `introductoryOffer`), and the free month shows only when `isEligibleForIntroOffer` is true. Someone who had the free month before sees "$9.99 a month. Charged today..." instead.

## Access rules

- **Access** (`hasStylingAccess(at:)`): a verified trial or paid month until its expiry date, and Apple's billing grace period until it ends. Billing retry without grace, expired, revoked and none give nothing. PRD §14.3.
- **Stale data**: the cache only lets the app show something before StoreKit answers. A cached status never grants past the dates Apple gave: a free month that has ended reads as expired until StoreKit says it renewed. Unverified transactions are finished and never granted.
- **After a purchase** StoreKit's status can lag a few hundred milliseconds. The status comes from the purchased transaction itself, and an empty answer from StoreKit within 60 seconds of a purchase doesn't erase it (still bounded by its own dates).
- **Not proof**: the server is the authority (SECURITY_STANDARD §8). Paid requests carry `X-Nook-Entitlement-Hint` (none, trial, active, grace, billing-retry, expired, revoked), worked out when each request is sent. The contract says it's a hint; neither the fake nor the real backend admits or refuses anything because of it. 30c adds the server's own check against Apple.
- **Listener**: `AppSubscriptions.service` starts `Transaction.updates` at launch, finishes every transaction, reads the status again and tells every screen that's listening (refunds, renewals, approved Ask to Buy, purchases on another device).

## Where it shows

- **Profile → Styling access** (under the name, as in `settings.html`): the status, the offer when she has no access, what's included, what's always free, Restore purchases, Manage subscription (Apple's `manageSubscriptionsSheet`) once there's a subscription, Terms of use and Privacy policy (the website pages, placeholders until 35b).
- **Try it on**: simulated pictures stay free ("Simulated pictures are free in this test build"). When the image service is real (`NookServices.tryOnIsSimulated = false`, Phase 33), a picture says it uses 1 of the month's pictures, or, without access, "Try-on pictures come with styling access" with See styling access, and Make a picture isn't offered.
- **Help → Free and paid** (Good to know): what's always free and what uses styling access, and where to manage it; the second line changes when she has access.
- **Delete my account**: the "doesn't cancel your subscription" note and a Manage subscription row show only while a subscription may still bill her (trial, active, grace period, billing retry).

## Why a custom paywall, not `SubscriptionStoreView`

`SubscriptionStoreView` shows Apple's own layout for the product and handles the trial wording, Restore and policies. It was not used because: the PRD and mockup need the allowances, what stays free and the first charge date in the app's plain words and soft design; the try-on sheet, Profile and Help share the same status; and snapshot and UI tests must draw it from a fake, which `SubscriptionStoreView` can't (it needs StoreKit, and package tests have no app). The App Store's own sheet still confirms every purchase, and Manage subscription is Apple's sheet. Guideline 3.1.2 is followed by the page itself: price and period from StoreKit, the free month and when the first charge comes, that it renews until cancelled, how to cancel (a day before, Settings → name → Subscriptions), Restore purchases, terms and privacy links. No countdowns, no pre-ticked choices, Not now always available.

## Testing

- **Hosted unit tests** (`NiftyOutfitNookTests/SubscriptionStoreKitTests.swift`): StoreKit's test sessions refuse to run in a package test bundle, so they live in a small unit-test target hosted in the app. Eleven tests: the offer, purchase (free month), access ending at Apple's date with an injected clock, a forced renewal, expiry, a refund through the `Transaction.updates` listener, a grace period, billing retry, restore on a fresh install, Ask to Buy approved, and the checkpoint (purchase, a renewal StoreKit makes by itself with a month every 30 seconds, restore, expiry). Restore in tests skips `AppStore.sync()`, which shows Apple's sign-in prompt; a test must never sign in.
- **Debug builds have `get-task-allow`** (`Configs/*-Debug.entitlements`): StoreKit's local testing on the simulator refuses an app without it ("not installed for development"). Release builds use the entitlements files without it, and `scripts/check-archive.sh` still checks them.
- **Package tests**: the access rules (`SubscriptionStatusTests`), the hint header (`PaidActionTests`), the screen's model, Profile, Help, try-on and Delete my account (`StylingAccessModelTests`), and the paywall snapshots (`StylingAccessSnapshotTests`).
- **UI test**: `StylingAccessTests` (scripted subscription). It needs adding to a CI UI part in `.github/workflows/ci.yml`.
- **By hand in Xcode**: Run uses `NiftyOutfitNookTests/NiftyOutfitNook.storekit` (the scheme's StoreKit configuration). Debug → StoreKit → Manage Transactions shows, refunds and expires purchases; Editor → Subscription Renewal Rate speeds up renewals.
- **Debug launches**: `-subscription none|trial|active|grace|retry|expired|revoked|used-trial` uses a scripted subscription with no StoreKit at all.

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
10. **App Store Server Notifications** (needed for 30c, set now or then): App Information → App Store Server Notifications → Version 2, production and sandbox URLs on the Convex HTTP action 30c builds.
11. **Legal links**: App Information → License Agreement (Apple's standard EULA, or a custom one), and the privacy policy URL. Apple asks for a terms of use (EULA) link in the app description too, for auto-renewable subscriptions.
12. **Attach to the version**: on the first version that sells it, App Store → the version → In-App Purchases and Subscriptions → select the subscription, and submit them together.
13. **Sandbox testers**: Users and Access → Sandbox → add a tester, then on the iPhone, Settings → Developer → Sandbox Apple Account. Check: buy, restore after reinstalling, cancel in Manage subscription, and that a sandbox month renews every 5 minutes.
14. **Group ID**: the app reads it from StoreKit (`subscriptionGroupID`), so nothing needs copying into the app.

## Questions for Jose

1. Price: US$9.99 a month, or another? Any storefronts to leave out?
2. The free month is one month, as the PRD says. Should the paywall say "we'll remind you before it ends" as the mockup does? The app sends no reminder today (that needs a local notification and her permission), so the paywall doesn't promise one.
3. Allowances on the paywall: confirm 10 Style Me requests a day, 40 swaps and questions a day, 30 try-on pictures a month (D12), or give the final numbers.
4. Family Sharing on or off?
5. Terms of use: Apple's standard EULA, or a custom one? The app links to the website's `/terms` page, which isn't written yet (35b).
6. Subscription group name and the product's display name, as customers will see them in Settings.
