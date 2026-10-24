#!/usr/bin/env python3
"""Builds Mindrop's custom symbols from the free Iconsax icons.

Usage: python3 Tools/MakeIconsaxSymbols.py <iconsax package dir>

The package is the official `iconsax` npm package (`npm pack iconsax`, then untar). Each icon
listed below is turned into an SF Symbol template by SwiftDraw (`brew install swiftdraw`) and
written to the asset catalog as `ix.<name>.<style>.symbolset`, so SwiftUI uses it like an SF
Symbol: `Image("ix.wifi.bulk")`.

Linear icons are strokes, so SwiftDraw derives a thinner and a heavier weight from them and
the symbol follows the text's weight. Bulk icons draw part of the shape at 40% opacity; those
parts become the symbol's secondary layer, so `.symbolRenderingMode(.hierarchical)` draws them
in a lighter shade of whatever colour the symbol is given.

Iconsax's free licence allows use in apps without attribution, but not redistributing the
icons as loose files: the symbols live only in the asset catalog.
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Mindrop/Resources/Assets.xcassets/Iconsax"
WATCH_CATALOG = ROOT / "MindropWatch/Assets.xcassets/Iconsax"

# (Iconsax name, style). Categories are Bulk; everything the user taps is Linear. Call and
# Tag are already in both styles below.
SYMBOLS = [
    # Categories, in MemoryCategory order, and the tag for memories without one.
    ("wifi", "bulk"), ("key", "bulk"), ("lock-circle", "bulk"), ("money", "bulk"), ("call", "bulk"),
    ("profile-2user", "bulk"), ("location", "bulk"), ("home-2", "bulk"), ("car", "bulk"),
    ("document-text", "bulk"), ("hospital", "bulk"), ("link", "bulk"), ("category", "bulk"), ("tag", "bulk"),
    # The same categories in Linear, for menus: they draw in one colour, where Bulk's soft
    # layer would cover its detail.
    ("wifi", "linear"), ("key", "linear"), ("lock-circle", "linear"), ("money", "linear"),
    ("profile-2user", "linear"), ("location", "linear"), ("home-2", "linear"), ("car", "linear"),
    ("document-text", "linear"), ("hospital", "linear"), ("link", "linear"), ("category", "linear"),
    # Actions and states.
    ("add", "linear"), ("trash", "linear"), ("undo-arrow", "linear"), ("copy", "linear"),
    ("export-arrow-01", "linear"), ("edit-2", "linear"), ("setting-2", "linear"), ("filter", "linear"),
    ("filter", "bold"), ("search-normal", "linear"), ("magic-star", "linear"), ("timer", "linear"),
    ("timer-pause", "linear"), ("calendar-remove", "linear"), ("layer", "linear"), ("tag", "linear"),
    ("info-circle", "linear"), ("danger", "linear"), ("unlock", "linear"), ("lock", "bold"),
    ("tick-circle", "linear"), ("global", "linear"), ("routing-2", "linear"), ("call", "linear"),
    ("arrow-right-02", "linear"), ("scan", "linear"), ("gallery", "linear"),
    # The empty Recently Deleted: its large icon, and the stages of a deleted memory.
    ("trash", "bulk"), ("clock", "linear"), ("close-circle", "linear"),
]

# Every icon is placed by the same fixed margin around Iconsax's 24-point grid, rather than
# fitted to its own outline, so icons keep their relative sizes (a plus stays smaller than a
# document) and sit at about 1.4 times the text's cap height, as SF Symbols do.
INSETS = "4.2,4.2,4.2,4.2"

# The few the Apple Watch app shows: Save, and the tick once saved.
WATCH_SYMBOLS = [("add", "linear"), ("tick-circle", "linear")]

SHAPE = re.compile(r"<(path|rect|circle|ellipse|line|polyline|polygon)\b([^>]*)>")


def source_svg(package: Path, name: str, style: str) -> str:
    manifest = json.loads((package / "dist/manifest.json").read_text())
    category = manifest[name]["category"]
    svg = json.loads((package / f"dist/data/{category}.json").read_text())[name][style]
    # Iconsax ships its icons in white or dark grey; the colour is the app's to choose.
    return re.sub(r'(fill|stroke)="(?!none)[^"]*"', r'\1="#000"', svg)


def secondary_flags(svg: str) -> list[bool]:
    """For each drawn shape, in order, whether it is one of Bulk's 40% parts."""
    body = re.sub(r"<defs>.*?</defs>", "", svg, flags=re.S)
    flags = []
    for _, attributes in SHAPE.findall(body):
        opacity = re.search(r'opacity="([\d.]+)"', attributes)
        flags.append(bool(opacity) and float(opacity.group(1)) < 1)
    return flags


