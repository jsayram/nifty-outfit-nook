---
name: Nifty Outfit Nook website
description: Existing Apple-inspired website system with app capture previews and a dated development timeline.
colors:
  bg: "#f5f5f7"
  surface: "#fff"
  ink: "#1d1d1f"
  secondary: "#626267"
  accent: "#72385f"
  tint: "#eee4ed"
  line: "#dedee3"
  nav: "rgba(245,245,247,.8)"
  dark-bg: "#171518"
  dark-surface: "#232025"
  dark-ink: "#f5f3f6"
  dark-secondary: "#b9b3bd"
  dark-accent: "#e0b7d3"
  dark-tint: "#30232e"
  dark-line: "#403843"
  dark-nav: "rgba(23,21,24,.85)"
  button-ink: "#fff"
  dark-button: "#c08caf"
  dark-button-ink: "#20161d"
  button-hover: "#5c294c"
  dark-button-hover: "#dbafce"
typography:
  display:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif'
    fontSize: "clamp(52px,6.9vw,88px)"
    fontWeight: 700
    lineHeight: 1.04
    letterSpacing: "-.05em"
  headline:
    fontSize: "clamp(36px,4.4vw,58px)"
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "-.055em"
  capture-title:
    fontSize: "32px"
    lineHeight: 1.13
    letterSpacing: "-.035em"
  body:
    fontSize: "17px"
    lineHeight: 1.6
  button:
    fontSize: "14px"
    fontWeight: 500
  capture-label:
    fontSize: "11px"
    fontWeight: 650
rounded:
  focus: "8px"
  control: "10px"
  preview: "14px"
  dialog: "20px"
  capture: "24px"
  timeline: "26px"
  panel: "28px"
  pill: "999px"
spacing:
  capture-gap: "14px"
  panel-inset: "44px"
  feature-gap: "40px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.button-ink}"
    rounded: "{rounded.pill}"
    padding: "12px 23px"
    typography: "{typography.button}"
  button-primary-hover:
    backgroundColor: "{colors.button-hover}"
  button-primary-dark:
    backgroundColor: "{colors.dark-button}"
    textColor: "{colors.dark-button-ink}"
  status-chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.accent}"
    rounded: "{rounded.pill}"
    padding: "7px 10px"
  timeline-card:
    backgroundColor: "{colors.bg}"
    rounded: "{rounded.timeline}"
    padding: "26px 28px 28px"
  timeline-card-current:
    backgroundColor: "{colors.tint}"
  capture-close:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "6px 12px"
---

# Design System: Nifty Outfit Nook website

## Overview

The existing identity is Apple-inspired: system typography, one plum accent, generous space, soft neutral surfaces, and rounded containers. This document captures the implemented website; it does not establish a new product identity or a new creative metaphor. The dark appearance follows the operating system.

The scoped expansion uses real app captures in a feature gallery and the existing dated, connected-dot timeline. Captions distinguish sample data, simulated services, and development previews. These are presentation constraints; milestone copy is not a reusable source of product capability claims.

**Key Characteristics:**

- System typography with compact headline tracking.
- Plum accents over quiet light or dark surfaces.
- Rounded, captioned captures with a full-image inspection path.
- Connected dates, status text, and distinguishable timeline dots.
- Native controls and operating-system accessibility preferences.

## Colors

### Primary

Plum (`accent`) identifies emphasized text, actions, timeline connectors, and focus. The pale plum `tint` distinguishes selected or current surfaces. In dark appearance, use the dark token counterparts; filled buttons use their own dark background and ink pair.

### Neutral

`bg` supplies the page and timeline-card canvas; `surface` supplies cards, preview frames, and controls. `ink` carries primary text, `secondary` explanatory copy and captions, and `line` dividers. The translucent `nav` supports the sticky header. Their dark counterparts preserve these roles.

**The One Accent Rule.** Extend the existing plum roles when adding previews; do not introduce a second feature-specific accent.

## Typography

Use the existing system font stack for display, body, labels, and controls. Optical sizing is enabled. Headings are bold and tightly tracked; supporting text is quieter and more openly spaced.

The frontmatter records the desktop display and section scales. Capture-story titles use `capture-title`; their mobile size is (29px). Feature descriptions use `body`. Captions remain secondary text with readable line height. Timeline dates use tabular numbers; phase and status labels use a small uppercase treatment. Preserve the date as distinct from the phase label.

## Layout

