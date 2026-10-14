#!/usr/bin/env python3
"""Builds the Home room art in the asset catalog from the mockup drawings.

    scripts/room-art.py

Reads every SVG in art/room/source (copied from the planning repo's
prototypes/RoomDirectionMockups/art, see art/room/README.md) and writes one image set per
drawing to Packages/NookKit/Sources/Features/Resources/Room.xcassets, with a light SVG and a
dark SVG. The image sets keep vector data at a single scale, so the art stays sharp at any size.

What it changes on the way:

- Colours. The mockups drew the room in the first pastel palette and only toned it down with a
  CSS filter for the palette study. Here each colour is recoloured for real into Lily's warm
  neutral palette: the mockup palette colours that have a design token (sage, pink, lilac,
  butter, cream, plum) become that token's light value, and every other colour keeps its
  lightness while its colourfulness drops and its hue moves toward the warm neutrals (see
  `warm`). Dark values are the light ones dimmed the way DesignSystem/README.md describes:
  red and green times 0.66, blue times 0.62.
- Garments (the wardrobe rail) keep their real colours, because they stand for her real
  clothes. In dark they're dimmed to 92%, as in the mockups' dark.css.
- The windows' blues are sky, so they keep their hue with much less colour (see `sky`).
- Maya keeps her apricot colours too, because she's a real dog. In dark she's in the same
  lamplight as the rest of the room.
- Some drawings are made from another one here rather than drawn twice (see DERIVED): the
  faded hamper for when laundry tracking is off is the empty hamper with the mockup's
  "faded" filter baked in.
- `<use>` elements are replaced by copies of what they point to, and comments are dropped, so
  the system's SVG renderer doesn't have to support references.

art/room/palette-map.json lists every source colour and what it became, for review.
Python 3 standard library only. Run it again after changing a source drawing.
"""

from __future__ import annotations

import copy
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art/room/source"
CATALOG = ROOT / "Packages/NookKit/Sources/Features/Resources/Room.xcassets"
PALETTE_MAP = ROOT / "art/room/palette-map.json"

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)

# Drawings that stand for her real clothes keep their colours.
GARMENTS = {"wardrobe-rail"}

# Drawings of real things that keep their own colours in light, and get the room's lamplight in dark.
KEEP_COLOURS = {"maya"}

# Mockup palette colours (css/room.css) with a warm design token (Palette.swift). Keep in step
# with RoomArtTests.tokenColours.
TOKEN_COLOURS = {
    "#B7D5B1": ("artSage", "#C9CDB4"),
    "#9FC49C": ("artSageDeep", "#B6BB9E"),
    "#7BA67D": ("artSageLine", "#959A7C"),
    "#F4B4C2": ("artSand", "#E3D3C6"),
    "#D8C6F0": ("artStone", "#DCD3CA"),
    "#FBE9A6": ("artButter", "#EFE3C8"),
    "#DDBB4E": ("artButterLine", "#CDB98F"),
    "#FFF7EA": ("signPanel", "#FFF7EA"),
    "#6A1F58": ("accent", "#4B3628"),
}

HEX = re.compile(r"#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")


# ----- colour ---------------------------------------------------------------------------------


def parse_hex(text: str) -> tuple[int, int, int]:
    text = text.lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def to_hex(rgb: tuple[float, float, float]) -> str:
    # Half rounds up, as Swift's rounded() does, so the tests can recompute the dark values.
    return "#%02X%02X%02X" % tuple(max(0, min(255, math.floor(c + 0.5))) for c in rgb)


def _linear(c: float) -> float:
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gamma(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)


