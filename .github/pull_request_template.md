## Summary

<!-- What this PR does and why. Link the phase in closet/SWIFT_BUILD_PLAN.md. -->

## What was tested

<!-- Commands run, devices or simulators, and anything checked by hand. -->

- [ ] `scripts/format.sh` is clean
- [ ] `scripts/test.sh` passes (the whole suite, not only new tests)

## Security checklist

Tick the sections of `closet/SECURITY_STANDARD.md` this change touches, then check every line under them. Write "n/a" next to a section the change doesn't touch.

**Always**
- [ ] No secrets, keys, tokens or team IDs in the diff (gitleaks hook ran)
- [ ] No backend code, prompts, fit or styling rules, or model config (this repo is public)
- [ ] No new dependency, or it was approved in writing first and is pinned exactly with `Package.resolved` committed
- [ ] No personal data in logs, URLs, analytics or test fixtures

**1. Data classification**
- [ ] New data is classified and added to `closet/DATA_MAP.md`

**3. Repository and supply chain** (CI, scripts, hooks, repo settings)
- [ ] Third-party actions pinned to a full commit SHA with a version comment
- [ ] Workflow permissions stay read-only unless a job needs more, and that job says why
- [ ] No secrets printed to logs

**4. The iOS app** (storage, network, privacy on the device)
- [ ] Sensitive and personal files use Data Protection `complete`, or the exception is documented
- [ ] Tokens and keys only in the Keychain (`WhenUnlockedThisDeviceOnly` or stricter)
- [ ] No App Transport Security exceptions; requests have timeouts, cancellation and bounded retries
- [ ] Photos come through the system picker; metadata is stripped before anything leaves the device
- [ ] Sensitive screens are hidden in the app switcher; no sensitive data on the pasteboard
- [ ] Logging uses `os.Logger` with privacy redaction
- [ ] Permissions are asked only when first needed, with a clear reason string
- [ ] `PrivacyInfo.xcprivacy` still matches what the app does

**8. Payments and entitlements**
- [ ] Nothing the client says about payment, credits or quota is trusted

**9. Privacy and legal**
- [ ] Privacy manifest and App Store labels still match

**11. Testing and review gates**
- [ ] Security tests added alongside the feature where it makes sense
- [ ] For a `develop` to `main` promotion: the security review gate was walked through

## Checkpoint for Jose

<!-- What Jose should look at or decide. -->