The main container is capped at (1100px), with total horizontal gutters of (64px), reducing to (40px) at the mobile breakpoint. The existing breakpoints are (900px) and (600px).

Feature stories use two equal columns with gaps of (64px vertically, 40px horizontally); at the middle breakpoint the gaps reduce, and on mobile they stack. Desktop preview windows are (490px) tall, middle widths use (390px), and mobile uses (420px). Photo-intake and weather previews can retain natural height on mobile. Cropped previews are inspection entry points, never substitutes for a complete image.

The iPad preview pairs text and landscape capture before stacking below the middle breakpoint. Timeline previews use two columns on desktop, one at middle widths, and two compact columns on mobile. A sole timeline capture spans both columns. Do not simplify this into a universal single-column rule: each pattern follows its implemented available width.

The announcements heading is sticky on larger screens and returns to normal document flow on mobile. Timeline dots and their connector stay aligned alongside the cards.

## Elevation & Depth

Depth comes primarily from neutral and tinted surface changes. The header adds blur (18px) and saturation (150%). Capture frames, the enlargement hint, current milestone, and dialog receive selective shadows; use the sidecar's exact values. The modal backdrop dims the page rather than changing screenshot content.

Respect reduced transparency by making the header opaque and removing blur. Increased contrast promotes secondary text and removes header translucency.

## Shapes

Pill actions and status chips contrast with larger rounded panels. Preview windows use medium corners; timeline cards and the capture dialog have their own smaller radii, recorded above. Keep captures rectangular and preserve their intrinsic aspect ratio in the full-image viewer. Cropped windows align images to their top edge.

## Components

### Buttons and navigation

Primary actions use a filled plum pill with press feedback. Fine-pointer hover lifts the button slightly and deepens its fill. The header combines the compact wordmark, subdued links, and a tinted status pill; secondary navigation links hide at the mobile breakpoint. Keyboard focus remains clearly outlined, and keyboard interaction suppresses transform feedback on existing primary controls.

### Status chips and timeline cards

Small uppercase status chips sit below timeline copy. A completed dot uses a check; the current dot uses a ring and center point. The current card uses tint and a soft shadow. Keep dates, phase, heading, copy, and status in that order, with captures between copy and status when present. Use semantic time elements and `aria-current="step"` for the current milestone.

### Capture previews

Captures are figure elements with descriptive alt text and captions. Their links have direct image URLs, accessible enlargement names, visible “View full capture” hints, and focus outlines. Lazy-loaded images carry intrinsic dimensions. Use the supplied metadata-free capture exports; keep sample and simulated-state qualifications adjacent to the relevant preview. A full source and a cropped thumbnail may differ, as with the weather-controls crop; preserve that intentional inspection path.

**The Full Capture Rule.** Every cropped capture must retain an accessible route to its complete image.

### Capture dialog

The native dialog has an accessible title, sticky heading and close control, explanatory sample-data note, and an uncropped scrollable image. It is capped at (860px) wide and (90dvh) high, moving to (96vw) and (94dvh) on mobile. The close control has a minimum height of (44px).

Ordinary activation opens the dialog when supported; modified clicks retain link behavior. Native Escape, the close form, and a click outside the dialog close it. Closing returns focus to the originating link without scrolling. Without JavaScript or native-dialog support, the direct image link remains functional. Do not add custom zoom, carousel, or focus-trap behavior without a separate requirement.

### Motion

Existing entrance and reveal animation lasts (700ms), using the established ease-out curve and small vertical travel. Primary press feedback lasts (160ms). Reduced motion keeps content visible and removes entrance and transform animation. The capture viewer introduces no entrance animation. Content remains available before enhancement and without JavaScript.

## Do's and Don'ts

### Do:

- **Do** reuse the system stack, plum roles, soft surfaces, and operating-system themes.
- **Do** keep sample, simulated, and development context beside captures.
- **Do** retain captions, alt text, keyboard focus, direct links, and focus restoration.
- **Do** preserve source image proportions in the full viewer.

### Don't:

- **Don't** present a sample or simulated capture as evidence of a live service.
- **Don't** encode current product status as a permanent visual-system fact.
- **Don't** remove the complete-image route when cropping a preview.
- **Don't** hide content behind required animation or JavaScript.

<!-- Extracted 2026-10-21 from /private/tmp/nifty-captures-20261021/{index.html,style.css,site.js}. Scoped documentation only. -->