def to_oklch(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    r, g, b = (_linear(c) for c in rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return lightness, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def from_oklch(lightness: float, chroma: float, hue: float) -> tuple[float, float, float]:
    a = chroma * math.cos(math.radians(hue))
    b = chroma * math.sin(math.radians(hue))
    l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return _gamma(r), _gamma(g), _gamma(bl)


def warm(source: str) -> str:
    """The warm neutral version of a mockup colour.

    Fitted to the pairs Lily approved (room.css colour -> palette-warm colour): lightness stays,
    greens keep some of their colour and turn olive (sage), yellows and woods soften toward
    sand, and pinks, purples and blues become warm stone.
    """
    key = to_hex(parse_hex(source))
    if key in TOKEN_COLOURS:
        return TOKEN_COLOURS[key][1]
    lightness, chroma, hue = to_oklch(parse_hex(key))
    if chroma < 0.012:  # whites, greys: already neutral
        return key
    if 100 <= hue < 175:  # greens: leaves, sage
        hue, chroma = hue - 25, chroma * 0.58
    elif 55 <= hue < 100:  # yellows, wood, cream
        hue, chroma = 75 + (hue - 75) * 0.6, chroma * 0.45
    else:  # pinks, reds, purples, blues
        hue, chroma = 65, chroma * 0.3
    return to_hex(from_oklch(lightness, chroma, hue))


def sky(source: str) -> str:
    """Window colours: blues (the sky, rain, the night) keep their hue with much less colour, so
    each weather still reads at a glance. Everything else in a window is warmed as usual."""
    key = to_hex(parse_hex(source))
    lightness, chroma, hue = to_oklch(parse_hex(key))
    if key in TOKEN_COLOURS or chroma < 0.012 or not 200 <= hue < 300:
        return warm(key)
    return to_hex(from_oklch(lightness, chroma * 0.4, hue))


def dim(light: str, factors: tuple[float, float, float] = (0.66, 0.66, 0.62)) -> str:
    """Dark appearance: the light colour in lamplight (DesignSystem/README.md)."""
    return to_hex(tuple(c * f for c, f in zip(parse_hex(light), factors)))


def garment_dark(light: str) -> str:
    return dim(light, (0.92, 0.92, 0.92))


def faded(light: str) -> str:
    """The mockup's faded hamper, `filter: saturate(.4) brightness(1.1) contrast(.8)`, baked in."""
    r, g, b = parse_hex(light)
    s = 0.4
    # CSS saturate() matrix
    rgb = (
        (0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * b,
        (0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * b,
        (0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * b,
    )
    rgb = tuple(min(255.0, c * 1.1) for c in rgb)
    rgb = tuple((c / 255 - 0.5) * 0.8 * 255 + 127.5 for c in rgb)
    return to_hex(rgb)


# Drawings whose blues are sky, not furniture: they keep a little of their colour (see `sky`).
SKIES = {"window-cloudy", "window-night", "window-plain", "window-rain", "window-snow", "window-sun"}

# Drawings made from another drawing: name -> (source drawing, colour change after the warm map).
DERIVED = {
    "home-hamper-faded": ("home-hamper", faded),
}


# ----- SVG ------------------------------------------------------------------------------------


def tag(element: ET.Element) -> str:
    return element.tag.split("}")[-1]


def inline_uses(root: ET.Element) -> None:
    """Replaces each <use> with a group holding a copy of what it points to."""
    by_id = {e.get("id"): e for e in root.iter() if e.get("id")}
    for _ in range(10):  # templates can use other templates
        found = False
        for parent in list(root.iter()):
            for index, child in enumerate(list(parent)):
                if tag(child) != "use":
                    continue
                found = True
                href = child.get("href") or child.get(f"{{{XLINK_NS}}}href")
                target = by_id[href.lstrip("#")]
                clone = copy.deepcopy(target)
                for e in clone.iter():
                    e.attrib.pop("id", None)
                transform = child.get("transform", "")
                x, y = child.get("x"), child.get("y")
                if x or y:
                    transform = f"{transform} translate({x or 0} {y or 0})".strip()
                extra = {k: v for k, v in child.attrib.items() if k not in ("href", f"{{{XLINK_NS}}}href", "x", "y", "transform")}
                if tag(parent) == "clipPath":
                    # A clip path takes shapes, not groups.
                    clone.attrib.update(extra)
                    if transform:
                        clone.set("transform", f"{transform} {clone.get('transform', '')}".strip())
                    replacement = clone
                else:
                    replacement = ET.Element(f"{{{SVG_NS}}}g", extra)
                    if transform:
                        replacement.set("transform", transform)
                    replacement.append(clone)
                parent.remove(child)
                parent.insert(index, replacement)
        if not found:
            return
    raise SystemExit("<use> nesting is deeper than expected")


def recolour(root: ET.Element, mapping) -> set[str]:
    seen = set()

    def replace(match: re.Match) -> str:
        source = to_hex(parse_hex(match.group(0)))
        seen.add(source)
        return mapping(source)

    for element in root.iter():
        for key, value in element.attrib.items():
            if HEX.search(value):
                element.set(key, HEX.sub(replace, value))
    return seen


def write_svg(root: ET.Element, path: Path) -> None:
    ET.indent(root, space="  ")
    path.write_text(ET.tostring(root, encoding="unicode") + "\n")


def contents_json(name: str) -> str:
    contents = {
        "images": [
            {"filename": f"{name}.svg", "idiom": "universal"},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": f"{name}-dark.svg",
                "idiom": "universal",
            },
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }
    return json.dumps(contents, indent=2) + "\n"


def main() -> None:
    sources = sorted(SOURCE.glob("*.svg"))
    if not sources:
        sys.exit(f"No drawings in {SOURCE}")
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for old in CATALOG.glob("*.imageset"):
        for file in old.iterdir():
            file.unlink()
        old.rmdir()

    palette = {}
    drawings = [(source.stem, source, None) for source in sources]
    drawings += [(name, SOURCE / f"{base}.svg", change) for name, (base, change) in sorted(DERIVED.items())]
    for name, source, change in drawings:
        light = ET.parse(source).getroot()
        inline_uses(light)
        dark = copy.deepcopy(light)
        if name in GARMENTS:
            recolour(dark, garment_dark)
        elif name in KEEP_COLOURS:
            recolour(dark, dim)
        else:
            shade = change or (lambda c: c)
            base = sky if name in SKIES else warm
            colours = recolour(light, lambda c: shade(base(c)))
            recolour(dark, lambda c: dim(shade(base(c))))
            for colour in colours:
                entry = palette.setdefault(colour, {"light": warm(colour), "dark": dim(warm(colour))})
                if colour in TOKEN_COLOURS:
                    entry["token"] = TOKEN_COLOURS[colour][0]
                if base is sky and sky(colour) != warm(colour):
                    entry["sky"] = sky(colour)
                if change:
                    entry["faded"] = shade(base(colour))
        imageset = CATALOG / f"{name}.imageset"
        imageset.mkdir()
        write_svg(light, imageset / f"{name}.svg")
        write_svg(dark, imageset / f"{name}-dark.svg")
        (imageset / "Contents.json").write_text(contents_json(name))
        print(f"wrote {imageset.relative_to(ROOT)}")

    ordered = {k: palette[k] for k in sorted(palette)}
    PALETTE_MAP.write_text(json.dumps(ordered, indent=2) + "\n")
    print(f"wrote {PALETTE_MAP.relative_to(ROOT)} ({len(ordered)} colours)")


if __name__ == "__main__":
    main()
