#!/usr/bin/env python3
"""compose.py - turns Blender frames + voice timings into the finished Kokpit 360 video.

  python3 compose.py PROJECT cues          -> data/cues.json (whoosh on every cut, pop on reveals, sparkle at the end)
                                             then run:  python3 tools/mix.py PROJECT   (-> data/mix.wav)
  python3 compose.py PROJECT ass  "SIFIRDAN UÇAK #3"   -> captions.ass (word-synced captions + series tag + end card)
  python3 compose.py PROJECT video renders/<slug>.mp4  -> frames/f_%04d.png (540x960) upscaled to 1080x1920 + ASS + mix.wav

Captions come from script.json lines[i].caps ("Kanat *iskeleti | {on iki} *12 kaburga"): chunks split by |, exactly one
*yellow word per chunk, {spoken words} anchors are not shown but count for timing. Caption zone y 1330-1630.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.normpath(os.path.join(HERE, '..', 'fonts'))
HANDLE = '@kokp.it360'


def tr_upper(s): return s.replace('i', 'İ').replace('ı', 'I').upper()


def load(P):
    lj = json.load(open(os.path.join(P, 'data/lines.json')))
    words = json.load(open(os.path.join(P, 'data/words.json')))
    script = json.load(open(os.path.join(P, 'script.json')))
    return lj, words, script


def chunks_for_line(caps, line_words, line_start, line_end):
    parts = [c.strip() for c in caps.split('|') if c.strip()]
    toks = []
    for c in parts:
        anchors = re.findall(r'\{([^}]*)\}', c)
        shown = re.sub(r'\{[^}]*\}', '', c).split()
        n_spoken = sum(len(a.split()) for a in anchors) + sum(1 for w in shown if not re.match(r'^\*?[\d.,%]+$', w))
        toks.append((shown, max(1, n_spoken)))
    total = sum(n for _, n in toks); nw = len(line_words); out = []; k = 0
    for j, (shown, n) in enumerate(toks):
        k2 = round(sum(t[1] for t in toks[:j + 1]) / total * nw) if nw else 0
        s = line_words[k]['s'] if nw and k < nw else line_start + (line_end - line_start) * j / len(toks)
        out.append([s, shown]); k = max(k + 1, k2) if nw else k
    for j in range(len(out)):
        out[j].append(out[j + 1][0] if j + 1 < len(out) else line_end + 0.15)
    return out


def ts(t):
    t = max(0, t); h = int(t // 3600); m = int(t % 3600 // 60); s = t % 60
    return f'{h}:{m:02d}:{s:05.2f}'


def make_ass(P, series):
    lj, words, script = load(P); dur = lj['duration']
    hdr = f"""[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Poppins ExtraBold,100,&H00FFFFFF,&H00FFFFFF,&H00140A05,&H96000000,0,0,0,0,100,100,0,0,1,7,4,5,40,40,0,1
Style: Tag,Poppins ExtraBold,52,&H00FFFFFF,&H00FFFFFF,&H00356BFF,&H00356BFF,0,0,0,0,100,100,2,0,3,14,0,5,40,40,0,1
Style: End,Poppins ExtraBold,96,&H00FFFFFF,&H00FFFFFF,&H00140A05,&H96000000,0,0,0,0,100,100,0,0,1,7,4,5,40,40,0,1
Style: Handle,Poppins ExtraBold,52,&H0026B8FC,&H00FFFFFF,&H00140A05,&H96000000,0,0,0,0,100,100,0,0,1,5,3,5,40,40,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    end_card = dur - 2.3
    for li, line in enumerate(script['lines']):
        L = lj['lines'][li]; lw = [w for w in words if w['line'] == li]
        for s, shown, e in chunks_for_line(line.get('caps', line['text']), lw, L['start'], L['end']):
            if s >= end_card: continue
            e = min(e, end_card)
            txt = ' '.join(('{\\c&H26B8FC&}' + tr_upper(w[1:]) + '{\\c&HFFFFFF&}') if w.startswith('*') else tr_upper(w) for w in shown)
            ev.append(f'Dialogue: 1,{ts(s)},{ts(e)},Cap,,0,0,0,,{{\\pos(540,1470)\\fscx70\\fscy70\\t(0,90,\\fscx104\\fscy104)\\t(90,160,\\fscx100\\fscy100)}}{txt}')
    if series:
        ev.append(f'Dialogue: 2,{ts(0)},{ts(2.6)},Tag,,0,0,0,,{{\\pos(540,330)\\fad(0,250)}}{tr_upper(series)}')
    ev.append(f'Dialogue: 2,{ts(end_card)},{ts(dur)},End,,0,0,0,,{{\\pos(540,1420)\\fad(150,0)}}SIRADAKİ {{\\c&H26B8FC&}}PARÇA?')
    ev.append(f'Dialogue: 2,{ts(end_card + 0.25)},{ts(dur)},Handle,,0,0,0,,{{\\pos(540,1540)\\fad(150,0)}}BEĞEN · YORUM · TAKİP ET  {HANDLE}')
    open(os.path.join(P, 'captions.ass'), 'w').write(hdr + '\n'.join(ev) + '\n')
    print('captions.ass', len(ev), 'events')


def make_cues(P):
    lj, words, script = load(P); cues = [{'t': 0.02, 'type': 'thud', 'gain': 0.7}]
    for L in lj['lines'][1:]:
        cues.append({'t': round(max(0, L['start'] - 0.22), 3), 'type': 'whoosh'})
    for li, line in enumerate(script['lines']):
        if '*' in line.get('caps', '') and li % 2 == 1:
            L = lj['lines'][li]; cues.append({'t': round(L['start'] + 0.35, 3), 'type': 'pop', 'gain': 0.45})
    cues.append({'t': round(lj['duration'] - 2.3, 3), 'type': 'sparkle', 'dur': 1.2})
    json.dump({'duration': lj['duration'], 'cues': cues}, open(os.path.join(P, 'data/cues.json'), 'w'), indent=1)
    print('data/cues.json', len(cues), 'cues')


def make_video(P, out):
    fr = os.path.join(P, 'frames'); n = len([f for f in os.listdir(fr) if f.endswith('.png')])
    lj = json.load(open(os.path.join(P, 'data/lines.json'))); need = round(lj['duration'] * 24) + 1
    if n < need - 1: sys.exit(f'only {n}/{need} frames rendered - render the rest first')
    ass = os.path.join(P, 'captions.ass').replace(':', r'\:')
    vf = f"scale=1080:1920:flags=lanczos,unsharp=5:5:0.5:5:5:0.0,ass='{ass}':fontsdir='{FONTS}'"
    os.makedirs(os.path.dirname(os.path.join(P, out)) or '.', exist_ok=True)
    cmd = ['ffmpeg', '-v', 'error', '-y', '-framerate', '24', '-i', os.path.join(fr, 'f_%04d.png'),
           '-i', os.path.join(P, 'data/mix.wav'), '-vf', vf, '-map', '0:v', '-map', '1:a', '-shortest',
           '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k',
           '-movflags', '+faststart', os.path.join(P, out)]
    subprocess.run(cmd, check=True); print(out)


if __name__ == '__main__':
    P, what = sys.argv[1], sys.argv[2]
    if what == 'ass': make_ass(P, sys.argv[3] if len(sys.argv) > 3 else '')
    elif what == 'cues': make_cues(P)
    elif what == 'video': make_video(P, sys.argv[3])
