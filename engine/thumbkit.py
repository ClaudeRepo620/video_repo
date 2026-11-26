#!/usr/bin/env python3
"""thumbkit.py - the user's channel thumbnail/cover template (since 2026-11-26), matching the 3 reference images in
engine/thumb_refs/ (kokpit360_jetmotor_cover.png, rota360_pamukkale_cover.png, ayetbilim_orumcek_cover.png).

Look: near-black navy background, one soft radial glow in the topic's colour behind ONE centred subject, and a short
Turkish all-caps headline under it in Poppins ExtraBold: white words + exactly ONE yellow word, soft drop shadow.
Nothing else (no handle, no frame, no logo) - everything sits inside the centre square so the Instagram grid crop works.

usage:
  python3 thumbkit.py OUT_PREFIX "MOTOR NEDEN *ERİMİYOR?" SUBJECT [--glow "#FF6A1F"] [--subject-w 470] [--subject-h 470]
    SUBJECT = a transparent PNG (Blender render with film_transparent, or any PNG) or an .svg file (flat 2D icon).
    The word starting with * is painted yellow (exactly one).
outputs:
  OUT_PREFIX_cover.jpg  1080x1920  (Instagram Reels cover_url + YouTube Shorts)
  OUT_PREFIX_thumb.jpg  1280x720   (YouTube upload `thumbnail` param - same design, landscape)
Channel glow defaults: Kokpit 360 orange #E2551B (engines/heat) or teal #2BB3C0; Rota 360 teal #2AA7C8 / sand #C7782E;
AyetBilim deep blue #1E4E8C. Pick the colour that matches the subject.
"""
import argparse, os, subprocess, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, 'fonts', 'Poppins-ExtraBold.ttf')
if not os.path.exists(FONT):
    FONT = '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf'
YELLOW = (252, 184, 38); WHITE = (255, 255, 255)
TOP = np.array([5, 7, 13]); MID = np.array([9, 13, 26]); BOT = np.array([5, 7, 13])


def hexrgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def tr_upper(s):
    return s.replace('i', 'İ').replace('ı', 'I').upper()


def background(W, H, cx, cy, r, glow, strength=0.55):
    y = np.linspace(0, 1, H)[:, None, None]
    # vertical: dark top -> faint navy around 70 % -> dark bottom
    k = np.exp(-((y - 0.70) / 0.18) ** 2)
    base = TOP * (1 - k) + MID * k
    base = np.broadcast_to(base, (H, W, 3)).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    g = np.clip(1 - d, 0, 1) ** 1.8 * strength
    img = base * (1 - g[..., None]) + np.array(glow, np.float32) * g[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert('RGBA')


def load_subject(path, w, h):
    if path.lower().endswith('.svg'):
        tmp = tempfile.mktemp(suffix='.png')
        subprocess.run(['rsvg-convert', '-w', str(w * 2), '-o', tmp, path], check=True)
        im = Image.open(tmp).convert('RGBA'); os.remove(tmp)
    else:
        im = Image.open(path).convert('RGBA')
    bb = im.getbbox()
    if bb: im = im.crop(bb)
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def paste_subject(img, sub, cx, cy, glow):
    x = round(cx - sub.width / 2); y = round(cy - sub.height / 2)
    # soft coloured halo hugging the subject's silhouette
    a = sub.split()[3]
    halo = Image.new('RGBA', img.size, (0, 0, 0, 0))
    hl = Image.new('RGBA', sub.size, glow + (255,)); hl.putalpha(a.point(lambda v: int(v * 0.55)))
    halo.paste(hl, (x, y), hl)
    halo = halo.filter(ImageFilter.GaussianBlur(max(8, sub.width // 22)))
    img.alpha_composite(halo)
    img.alpha_composite(sub, (x, y))


def headline(img, text, cx, cy, maxw, size):
    words = text.split()
    words = [(tr_upper(w[1:]), True) if w.startswith('*') else (tr_upper(w), False) for w in words]
    d = ImageDraw.Draw(img)
    while True:
        f = ImageFont.truetype(FONT, size)
        sp = d.textlength(' ', font=f)
        tw = sum(d.textlength(w, font=f) for w, _ in words) + sp * (len(words) - 1)
        if tw <= maxw or size <= 30: break
        size -= 2
    asc, desc = f.getmetrics(); x0 = cx - tw / 2; y0 = cy - (asc + desc) / 2 - size * 0.06
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0)); sd = ImageDraw.Draw(sh)
    x = x0
    for w, _ in words:
        sd.text((x + size * 0.05, y0 + size * 0.08), w, font=f, fill=(0, 0, 0, 210)); x += d.textlength(w, font=f) + sp
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(size * 0.07)))
    d = ImageDraw.Draw(img); x = x0
    for w, yel in words:
        d.text((x, y0), w, font=f, fill=YELLOW if yel else WHITE); x += d.textlength(w, font=f) + sp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('headline'); ap.add_argument('subject')
    ap.add_argument('--glow', default='#E2551B')
    ap.add_argument('--subject-w', type=int, default=470); ap.add_argument('--subject-h', type=int, default=470)
    a = ap.parse_args()
    glow = hexrgb(a.glow)
    assert sum(w.startswith('*') for w in a.headline.split()) == 1, 'exactly ONE *yellow word'
    # 9:16 cover (layout measured from the reference images)
    W, H = 1080, 1920; cy = 880
    img = background(W, H, 505, cy, 640, glow, 0.62)
    sub = load_subject(a.subject, a.subject_w, a.subject_h)
    paste_subject(img, sub, 505, cy, glow)
    headline(img, a.headline, 505, 1208, 790, 112)
    img.convert('RGB').save(a.out + '_cover.jpg', quality=93)
    # 16:9 YouTube thumbnail, same design
    W, H = 1280, 720; cy = 300
    img = background(W, H, 640, cy, 430, glow, 0.6)
    s = 380 / max(a.subject_w, a.subject_h)
    sub = load_subject(a.subject, round(a.subject_w * s * 1.15), round(a.subject_h * s))
    paste_subject(img, sub, 640, cy, glow)
    headline(img, a.headline, 640, 606, 1120, 118)
    img.convert('RGB').save(a.out + '_thumb.jpg', quality=93)
    print(a.out + '_cover.jpg', a.out + '_thumb.jpg')


if __name__ == '__main__':
    main()