def annotate(template: str, flags: list[bool]) -> str:
    """Puts each variant's paths on the primary or secondary layer, matching the source."""
    def annotate_group(match: re.Match) -> str:
        group = match.group(0)
        paths = re.findall(r"<path ", group)
        if len(paths) != len(flags):
            raise SystemExit(f"layer count mismatch: {len(paths)} paths for {len(flags)} shapes")
        index = iter(flags)

        def tag(_: re.Match) -> str:
            secondary = next(index)
            layer = "monochrome-1 hierarchical-1:secondary" if secondary else "monochrome-0 hierarchical-0:primary"
            return f'<path class="{layer}" '

        return re.sub(r"<path ", tag, group)

    return re.sub(r'<g id="(Ultralight|Regular|Black)-S"[^>]*>.*?</g>', annotate_group, template, flags=re.S)


def interpolatable(template: str) -> bool:
    """Whether the Ultralight, Regular and Black outlines have the same commands, path by path."""
    def commands(variant: str) -> list[str]:
        group = re.search(rf'<g id="{variant}-S"[^>]*>(.*?)</g>', template, re.S).group(1)
        return ["".join(re.findall(r"[MLCZHVQA]", d)) for d in re.findall(r'd="([^"]+)"', group)]
    return commands("Ultralight") == commands("Regular") == commands("Black")


def make(package: Path, name: str, style: str, catalog: Path = CATALOG) -> None:
    svg = source_svg(package, name, style)
    asset = f"ix.{name}.{style}"
    folder = catalog / f"{asset}.symbolset"
    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        source = Path(temporary) / f"{asset}.svg"
        source.write_text(svg)
        output = folder / f"{asset}.svg"
        command = ["swiftdraw", str(source), "--format", "sfsymbol", "--output", str(output),
                   "--insets", INSETS, "--ultralight-insets", INSETS, "--black-insets", INSETS]
        if style == "linear":
            subprocess.run(command + ["--ultralight-stroke-width", "0.6", "--black-stroke-width", "1.6"],
                           check=True, capture_output=True)
            # iOS draws the weights in between by interpolating the three outlines, which
            # needs the same points in each. Thickening some strokes changes their points,
            # and Xcode then leaves the symbol out without an error: those keep one weight.
            if not interpolatable(output.read_text()):
                subprocess.run(command, check=True, capture_output=True)
                print(f"  {asset}: one weight only")
        else:
            subprocess.run(command, check=True, capture_output=True)
    flags = secondary_flags(svg)
    if any(flags):
        output.write_text(annotate(output.read_text(), flags))
    (folder / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "symbols": [{"filename": f"{asset}.svg", "idiom": "universal"}],
    }, indent=2) + "\n")


def main() -> None:
    package = Path(sys.argv[1])
    for catalog, symbols in ((CATALOG, SYMBOLS), (WATCH_CATALOG, WATCH_SYMBOLS)):
        catalog.mkdir(parents=True, exist_ok=True)
        (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
        for name, style in symbols:
            make(package, name, style, catalog)
            print(f"{catalog.parent.parent.name}: ix.{name}.{style}")


if __name__ == "__main__":
    main()
