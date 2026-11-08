#!/usr/bin/env python3
"""App Store screenshots: a caption over a gradient and the screen in a phone frame, after Telegram's.

Usage: script/app_store_screenshots.py RAW OUT [en] [ru]

RAW holds the readme demo's screens at device resolution, taken on an iPhone 17 Pro Max (1320x2868):
chats-light, chat-light, menu2-light (a photo's menu), group-dark, attach-dark (three photos picked) and
bettertg-dark (Settings > BetterTG); RAW/ru the same in Russian. duo-en and duo-ru are an unfolded iPhone Duo with
Mia Chen open, at 2x. OUT/<lang> gets the 6.9" screenshots in their order.
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument("raw", type=Path)
parser.add_argument("out", type=Path)
parser.add_argument("languages", nargs="*", default=["en", "ru"])
ARGS = parser.parse_args()
RAW = ARGS.raw
OUT = ARGS.out
W, H = 1320, 2868
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight, width=100):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([width, min(96, size / 3), 400, weight])
    return f


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

SLIDES = {
    "en": [
        ("chats-light", "Native", "Open source and written in UIKit.\nFast and smooth on every iPhone."),
        ("chat-light", "Familiar", "Photos, replies, reactions,\nvoice messages and link previews."),
        ("menu2-light", "Liquid Glass", "Menus, bars and buttons\nin the new iOS design."),
        ("group-dark", "Groups", "Polls, pinned messages\nand reactions."),
        ("attach-dark", "Sharing", "Photos, files, polls, checklists,\nlocations and contacts."),
        ("bettertg-dark", "Yours", "Hide the tab bar or stories,\nmove folder tabs up or down."),
        ("duo-en", "iPhone Duo", "The chat list and the chat\nside by side when it's unfolded."),
    ],
    "ru": [
        ("chats-light", "Нативный", "Открытый код и UIKit:\nбыстро и плавно на любом iPhone."),
        ("chat-light", "Привычный", "Фото, ответы, реакции,\nголосовые и превью ссылок."),
        ("menu2-light", "Liquid Glass", "Меню, панели и кнопки\nв новом дизайне iOS."),
        ("group-dark", "Группы", "Опросы, закреплённые\nсообщения и реакции."),
        ("attach-dark", "Вложения", "Фото, файлы, опросы, чек-листы,\nгеопозиция и контакты."),
        ("bettertg-dark", "Под себя", "Скройте панель вкладок или истории,\nперенесите вкладки папок."),
        ("duo-ru", "iPhone Duo", "Список чатов и чат рядом,\nкогда iPhone раскрыт."),
    ],
}


def gradient(top, bottom):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    bg = g.resize((W, H), Image.BICUBIC)
    # A soft light in the upper corner, so the flat gradient reads as lit.
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-500, -700, 1100, 900), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(260))
    return Image.composite(Image.new("RGB", (W, H), (255, 255, 255)), bg, glow)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def phone(screen, screen_width, corner, island=True, bezel=22):
    """The screen in a black bezel with a thin titanium edge and the Dynamic Island."""
    s = screen_width / screen.width
    screen = screen.convert("RGB").resize((screen_width, round(screen.height * s)), Image.LANCZOS)
    sw, sh = screen.size
    rim = 5
    fw, fh = sw + 2 * (bezel + rim), sh + 2 * (bezel + rim)
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, fw - 1, fh - 1), corner + bezel + rim, fill=(150, 155, 165, 255))
    d.rounded_rectangle((rim, rim, fw - 1 - rim, fh - 1 - rim), corner + bezel, fill=(8, 8, 10, 255))
    frame.paste(screen, (bezel + rim, bezel + rim), rounded_mask(screen.size, corner))
    if island:
        iw, ih = round(125 * 3 * s), round(37 * 3 * s)
        x0 = (fw - iw) // 2
        y0 = bezel + rim + round(11 * 3 * s)
        d.rounded_rectangle((x0, y0, x0 + iw, y0 + ih), ih // 2, fill=(0, 0, 0, 255))
    return frame


def shadow(img, offset=30, blur=50, alpha=90):
    a = img.split()[3].point(lambda v: alpha if v else 0)
    sh = Image.new("RGBA", (img.width + 4 * blur, img.height + 4 * blur), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", img.size, (0, 0, 40, 255)), (2 * blur, 2 * blur + offset), a)
    return sh.filter(ImageFilter.GaussianBlur(blur)), 2 * blur


def draw_caption(canvas, title, subtitle, top):
    d = ImageDraw.Draw(canvas)
    tf = font(128, 860, 125)
    while d.textlength(title, font=tf) > W - 140:
        tf = font(tf.size - 6, 860, 125)
    tw = d.textlength(title, font=tf)
    d.text(((W - tw) / 2, top), title, font=tf, fill="white")
    sf = font(54, 500)
    y = top + tf.size + 46
    for line in subtitle.split("\n"):
        lw = d.textlength(line, font=sf)
        d.text(((W - lw) / 2, y), line, font=sf, fill=(255, 255, 255, 235))
        y += 72
    return y


def render(lang):
    out = OUT / lang
    out.mkdir(parents=True, exist_ok=True)
    raw = RAW if lang == "en" else RAW / "ru"
    for i, (name, title, subtitle) in enumerate(SLIDES[lang]):
        canvas = gradient(*PALETTE[i]).convert("RGBA")
        text_bottom = draw_caption(canvas, title, subtitle, 150)
        src = RAW / f"{name}.png" if name.startswith("duo") else raw / f"{name}.png"
        shot = Image.open(src)
        if name.startswith("duo"):
            # Large, running off the right edge: the list whole and the chat beside it.
            dev = phone(shot, 2050, 70, island=False, bezel=40)
            top = text_bottom + (H - text_bottom - dev.height) // 2 - 40
            sh, pad = shadow(dev)
            canvas.alpha_composite(sh, (80 - pad, top - pad))
            canvas.alpha_composite(dev, (80, top))
            canvas.convert("RGB").save(out / f"{i + 1:02d}-duo.png", optimize=True)
            continue
        else:
            dev = phone(shot, 1010, round(62 * 3 * 1010 / 1320))
            top = text_bottom + 70
        sh, pad = shadow(dev)
        x = (W - dev.width) // 2
        canvas.alpha_composite(sh, (x - pad, top - pad))
        canvas.alpha_composite(dev, (x, top))
        canvas.convert("RGB").save(out / f"{i + 1:02d}-{name.split('-')[0]}.png", optimize=True)
        print(out / f"{i + 1:02d}-{name.split('-')[0]}.png")


for lang in ARGS.languages:
    render(lang)
