#!/usr/bin/env python3
"""Export app, launch, README and website icons from docs/branding/bettertg-icon.svg.

Run after editing the SVG. Requires rsvg-convert from librsvg.
"""

from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "BetterTG/Assets.xcassets"
SVG_NAMESPACE = "http://www.w3.org/2000/svg"


def main() -> None:
    renderer = shutil.which("rsvg-convert")
    if renderer is None:
        raise SystemExit("rsvg-convert is required to export the app icons.")

    source = (ROOT / "docs/branding/bettertg-icon.svg").read_bytes()

    def render(svg: bytes, path: Path, size: int) -> None:
        subprocess.run(
            [renderer, "--width", str(size), "--height", str(size), "--output", str(path)],
            input=svg,
            check=True,
        )

    # iOS masks the app and Home Screen bookmark icons itself.
    render(source, ASSETS / "AppIcon.appiconset/bettertg.png", 1024)
    shutil.copyfile(ASSETS / "AppIcon.appiconset/bettertg.png", ROOT / "docs/branding/bettertg-icon.png")
    render(source, ROOT / "Website/icon.png", 256)

    # Images shown in content need their own rounded background.
    ET.register_namespace("", SVG_NAMESPACE)
    rounded = ET.fromstring(source)
    background = rounded.find(f"{{{SVG_NAMESPACE}}}rect[@id='background']")
    if background is None:
        raise SystemExit("The icon SVG must contain a background rectangle.")
    background.set("rx", "224")
    rounded_svg = ET.tostring(rounded, encoding="utf-8") + b"\n"
    (ROOT / "Website/icon.svg").write_bytes(rounded_svg)
    render(rounded_svg, ASSETS / "AppIcon_README.imageset/bettertg256.png", 256)
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        render(
            rounded_svg,
            ASSETS / f"launchScreen.imageset/bettertg-launchScreen128{suffix}.png",
            128 * scale,
        )


if __name__ == "__main__":
    main()
