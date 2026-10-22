# 0011: Sign-in when it's first needed, and reporting AI results

Status: built 22 October 2026 for the release audit's blockers on sign-in and on reporting AI content. Where sign-in lives was never decided (24a, question 5), so this is the least intrusive standard pattern, made easy to move.

## Sign-in

- **Nothing asks at launch.** Her closet, Quick ideas, backups and everything else on the phone work signed out.
- **The sheet comes when she first starts something that needs the server:** cloud styling, a real try-on picture, buying styling access or a picture pack (or redeeming a code), sending a note to the support queue, sending a report, and Delete my account if her session has ended. It says why in one line, says what still works signed out, and offers Apple's own Sign in with Apple button (`ASAuthorizationAppleIDButton`, black in light mode and white in dark), Not now, and the privacy policy.
- **After signing in, what she started carries on** (the look is styled, the picture is made, the purchase goes ahead). Not now cancels it with nothing sent or bought. Style Me falls back to Quick ideas, with a Sign in button beside them; its Not now is remembered while the app runs, so Style Me doesn't ask every time.
- **Profile** has an account row: "Signed in with Apple" with Sign out (asked first), or "Sign in". Send feedback signed out keeps the share sheet and adds "Sign in to send it to us directly".
- **How it's built:** `SignInGate` and `.signInGate()` (Features/Shared/SignIn). Screens read `\.signIn` from the environment and call it before cloud work; the root and each sheet that starts cloud work install their own gate, since a sheet can't be presented from under another sheet. The button only starts the app's own sign-in: `AccountService.signIn()`, which is Clerk's when it's configured and the fake in a Debug build. `NookServices.offersSignIn` is true whenever the gateway isn't in its unavailable mode.
- **Release with no backend settings** (32b, L9) has no sign-in: the gate never asks, the cloud features keep saying "Not available right now", and Profile's row says signing in isn't available right now. No fake.

To move sign-in somewhere else later (onboarding, or a single account screen), only the places that call `\.signIn` change.

## Reporting an AI result (Guideline 1.2)

- **Report a problem** sits under a look the cloud stylist made (or Apple's on-device model, once there is one) and on a real try-on picture's page. Quick ideas are rules on the phone and simulated pictures are drawn on the phone, so they have none. Ask stylist answers can be reported by the same sheet (`AIReportSubject.askAnswer`) once the Ask stylist screen exists; the screen is still the stand-in.
- **The sheet:** four reasons (wrong or offensive, not my clothes, looks wrong on me, other), an optional note of up to 500 characters, "The outfit" or "The reason under it" when the look has a why line, Include the picture (try-on only, off every time), Hide, and Send. A reason is needed before Send.
- **What goes:** `POST /v1/feedback` with `kind: "aiReport"` and an `aiReport` block: the subject, the reason, the result's ID, the server's action ID when the app has it, the look's version, who made it (cloud, on-device, phone), when, and whether she hid it. Never a provider or model: the contract refuses those fields and the backend adds them from its own records. No picture unless she ticked Include the picture; then the picture is cleaned like a screenshot (JPEG, no metadata, at most 600 KB).
- **IDs:** since this change a cloud result's ID and a real picture's ID are the server's action ID (`act_...`), so a report can name the action without new stored fields. Older results keep random IDs and are matched on the server by time.
- **Hide:** a look's result leaves her history (a look she saved stays saved) and Your looks offers Try a different outfit, which avoids those pieces together; a picture is removed as Delete picture does, with Undo. Hiding happens once the report is sent.
- **Limits** are the backend's: reports have their own bucket (5 in a burst, then one every 12 minutes) and 20 a day, so they never use up her support notes.

## Not built

- The sign-in sheet hasn't run against a real Clerk instance (there isn't one yet).
- No in-app answer to a report; Jose reads reports in the Convex dashboard like support notes.
