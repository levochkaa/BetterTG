#!/usr/bin/env python3
"""App Store screenshots, product page header and search results asset, after Telegram's screenshots: a caption over a
gradient and the app's screens in phone frames.

Usage: script/app_store_screenshots.py RAW ASO OUT [LOCALE...]

RAW/<language> holds the readme demo's screens at device resolution in one app language, taken on an iPhone 17 Pro Max
(1320x2868): chats-light, chat-light, menu2-light (a photo's menu), group-dark, attach-dark (three photos picked) and
bettertg-dark (Settings > BetterTG), plus duo, an unfolded iPhone Duo with Mia Chen open, at 2x. ASO/<locale>.json is
the locale's App Store text: its subtitle heads the header, and captions holds the seven [title, "line\\nline"] pairs.
RAW/<language> also holds the unfolded Duo's duo-chat-light, duo-menu-light, duo-group-dark, duo-attach-dark and
duo-bettertg-dark at 3x (2853x2007). OUT/<locale> gets 01…07 (6.9" screenshots), duo-01…05 (iPhone Duo), header.png (3840x1646) and search.png (3600x2400). Without locales it
renders every ASO file.
"""
import argparse
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
FONTS = Path("/System/Library/Fonts")
SCREENS = ["chats-light", "chat-light", "menu2-light", "group-dark", "attach-dark", "bettertg-dark", "duo"]

# The app language each App Store locale's screens show: Telegram's language packs, else English.
UI_LANGUAGE = {
    "ar-SA": "ar", "ca": "ca", "cs": "cs", "de-DE": "de", "es-ES": "es", "es-MX": "es", "fi": "fi", "fr-CA": "fr",
    "fr-FR": "fr", "he": "he", "hr": "hr", "hu": "hu", "id": "id", "it": "it", "ko": "ko", "ms": "ms", "nl-NL": "nl",
    "no": "nb", "pl": "pl", "pt-BR": "pt-br", "pt-PT": "pt-br", "ro": "ro", "ru": "ru", "sk": "sk", "sv": "sv",
    "tr": "tr", "uk": "uk", "vi": "vi", "zh-Hans": "zh-hans", "zh-Hant": "zh-hant",
}
RTL = {"ar-SA", "he"}

# Brand blue #1A9AF1 leads; neighbours on the wheel keep the set together, as Telegram's colours do.
PALETTE = [
    ((40, 170, 255), (20, 90, 230)),
    ((70, 120, 255), (110, 60, 220)),
    ((130, 90, 250), (200, 80, 200)),
    ((20, 70, 170), (10, 30, 90)),
    ((30, 190, 210), (20, 110, 220)),
    ((90, 70, 200), (30, 30, 110)),
    ((40, 160, 255), (60, 70, 220)),
]


def sf(size, weight, width=100):
    f = ImageFont.truetype(str(FONTS / "SFNS.ttf"), size)
    f.set_variation_by_axes([width, min(96, size / 3), 400, weight])
    return f


def variable(name, size, weight):
    f = ImageFont.truetype(str(FONTS / name), size)
    f.set_variation_by_axes([weight, min(80, size / 3)] if "Arabic" in name else [weight, 28])
    return f


