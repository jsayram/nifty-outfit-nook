# Nifty Outfit Nook

A native iOS app (SwiftUI) that styles outfits from the clothes you already own.

This repo holds the shipping app (the Xcode project, Swift packages, tests and CI) and the app's website in `website/`. Planning, the product requirements, design mockups and the security standard live in the separate `closet` repo:

- Build plan: `closet/SWIFT_BUILD_PLAN.md`
- Security standard (required): `closet/SECURITY_STANDARD.md`
- Product requirements: `closet/Nifty_Outfit_Nook_PRD_v2.md`

## Branches

Git Flow. `main` is what's released, `develop` is the integration branch, and every phase is a `feature/*` branch off `develop`. Releases go through `release/*`, urgent fixes through `hotfix/*`. Nothing is pushed straight to `main` or `develop`.

## License

Copyright © 2026 Jose Ramirez-Villa. All rights reserved. No license is granted to use, copy, modify or distribute this code.
