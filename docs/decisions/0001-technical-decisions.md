# 0001. Technical decisions

Status: **proposed**, waiting for Jose's approval (Phase 0a checkpoint)
Date: 13 October 2026
Plan: `closet/SWIFT_BUILD_PLAN.md`, Phase 0a. Security rules: `closet/SECURITY_STANDARD.md`.

Checked against the tools on the build Mac today: Xcode 26.6, Swift 6.3.3, swift-format 6.3, iOS 26.5 and 27.0 simulators.

## Decisions

| # | Topic | Decision | Why |
|---|---|---|---|
| 1 | Starting point | A **new project**. The SwiftUI prototype (`closet/prototypes/LilyStyleMockup`) is reference only; ideas and art can be carried over, code isn't copied wholesale. | The prototype was built for speed with demo toggles and fake services. The real app needs clean boundaries, tests and security from the first commit. |
| 2 | Minimum iOS | **iOS 26.0** (pending Lily's version, see question 1). iPhone and iPad, universal. | Lily's iPhone 12 runs iOS 26 and 27. There's no deadline, so by launch nearly all active devices will be on 26 or later. It gives us the current SwiftUI, SwiftData and Observation APIs, Apple's current design language, and fewer workarounds. Dropping iOS 18 only excludes phones older than the iPhone 11. |
| 3 | Project setup | A **thin Xcode app project** using folder-synchronized groups, plus **one local Swift package** that holds almost all code. No project generator (XcodeGen isn't used). | Synchronized folders mean adding a file never touches the project file, so merge conflicts are rare. Code in a package is plain text (`Package.swift`), builds and tests fast without the app, and keeps modules honest. Not depending on XcodeGen follows the "prefer Apple tools" rule. |
| 4 | Code layout | Package `NookKit` with targets: **DesignSystem** (tokens, components), **Models** (domain types and service protocols), **Fixtures** (mock data sets), **Features** (screens and view models, one folder per feature). Later stages add **Persistence**, **Networking** and **Services**. The app target only wires things together. | Features depend on protocols in Models, never on concrete services, so Stage A runs entirely on fixtures and Stage B swaps in real services without touching screens. |
| 5 | Language | **Swift 6 language mode, complete strict concurrency**, warnings treated as errors in CI. UI targets default to main-actor isolation; background work is explicit. | Data races become compile errors instead of rare crashes. |
| 6 | Unit and integration tests | **Swift Testing** (`@Test`, `#expect`) for everything that isn't UI automation. | Apple's current framework, parallel by default, clearer failures. |
| 7 | UI tests | **XCUITest** for end-to-end flows (Style Me, swap, save, recovery), using launch arguments to choose a fixture set. | The only Apple option for driving the real app. |
| 8 | Snapshot tests | **swift-snapshot-testing** (Point-Free), **test targets only**, pinned to an exact version. Needs Jose's written approval as a dependency (question 3). Snapshots cover light/dark, Dynamic Type sizes, iPhone and iPad. | It's the standard tool, MIT-licensed, widely used, and never ships in the app. The alternative is our own `ImageRenderer` comparison helper, which is more code to maintain. |
| 9 | Lint and format | **swift-format** (ships with the Swift toolchain) with a checked-in configuration, run locally and in CI. No SwiftLint. | No third-party tool needed. |
| 10 | Dependencies | **None in the shipping app during Stage A.** Every dependency, including test-only ones, needs Jose's written approval recording who maintains it, how widely it's used, its license, what it can access, and why an Apple framework won't do. Exact versions pinned, `Package.resolved` committed, Dependabot alerts on. Never: analytics, ad or tracking SDKs, or anything that phones home. | `SECURITY_STANDARD.md` section 3. Each dependency is code we ship and must trust. |
| 11 | CI | **GitHub Actions** on GitHub-hosted macOS runners: build, swift-format check, unit, snapshot and UI tests, and gitleaks on every pull request. Set up in Phase 1b with actions pinned to commit SHAs. | The repo is public, so hosted runners, macOS included, cost nothing. Xcode Cloud stays an option for TestFlight uploads later. |
| 12 | Configurations | **Debug** and **Release** build configurations, with environment settings (Dev, Staging, Production) in `.xcconfig` files. No secrets in any of them. A `Secrets.xcconfig` pattern is ignored by git and only ever holds non-secret identifiers. | Environments are settings, not branches (Git Flow stays for code). The app never holds a real secret; the backend does. |
| 13 | Bundle ID | `com.jsayram.niftyoutfitnook` unless Jose prefers another (question 2). It can't be changed after the first App Store release. | Reverse-domain of something Jose controls. The GitHub handle works without buying a domain. |
| 14 | Strings and accessibility | All user-facing text in a **String Catalog** (English first). Dynamic Type, VoiceOver labels, Reduce Motion and contrast checks are part of every screen's definition of done. | Retrofitting either one later is expensive. |
| 15 | Design tokens | Colours from Lily's **warm neutral** palette (`closet/prototypes/RoomDirectionMockups/css/palette.css`), as asset-catalog colours with dark variants, plus spacing, radius and shadow tokens for the soft no-box style. Built in Phase 2a. | Lily chose it on 13 October 2026. |

## What this changes elsewhere

- **On-device AI (Phase 28).** Apple's Foundation Models framework needs Apple Intelligence, which starts at the iPhone 15 Pro. **Lily's iPhone 12 can't run it.** Phase 28 becomes an optional speed and cost saving on newer devices; her styling always goes through the cloud stylist (Phase 27). The app must work fully without it.
- **Subject lifting for sticker cutouts (Phase 8)** uses Vision and VisionKit, which run on the iPhone 12. Speed still has to be measured on her phone in Phase 8a.
- **Persistence** (SwiftData or another store) is decided in Phase 20a. Stage A uses protocols with in-memory fixtures, so that choice doesn't block anything now.

## Questions for Jose (checkpoint)

1. **Lily's iOS version:** on her iPhone, Settings › General › About › iOS Version. If it's 26 or later, iOS 26.0 is the floor.
2. **Bundle ID:** keep `com.jsayram.niftyoutfitnook`, or use another prefix (for example a domain you'll own)?
3. **Snapshot testing:** approve `swift-snapshot-testing` as a test-only dependency, or have us write our own small helper?
4. **Apple Developer Program:** do you have a paid membership ($99 a year)? It's needed to run on Lily's phone over a cable for more than 7 days, and for TestFlight (Phase 18). Not needed until then.

Approving this note means the decisions above stand until a later decision note replaces one of them.
