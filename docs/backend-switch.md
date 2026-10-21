# Switching from the fakes to Clerk and Convex

The app runs on a fake sign-in and an in-process fake backend until two build settings are set (Phase 24a, [decision 0005](decisions/0005-gateway-and-identity.md)). This page lists what Jose does to switch. The backend side, with the Convex commands, is in the private backend repo's README.

Nothing here is secret, and no secret goes in this repo. The Clerk **publishable** key ships inside every app; the Clerk **secret** key and every provider key live only in Convex environment variables.

## 1. Clerk (dashboard, Jose)

1. Create the application, with a **development** instance for now. Turn on two-factor sign-in for the Clerk account.
2. Sign-in options: **Apple** only. Don't require a name. If Clerk insists on an email for Apple sign-ups, allow Apple's private relay address (decision D6).
3. Native applications: register the iOS app (team ID and bundle ID `com.jsayram.niftyoutfitnook`), as Clerk's iOS guide asks.
4. JWT templates: create one named exactly **`convex`**, using Clerk's Convex preset, so its `aud` claim is `convex`. Note the token lifetime it shows (decision 0005, open point 3).
5. Copy the **Frontend API URL** (for example `https://verb-noun-00.clerk.accounts.dev`) for the backend, and the **publishable key** (`pk_test_...`) for the app.

## 2. The backend (Jose, then an agent)

In `nifty-outfit-nook-backend`, following its README: Jose runs `npx convex login` himself and links the dev deployment `beaming-oyster-905`; then `npx convex env set CLERK_JWT_ISSUER_DOMAIN <Frontend API URL>` and `npx convex deploy` to the dev deployment.

## 3. The app

1. Copy `Configs/Secrets.xcconfig.example` to `Configs/Secrets.xcconfig` (git ignores it).
2. Set `CLERK_PUBLISHABLE_KEY` to the publishable key and `NOOK_API_BASE_URL` to `https:/$()/beaming-oyster-905.convex.site` (the HTTP actions URL, `.convex.site`; the `$()` stops xcconfig reading `//` as a comment).
3. Add the **Sign in with Apple** capability to the app target in Xcode, so the entitlement is in the build.
4. Build and run with `-gateway-lab`. The Sign-in row says "Clerk (real)". Sign in with Apple, then Who am I?.

With either value missing or malformed the app stays on the fakes, so a fresh clone or CI never needs these.

## Paid actions and App Attest (Phase 24b)

The paid endpoints need App Attest, which the simulator can't do, so on the real backend they work only on a device, and only after the steps in [decision 0006](decisions/0006-limits-and-cost-protection.md), "Device checklist": the App Attest capability and entitlement, then the backend's Apple attestation check. Until then the real backend refuses every key registration (it fails closed), and `-limits-lab` shows "This iPhone couldn't be checked". On the fakes everything works on the simulator.

The backend needs its switches and ceilings set before any paid work runs (backend README, "Switches and ceilings"); a fresh deployment pauses every paid feature.

## Before production

- Decision 0005's open points: the Clerk Keychain accessibility class needs Jose's written exception first.
- A separate Clerk **production** instance and Convex production deployment, each with its own settings (STACK.md, SECURITY_STANDARD §5). A dev token must fail against production: the backend's issuer check does this, and the backend README has the test.
- The Privacy and terms wording, the privacy policy and the App Store privacy label name Clerk as a processor (closet `DATA_MAP.md`).

## Going back to the fakes

Delete `Configs/Secrets.xcconfig` (or empty either value) and rebuild.