class Mixed:
    """A right-to-left script's font with SF for the Latin runs it has no glyphs for, such as "iOS"."""

    def __init__(self, script, latin):
        self.script, self.latin, self.size = script, latin, script.size

    def runs(self, text):
        """Logical runs of (text, uses_latin_font, space_before): Latin phrases stay whole and left to right, and ASCII
        punctuation, which the script fonts lack, takes the Latin font."""
        out, space = [], False
        for token in re.findall(r"\s+|[A-Za-z0-9]+(?:[.'’-][A-Za-z0-9]+)*|[!-/:-@\[-`{-~]+|[^\sA-Za-z0-9!-/:-@\[-`{-~]+", text):
            if token.isspace():
                space = True
                continue
            kind = "latin" if token[0].isascii() and token[0].isalnum() else "punct" if token[0].isascii() else "script"
            if out and out[-1][3] == kind and kind != "punct":
                out[-1] = (out[-1][0] + (" " if space else "") + token, out[-1][1], out[-1][2], kind)
            else:
                out.append((token, kind != "script", space, kind))
            space = False
        return [run[:3] for run in out]

    def font(self, latin):
        return self.latin if latin else self.script

    def length(self, draw, text):
        gap = draw.textlength(" ", font=self.script)
        return sum(draw.textlength(t, font=self.font(l)) + (gap if sp else 0) for t, l, sp in self.runs(text))

    def draw(self, draw, x, y, text, fill):
        """Right to left: the first run at the right edge."""
        gap = draw.textlength(" ", font=self.script)
        right = x + self.length(draw, text)
        for t, latin, space in self.runs(text):
            right -= gap if space else 0
            w = draw.textlength(t, font=self.font(latin))
            dy = (self.script.size - self.font(latin).size) / 2
            draw.text((right - w, y + dy), t, font=self.font(latin), fill=fill,
                      direction=None if latin else "rtl")
            right -= w


def length(draw, text, font):
    return font.length(draw, text) if isinstance(font, Mixed) else draw.textlength(text, font=font)


def fonts(locale):
    """(title, body) font factories by size: SF where it has the script, else the system's font for it."""
    bold = {
        "ar-SA": lambda s: Mixed(variable("SFArabic.ttf", s, 800), sf(s, 800)),
        "he": lambda s: Mixed(variable("SFHebrew.ttf", s, 800), sf(s, 800)),
        "ja": lambda s: ImageFont.truetype(str(FONTS / "ヒラギノ角ゴシック W8.ttc"), s),
        "ko": lambda s: ImageFont.truetype(str(FONTS / "AppleSDGothicNeo.ttc"), s, index=16),
        "zh-Hans": lambda s: ImageFont.truetype(str(FONTS / "Hiragino Sans GB.ttc"), s, index=2),
        "zh-Hant": lambda s: ImageFont.truetype(str(FONTS / "Hiragino Sans GB.ttc"), s, index=2),
        "th": lambda s: ImageFont.truetype(str(FONTS / "Supplemental/SukhumvitSet.ttc"), s, index=5),
        "hi": lambda s: ImageFont.truetype(str(FONTS / "Kohinoor.ttc"), s, index=3),
    }
    regular = {
        "ar-SA": lambda s: Mixed(variable("SFArabic.ttf", s, 500), sf(s, 500)),
        "he": lambda s: Mixed(variable("SFHebrew.ttf", s, 500), sf(s, 500)),
        "ja": lambda s: ImageFont.truetype(str(FONTS / "ヒラギノ角ゴシック W4.ttc"), s),
        "ko": lambda s: ImageFont.truetype(str(FONTS / "AppleSDGothicNeo.ttc"), s, index=2),
        "zh-Hans": lambda s: ImageFont.truetype(str(FONTS / "Hiragino Sans GB.ttc"), s, index=0),
        "zh-Hant": lambda s: ImageFont.truetype(str(FONTS / "Hiragino Sans GB.ttc"), s, index=0),
        "th": lambda s: ImageFont.truetype(str(FONTS / "Supplemental/SukhumvitSet.ttc"), s, index=3),
        "hi": lambda s: ImageFont.truetype(str(FONTS / "Kohinoor.ttc"), s, index=1),
    }
    return bold.get(locale, lambda s: sf(s, 860, 125)), regular.get(locale, lambda s: sf(s, 500))


