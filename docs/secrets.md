# Secrets and the app (Phase 25a)

This repo is public, so this page says only what the app holds and how that's checked. The full register of server secrets, with rotation and access, lives in the private backend repo.

## What ships in the app

Two values, both public by design, set at build time in `Configs/Secrets.xcconfig` (ignored by git; template in `Configs/Secrets.xcconfig.example`):

- the Clerk **publishable** key (`pk_test_...` or `pk_live_...`), and
- the gateway URL (`https://<name>.convex.site`).

Both end up in `Info.plist` and can be read by anyone with the app. Nothing may depend on them staying hidden. The app never accepts a Clerk secret key (`sk_...`) as a publishable one, and it ignores a gateway URL that isn't https, has a query string, or carries a user name or password (`GatewaySettings`, with tests).

## What never ships

AI provider keys (Anthropic, Black Forest Labs, OpenAI), the Clerk secret key, Convex deploy keys, the result-cache key, the subject pepper, push and App Store keys, and the backup keys. They exist only as environment variables on the server. The app calls only our own gateway, never a provider.

## How it's checked

- **gitleaks** runs as a pre-commit hook and in CI over the full history.
- **`scripts/check-release.sh`** runs in CI on the Release build (through `scripts/check-archive.sh`). It fails if the built app holds anything that looks like a key, a private key, a server-only setting name, a provider's address, a URL with a password in it, a plain `http://` or `localhost` address, a key file (`.env`, `.p8`, `.p12`, `.pem`, `.key`, `.xcconfig`), or an Info.plist key named like a secret. The two public values above are allowed in `Info.plist` only. Matches are masked in the output.

## Review of 22 October 2026

No secret in the full history of this repo (135 commits, all branches), none in the built Release app (binary, Info.plist and every resource), and none in the committed templates. Details and the server side are in the backend repo's `docs/secrets.md`.
