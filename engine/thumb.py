#!/usr/bin/env python3
"""Code-made thumbnails (free): 1080x1920 Instagram cover + 1280x720 YouTube thumbnail.
usage: thumb.py out_prefix "LINE1" "LINE2" "YELLOW_WORDS" "@handle" frame1.jpg [frame2.jpg frame3.jpg]
 - LINE1/LINE2: headline lines (2-4 words total, uppercase applied with Turkish rules)
 - YELLOW_WORDS: words (space separated) painted yellow
 - 1 frame = full background; 3 frames = collage
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "/usr/share/fonts/truetype/google-fonts/ofl/anton/Anton-Regular.ttf"
YEL = (255, 214, 10); WHITE = (255, 255, 255)

def tr_upper(s):
    return s.replace("i", "İ").replace("ı", "I").upper()

def cover(img, w, h, fy=0.5):
    s = max(w / img.width, h / img.height)
    im = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x = (im.width - w) // 2; y = int((im.height - h) * fy)
    return im.crop((x, y, x + w, y + h))

def background(frames, w, h, fy):
    if len(frames) == 1:
        return cover(frames[0], w, h, fy)
    bg = Image.new("RGB", (w, h))
    n = len(frames)
    if w > h:   # side by side
        pw = w // n
        for i, f in enumerate(frames):
            bg.paste(cover(f, pw, h, fy), (i * pw, 0))
    else:       # stacked
        ph = h // n
        for i, f in enumerate(frames):
            bg.paste(cover(f, w, ph, 0.5), (0, i * ph))
    return bg

def gradient(w, h, y0, y1, a0, a1):
    g = Image.new("L", (w, h), 0); d = ImageDraw.Draw(g)
    for y in range(h):
        if y < y0 or y > y1: continue
        t = (y - y0) / max(1, y1 - y0)
        d.line([(0, y), (w, y)], fill=int(a0 + (a1 - a0) * t))
    return g

def draw_lines(img, lines, yellow, cx, cy, maxw, size):
    d = ImageDraw.Draw(img)
    yellow = {tr_upper(w) for w in yellow}
    while True:
        f = ImageFont.truetype(FONT, size)
        widths = [d.textlength(l, font=f) for l in lines]
        if max(widths) <= maxw or size < 40: break
        size -= 6
    lh = int(size * 1.08); top = cy - lh * len(lines) // 2
    for i, l in enumerate(lines):
        x = cx - widths[i] / 2; y = top + i * lh
        for wd in l.split(" "):
            col = YEL if wd.strip("?!.,") in {w.strip("?!.,") for w in yellow} or wd in yellow else WHITE
            d.text((x, y), wd, font=f, fill=col, stroke_width=max(4, size // 14), stroke_fill=(10, 10, 14))
            x += d.textlength(wd + " ", font=f)
    return top, top + lh * len(lines)

def mark(img, text, x, y, size):
    d = ImageDraw.Draw(img); f = ImageFont.truetype(FONT, size)
    tw = d.textlength(text, font=f); pad = size // 2
    d.rounded_rectangle([x - tw / 2 - pad, y - pad // 2, x + tw / 2 + pad, y + size + pad // 2], radius=size, fill=(0, 0, 0, 170))
    d.text((x - tw / 2, y - size * 0.12), text, font=f, fill=WHITE)

def main():
    args = sys.argv[1:]
    stack = "--stack" in args
    short = "--short" in args
    args = [a for a in args if a not in ("--stack", "--short")]
    sys.argv = [sys.argv[0]] + args
    out, l1, l2, yel, handle = sys.argv[1:6]
    if short:
        return universal(out, l1, l2, yel, handle, Image.open(sys.argv[6]).convert("RGB"))
    if stack:
        return stacked(out, l1, l2, yel, handle, Image.open(sys.argv[6]).convert("RGB"))
    frames = [Image.open(p).convert("RGB") for p in sys.argv[6:]]
    lines = [tr_upper(x) for x in (l1, l2) if x]
    yellow = yel.split()
    # vertical cover: text in the centre square (y 420-1500) so it survives the profile-grid crop
    v = background(frames, 1080, 1920, 0.5).convert("RGBA")
    shade = Image.new("RGBA", v.size, (6, 8, 16, 255))
    band = Image.new("L", v.size, 25); bd = ImageDraw.Draw(band)
    bd.rectangle([0, 560, 1080, 960], fill=150)
    band = band.filter(ImageFilter.GaussianBlur(120))
    v = Image.composite(shade, v, band)
    draw_lines(v, lines, yellow, 540, 760, 980, 230)
    mark(v, handle, 540, 1380, 46)
    v.convert("RGB").save(out + "_cover.jpg", quality=92)
    # landscape YouTube thumbnail
    h = background(frames, 1280, 720, 0.45).convert("RGBA")
    sh2 = Image.new("RGBA", h.size, (6, 8, 16, 255))
    lg = Image.new("L", h.size, 0); ld = ImageDraw.Draw(lg)
    for x in range(1280):
        ld.line([(x, 0), (x, 720)], fill=int(max(0, 190 - x * 0.24)))
    h = Image.composite(sh2, h, lg)
    draw_lines(h, lines, yellow, 380, 330, 700, 150)
    mark(h, handle, 380, 600, 30)
    h.convert("RGB").save(out + "_thumb.jpg", quality=92)
    print(out + "_cover.jpg", out + "_thumb.jpg")

def stacked(out, l1, l2, yel, handle, fr):
    """2D/flat style: picture placed whole (not cropped) on the channel's dark background, headline beside it."""
    lines = [tr_upper(x) for x in (l1, l2) if x]; yellow = yel.split()
    bgc = fr.getpixel((5, 5))
    v = Image.new("RGBA", (1080, 1920), bgc + (255,))
    f = fr.resize((1080, round(fr.height * 1080 / fr.width)))
    v.paste(f, (0, 1640 - f.height))
    draw_lines(v, lines, yellow, 540, 470, 980, 200)
    mark(v, handle, 540, 1690, 46)
    v.convert("RGB").save(out + "_cover.jpg", quality=92)
    h = Image.new("RGBA", (1280, 720), bgc + (255,))
    f = fr.resize((round(fr.width * 720 / fr.height), 720))
    h.paste(f, (1280 - f.width + 60, 0))
    lg = Image.new("L", h.size, 0); ld = ImageDraw.Draw(lg)
    for x in range(1280):
        ld.line([(x, 0), (x, 720)], fill=int(max(0, 230 - max(0, x - 380) * 0.6)))
    h = Image.composite(Image.new("RGBA", h.size, bgc + (255,)), h, lg)
    draw_lines(h, lines, yellow, 340, 330, 600, 150)
    mark(h, handle, 340, 600, 30)
    h.convert("RGB").save(out + "_thumb.jpg", quality=92)
    print(out + "_cover.jpg", out + "_thumb.jpg")