def gradient(size, top, bottom, horizontal=False):
    w, h = size
    g = Image.new("RGB", (256, 1) if horizontal else (1, 256))
    for i in range(256):
        t = i / 255
        g.putpixel((i, 0) if horizontal else (0, i), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    bg = g.resize(size, Image.BICUBIC)
    # A soft light in the upper corner, so the flat gradient reads as lit.
    glow = Image.new("L", size, 0)
    ImageDraw.Draw(glow).ellipse((-w * 0.38, -h * 0.24, w * 0.83, h * 0.31), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.09))
    return Image.composite(Image.new("RGB", size, (255, 255, 255)), bg, glow).convert("RGBA")


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def phone(screen, screen_width, corner=None, island=True, bezel=22):
    """The screen in a black bezel with a thin titanium edge and the Dynamic Island."""
    s = screen_width / screen.width
    corner = corner if corner is not None else round(62 * 3 * s)
    bezel = round(bezel * screen_width / 1010) if island else bezel
    screen = screen.convert("RGB").resize((screen_width, round(screen.height * s)), Image.LANCZOS)
    sw, sh = screen.size
    rim = max(3, round(5 * screen_width / 1010))
    fw, fh = sw + 2 * (bezel + rim), sh + 2 * (bezel + rim)
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, fw - 1, fh - 1), corner + bezel + rim, fill=(150, 155, 165, 255))
    d.rounded_rectangle((rim, rim, fw - 1 - rim, fh - 1 - rim), corner + bezel, fill=(8, 8, 10, 255))
    frame.paste(screen, (bezel + rim, bezel + rim), rounded_mask(screen.size, corner))
    if island:
        iw, ih = round(125 * 3 * s), round(37 * 3 * s)
        x0, y0 = (fw - iw) // 2, bezel + rim + round(11 * 3 * s)
        d.rounded_rectangle((x0, y0, x0 + iw, y0 + ih), ih // 2, fill=(0, 0, 0, 255))
    return frame


def place(canvas, device, x, y, blur=50):
    a = device.split()[3].point(lambda v: 90 if v else 0)
    sh = Image.new("RGBA", (device.width + 4 * blur, device.height + 4 * blur), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", device.size, (0, 0, 40, 255)), (2 * blur, 2 * blur + blur * 3 // 5), a)
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)), (x - 2 * blur, y - 2 * blur))
    canvas.alpha_composite(device, (x, y))


def fit(draw, lines, factory, size, width):
    """The largest font up to size whose widest line fits."""
    while size > 20:
        f = factory(size)
        if max(length(draw, l, f) for l in lines) <= width:
            return f
        size -= 2
    return factory(size)


def text_lines(canvas, lines, font, y, step, align="center", x=None, fill="white"):
    d = ImageDraw.Draw(canvas)
    for line in lines:
        lw = length(d, line, font)
        lx = (canvas.width - lw) / 2 if align == "center" else x if align == "left" else x - lw
        if isinstance(font, Mixed):
            font.draw(d, lx, y, line, fill)
        else:
            d.text((lx, y), line, font=font, fill=fill)
        y += step
    return y


