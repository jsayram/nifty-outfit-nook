# Nifty Outfit Nook prelaunch website

Public site: https://niftyoutfitnook.pages.dev/

## What it is

A product tour for an app in development. It describes plans as plans: no release date, download, waitlist, pricing or working AI or try-on feature is claimed. There is no email address or signup form, because a public support contact hasn't been chosen yet. The page is an independent design with no Apple affiliation.

Static HTML, CSS and one small local script (`site.js`, which only handles scroll reveals and keyboard focus styling). No packages, external fonts, analytics, trackers or app services are loaded. `_headers` sets a strict Content Security Policy (`default-src 'none'`, with only same-origin scripts, styles and images), `nosniff`, `no-referrer` and a Permissions-Policy that turns off camera, microphone and location.

The product images in `public/assets/` are snapshot-test captures from this repo, made with sample data and saved as WebP at 804 px wide. They cover Home in light and dark, Closet, the Style Me request, an outfit result, the simulated Try It On state, Suitcases and Laundry. They carry no EXIF or location metadata. An earlier generated wardrobe illustration was removed from the page and the assets on 15 October 2026.

## Content rules

The "Current announcements" timeline is a public development log. Its cards must not show dates, pull request numbers, repository links or a GitHub account. Keep the wording at the level of what a user would notice, and don't suggest that sample-data screens, AI services or launch systems are live.

The page uses its own "Coming to iOS" badge, not an App Store badge, because the app isn't listed yet.

Motion is limited to entrance and scroll reveals (700 ms, transform and opacity) and press feedback (160 ms). The FAQs are native `<details>` elements. Reduced motion, reduced transparency, increased contrast and dark appearance all have stylesheet rules.

## Preview and deploy

From the repository root:

```sh
python3 -m http.server 8789 --directory website/public --bind 127.0.0.1
```

The site is a Cloudflare Pages Direct Upload project (`niftyoutfitnook`), so deploys are manual. Upload only the contents of `public/`, including `_headers`, as a Production deployment. Never upload the repository or this README. No custom domain or paid plan is needed.

Before App Store submission, add real support and privacy pages based on the shipped app.

## Status

First published on 13 October 2026 as a one-section holding page. The product tour replaced it on 15 October 2026.

This folder was added to the repo on 17 October 2026 from the working copy used for that deploy. Its images, `site.js` and `_headers` match the live site byte for byte. `index.html` and `style.css` are a few minutes newer than the deploy: they add the three-step "How the styling assistant helps" list to the AI styling section and give the Home preview more room. Those two changes aren't live yet and go out with the next upload.

All rights reserved.
