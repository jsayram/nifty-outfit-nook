# 0009: Support and feedback channel (Phase 24d)

Status: built against the fake backend, 22 October 2026. The real backend is a configuration switch away, like Phases 24a to 24c.

## What was decided

1. **Send feedback goes to a private support queue when she is signed in; the share sheet stays for everyone else.** There is no sign-in screen yet (decision 0005), so on a build without the real services, support still has to work. Signed out, nothing about the page changes. This also means the queue's extras (reply address, screenshot, closet size) exist only where the queue is.
2. **No App Attest on `POST /v1/feedback`.** Support has to work on a device that can't attest, and a note costs nothing, so there is nothing for attestation to protect. The protection is the token (every note belongs to an account and goes with it), limits, and size caps. The same reasoning as account deletion (decision 0007).
3. **Limits are the backend's.** A burst of 5 notes then one every 12 minutes, 10 notes and 3 screenshots a day per account, 300 notes a day for everyone, a 1 MiB body for this endpoint only. Closing intake is an environment variable, no app update. Over a limit she is told how long to wait.
4. **No queue on the phone.** A note that can't go stays in the draft and goes when she taps Send again (Jose, as for Phase 26). A random submission ID, kept while the note is unchanged, makes a repeat harmless.
5. **Only what she sees is sent.** The page lists every value; `FeedbackNote.sentValues` is the list, and tests check that the page shows each one and that the request carries those and nothing else. Diagnostics stay the three lines (version and build, iOS, device model) behind the existing switch. Closet data is three numbers behind its own switch.
6. **The screenshot is hers, small and clean.** She picks it with the system picker (no permission), sees it, and can remove it. The app rewrites it from its pixels (no EXIF, GPS, time, device or caption); the backend does it again from the file's structure. It is not kept in the draft.
7. **The support page is a config value.** `NOOK_SUPPORT_URL`, a placeholder until Phase 35b. The app holds no email address (STACK.md).

## Not built (waiting on Jose, or later)

- A way for Jose to answer inside the app. He answers by email to the reply address; a note without one can't be answered, and the page says so.
- The public feedback board and the opt-in email program: written decision in the closet repo's plan (left for later).
- The email notification to Jose: a hook with a mock; the real sender needs his choice of mailbox or service.
- A real sign-in screen, so signed-out users reach the queue.

## Device checklist

The photo picker's screenshot filter, a real screenshot (a PNG with a colour profile) cleaned and attached, the keyboard type of the reply field, VoiceOver reading the failure and the success, and a note sent over cellular.
