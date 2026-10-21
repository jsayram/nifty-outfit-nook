# 0007: Authorization and account deletion

Phase 24c, 21 October 2026. Built against the fake sign-in and fake backend, like 0005 and 0006; the real Clerk and Apple calls are configuration in the private backend.

## Authorization

Convex has no row-level security. The backend's rules: HTTP actions are the only public functions (a check fails on any other), every internal function takes the caller from the verified token, and no request can name an account: the contract rejects unknown fields and no request schema has a user, account or principal field (a contract test enforces this). A cross-user suite in the backend runs a second account against every endpoint and fails on a new endpoint without a case.

## Account deletion

- **Where:** Privacy and terms, Delete my account, only while signed in (Guideline 5.1.1(v)). Delete my data stays as it was.
- **Re-authentication:** Apple's sign-in sheet after the question. Its authorization code goes to the backend once, which needs it to revoke the Apple link. App Attest isn't required: a device that can't attest must still be able to delete.
- **Order:** Apple and the backend first; nothing is deleted anywhere if either says no. Then the backend's steps are read, the iCloud copy is deleted (hook), this iPhone is erased, and she's signed out with the App Attest key ID forgotten.
- **API:** `POST /v1/account/deletion` (token, `confirm: "delete-my-account"` and the code; 202 with three steps) and `POST /v1/account/deletion/status` (no token, by the random `del_` ID). The plan's draft was `DELETE /v1/account` and `GET .../deletion/{id}`; the status ID went into a body so it never sits in a URL or a log, and both stay simple POSTs.
- **Partial failure:** every step repeats safely. The backend retries on its own and alerts if it keeps failing; the app's Try again repeats only what's left. The screen never says done while a step is pending.
- **Subscriptions:** the screen says deleting doesn't cancel one. Phase 30 adds the link.

## Not built, and why

- The real Apple revocation (needs the Sign in with Apple key) and a run of the real Clerk deletion (no instance yet).
- iCloud deletion: sync doesn't exist; `ICloudCopyDeletion` is the hook decision 0004 §6 fills.
- A later screen showing a deletion the server is still finishing after the app has restarted. The server finishes on its own; the deletion ID isn't kept on the phone.