def universal(out, l1, l2, yel, handle, fr):
    """ONE master for YouTube Shorts + Instagram Reels (2D videos): 1080x1920, with the headline AND the picture inside the
    centre 1080x1080 square (y 420-1500), so any crop (1:1, 4:5, 3:4 grid, 16:9) still shows the whole message.
    Only the small brand line and handle sit outside the square. frame = the picture alone (no captions/chips), any size."""
    lines = [tr_upper(x) for x in (l1, l2) if x]; yellow = yel.split()
    bgc = fr.getpixel((5, 5)); W, H = 1080, 1920
    v = Image.new("RGBA", (W, H), bgc + (255,))
    ph = 640; f = fr.resize((round(fr.width * ph / fr.height), ph), Image.LANCZOS)
    import numpy as np
    yy, xx = np.mgrid[0:f.height, 0:f.width]; e = np.minimum.reduce([yy, f.height - 1 - yy, xx, f.width - 1 - xx]).clip(0, 40) / 40.0
    m = Image.fromarray((e * 255).astype("uint8"))
    v.paste(f, ((W - f.width) // 2, 870), m)
    top, bot = draw_lines(v, lines, yellow, 540, 660, 940, 190)
    d = ImageDraw.Draw(v); fb = ImageFont.truetype(FONT, 44); t = "AYET & BİLİM"
    d.text(((W - d.textlength(t, font=fb)) / 2, 250), t, font=fb, fill=(245, 197, 66))
    mark(v, handle, 540, 1620, 46)
    v.convert("RGB").save(out + "_thumb.jpg", quality=93)          # master 9:16 (Shorts + Reels cover)
    # landscape fallback (YouTube upload API): headline left, picture right
    stacked(out + "_tmp", l1, l2, yel, handle, fr)
    import os; os.replace(out + "_tmp_thumb.jpg", out + "_thumb16.jpg"); os.remove(out + "_tmp_cover.jpg")
    print(out + "_thumb.jpg", out + "_thumb16.jpg")

if __name__ == "__main__":
    main()