def screenshots(locale, raw, aso, out):
    bold, regular = fonts(locale)
    for i, (screen, (title, subtitle)) in enumerate(zip(SCREENS, aso["captions"])):
        canvas = gradient((W, H), *PALETTE[i])
        d = ImageDraw.Draw(canvas)
        tf = fit(d, [title], bold, 128, W - 140)
        text_lines(canvas, [title], tf, 150, 0)
        lines = subtitle.split("\n")
        sf_ = fit(d, lines, regular, 54, W - 120)
        bottom = text_lines(canvas, lines, sf_, 150 + tf.size + 46, round(sf_.size * 1.33))
        shot = Image.open(raw / f"{screen}.png")
        if screen == "duo":
            # Large, running off the edge: the list whole and the chat beside it.
            dev = phone(shot, 2050, 70, island=False, bezel=40)
            y = bottom + (H - bottom - dev.height) // 2 - 40
            # The split view keeps the list on the left in right-to-left languages too.
            place(canvas, dev, 80, y)
        else:
            dev = phone(shot, 1010)
            place(canvas, dev, (W - dev.width) // 2, bottom + 70)
        canvas.convert("RGB").save(out / f"{i + 1:02d}-{screen.split('-')[0]}.png", optimize=True)


# The unfolded iPhone Duo's own screenshots: its screen at 3x and the slide whose caption each takes.
DUO_SCREENS = [("duo-chat-light", 6), ("duo-menu-light", 2), ("duo-group-dark", 3), ("duo-attach-dark", 4),
               ("duo-bettertg-dark", 5)]


def duo_screenshots(locale, raw, aso, out):
    """2853x2007, the unfolded iPhone Duo's landscape: the caption on one line over the device."""
    dw, dh = 2853, 2007
    bold, regular = fonts(locale)
    for i, (screen, caption) in enumerate(DUO_SCREENS):
        title, subtitle = aso["captions"][caption]
        canvas = gradient((dw, dh), *PALETTE[caption])
        d = ImageDraw.Draw(canvas)
        tf = fit(d, [title], bold, 140, dw - 200)
        text_lines(canvas, [title], tf, 90, 0)
        line = " ".join(subtitle.split("\n"))
        sf_ = fit(d, [line], regular, 64, dw - 200)
        bottom = text_lines(canvas, [line], sf_, 90 + tf.size + 40, 0) + sf_.size
        dev = phone(Image.open(raw / f"{screen}.png"), 2010, 90, island=False, bezel=44)
        place(canvas, dev, (dw - dev.width) // 2, max(bottom + 70, dh - dev.height - 40))
        canvas.convert("RGB").save(out / f"duo-{i + 1:02d}.png", optimize=True)


def header(locale, raw, aso, out):
    """21:9, 3840x1646: the subtitle over three phones rising from the bottom edge, all in the middle."""
    hw, hh = 3840, 1646
    canvas = gradient((hw, hh), (40, 150, 255), (120, 70, 230), horizontal=True)
    bold, _ = fonts(locale)
    d = ImageDraw.Draw(canvas)
    tf = fit(d, [aso["subtitle"]], bold, 150, 2600)
    text_lines(canvas, [aso["subtitle"]], tf, 130, 0)
    top = 130 + tf.size + 130
    side = [phone(Image.open(raw / f"{n}.png"), 640) for n in ("chat-light", "group-dark")]
    middle = phone(Image.open(raw / "chats-light.png"), 760)
    for dev, dx in zip(side, (-760, 760)):
        place(canvas, dev, (hw - dev.width) // 2 + dx, top + 150)
    place(canvas, middle, (hw - middle.width) // 2, top)
    canvas.convert("RGB").save(out / "header.png", optimize=True)


def search(locale, raw, aso, out):
    """3:2, 3600x2400: the first caption beside two phones."""
    sw, sh = 3600, 2400
    canvas = gradient((sw, sh), *PALETTE[0])
    bold, regular = fonts(locale)
    d = ImageDraw.Draw(canvas)
    title, subtitle = aso["captions"][0]
    rtl = locale in RTL
    tf = fit(d, [title], bold, 300, 1500)
    lines = subtitle.split("\n")
    bf = fit(d, lines, regular, 120, 1500)
    block = tf.size + 90 + len(lines) * round(bf.size * 1.3)
    y = (sh - block) // 2 - 60
    x = sw - 220 if rtl else 220
    align = "right" if rtl else "left"
    text_lines(canvas, [title], tf, y, 0, align, x)
    text_lines(canvas, lines, bf, y + tf.size + 90, round(bf.size * 1.3), align, x, (255, 255, 255, 235))
    back = phone(Image.open(raw / "group-dark.png"), 780)
    front = phone(Image.open(raw / "chats-light.png"), 860)
    for dev, x, y in ((back, 2640, 470), (front, 1900, 260)):
        place(canvas, dev, sw - x - dev.width if rtl else x, y)
    canvas.convert("RGB").save(out / "search.png", optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("raw", type=Path)
    parser.add_argument("aso", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("locales", nargs="*")
    args = parser.parse_args()
    locales = args.locales or sorted(p.stem for p in args.aso.glob("*.json"))
    for locale in locales:
        aso = json.loads((args.aso / f"{locale}.json").read_text())
        raw = args.raw / UI_LANGUAGE.get(locale, "en")
        out = args.out / locale
        out.mkdir(parents=True, exist_ok=True)
        screenshots(locale, raw, aso, out)
        duo_screenshots(locale, raw, aso, out)
        header(locale, raw, aso, out)
        search(locale, raw, aso, out)
        print(out)


if __name__ == "__main__":
    main()
