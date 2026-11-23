#!/bin/bash
# World Tour engine bundle. usage: bash bundle.sh <project-dir>
set -eu
P="${1:?project dir}"
mkdir -p "$P/src/core" "$P/tools" "$P/examples" "$HOME/faceless-shorts/system"
rm -f "$P/src/sheet.js" "$P/sheet.html" "$P/src/core/human.js" "$P/src/core/sets.js" "$P/src/core/board.js"
cat > "$P/index.html" <<'__EOF_WT__'
<!doctype html>
<html><head><meta charset="utf-8"><title>Deep Dive 3D</title>
<style>
@font-face { font-family: 'Inter'; font-weight: 900; src: url('fonts/Inter-Black.otf'); }
@font-face { font-family: 'Inter'; font-weight: 800; src: url('fonts/Inter-ExtraBold.otf'); }
html, body { margin: 0; background: #111; height: 100%; } body { display: flex; align-items: center; justify-content: center; }
#cv { display: block; height: 100vh; width: auto; } body.capture #cv { height: auto; } #gl { display: none; }
#play { position: fixed; font: 900 28px Inter, sans-serif; padding: 18px 36px; border: 0; border-radius: 40px; background: #FFD43B; cursor: pointer; }
</style></head>
<body>
<canvas id="cv" width="1080" height="1920"></canvas><canvas id="gl" width="1080" height="1920"></canvas>
<button id="play" hidden>▶ PLAY</button>
<script>if (location.search.includes('capture')) document.body.className = 'capture';</script>
<script type="importmap">{"imports":{"three":"./vendor/three.module.js","three/addons/":"./vendor/addons/"}}</script>
<script type="module" src="src/main.js"></script>
</body></html>
__EOF_WT__
cat > "$P/src/main.js" <<'__EOF_WT__'
// Boot: fonts → script + timing → 3D engine + sets → captions → shots. draw(t) renders film time t (pure function of t):
// the shot renders its 3D frame into the hidden WebGL canvas, which is copied onto the 2D canvas, then the 2D layer
// (labels, counters) and the captions go on top. window.OP is the API tools/capture.mjs drives.
import { W, H, setCtx, ctx, clamp } from './core/lib.js';
import { T, loadTiming } from './core/timing.js';
import { buildCaptions, drawCaption, captionList } from './core/captions.js';
import { makeEngine, RES, AA } from './core/engine.js';
import { buildShots } from './shots.js';

const cv = document.getElementById('cv'), GL = document.getElementById('gl');
setCtx(cv.getContext('2d'));
const OP = (window.OP = { ready: false });

function draw(t) {
  t = clamp(t, 0, T.dur - 1e-4);
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.letterSpacing = '0px';
  const S = OP._shots; let i = S.length - 1; while (i > 0 && S[i].at > t) i--;
  const sh = S[i], end = i < S.length - 1 ? S[i + 1].at : T.dur, d = end - sh.at, lt = t - sh.at;
  const blit = () => ctx.drawImage(GL, 0, 0, W, H);
  ctx.save(); sh.draw(lt, d, t, blit); ctx.restore();
  ctx.globalAlpha = 1; ctx.letterSpacing = '0px';
  const fade = Math.min(clamp(t / 0.25), clamp((T.dur - t) / 0.4));
  if (fade < 1) { ctx.fillStyle = '#000'; ctx.globalAlpha = 1 - fade; ctx.fillRect(0, 0, W, H); ctx.globalAlpha = 1; }
  drawCaption(t);
}

(async () => {
  try {
    await document.fonts.load('900 100px Inter'); await document.fonts.load('800 100px Inter');
    const script = await (await fetch('script.json', { cache: 'no-store' })).json();
    await loadTiming();
    buildCaptions(script);
    GL.width = Math.round(1080 * RES); GL.height = Math.round(1920 * RES);
    const E = makeEngine(GL, { w: GL.width, h: GL.height, samples: AA });
    const { shots, cues } = buildShots(E);
    shots.sort((a, b) => a.at - b.at);
    OP._shots = shots; OP.script = script;
    OP.duration = () => T.dur;
    OP.draw = draw;
    const CLEAN = new URLSearchParams(location.search).has('clean');
    OP.frame = (t, q = 0.92) => { draw(t); return (CLEAN ? GL : cv).toDataURL('image/jpeg', q); };
    OP.shots = () => shots.map((s, i) => ({ id: s.id, at: +s.at.toFixed(3), end: +(i < shots.length - 1 ? shots[i + 1].at : T.dur).toFixed(3), note: s.note || '' }));
    OP.captions = () => captionList().map((c) => ({ s: +c.s.toFixed(3), e: +c.e.toFixed(3), text: c.words.map((w) => (w.hi ? '*' : '') + w.txt).join(' ') }));
    OP.cues = () => cues.slice().sort((a, b) => a.t - b.t);
    OP.ready = true;
    const q = new URLSearchParams(location.search);
    if (!q.has('capture')) {
      if (q.has('t')) draw(+q.get('t'));
      else {
        const audio = new Audio('data/mix.wav'); let t0 = null; const btn = document.getElementById('play'); btn.hidden = false;
        btn.onclick = () => { btn.hidden = true; t0 = performance.now(); audio.currentTime = 0; audio.play().catch(() => {}); };
        const loop = (now) => { const t = t0 == null ? 0 : (now - t0) / 1000; draw(t); if (t0 != null && t > T.dur) { t0 = null; btn.hidden = false; } requestAnimationFrame(loop); };
        requestAnimationFrame(loop);
      }
    }
  } catch (e) { OP.bootError = String(e && e.stack || e); console.error(e); }
})();
__EOF_WT__
cat > "$P/examples/shots.js" <<'__EOF_WT__'
// KOKPİT 360 · Parça Parça Uçak #2 · "Uçak penceresindeki delik ne işe yarar?" — three-pane window, front + section views.
import * as THREE from 'three';
import { ctx, W, H, clamp, lerp, seg, eo, eio, eob } from './core/lib.js';
import { L, Wd, T } from './core/timing.js';
import * as WD from './core/world.js';
import * as AE from './core/aero.js';
import * as O from './core/overlays.js';

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
function screen(p, cam) { const v = p.clone().project(cam); return [(v.x + 1) / 2 * W, (1 - v.y) / 2 * H]; }
const safeWd = (w, i, fb) => { try { return Wd(w, i); } catch { return fb; } };
const CY = '#4FD1E8', INK = '#101318', YEL = '#FFD43B', RED = '#E5484D', GLASS = 'rgba(12,15,22,0.85)';

export function buildShots(E) {
  const S = [], CUES = [], cue = (t, type, o = {}) => CUES.push({ t: +Math.max(0, t).toFixed(3), type, ...o });
  const cam = WD.cameraWide(34);
  const add = (o) => { const dr = o.draw; o.draw = (...a) => { const f = o.fov || 34; if (cam.fov !== f) { cam.fov = f; cam.updateProjectionMatrix(); } dr(...a); }; S.push(o); return o; };
  const cut = (i) => (i === 0 ? 0 : L(i) - 0.1), end = (i) => (i + 1 < T.lines.length ? cut(i + 1) : T.dur);
  const LOOK = { aperture: 0, bloom: 0.3, bloomThreshold: 0.9, vignette: 0.4, grain: 0.018, warm: 0, exposure: 0.85 };
  const look = (x = {}) => ({ ...LOOK, ...x });
  const WR = AE.windowRig(E), st = WR.state;
  const reset = () => Object.assign(st, { view: 'front', ex: 0, eq: 0, vent: 0, fog: 0, arrows: 0, arrowZ: 0.9, single: 0, outGlow: 0, midGlow: 0, crack: 0, holeGlow: 0 });
  // section camera: cabin at the TOP of the frame, outside at the bottom (camera.up = +Z, looking along -X)
  const secCam = (k, zoom0 = 5.6, zoom1 = 5.0, zc = -0.3, yc = 0, yaw = 0.12) => {
    const d = lerp(zoom0, zoom1, eio(clamp(k))), a = yaw * Math.sin(k * 1.6);
    cam.up.set(0, 0, 1); cam.position.set(Math.cos(a) * d, yc + Math.sin(a) * d * 0.6, zc); cam.lookAt(0, yc, zc);
  };
  const frontCam = (A, B, at, k) => { cam.up.set(0, 1, 0); cam.position.copy(A.clone().lerp(B, eio(clamp(k)))); cam.lookAt(at); };
  const pulse = (x, y, r, k, t) => { if (k <= 0) return; ctx.save(); ctx.strokeStyle = `rgba(255,212,59,${clamp(k)})`; ctx.lineWidth = 9; ctx.setLineDash([24, 14]); ctx.lineDashOffset = -t * 70; ctx.beginPath(); ctx.arc(x, y, r * (1 + 0.1 * Math.sin(t * 8)), 0, 7); ctx.stroke(); ctx.restore(); };
  const render = (blit, x = {}) => { E.render(WR.scene, cam, look(x)); blit(); };
  const tag = (lt, text, k0 = 0.1) => O.pillAt(text, 540, 330, eob(seg(lt, k0, k0 + 0.35)), INK, YEL, 66);
  const sub = (lt, text, k0, y = 500, bg = GLASS, fg = '#fff', size = 54, x = 540) => O.pillAt(text, x, y, eob(seg(lt, k0, k0 + 0.3)), fg, bg, size);

  // 0 · HOOK: through the cabin window, pushing in, the tiny hole pulses. series tag on frame 1.
  add({ id: 'S00', at: 0, note: 'cabin window front view, push in, hole ring + hook text', fov: 38, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; WR.update(t); frontCam(V3(0.5, 0, 4.4), V3(0.1, -0.2, 3.2), V3(0, -0.1, 0), lt / d); render(blit, { bloom: 0.35 });
    O.topShade(1); O.pillAt('PARÇA PARÇA UÇAK #2', 540, 250, eob(seg(lt, 0, 0.3)), '#fff', GLASS, 44);
    O.pillAt('BU DELİK HATA MI?', 540, 350, eob(seg(lt, 0.05, 0.4)), INK, YEL, 70);
    const [hx, hy] = screen(WR.holePt.clone().setZ(0.05), cam); pulse(hx, hy, 46, seg(lt, 1.0, 1.3), t);
  } });
  cue(0.05, 'impact', { gain: 0.6 }); cue(0.1, 'wind', { dur: end(0), gain: 0.5 }); cue(1.0, 'pop', { gain: 0.5 });

  // 1 · macro: needle-tip hole
  add({ id: 'S01', at: cut(1), note: 'macro push to the hole, callout "İĞNE UCU KADAR"', fov: 30, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; WR.update(t); frontCam(V3(0.1, -0.35, 2.4), V3(0.02, -0.46, 1.5), V3(0, -0.5, 0), lt / d); render(blit, { bloom: 0.35 });
    O.topShade(1); const [hx, hy] = screen(WR.holePt.clone().setZ(0.05), cam); const k = seg(lt, safeWd('iğne', 1, cut(1) + 2.4) - cut(1) - 0.1, safeWd('iğne', 1, cut(1) + 2.4) - cut(1) + 0.35);
    O.callout('İĞNE UCU KADAR', 540, 560, hx, hy, k); pulse(hx, hy, 50, seg(lt, 0.2, 0.5), t); tag(lt, 'PENCERENİN ALTINDA', 0.05);
  } });
  cue(cut(1), 'whoosh'); cue(cut(1) + 1.8, 'pop');

  // 2 · cabin air thick, outside air thin (section)
  add({ id: 'S02', at: cut(2), note: 'section view: dense cabin air vs thin outside air', fov: 34, draw(lt, d, t, blit) {
    reset(); st.view = 'sec'; WR.update(t); secCam(lt / d, 6.2, 5.2); render(blit);
    O.topShade(1); tag(lt, 'KABİN | DIŞARI', 0.05);
    sub(lt, 'KABİN: YOĞUN', safeWd('kabinde', 2, cut(2) + 0.3) - cut(2), 560, 'rgba(12,15,22,0.85)', CY, 48);
    sub(lt, 'DIŞ HAVA: ÇOK İNCE', safeWd('ince', 2, cut(2) + 2.8) - cut(2) - 0.1, 1180, 'rgba(12,15,22,0.85)', '#fff', 48);
  } });
  cue(cut(2), 'whoosh'); cue(cut(2) + 0.3, 'pop', { gain: 0.5 }); cue(cut(2) + 2.8, 'pop', { gain: 0.5 });

  // 3 · pressure difference: arrows push the window outward, 8 psi
  { const s0 = cut(3), pk = safeWd('sekiz', 3, s0 + 1.7) - s0;
    add({ id: 'S03', at: s0, note: 'orange arrows push the window outward, 8 psi', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.arrows = eob(seg(lt, pk - 0.4, pk)); st.arrowZ = lerp(1.0, 0.75, eio(seg(lt, pk - 0.4, d))); WR.update(t); secCam(lt / d, 5.2, 4.8); render(blit);
      if (lt > pk - 0.1) O.factCard('BASINÇ FARKI', 8, 'psi', lt - pk + 0.1, { dur: 0.7, y: 380 }); else O.topShade(clamp(lt / 0.3));
      sub(lt, 'CAM DIŞARI İTİLİYOR', safeWd('itiliyor', 3, s0 + 3.8) - s0 - 0.2, 620, GLASS, '#FF9C4D', 46);
    } });
    cue(s0, 'whoosh'); cue(s0 + pk, 'impact', { gain: 0.5 }); cue(s0 + pk, 'riser', { dur: 1.6, gain: 0.4 }); }

  // 4 · SORUN: a single pane carrying it all
  add({ id: 'S04', at: cut(4), note: 'SORUN: a single pane glowing red under pressure, crack', fov: 34, draw(lt, d, t, blit) {
    reset(); st.view = 'sec'; st.single = 1; st.arrows = 1; st.arrowZ = 0.45; st.crack = seg(lt, d - 1.0, d - 0.9); WR.update(t); secCam(lt / d, 4.6, 4.0, -0.1); render(blit, { bloom: 0.4 });
    O.topShade(1); O.pillAt('SORUN', 540, 330, eob(seg(lt, 0.05, 0.4)), '#fff', RED, 70); sub(lt, 'TEK CAM → YEDEK YOK', safeWd('yedeği', 4, cut(4) + 1.8) - cut(4) - 0.5, 1170, GLASS, '#fff', 44);
  } });
  cue(cut(4), 'whoosh'); cue(cut(4) + 0.1, 'alarm', { dur: 1.3, gain: 0.3 });

  // 5 · ÇÖZÜM: three layers (exploded)
  add({ id: 'S05', at: cut(5), note: 'ÇÖZÜM: the window splits into three layers', fov: 38, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; st.ex = eio(seg(lt, 0.1, 1.2)); WR.update(t); const a = lerp(0.35, 0.55, eio(lt / d)); frontCam(V3(Math.sin(a) * 5.4, 1.1, Math.cos(a) * 5.4), V3(Math.sin(a + 0.1) * 5.0, 0.9, Math.cos(a + 0.1) * 5.0), V3(0, -0.05, 0), lt / d); render(blit, { bloom: 0.4 });
    O.topShade(1); O.pillAt('ÇÖZÜM', 540, 330, eob(seg(lt, 0.05, 0.4)), INK, CY, 70); sub(lt, '3 KATMAN', safeWd('üç', 5, cut(5) + 1.3) - cut(5), 500, YEL, INK, 56);
  } });
  cue(cut(5), 'whoosh'); cue(cut(5) + 0.4, 'slide', { dur: 1.0, gain: 0.5 }); cue(cut(5) + 1.3, 'pop');

  // 6 · outer carries the load, middle is the backup
  { const s0 = cut(6), dk = safeWd('dıştaki', 6, s0 + 0.2) - s0, mk = safeWd('ortadaki', 6, s0 + 2.0) - s0;
    add({ id: 'S06', at: s0, note: 'exploded layers: DIŞ CAM = yük, ORTA CAM = yedek', fov: 38, draw(lt, d, t, blit) {
      reset(); st.view = 'front'; st.ex = 1; st.outGlow = eio(seg(lt, dk, dk + 0.5)); WR.update(t); const a = lerp(0.6, 0.3, eio(lt / d)); frontCam(V3(Math.sin(a) * 5.4, 0.9, Math.cos(a) * 5.4), V3(Math.sin(a) * 4.8, 0.6, Math.cos(a) * 4.8), V3(0, -0.05, 0), lt / d); render(blit, { bloom: 0.45 });
      O.topShade(1); const po = screen(V3(0.0, 0.5, WR.P.out.g.position.z), cam), pm = screen(V3(0.0, 0.62, WR.P.mid.g.position.z), cam);
      O.callout('DIŞ CAM: YÜKÜ TAŞIR', 540, 330, po[0], po[1], seg(lt, dk + 0.1, dk + 0.5)); O.callout('ORTA CAM: YEDEK', 540, 520, pm[0], pm[1], seg(lt, mk, mk + 0.4));
    } });
    cue(s0, 'whoosh'); cue(s0 + dk + 0.2, 'pop'); cue(s0 + mk, 'pop', { gain: 0.5 }); }

  // 7 · the hole passes cabin pressure into the gap
  { const s0 = cut(7), hk = safeWd('delik', 7, s0) - s0, ik = safeWd('iki', 7, s0 + 2.4) - s0;
    add({ id: 'S07', at: s0, note: 'section: cabin air flows through the hole into the gap between the panes', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.eq = eio(seg(lt, 0.8, 3.0)); st.holeGlow = 1; WR.update(t); secCam(lt / d, 4.4, 3.6, -0.15, -0.3, 0.2); render(blit, { bloom: 0.4 });
      O.topShade(1); const [hx, hy] = screen(V3(0, WR.HY, 0), cam); O.callout('DELİK', 540, 350, hx, hy, seg(lt, hk + 0.1, hk + 0.5)); sub(lt, 'KABİN BASINCI → ARAYA', ik - 0.4, 520, GLASS, CY, 44);
    } });
    cue(s0, 'whoosh'); cue(s0 + 0.3, 'pop'); cue(s0 + 0.9, 'slide', { dur: 1.8, gain: 0.4 }); cue(s0 + ik, 'pop', { gain: 0.5 }); }

  // 8 · all the load on the outer pane, the middle one rests
  { const s0 = cut(8), yk = safeWd('yük', 8, s0 + 0.5) - s0;
    add({ id: 'S08', at: s0, note: 'section: outer pane glows (all the load), middle rests', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.eq = 1; st.holeGlow = 0.35; st.arrows = 1; st.arrowZ = lerp(-0.12, -0.28, eio(seg(lt, 0, 0.6))); st.outGlow = eio(seg(lt, yk, yk + 0.5)); WR.update(t); secCam(lt / d, 3.7, 4.2, -0.3, 0, 0.18); render(blit, { bloom: 0.45 });
      O.topShade(1); tag(lt, 'YÜK: DIŞ CAMDA', 0.1); sub(lt, 'ORTA CAM: RAHAT', safeWd('ortadaki', 8, s0 + 1.8) - s0, 500, GLASS, YEL, 46);
    } });
    cue(s0, 'whoosh'); cue(s0 + yk, 'impact', { gain: 0.5 }); cue(s0 + 1.8, 'pop', { gain: 0.5 }); }

  // 9 · moisture: fog gathers, then leaves through the hole
  { const s0 = cut(9), nk = safeWd('nemi', 9, s0 + 0.3) - s0, bk = safeWd('buğulanmaz', 9, s0 + 2.6) - s0;
    add({ id: 'S09', at: s0, note: 'section: fog in the gap clears as moisture leaves through the hole', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.eq = 1; st.holeGlow = 0.2; st.fog = lt < bk ? eio(seg(lt, 0, 0.6)) : 1 - eio(seg(lt, bk, bk + 0.8)); st.vent = lt > nk ? 1 : 0; WR.update(t); secCam(lt / d, 4.2, 3.5, -0.2, -0.25, 0.2); render(blit, { bloom: 0.4 });
      O.topShade(1); tag(lt, 'NEM DIŞARI ÇIKAR', 0.1); sub(lt, 'BUĞU YOK • BUZ YOK', bk - 0.2, 500, YEL, INK, 50);
    } });
    cue(s0, 'whoosh'); cue(s0 + nk, 'slide', { dur: 1.6, gain: 0.4 }); cue(s0 + bk, 'sparkle', { dur: 1, gain: 0.5 }); }

  // 10 · punchline: back to the clean window
  add({ id: 'S10', at: cut(10), note: 'clean window front view, KUSUR DEĞİL | MÜHENDİSLİK', fov: 38, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; st.outGlow = 0; WR.update(t); frontCam(V3(-0.6, 0.2, 3.4), V3(0.3, -0.05, 4.4), V3(0, -0.1, 0), lt / d); render(blit, { bloom: 0.35 });
    O.topShade(1); O.pillAt('KUSUR', 540, 330, eob(seg(lt, safeWd('kusur', 10, cut(10) + 0.9) - cut(10) - 0.1, safeWd('kusur', 10, cut(10) + 0.9) - cut(10) + 0.25)), '#fff', RED, 62);
    O.pillAt('MÜHENDİSLİK', 540, 480, eob(seg(lt, safeWd('mühendislik', 10, cut(10) + 1.8) - cut(10) - 0.1, safeWd('mühendislik', 10, cut(10) + 1.8) - cut(10) + 0.25)), INK, CY, 62);
    const [hx, hy] = screen(WR.holePt.clone().setZ(0.05), cam); pulse(hx, hy, 40, seg(lt, 0.3, 0.6), t);
  } });
  cue(cut(10), 'whoosh'); cue(cut(10) + 0.9, 'pop', { gain: 0.5 }); cue(cut(10) + 1.8, 'pop');

  // 11 · CTA
  { const LIST = [['A', 'Kanat'], ['B', 'Kara kutu'], ['C', 'İniş takımı'], ['D', 'Otopilot']];
    add({ id: 'S11', at: cut(11), note: 'window view; "SIRADAKİ PARÇA?" list', fov: 38, draw(lt, d, t, blit) {
      reset(); st.view = 'front'; WR.update(t); frontCam(V3(0.3, 0.0, 4.4), V3(-0.1, 0.0, 5.2), V3(0, -0.1, 0), lt / d); render(blit, { bloom: 0.35, exposure: 0.75 });
      O.flash(lt, 0.18); O.topShade(1); O.pillAt('SIRADAKİ PARÇA?', 540, 280, eob(seg(lt, 0, 0.35)), INK, YEL, 64);
      LIST.forEach(([a, b], i) => O.pillAt(`${a} · ${b}`, i % 2 ? 805 : 275, 470 + Math.floor(i / 2) * 130, eob(seg(lt, 0.4 + i * 0.15, 0.7 + i * 0.15)), '#fff', GLASS, 52));
      O.pillAt('@kokp.it360', 540, 1190, eo(seg(lt, 1.2, 1.6)), CY, GLASS, 52);
    } });
    cue(cut(11), 'whoosh'); for (let i = 0; i < 4; i++) cue(cut(11) + 0.4 + i * 0.15, 'tock', { gain: 0.5 }); cue(T.dur - 1.3, 'chime', { gain: 0.5 }); }

  // flash on every cut (except the first and the CTA, which flashes itself)
  S.forEach((s, i) => { if (i > 0 && s.id !== 'S11') { const dr = s.draw; s.draw = (lt, d, t, blit) => { dr(lt, d, t, blit); O.flash(lt, 0.15); }; } });
  return { shots: S, cues: CUES };
}
__EOF_WT__
cat > "$P/src/shots.js" <<'__EOF_WT__'
// KOKPİT 360 · Parça Parça Uçak #2 · "Uçak penceresindeki delik ne işe yarar?" — three-pane window, front + section views.
import * as THREE from 'three';
import { ctx, W, H, clamp, lerp, seg, eo, eio, eob } from './core/lib.js';
import { L, Wd, T } from './core/timing.js';
import * as WD from './core/world.js';
import * as AE from './core/aero.js';
import * as O from './core/overlays.js';

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
function screen(p, cam) { const v = p.clone().project(cam); return [(v.x + 1) / 2 * W, (1 - v.y) / 2 * H]; }
const safeWd = (w, i, fb) => { try { return Wd(w, i); } catch { return fb; } };
const CY = '#4FD1E8', INK = '#101318', YEL = '#FFD43B', RED = '#E5484D', GLASS = 'rgba(12,15,22,0.85)';

export function buildShots(E) {
  const S = [], CUES = [], cue = (t, type, o = {}) => CUES.push({ t: +Math.max(0, t).toFixed(3), type, ...o });
  const cam = WD.cameraWide(34);
  const add = (o) => { const dr = o.draw; o.draw = (...a) => { const f = o.fov || 34; if (cam.fov !== f) { cam.fov = f; cam.updateProjectionMatrix(); } dr(...a); }; S.push(o); return o; };
  const cut = (i) => (i === 0 ? 0 : L(i) - 0.1), end = (i) => (i + 1 < T.lines.length ? cut(i + 1) : T.dur);
  const LOOK = { aperture: 0, bloom: 0.3, bloomThreshold: 0.9, vignette: 0.4, grain: 0.018, warm: 0, exposure: 0.85 };
  const look = (x = {}) => ({ ...LOOK, ...x });
  const WR = AE.windowRig(E), st = WR.state;
  const reset = () => Object.assign(st, { view: 'front', ex: 0, eq: 0, vent: 0, fog: 0, arrows: 0, arrowZ: 0.9, single: 0, outGlow: 0, midGlow: 0, crack: 0, holeGlow: 0 });
  // section camera: cabin at the TOP of the frame, outside at the bottom (camera.up = +Z, looking along -X)
  const secCam = (k, zoom0 = 5.6, zoom1 = 5.0, zc = -0.3, yc = 0, yaw = 0.12) => {
    const d = lerp(zoom0, zoom1, eio(clamp(k))), a = yaw * Math.sin(k * 1.6);
    cam.up.set(0, 0, 1); cam.position.set(Math.cos(a) * d, yc + Math.sin(a) * d * 0.6, zc); cam.lookAt(0, yc, zc);
  };
  const frontCam = (A, B, at, k) => { cam.up.set(0, 1, 0); cam.position.copy(A.clone().lerp(B, eio(clamp(k)))); cam.lookAt(at); };
  const pulse = (x, y, r, k, t) => { if (k <= 0) return; ctx.save(); ctx.strokeStyle = `rgba(255,212,59,${clamp(k)})`; ctx.lineWidth = 9; ctx.setLineDash([24, 14]); ctx.lineDashOffset = -t * 70; ctx.beginPath(); ctx.arc(x, y, r * (1 + 0.1 * Math.sin(t * 8)), 0, 7); ctx.stroke(); ctx.restore(); };
  const render = (blit, x = {}) => { E.render(WR.scene, cam, look(x)); blit(); };
  const tag = (lt, text, k0 = 0.1) => O.pillAt(text, 540, 330, eob(seg(lt, k0, k0 + 0.35)), INK, YEL, 66);
  const sub = (lt, text, k0, y = 500, bg = GLASS, fg = '#fff', size = 54, x = 540) => O.pillAt(text, x, y, eob(seg(lt, k0, k0 + 0.3)), fg, bg, size);

  // 0 · HOOK: through the cabin window, pushing in, the tiny hole pulses. series tag on frame 1.
  add({ id: 'S00', at: 0, note: 'cabin window front view, push in, hole ring + hook text', fov: 38, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; WR.update(t); frontCam(V3(0.5, 0, 4.4), V3(0.1, -0.2, 3.2), V3(0, -0.1, 0), lt / d); render(blit, { bloom: 0.35 });
    O.topShade(1); O.pillAt('PARÇA PARÇA UÇAK #2', 540, 250, eob(seg(lt, 0, 0.3)), '#fff', GLASS, 44);
    O.pillAt('BU DELİK HATA MI?', 540, 350, eob(seg(lt, 0.05, 0.4)), INK, YEL, 70);
    const [hx, hy] = screen(WR.holePt.clone().setZ(0.05), cam); pulse(hx, hy, 46, seg(lt, 1.0, 1.3), t);
  } });
  cue(0.05, 'impact', { gain: 0.6 }); cue(0.1, 'wind', { dur: end(0), gain: 0.5 }); cue(1.0, 'pop', { gain: 0.5 });

  // 1 · macro: needle-tip hole
  add({ id: 'S01', at: cut(1), note: 'macro push to the hole, callout "İĞNE UCU KADAR"', fov: 30, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; WR.update(t); frontCam(V3(0.1, -0.35, 2.4), V3(0.02, -0.46, 1.5), V3(0, -0.5, 0), lt / d); render(blit, { bloom: 0.35 });
    O.topShade(1); const [hx, hy] = screen(WR.holePt.clone().setZ(0.05), cam); const k = seg(lt, safeWd('iğne', 1, cut(1) + 2.4) - cut(1) - 0.1, safeWd('iğne', 1, cut(1) + 2.4) - cut(1) + 0.35);
    O.callout('İĞNE UCU KADAR', 540, 560, hx, hy, k); pulse(hx, hy, 50, seg(lt, 0.2, 0.5), t); tag(lt, 'PENCERENİN ALTINDA', 0.05);
  } });
  cue(cut(1), 'whoosh'); cue(cut(1) + 1.8, 'pop');

  // 2 · cabin air thick, outside air thin (section)
  add({ id: 'S02', at: cut(2), note: 'section view: dense cabin air vs thin outside air', fov: 34, draw(lt, d, t, blit) {
    reset(); st.view = 'sec'; WR.update(t); secCam(lt / d, 6.2, 5.2); render(blit);
    O.topShade(1); tag(lt, 'KABİN | DIŞARI', 0.05);
    sub(lt, 'KABİN: YOĞUN', safeWd('kabinde', 2, cut(2) + 0.3) - cut(2), 560, 'rgba(12,15,22,0.85)', CY, 48);
    sub(lt, 'DIŞ HAVA: ÇOK İNCE', safeWd('ince', 2, cut(2) + 2.8) - cut(2) - 0.1, 1180, 'rgba(12,15,22,0.85)', '#fff', 48);
  } });
  cue(cut(2), 'whoosh'); cue(cut(2) + 0.3, 'pop', { gain: 0.5 }); cue(cut(2) + 2.8, 'pop', { gain: 0.5 });

  // 3 · pressure difference: arrows push the window outward, 8 psi
  { const s0 = cut(3), pk = safeWd('sekiz', 3, s0 + 1.7) - s0;
    add({ id: 'S03', at: s0, note: 'orange arrows push the window outward, 8 psi', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.arrows = eob(seg(lt, pk - 0.4, pk)); st.arrowZ = lerp(1.0, 0.75, eio(seg(lt, pk - 0.4, d))); WR.update(t); secCam(lt / d, 5.2, 4.8); render(blit);
      if (lt > pk - 0.1) O.factCard('BASINÇ FARKI', 8, 'psi', lt - pk + 0.1, { dur: 0.7, y: 380 }); else O.topShade(clamp(lt / 0.3));
      sub(lt, 'CAM DIŞARI İTİLİYOR', safeWd('itiliyor', 3, s0 + 3.8) - s0 - 0.2, 620, GLASS, '#FF9C4D', 46);
    } });
    cue(s0, 'whoosh'); cue(s0 + pk, 'impact', { gain: 0.5 }); cue(s0 + pk, 'riser', { dur: 1.6, gain: 0.4 }); }

  // 4 · SORUN: a single pane carrying it all
  add({ id: 'S04', at: cut(4), note: 'SORUN: a single pane glowing red under pressure, crack', fov: 34, draw(lt, d, t, blit) {
    reset(); st.view = 'sec'; st.single = 1; st.arrows = 1; st.arrowZ = 0.45; st.crack = seg(lt, d - 1.0, d - 0.9); WR.update(t); secCam(lt / d, 4.6, 4.0, -0.1); render(blit, { bloom: 0.4 });
    O.topShade(1); O.pillAt('SORUN', 540, 330, eob(seg(lt, 0.05, 0.4)), '#fff', RED, 70); sub(lt, 'TEK CAM → YEDEK YOK', safeWd('yedeği', 4, cut(4) + 1.8) - cut(4) - 0.5, 1170, GLASS, '#fff', 44);
  } });
  cue(cut(4), 'whoosh'); cue(cut(4) + 0.1, 'alarm', { dur: 1.3, gain: 0.3 });

  // 5 · ÇÖZÜM: three layers (exploded)
  add({ id: 'S05', at: cut(5), note: 'ÇÖZÜM: the window splits into three layers', fov: 38, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; st.ex = eio(seg(lt, 0.1, 1.2)); WR.update(t); const a = lerp(0.35, 0.55, eio(lt / d)); frontCam(V3(Math.sin(a) * 5.4, 1.1, Math.cos(a) * 5.4), V3(Math.sin(a + 0.1) * 5.0, 0.9, Math.cos(a + 0.1) * 5.0), V3(0, -0.05, 0), lt / d); render(blit, { bloom: 0.4 });
    O.topShade(1); O.pillAt('ÇÖZÜM', 540, 330, eob(seg(lt, 0.05, 0.4)), INK, CY, 70); sub(lt, '3 KATMAN', safeWd('üç', 5, cut(5) + 1.3) - cut(5), 500, YEL, INK, 56);
  } });
  cue(cut(5), 'whoosh'); cue(cut(5) + 0.4, 'slide', { dur: 1.0, gain: 0.5 }); cue(cut(5) + 1.3, 'pop');

  // 6 · outer carries the load, middle is the backup
  { const s0 = cut(6), dk = safeWd('dıştaki', 6, s0 + 0.2) - s0, mk = safeWd('ortadaki', 6, s0 + 2.0) - s0;
    add({ id: 'S06', at: s0, note: 'exploded layers: DIŞ CAM = yük, ORTA CAM = yedek', fov: 38, draw(lt, d, t, blit) {
      reset(); st.view = 'front'; st.ex = 1; st.outGlow = eio(seg(lt, dk, dk + 0.5)); WR.update(t); const a = lerp(0.6, 0.3, eio(lt / d)); frontCam(V3(Math.sin(a) * 5.4, 0.9, Math.cos(a) * 5.4), V3(Math.sin(a) * 4.8, 0.6, Math.cos(a) * 4.8), V3(0, -0.05, 0), lt / d); render(blit, { bloom: 0.45 });
      O.topShade(1); const po = screen(V3(0.0, 0.5, WR.P.out.g.position.z), cam), pm = screen(V3(0.0, 0.62, WR.P.mid.g.position.z), cam);
      O.callout('DIŞ CAM: YÜKÜ TAŞIR', 540, 330, po[0], po[1], seg(lt, dk + 0.1, dk + 0.5)); O.callout('ORTA CAM: YEDEK', 540, 520, pm[0], pm[1], seg(lt, mk, mk + 0.4));
    } });
    cue(s0, 'whoosh'); cue(s0 + dk + 0.2, 'pop'); cue(s0 + mk, 'pop', { gain: 0.5 }); }

  // 7 · the hole passes cabin pressure into the gap
  { const s0 = cut(7), hk = safeWd('delik', 7, s0) - s0, ik = safeWd('iki', 7, s0 + 2.4) - s0;
    add({ id: 'S07', at: s0, note: 'section: cabin air flows through the hole into the gap between the panes', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.eq = eio(seg(lt, 0.8, 3.0)); st.holeGlow = 1; WR.update(t); secCam(lt / d, 4.4, 3.6, -0.15, -0.3, 0.2); render(blit, { bloom: 0.4 });
      O.topShade(1); const [hx, hy] = screen(V3(0, WR.HY, 0), cam); O.callout('DELİK', 540, 350, hx, hy, seg(lt, hk + 0.1, hk + 0.5)); sub(lt, 'KABİN BASINCI → ARAYA', ik - 0.4, 520, GLASS, CY, 44);
    } });
    cue(s0, 'whoosh'); cue(s0 + 0.3, 'pop'); cue(s0 + 0.9, 'slide', { dur: 1.8, gain: 0.4 }); cue(s0 + ik, 'pop', { gain: 0.5 }); }

  // 8 · all the load on the outer pane, the middle one rests
  { const s0 = cut(8), yk = safeWd('yük', 8, s0 + 0.5) - s0;
    add({ id: 'S08', at: s0, note: 'section: outer pane glows (all the load), middle rests', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.eq = 1; st.holeGlow = 0.35; st.arrows = 1; st.arrowZ = lerp(-0.12, -0.28, eio(seg(lt, 0, 0.6))); st.outGlow = eio(seg(lt, yk, yk + 0.5)); WR.update(t); secCam(lt / d, 3.7, 4.2, -0.3, 0, 0.18); render(blit, { bloom: 0.45 });
      O.topShade(1); tag(lt, 'YÜK: DIŞ CAMDA', 0.1); sub(lt, 'ORTA CAM: RAHAT', safeWd('ortadaki', 8, s0 + 1.8) - s0, 500, GLASS, YEL, 46);
    } });
    cue(s0, 'whoosh'); cue(s0 + yk, 'impact', { gain: 0.5 }); cue(s0 + 1.8, 'pop', { gain: 0.5 }); }

  // 9 · moisture: fog gathers, then leaves through the hole
  { const s0 = cut(9), nk = safeWd('nemi', 9, s0 + 0.3) - s0, bk = safeWd('buğulanmaz', 9, s0 + 2.6) - s0;
    add({ id: 'S09', at: s0, note: 'section: fog in the gap clears as moisture leaves through the hole', fov: 34, draw(lt, d, t, blit) {
      reset(); st.view = 'sec'; st.eq = 1; st.holeGlow = 0.2; st.fog = lt < bk ? eio(seg(lt, 0, 0.6)) : 1 - eio(seg(lt, bk, bk + 0.8)); st.vent = lt > nk ? 1 : 0; WR.update(t); secCam(lt / d, 4.2, 3.5, -0.2, -0.25, 0.2); render(blit, { bloom: 0.4 });
      O.topShade(1); tag(lt, 'NEM DIŞARI ÇIKAR', 0.1); sub(lt, 'BUĞU YOK • BUZ YOK', bk - 0.2, 500, YEL, INK, 50);
    } });
    cue(s0, 'whoosh'); cue(s0 + nk, 'slide', { dur: 1.6, gain: 0.4 }); cue(s0 + bk, 'sparkle', { dur: 1, gain: 0.5 }); }

  // 10 · punchline: back to the clean window
  add({ id: 'S10', at: cut(10), note: 'clean window front view, KUSUR DEĞİL | MÜHENDİSLİK', fov: 38, draw(lt, d, t, blit) {
    reset(); st.view = 'front'; st.outGlow = 0; WR.update(t); frontCam(V3(-0.6, 0.2, 3.4), V3(0.3, -0.05, 4.4), V3(0, -0.1, 0), lt / d); render(blit, { bloom: 0.35 });
    O.topShade(1); O.pillAt('KUSUR', 540, 330, eob(seg(lt, safeWd('kusur', 10, cut(10) + 0.9) - cut(10) - 0.1, safeWd('kusur', 10, cut(10) + 0.9) - cut(10) + 0.25)), '#fff', RED, 62);
    O.pillAt('MÜHENDİSLİK', 540, 480, eob(seg(lt, safeWd('mühendislik', 10, cut(10) + 1.8) - cut(10) - 0.1, safeWd('mühendislik', 10, cut(10) + 1.8) - cut(10) + 0.25)), INK, CY, 62);
    const [hx, hy] = screen(WR.holePt.clone().setZ(0.05), cam); pulse(hx, hy, 40, seg(lt, 0.3, 0.6), t);
  } });
  cue(cut(10), 'whoosh'); cue(cut(10) + 0.9, 'pop', { gain: 0.5 }); cue(cut(10) + 1.8, 'pop');

  // 11 · CTA
  { const LIST = [['A', 'Kanat'], ['B', 'Kara kutu'], ['C', 'İniş takımı'], ['D', 'Otopilot']];
    add({ id: 'S11', at: cut(11), note: 'window view; "SIRADAKİ PARÇA?" list', fov: 38, draw(lt, d, t, blit) {
      reset(); st.view = 'front'; WR.update(t); frontCam(V3(0.3, 0.0, 4.4), V3(-0.1, 0.0, 5.2), V3(0, -0.1, 0), lt / d); render(blit, { bloom: 0.35, exposure: 0.75 });
      O.flash(lt, 0.18); O.topShade(1); O.pillAt('SIRADAKİ PARÇA?', 540, 280, eob(seg(lt, 0, 0.35)), INK, YEL, 64);
      LIST.forEach(([a, b], i) => O.pillAt(`${a} · ${b}`, i % 2 ? 805 : 275, 470 + Math.floor(i / 2) * 130, eob(seg(lt, 0.4 + i * 0.15, 0.7 + i * 0.15)), '#fff', GLASS, 52));
      O.pillAt('@kokp.it360', 540, 1190, eo(seg(lt, 1.2, 1.6)), CY, GLASS, 52);
    } });
    cue(cut(11), 'whoosh'); for (let i = 0; i < 4; i++) cue(cut(11) + 0.4 + i * 0.15, 'tock', { gain: 0.5 }); cue(T.dur - 1.3, 'chime', { gain: 0.5 }); }

  // flash on every cut (except the first and the CTA, which flashes itself)
  S.forEach((s, i) => { if (i > 0 && s.id !== 'S11') { const dr = s.draw; s.draw = (lt, d, t, blit) => { dr(lt, d, t, blit); O.flash(lt, 0.15); }; } });
  return { shots: S, cues: CUES };
}
__EOF_WT__
cat > "$P/src/core/world.js" <<'__EOF_WT__'
// World Tour sets: stylized, sunlit 3D landmarks built from code (no models, no images). Units ≈ 10 m.
// Each set returns { scene, update(t), ...handles }. All motion is a pure function of film time t.
import * as THREE from 'three';
import { noise3 } from './sdf.js';
import { SHADOW } from './engine.js';

const TAU = Math.PI * 2;
export const std = (color, rough = 0.85, x = {}) => new THREE.MeshStandardMaterial({ color, roughness: rough, ...x });
const sh = (m, cast = true) => { m.castShadow = cast; m.receiveShadow = true; return m; };
const rnd = (i) => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
export const fbm = (x, z, o = 4) => { let a = 0, f = 1, w = 0.5; for (let i = 0; i < o; i++) { a += noise3(x * f, 0.37 * i, z * f) * w; f *= 2.03; w *= 0.5; } return a; };
const smooth = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const col = (h) => new THREE.Color(h);
const lerpC = (a, b, k) => a.clone().lerp(b, k);

export function cameraWide(fov = 34) { return new THREE.PerspectiveCamera(fov, 1080 / 1920, 0.3, 5000); }

function gradTex(stops) {
  const c = document.createElement('canvas'); c.width = 4; c.height = 512; const g = c.getContext('2d');
  const gr = g.createLinearGradient(0, 0, 0, 512); stops.forEach(([p, s]) => gr.addColorStop(p, s)); g.fillStyle = gr; g.fillRect(0, 0, 4, 512);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
function radialTex(inner = 'rgba(255,240,200,1)') {
  const c = document.createElement('canvas'); c.width = c.height = 256; const g = c.getContext('2d');
  const gr = g.createRadialGradient(128, 128, 0, 128, 128, 128); gr.addColorStop(0, inner); gr.addColorStop(0.18, inner.replace(/[\d.]+\)$/, '0.55)')); gr.addColorStop(1, 'rgba(255,200,150,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 256, 256); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
/** scene with gradient sky (top → horizon), fog and the soft room environment */
function base(E, { sky, fog, near = 60, far = 600, env = 0.35 }) {
  const scene = new THREE.Scene(); scene.background = gradTex(sky); scene.fog = new THREE.Fog(fog, near, far);
  scene.environment = E.envMap; scene.environmentIntensity = env; return scene;
}
/** the sun: directional light with a big soft shadow box + a glowing disc and halo in the sky */
function sun(scene, { dir, color = '#FFE0B0', I = 3.0, box = 60, target = [0, 0, 0], disc = true, discCol = '#FFF2D0', discSize = 30, dist = 1500, halo = 1 }) {
  const d = new THREE.Vector3(...dir).normalize(), L = new THREE.DirectionalLight(color, I);
  L.position.copy(d.clone().multiplyScalar(box * 3).add(new THREE.Vector3(...target))); L.target.position.set(...target); L.castShadow = true;
  L.shadow.mapSize.set(SHADOW, SHADOW); L.shadow.bias = -0.0006; L.shadow.normalBias = 0.05; L.shadow.radius = 4;
  Object.assign(L.shadow.camera, { left: -box, right: box, top: box, bottom: -box, near: 1, far: box * 7 }); L.shadow.camera.updateProjectionMatrix();
  scene.add(L, L.target);
  if (disc) {
    const p = d.clone().multiplyScalar(dist);
    const m = new THREE.Mesh(new THREE.SphereGeometry(discSize, 24, 16), new THREE.MeshBasicMaterial({ color: col(discCol).multiplyScalar(3), fog: false })); m.position.copy(p); scene.add(m);
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: radialTex(), color: col(discCol), transparent: true, depthWrite: false, fog: false, blending: THREE.AdditiveBlending, opacity: 0.9 * halo }));
    s.scale.setScalar(discSize * 16); s.position.copy(p); scene.add(s);
  }
  return L;
}
function hemi(scene, sky, ground, I) { const h = new THREE.HemisphereLight(sky, ground, I); scene.add(h); return h; }

/** heightfield terrain: hf(x, z) → y, cf(x, y, z, slope) → THREE.Color */
function terrain(size, seg, hf, cf, { flat = false, rough = 0.95, cx = 0, cz = 0 } = {}) {
  const g = new THREE.PlaneGeometry(size, size, seg, seg); g.rotateX(-Math.PI / 2);
  const p = g.attributes.position, C = new Float32Array(p.count * 3);
  for (let i = 0; i < p.count; i++) { const x = p.getX(i) + cx, z = p.getZ(i) + cz; p.setX(i, x); p.setZ(i, z); p.setY(i, hf(x, z)); }
  g.computeVertexNormals(); const n = g.attributes.normal;
  for (let i = 0; i < p.count; i++) { const c = cf(p.getX(i), p.getY(i), p.getZ(i), 1 - n.getY(i)); C[i * 3] = c.r; C[i * 3 + 1] = c.g; C[i * 3 + 2] = c.b; }
  g.setAttribute('color', new THREE.BufferAttribute(C, 3));
  return sh(new THREE.Mesh(g, std('#ffffff', rough, { vertexColors: true, flatShading: flat })), false);
}
/** InstancedMesh from a list of { p:[x,y,z], s:[sx,sy,sz] | number, r:[rx,ry,rz], c:'#hex' } */
function inst(geo, mat, items, cast = true) {
  const m = new THREE.InstancedMesh(geo, mat, items.length), o = new THREE.Object3D();
  items.forEach((it, i) => {
    o.position.set(...it.p); o.rotation.set(...(it.r || [0, 0, 0])); const s = it.s ?? 1; Array.isArray(s) ? o.scale.set(...s) : o.scale.setScalar(s); o.updateMatrix(); m.setMatrixAt(i, o.matrix);
    if (it.c) m.setColorAt(i, col(it.c));
  });
  m.castShadow = cast; m.receiveShadow = true; return m;
}
/** merge plain geometries (positions + normals) into one, so a lattice of struts is one draw call */
function merge(geos) {
  let n = 0; const parts = geos.map((g) => { const q = g.index ? g.toNonIndexed() : g; n += q.attributes.position.count; return q; });
  const P = new Float32Array(n * 3), N = new Float32Array(n * 3); let o = 0;
  for (const q of parts) { P.set(q.attributes.position.array, o * 3); N.set(q.attributes.normal.array, o * 3); o += q.attributes.position.count; }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(P, 3)); g.setAttribute('normal', new THREE.BufferAttribute(N, 3)); return g;
}
const _up = new THREE.Vector3(0, 1, 0);
function strut(a, b, r, seg = 5) {
  const A = new THREE.Vector3(...a), B = new THREE.Vector3(...b), L = A.distanceTo(B), g = new THREE.CylinderGeometry(r, r, L, seg, 1, true);
  const q = new THREE.Quaternion().setFromUnitVectors(_up, B.clone().sub(A).normalize());
  g.applyMatrix4(new THREE.Matrix4().compose(A.clone().add(B).multiplyScalar(0.5), q, new THREE.Vector3(1, 1, 1))); return g;
}
function water(size, color, { rough = 0.08, metal = 0.25, y = 0, cx = 0, cz = 0, opacity = 1 } = {}) {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size, 1, 1), new THREE.MeshPhysicalMaterial({ color, roughness: Math.max(0.22, rough), metalness: Math.min(0.3, metal), clearcoat: 0.5, clearcoatRoughness: 0.25, transparent: opacity < 1, opacity }));
  m.rotation.x = -Math.PI / 2; m.position.set(cx, y, cz); m.receiveShadow = true; return m;
}
/** soft cumulus puffs: count clouds, each 5-9 spheres, spread over an area */
function cloudField(n, { x = [-200, 200], z = [-300, 50], y = [20, 40], s = [4, 9], seed = 1, color = '#FFFFFF', emissive = '#FFE9D6', ei = 0.12, flat = 0.55 } = {}) {
  const items = [];
  for (let i = 0; i < n; i++) {
    const cx = x[0] + rnd(i * 3 + seed) * (x[1] - x[0]), cz = z[0] + rnd(i * 5 + seed * 7) * (z[1] - z[0]), cy = y[0] + rnd(i * 7 + seed * 3) * (y[1] - y[0]), S = s[0] + rnd(i * 11 + seed) * (s[1] - s[0]);
    const k = 5 + Math.floor(rnd(i * 13 + seed) * 5);
    for (let j = 0; j < k; j++) { const a = (j / k) * TAU + rnd(i + j), r = S * (0.5 + 0.6 * rnd(i * 17 + j)); const ss = S * (0.55 + 0.5 * rnd(i * 19 + j * 3)); items.push({ p: [cx + Math.cos(a) * r * 1.4, cy + rnd(j * 23 + i) * S * 0.3, cz + Math.sin(a) * r * 0.8], s: [ss, ss * flat + S * 0.1, ss] }); }
    items.push({ p: [cx, cy + S * 0.25, cz], s: [S * 1.1, S * 0.75, S * 1.0] });
  }
  return inst(new THREE.IcosahedronGeometry(1, 2), std(color, 1, { emissive, emissiveIntensity: ei }), items, false);
}
function trees(items, { crown = '#4E8A3E', trunk = '#6B4A30', shape = 'round' } = {}) {
  const g = new THREE.Group();
  const cg = shape === 'cone' ? new THREE.ConeGeometry(1, 1, 7) : new THREE.IcosahedronGeometry(1, 1);
  g.add(inst(cg, std(crown, 0.9, { flatShading: true }), items.map((t) => ({ p: [t.p[0], t.p[1] + (shape === 'cone' ? t.h * 0.5 + t.h * 0.15 : t.h * 0.75), t.p[2]], s: shape === 'cone' ? [t.w, t.h, t.w] : [t.w, t.h * 0.55, t.w], c: t.c }))));
  g.add(inst(new THREE.CylinderGeometry(0.12, 0.16, 1, 5), std(trunk), items.map((t) => ({ p: [t.p[0], t.p[1] + t.h * 0.2, t.p[2]], s: [t.w * 0.6, t.h * 0.45, t.w * 0.6] }))));
  return g;
}

// ═════════════════════════ 0 · FLIGHT ABOVE THE CLOUDS (sunrise) ═════════════════════════
export function flight(E) {
  const scene = base(E, { sky: [[0, '#2C4E8C'], [0.55, '#E79A74'], [0.8, '#FFC98E'], [1, '#FFE3B5']], fog: '#F4C79E', near: 120, far: 900, env: 0.4 });
  sun(scene, { dir: [-0.35, 0.12, -1], color: '#FFD3A0', I: 2.6, box: 40, discSize: 26, discCol: '#FFE8C2' }); hemi(scene, '#FFE6CF', '#B98B7A', 1.1);
  scene.add(cloudField(150, { x: [-420, 420], z: [-900, 120], y: [-14, -6], s: [10, 24], seed: 3, flat: 0.4, color: '#F3E6DE', emissive: '#E8A88A', ei: 0.06 }));
  scene.add(cloudField(26, { x: [-500, 500], z: [-1100, -500], y: [30, 80], s: [20, 40], seed: 9, flat: 0.4, ei: 0.25 }));
  const plane = new THREE.Group(), white = std('#F6F7FA', 0.35, { metalness: 0.2 }), accent = std('#1FA3A8', 0.4), grey = std('#B9C0C8', 0.4, { metalness: 0.6 });
  const fus = sh(new THREE.Mesh(new THREE.CapsuleGeometry(0.55, 6, 8, 20), white)); plane.scale.setScalar(1.4); fus.rotation.x = Math.PI / 2; plane.add(fus);
  const nose = sh(new THREE.Mesh(new THREE.SphereGeometry(0.55, 20, 14), white)); nose.scale.set(1, 1, 1.6); nose.position.z = -3.4; plane.add(nose);
  const wingShape = new THREE.Shape([new THREE.Vector2(0, 0), new THREE.Vector2(5.2, 1.6), new THREE.Vector2(5.2, 2.2), new THREE.Vector2(0, 1.6)]);
  for (const s of [-1, 1]) {
    const w = sh(new THREE.Mesh(new THREE.ExtrudeGeometry(wingShape, { depth: 0.12, bevelEnabled: false }), white)); w.rotation.x = Math.PI / 2; w.scale.set(s, 1, 1); w.position.set(0, -0.15, -0.9); w.rotation.z = 0; plane.add(w);
    const eng = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.28, 1.3, 16), grey)); eng.rotation.x = Math.PI / 2; eng.position.set(s * 2.0, -0.55, -0.1); plane.add(eng);
    const st = sh(new THREE.Mesh(new THREE.ExtrudeGeometry(new THREE.Shape([new THREE.Vector2(0, 0), new THREE.Vector2(1.8, 0.7), new THREE.Vector2(1.8, 1.1), new THREE.Vector2(0, 0.9)]), { depth: 0.08, bevelEnabled: false }), white));
    st.rotation.x = Math.PI / 2; st.scale.set(s, 1, 1); st.position.set(0, 0.1, 2.5); plane.add(st);
  }
  const fin = sh(new THREE.Mesh(new THREE.ExtrudeGeometry(new THREE.Shape([new THREE.Vector2(0, 0), new THREE.Vector2(1.9, 0), new THREE.Vector2(2.3, 2.0), new THREE.Vector2(1.6, 2.0)]), { depth: 0.1, bevelEnabled: false }), accent));
  fin.rotation.y = -Math.PI / 2; fin.position.set(0.05, 0.3, 1.5); plane.add(fin);
  const stripe = new THREE.Mesh(new THREE.CylinderGeometry(0.56, 0.56, 4.5, 24, 1, true, -0.6, 1.2), accent); stripe.rotation.x = Math.PI / 2; stripe.rotation.y = Math.PI; stripe.position.z = -0.5; plane.add(stripe);
  scene.add(plane);
  return { scene, plane, update(t) { plane.position.set(Math.sin(t * 0.5) * 1.5, 36 + Math.sin(t * 0.8) * 0.4, -t * 16); plane.rotation.set(0.03 * Math.sin(t * 0.7), 0, 0.07 * Math.sin(t * 0.5)); } };
}

// ═════════════════════════ 1 · PARIS: EIFFEL TOWER (golden hour) ═════════════════════════
export function paris(E) {
  const scene = base(E, { sky: [[0, '#3B65A8'], [0.5, '#9DB4D2'], [0.78, '#F3BE8A'], [1, '#FFDDB0']], fog: '#EDC9A6', near: 80, far: 520, env: 0.35 });
  sun(scene, { dir: [-0.75, 0.32, -0.55], color: '#FFCF98', I: 3.4, box: 45, target: [0, 8, 0], discSize: 22 }); hemi(scene, '#CFE0FF', '#8A6E52', 0.9);
  const ground = terrain(1400, 120, (x, z) => 0, (x, y, z) => { const n = fbm(x * 0.02, z * 0.02); return col('#7E8F5E').lerp(col('#A99A7A'), 0.3 + 0.3 * n); });
  scene.add(ground);
  // Champ de Mars: lawns + gravel paths in front (+z) of the tower, tree rows on both sides
  const lawn = std('#6DA34D', 0.95), gravel = std('#D8C7A4', 1);
  for (const [x, w] of [[-9, 9], [9, 9]]) for (let k = 0; k < 4; k++) { const m = sh(new THREE.Mesh(new THREE.BoxGeometry(w, 0.12, 20), lawn), false); m.position.set(x * 0.85, 0.06, 18 + k * 23); scene.add(m); }
  const path = sh(new THREE.Mesh(new THREE.BoxGeometry(46, 0.06, 110), gravel), false); path.position.set(0, 0.03, 52); scene.add(path);
  const tr = []; for (let k = 0; k < 26; k++) for (const x of [-21, -24, 21, 24]) tr.push({ p: [x, 0, 10 + k * 3.6], w: 1.5, h: 4.2 + rnd(k + x) * 0.8, c: rnd(k * 3 + x) > 0.5 ? '#4F8A3C' : '#5E9642' });
  for (let k = 0; k < 50; k++) { const a = rnd(k) * TAU, r = 16 + rnd(k * 7) * 6; tr.push({ p: [Math.cos(a) * r, 0, -Math.abs(Math.sin(a)) * r - 4], w: 1.6, h: 4.5, c: '#4F8A3C' }); }
  scene.add(trees(tr));
  // the Seine behind, city blocks around (cream stone, blue-grey zinc roofs)
  scene.add(water(1, '#5C7E92', { rough: 0.15 })); const seine = scene.children[scene.children.length - 1]; seine.scale.set(800, 18, 1); seine.position.set(0, 0.05, -34);
  const blocks = [], roofs = [];
  for (let i = 0; i < 520; i++) {
    const x = (rnd(i * 3) - 0.5) * 520, z = (rnd(i * 5) - 0.5) * 520; if (Math.abs(x) < 30 && z > -44 && z < 140) continue; if (z > -44 && z < -24) continue;
    const w = 6 + rnd(i * 7) * 8, d = 6 + rnd(i * 11) * 8, h = 2.2 + rnd(i * 13) * 1.4;
    blocks.push({ p: [x, h / 2, z], s: [w, h, d], c: rnd(i) > 0.5 ? '#E8DCC4' : '#DCCDB2' }); roofs.push({ p: [x, h + 0.45, z], s: [w * 0.92, 0.9, d * 0.92], c: '#6E7C8C' });
  }
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.9), blocks), inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.6, { metalness: 0.3 }), roofs));
  // the tower (1 unit = 10 m): corner rails follow w(y), lattice ties + X braces, arches, three platforms, antenna
  const w = (y) => 6.25 * Math.exp(-y / 9.2) + 0.12, lw = (y) => Math.max(0.12, 1.5 * (1 - y / 12));
  const G = [], R = 0.1, step = 0.55;
  const corner = (sx, sz, y, ox = 0, oz = 0) => [sx * (w(y) - ox), y, sz * (w(y) - oz)];
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    for (let y = 0; y < 27.6; y += step) {
      const y2 = Math.min(27.6, y + step), a = lw(y), b = lw(y2);
      const rails = [[0, 0], [a, 0], [0, a], [a, a]], rails2 = [[0, 0], [b, 0], [0, b], [b, b]];
      if (y < 12) rails.forEach((r, k) => G.push(strut(corner(sx, sz, y, ...r), corner(sx, sz, y2, ...rails2[k]), R * (y < 6 ? 1.3 : 1))));
      else G.push(strut(corner(sx, sz, y), corner(sx, sz, y2), R * 0.9));
      if (y < 12 && Math.round(y / step) % 2 === 0) { // leg ties + braces
        const q = (r) => corner(sx, sz, y, ...r); G.push(strut(q([0, 0]), q([a, 0]), 0.05), strut(q([0, 0]), q([0, a]), 0.05), strut(q([a, 0]), q([a, a]), 0.05), strut(q([0, a]), q([a, a]), 0.05));
        const q2 = (r) => corner(sx, sz, y2 + step, ...r); G.push(strut(q([0, 0]), q2([a, 0]), 0.04), strut(q([a, 0]), q2([0, 0]), 0.04), strut(q([0, 0]), q2([0, a]), 0.04), strut(q([0, a]), q2([0, 0]), 0.04));
      }
    }
  }
  for (let y = 5.7; y < 27.6; y += 1.1) { // tower body ties + X braces on the four faces
    const y2 = Math.min(27.6, y + 1.1), c = (sx, sz, yy) => [sx * w(yy), yy, sz * w(yy)];
    for (const [a, b] of [[[-1, -1], [1, -1]], [[1, -1], [1, 1]], [[1, 1], [-1, 1]], [[-1, 1], [-1, -1]]]) {
      G.push(strut(c(...a, y), c(...b, y), 0.06)); G.push(strut(c(...a, y), c(...b, y2), 0.04), strut(c(...b, y), c(...a, y2), 0.04));
    }
  }
  for (let f = 0; f < 4; f++) { // arches under the first floor
    const pts = []; for (let k = 0; k <= 24; k++) { const th = Math.PI * k / 24, x = 4.3 * Math.cos(th), y = 0.9 + 4.35 * Math.sin(th); pts.push(new THREE.Vector3(x, y, w(y) - 0.25)); }
    const g = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 40, 0.16, 6); g.applyMatrix4(new THREE.Matrix4().makeRotationY(f * Math.PI / 2)); G.push(g);
  }
  const iron = std('#5C4636', 0.55, { metalness: 0.55 });
  const tower = new THREE.Group(); tower.add(sh(new THREE.Mesh(merge(G), iron)));
  for (const [y, h, pad] of [[5.7, 0.55, 0.7], [11.6, 0.4, 0.45]]) { const s = 2 * w(y) + pad; const p = sh(new THREE.Mesh(new THREE.BoxGeometry(s, h, s), std('#4E3B2E', 0.6, { metalness: 0.4 }))); p.position.y = y; tower.add(p); const rail = sh(new THREE.Mesh(new THREE.BoxGeometry(s + 0.1, 0.25, s + 0.1), std('#6A5242', 0.6, { metalness: 0.4 }))); rail.position.y = y + h * 0.5 + 0.12; tower.add(rail); }
  const top = sh(new THREE.Mesh(new THREE.BoxGeometry(1.1, 1.0, 1.1), iron)); top.position.y = 27.9; tower.add(top);
  const cap = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.5, 1.2, 8), iron)); cap.position.y = 29; tower.add(cap);
  const ant = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.1, 3.6, 6), std('#C9C2B8', 0.4, { metalness: 0.7 }))); ant.position.y = 31.4; tower.add(ant);
  const beacon = new THREE.Mesh(new THREE.SphereGeometry(0.18, 12, 8), new THREE.MeshBasicMaterial({ color: col('#FFE6A0').multiplyScalar(4) })); beacon.position.y = 33.1; tower.add(beacon);
  scene.add(tower);
  return { scene, tower, top: new THREE.Vector3(0, 33, 0), update(t) { beacon.scale.setScalar(0.8 + 0.4 * (0.5 + 0.5 * Math.sin(t * 6))); } };
}

// ═════════════════════════ 2 · GIZA PYRAMIDS (hot afternoon) ═════════════════════════
export function giza(E) {
  const scene = base(E, { sky: [[0, '#3F86C8'], [0.6, '#9CC6E6'], [0.85, '#EBD9B8'], [1, '#F3E3C4']], fog: '#EAD7B6', near: 90, far: 700, env: 0.3 });
  sun(scene, { dir: [0.9, 0.42, -0.35], color: '#FFF0D2', I: 3.8, box: 70, target: [-20, 0, -20], discSize: 18 }); hemi(scene, '#CFE3FF', '#C89A63', 0.55);
  const h = (x, z) => 1.4 * Math.sin(x * 0.045 + z * 0.02) * Math.sin(z * 0.06) + 2.2 * fbm(x * 0.012, z * 0.012) + (Math.hypot(x + 26, z + 24) < 30 ? 0.6 : 0) * 0;
  const flat = (x, z) => { const d = Math.min(Math.hypot(x, z) - 22, Math.hypot(x + 26, z + 24) - 21, Math.hypot(x + 46, z + 48) - 11); return smooth(0, 14, d); };
  scene.add(terrain(1600, 180, (x, z) => h(x, z) * flat(x, z) - 0.2, (x, y, z, s) => lerpC(col('#E2BF86'), col('#C99B62'), 0.35 + 0.4 * fbm(x * 0.05, z * 0.05) + s * 1.5)));
  const stone = std('#D7AE76', 0.95, { flatShading: true }), casing = std('#ECDDB8', 0.9, { flatShading: true });
  const pyr = (r, hh, x, z, capK = 0) => {
    const g = new THREE.Group(), m = sh(new THREE.Mesh(new THREE.ConeGeometry(r, hh, 4, 6), stone)); m.position.y = hh / 2; g.add(m);
    if (capK) { const c = sh(new THREE.Mesh(new THREE.ConeGeometry(r * capK, hh * capK, 4, 1), casing)); c.position.y = hh * (1 - capK / 2) + 0.03; g.add(c); }
    g.rotation.y = Math.PI / 4; g.position.set(x, 0, z); scene.add(g); return g;
  };
  const khufu = pyr(16.3, 14.6, 0, 0), khafre = pyr(15.2, 13.6, -26, -24, 0.16), menk = pyr(7.3, 6.5, -46, -48);
  for (let k = 0; k < 3; k++) pyr(3.2, 2.9, 20 + k * 1.5, -6 + k * 7.5);
  // ring of tiny stone blocks at the base (rubble) + a few palms toward the camera side
  const rub = []; for (let i = 0; i < 160; i++) { const a = rnd(i) * TAU, r = 18 + rnd(i * 3) * 8; rub.push({ p: [Math.cos(a) * r, 0.2, Math.sin(a) * r], s: [0.5 + rnd(i * 5), 0.4, 0.5 + rnd(i * 7)], r: [0, rnd(i) * 3, 0], c: '#CDA672' }); }
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 1), rub));
  const palms = new THREE.Group(); for (let i = 0; i < 9; i++) {
    const x = 34 + rnd(i * 3) * 30, z = 30 + rnd(i * 5) * 40, tr = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.2, 4, 6), std('#8A6A45'))); tr.position.set(x, 2, z); tr.rotation.z = (rnd(i) - 0.5) * 0.3; palms.add(tr);
    for (let f = 0; f < 7; f++) { const l = sh(new THREE.Mesh(new THREE.ConeGeometry(0.35, 2.4, 4), std('#4E8B3A', 0.9, { flatShading: true }))); l.position.set(x + Math.cos(f) * 0.9, 4.0, z + Math.sin(f) * 0.9); l.rotation.set(Math.sin(f) * 1.2, 0, -Math.cos(f) * 1.2); palms.add(l); }
  } scene.add(palms);
  return { scene, khufu, top: new THREE.Vector3(0, 14.6, 0), update() {} };
}

// ═════════════════════════ 3 · TAJ MAHAL (soft pink morning) ═════════════════════════
function onionDome(r, h) { const pts = []; for (let k = 0; k <= 30; k++) { const v = k / 30; const rr = v < 0.35 ? r * (1 + 0.16 * Math.sin(v / 0.35 * Math.PI / 2)) : r * 1.16 * Math.pow(Math.cos((v - 0.35) / 0.65 * Math.PI / 2), 0.9); pts.push(new THREE.Vector2(Math.max(0.001, rr), v * h)); } return new THREE.LatheGeometry(pts, 40); }
function archShape(w, h) { const s = new THREE.Shape(); s.moveTo(-w / 2, 0); s.lineTo(-w / 2, h * 0.62); s.quadraticCurveTo(-w / 2, h * 0.9, 0, h); s.quadraticCurveTo(w / 2, h * 0.9, w / 2, h * 0.62); s.lineTo(w / 2, 0); s.closePath(); return s; }
function chhatri(marble, s = 1) {
  const g = new THREE.Group(); for (let k = 0; k < 6; k++) { const a = k / 6 * TAU, p = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.05 * s, 0.05 * s, 0.7 * s, 6), marble)); p.position.set(Math.cos(a) * 0.38 * s, 0.35 * s, Math.sin(a) * 0.38 * s); g.add(p); }
  const roof = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.5 * s, 0.5 * s, 0.1 * s, 12), marble)); roof.position.y = 0.72 * s; g.add(roof);
  const d = sh(new THREE.Mesh(onionDome(0.36 * s, 0.75 * s), marble)); d.position.y = 0.76 * s; g.add(d); return g;
}
export function taj(E) {
  const scene = base(E, { sky: [[0, '#6E95CF'], [0.55, '#C9C3D8'], [0.82, '#F4C6AE'], [1, '#FBDCC4']], fog: '#F1D3C2', near: 70, far: 420, env: 0.45 });
  sun(scene, { dir: [-0.8, 0.35, 0.45], color: '#FFD8B8', I: 3.0, box: 30, target: [0, 3, -4], discSize: 18, discCol: '#FFE4CC' }); hemi(scene, '#E7E2FF', '#9C8A72', 1.0);
  scene.add(terrain(900, 90, () => 0, (x, y, z) => lerpC(col('#6E9A55'), col('#8FA866'), 0.5 + 0.5 * fbm(x * 0.05, z * 0.05))));
  const marble = new THREE.MeshPhysicalMaterial({ color: '#F6F2EA', roughness: 0.35, clearcoat: 0.4, emissive: '#3A2E2A', emissiveIntensity: 0.05 });
  const shade = std('#D9CFC0', 0.6), inner = std('#BFB2A0', 0.7), redS = std('#B4553E', 0.85), path = std('#ECE6DA', 0.8);
  const g = new THREE.Group(); g.position.z = -6;
  const plinth = sh(new THREE.Mesh(new THREE.BoxGeometry(19, 1.4, 19), marble)); plinth.position.y = 0.7; g.add(plinth);
  const body = sh(new THREE.Mesh(new THREE.CylinderGeometry(4.25, 4.25, 3.5, 8), marble)); body.rotation.y = Math.PI / 8; body.scale.set(1, 1, 1); body.position.y = 1.4 + 1.75; g.add(body);
  const fr = 4.25 * Math.cos(Math.PI / 8);
  for (let f = 0; f < 8; f++) { // pointed-arch iwans on the 8 faces (big on the 4 main faces)
    const big = f % 2 === 0, a = f * Math.PI / 4, ag = new THREE.Group(); ag.rotation.y = a; ag.position.y = 1.4;
    const frame = new THREE.Mesh(new THREE.PlaneGeometry(big ? 2.4 : 1.4, big ? 3.2 : 1.5), shade); frame.position.set(0, big ? 1.75 : 2.4, fr + 0.02); if (big) ag.add(frame);
    const ar = new THREE.Mesh(new THREE.ShapeGeometry(archShape(big ? 1.9 : 1.0, big ? 2.8 : 1.3)), inner); ar.position.set(0, big ? 0.15 : 0.25, fr + 0.04); ag.add(ar);
    if (!big) { const a2 = new THREE.Mesh(new THREE.ShapeGeometry(archShape(1.0, 1.2)), inner); a2.position.set(0, 1.85, fr + 0.04); ag.add(a2); }
    g.add(ag);
  }
  const drum = sh(new THREE.Mesh(new THREE.CylinderGeometry(1.75, 1.75, 1.0, 40), marble)); drum.position.y = 4.9 + 0.5; g.add(drum);
  const dome = sh(new THREE.Mesh(onionDome(1.75, 3.1), marble)); dome.position.y = 5.9; g.add(dome);
  const gold = std('#D9B25A', 0.3, { metalness: 0.9 }); const fin = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.08, 1.1, 8), gold)); fin.position.y = 9.4; g.add(fin);
  for (const y of [9.1, 9.45]) { const b = new THREE.Mesh(new THREE.SphereGeometry(0.1, 12, 8), gold); b.position.y = y; g.add(b); }
  for (const [x, z] of [[-2.3, -2.3], [2.3, -2.3], [-2.3, 2.3], [2.3, 2.3]]) { const c = chhatri(marble, 1.2); c.position.set(x, 4.9, z); g.add(c); }
  for (const [x, z] of [[-8.6, -8.6], [8.6, -8.6], [-8.6, 8.6], [8.6, 8.6]]) { // minarets
    const m = new THREE.Group(); m.position.set(x, 1.4, z);
    const sh1 = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.33, 0.45, 4.2, 16), marble)); sh1.position.y = 2.1; m.add(sh1);
    for (const y of [1.4, 2.8, 4.2]) { const b = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.55, 0.14, 16), marble)); b.position.y = y; m.add(b); }
    const c = chhatri(marble, 1.0); c.position.y = 4.25; m.add(c); g.add(m);
  }
  scene.add(g);
  // garden: long reflecting channel toward the camera, marble paths, cypress rows; red sandstone side buildings
  const ch = water(1, '#6F8FB3', { rough: 0.03, metal: 0.6 }); ch.scale.set(2.6, 64, 1); ch.position.set(0, 0.08, 38); scene.add(ch);
  const pth = sh(new THREE.Mesh(new THREE.BoxGeometry(7, 0.06, 66), path), false); pth.position.set(0, 0.03, 38); scene.add(pth);
  const cross = sh(new THREE.Mesh(new THREE.BoxGeometry(60, 0.06, 4), path), false); cross.position.set(0, 0.04, 40); scene.add(cross);
  const cyp = []; for (let k = 0; k < 18; k++) for (const x of [-4.3, 4.3]) cyp.push({ p: [x, 0, 8 + k * 3.6], w: 0.55, h: 3.2 + rnd(k + x) * 0.5, c: '#2F5B33' });
  scene.add(trees(cyp, { shape: 'cone', crown: '#2F5B33' }));
  for (const x of [-26, 26]) { const b = sh(new THREE.Mesh(new THREE.BoxGeometry(9, 3.2, 5), redS)); b.position.set(x, 1.6, -6); scene.add(b); for (const dx of [-2.6, 0, 2.6]) { const d = sh(new THREE.Mesh(onionDome(0.8, 1.2), marble)); d.position.set(x + dx, 3.2, -6); scene.add(d); } }
  const wall = sh(new THREE.Mesh(new THREE.BoxGeometry(80, 1.6, 0.8), redS)); wall.position.set(0, 0.8, -20); scene.add(wall);
  return { scene, dome: new THREE.Vector3(0, 7.4, -6), update() {} };
}

// ═════════════════════════ 4 · MACHU PICCHU (misty morning in the Andes) ═════════════════════════
export function machu(E) {
  const scene = base(E, { sky: [[0, '#6B9AD0'], [0.6, '#B7CFE2'], [1, '#E7EEF0']], fog: '#DCE5E9', near: 60, far: 420, env: 0.45 });
  sun(scene, { dir: [0.6, 0.55, 0.6], color: '#FFF1DC', I: 3.0, box: 50, target: [0, 10, 0], discSize: 16 }); hemi(scene, '#DDEBFF', '#4F6A44', 1.0);
  const peak = (x, z, cx, cz, hh, r) => hh * Math.exp(-((x - cx) ** 2 + (z - cz) ** 2) / (2 * r * r));
  const H = (x, z) => {
    const ridge = 10 * Math.exp(-(z * z) / (2 * 9 * 9)) * smooth(60, 20, Math.abs(x));             // the saddle the city sits on
    const plateau = Math.abs(z) < 7 && Math.abs(x) < 16 ? 0 : 0;
    const huayna = peak(x, z, 3, -27, 30, 6.5) + peak(x, z, -2, -33, 18, 9);
    const far = (smooth(55, 120, Math.hypot(x, z + 10))) * (40 + 30 * fbm(x * 0.012, z * 0.012));
    const valley = -22 * smooth(12, 30, Math.abs(z)) * (1 - smooth(70, 120, Math.hypot(x, z)));
    return Math.max(ridge + huayna + far + valley + 2.5 * fbm(x * 0.08, z * 0.08) + plateau, -22);
  };
  const T = (x, z) => { const y = H(x, z); const onSite = Math.abs(x) < 18 && Math.abs(z) < 14 && y > 1 && y < 11.5; return onSite ? Math.floor(y / 0.7) * 0.7 + 0.12 * fbm(x, z) : y; };
  scene.add(terrain(700, 260, T, (x, y, z, s) => {
    if (Math.abs(x) < 18 && Math.abs(z) < 14 && y > 1 && y < 11.5) { const f = (y / 0.7) % 1; return f < 0.18 ? col('#8F8B80') : col('#79B24E').lerp(col('#5E9A3E'), 0.5 + 0.5 * fbm(x * 0.2, z * 0.2)); }
    return lerpC(col('#3F7A39'), col('#6D7A5A'), Math.min(1, s * 2.2 + smooth(30, 60, y) * 0.6)).lerp(col('#E8EEF0'), smooth(62, 80, y));
  }, { cz: -40 }));
  // the citadel: grey stone houses (walls + dark thatch roofs), a green plaza, terraces around
  const houses = [], roofs = [];
  for (let i = 0; i < 140; i++) {
    const x = (rnd(i * 3) - 0.5) * 28, z = (rnd(i * 7) - 0.5) * 9; if (Math.abs(x) < 4 && Math.abs(z) < 2.5) continue;
    const y = H(x, z), w = 0.9 + rnd(i * 11) * 0.9, d = 0.7 + rnd(i * 13) * 0.6, hh = 0.55 + rnd(i * 17) * 0.25, ry = Math.round(rnd(i * 5) * 2) * Math.PI / 2;
    houses.push({ p: [x, y + hh / 2 - 0.05, z], s: [w, hh, d], r: [0, ry, 0], c: rnd(i) > 0.5 ? '#A9A397' : '#9A9488' });
    if (rnd(i * 19) > 0.55) roofs.push({ p: [x, y + hh + 0.22, z], s: [w * 0.75, 0.5, d * 1.05], r: [0, ry + Math.PI / 4, 0], c: '#7A5E3A' });
  }
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.95), houses), inst(new THREE.ConeGeometry(0.75, 1, 4), std('#ffffff', 1, { flatShading: true }), roofs));
  const mist = cloudField(30, { x: [-110, 110], z: [-90, 20], y: [-16, -2], s: [6, 13], seed: 5, flat: 0.5, emissive: '#FFFFFF', ei: 0.12 });
  mist.material.transparent = true; mist.material.opacity = 0.88; scene.add(mist);
  return { scene, mist, site: new THREE.Vector3(0, 10, 0), update(t) { mist.position.x = Math.sin(t * 0.07) * 6 + t * 0.6; } };
}

// ═════════════════════════ 5 · SANTORINI (sunset over the caldera) ═════════════════════════
export function santorini(E) {
  const scene = base(E, { sky: [[0, '#2B477E'], [0.45, '#8C6C9A'], [0.75, '#F08C5E'], [1, '#FFC47A']], fog: '#E9A77F', near: 140, far: 900, env: 0.35 });
  const C0 = new THREE.Vector3(0, 0, -62), R = 60;
  sun(scene, { dir: [-0.8, 0.14, -0.6], color: '#FFB27A', I: 3.2, box: 40, target: [0, 20, 0], discSize: 22, discCol: '#FFD9A0', halo: 0.45 }); hemi(scene, '#C9B6E8', '#6B4A3A', 1.0);
  const ang = (x, z) => Math.atan2(x - C0.x, z - C0.z);
  const land = (x, z) => {
    const d = Math.hypot(x - C0.x, z - C0.z), a = ang(x, z), main = smooth(1.45, 1.0, Math.abs(a)) ; // main island: the arc facing +z
    const far = (1 - smooth(2.2, 2.6, Math.abs(a))) * 0 + (Math.abs(a) > 2.3 ? 0.65 : 0);   // Thirasia across the caldera
    const k = Math.max(main, far * smooth(0.2, 0.6, Math.sin(a * 5) * 0.5 + 0.5));
    const cliff = smooth(R - 0.5, R + 4.5, d), top = 26 + 3 * fbm(x * 0.03, z * 0.03) - (d - R) * 0.12;
    const y = (-10 + (top + 10) * cliff) * k + (-10) * (1 - k);
    const volcano = 9 * Math.exp(-((x - C0.x - 6) ** 2 + (z - C0.z + 4) ** 2) / (2 * 11 * 11)) - 2;
    return Math.max(y, volcano, -10);
  };
  scene.add(terrain(900, 300, land, (x, y, z, s) => {
    if (y < 0.5) return col('#3A2A26');
    if (s > 0.35) { const b = Math.floor(y / 3.2) % 3; return [col('#8E4B3A'), col('#6E625C'), col('#B79A7E')][b].lerp(col('#5A3A30'), 0.2 * fbm(x * 0.2, y * 0.3)); }
    const d = Math.hypot(x - C0.x, z - C0.z); return d < R - 10 ? col('#3E2E2A') : lerpC(col('#B49B7A'), col('#9C7E62'), 0.5 + 0.5 * fbm(x * 0.05, z * 0.05));
  }, { cz: -40 }));
  scene.add(water(3000, '#1E4F7E', { rough: 0.12, metal: 0.35, y: 0.2 }));
  // Oia-style village on the rim and cascading down the cliff (white cubes, blue domes, a bell tower)
  const white = [], dark = [], domes = [];
  for (let i = 0; i < 900; i++) {
    const a = (rnd(i * 3) - 0.5) * 0.62, d = R + 0.6 + rnd(i * 7) * 9, x = C0.x + Math.sin(a) * d, z = C0.z + Math.cos(a) * d, y = land(x, z); if (y < 9) continue;
    const w = 1.0 + rnd(i * 11) * 1.4, hh = 0.9 + rnd(i * 13) * 0.9, dd = 1.0 + rnd(i * 17) * 1.2;
    white.push({ p: [x, y + hh / 2 - 0.3, z], s: [w, hh, dd], r: [0, a + (rnd(i) - 0.5) * 0.3, 0], c: rnd(i * 23) > 0.86 ? '#F3D9B5' : rnd(i * 29) > 0.92 ? '#F2C1A8' : '#FBFAF6' });
    if (rnd(i * 31) > 0.7) dark.push({ p: [x + Math.sin(a) * dd * 0.5, y + hh * 0.35 - 0.3, z + Math.cos(a) * dd * 0.5 - 0.02], s: [w * 0.25, hh * 0.45, 0.06], r: [0, a, 0], c: rnd(i) > 0.5 ? '#2A62C9' : '#3B3B3B' });
  }
  for (let i = 0; i < 14; i++) { const a = (rnd(i * 41) - 0.5) * 0.5, d = R + 1.5 + rnd(i * 43) * 6, x = C0.x + Math.sin(a) * d, z = C0.z + Math.cos(a) * d, y = land(x, z); if (y < 10) continue;
    white.push({ p: [x, y + 0.7, z], s: [2.0, 1.6, 2.0], r: [0, a, 0], c: '#FFFFFF' }); domes.push({ p: [x, y + 1.5, z], s: [0.95, 1.0, 0.95], c: '#2457C7' });
    if (i % 5 === 0) { white.push({ p: [x + 1.7, y + 1.4, z], s: [0.8, 2.8, 0.8], r: [0, a, 0], c: '#FFFFFF' }); domes.push({ p: [x + 1.7, y + 2.85, z], s: [0.4, 0.5, 0.4], c: '#2457C7' }); } }
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.7, { emissive: '#4A2A1A', emissiveIntensity: 0.06 }), white), inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.5), dark, false),
    inst(new THREE.SphereGeometry(1, 24, 12, 0, TAU, 0, Math.PI / 2), std('#ffffff', 0.35, { metalness: 0.1 }), domes));
  const boats = []; for (let i = 0; i < 6; i++) boats.push({ p: [C0.x + (rnd(i) - 0.5) * 70, 0.4, C0.z + 10 + rnd(i * 3) * 30], s: [0.8, 0.5, 2.4], r: [0, rnd(i * 5) * 3, 0], c: '#FFFFFF' });
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.5), boats));
  return { scene, center: C0.clone(), village: new THREE.Vector3(0, 24, -1), update() {} };
}

// ═════════════════════════ 6 · GREAT WALL (autumn mountains, morning mist) ═════════════════════════
export function wall(E) {
  const scene = base(E, { sky: [[0, '#6F98C8'], [0.6, '#C7D3DC'], [1, '#EBE3D3']], fog: '#D9D8D0', near: 50, far: 460, env: 0.4 });
  sun(scene, { dir: [0.7, 0.45, 0.3], color: '#FFE6C4', I: 3.2, box: 70, target: [0, 10, -40], discSize: 16 }); hemi(scene, '#DCE8FF', '#5F5A3E', 1.0);
  // the wall's path (xz), then a terrain whose ridges follow it
  const P = []; for (let k = 0; k <= 60; k++) { const s = k / 60; P.push([Math.sin(s * 5.2) * 26 + Math.sin(s * 13) * 6 - 4, 20 - s * 220]); }
  const dist = (x, z) => { let m = 1e9; for (let k = 0; k < P.length - 1; k++) { const [ax, az] = P[k], [bx, bz] = P[k + 1], vx = bx - ax, vz = bz - az, t = Math.max(0, Math.min(1, ((x - ax) * vx + (z - az) * vz) / (vx * vx + vz * vz))); m = Math.min(m, Math.hypot(x - ax - vx * t, z - az - vz * t)); } return m; };
  const base0 = (x, z) => 8 + 18 * fbm(x * 0.012, z * 0.012) + 6 * fbm(x * 0.04, z * 0.04);
  const H = (x, z) => { const d = dist(x, z); return base0(x, z) * 0.55 + 16 * Math.exp(-(d * d) / (2 * 12 * 12)) + 7 * fbm(x * 0.03 + 5, z * 0.03) * smooth(5, 25, d) - 6 * smooth(20, 60, d) + 30 * smooth(120, 260, Math.hypot(x, z + 80)); };
  scene.add(terrain(800, 280, H, (x, y, z, s) => {
    const n = fbm(x * 0.06, z * 0.06), au = smooth(0.05, 0.35, n);
    return col('#4E7A3C').lerp(col('#C27B36'), au * 0.7).lerp(col('#A4462A'), smooth(0.3, 0.5, n) * 0.6).lerp(col('#8C8574'), Math.min(1, s * 1.6));
  }, { flat: true, cz: -80 }));
  // wall segments every ~1.6 units along the path, crenellations both sides, a watchtower every 14 segments
  const seg = [], cren = [], towers = [], pts = [];
  for (let k = 0; k < P.length - 1; k++) { const [ax, az] = P[k], [bx, bz] = P[k + 1], L = Math.hypot(bx - ax, bz - az), n = Math.ceil(L / 1.6); for (let j = 0; j < n; j++) pts.push([ax + (bx - ax) * j / n, az + (bz - az) * j / n]); }
  for (let i = 0; i < pts.length - 1; i++) {
    const [x, z] = pts[i], [x2, z2] = pts[i + 1], y = H(x, z), y2 = H(x2, z2), a = Math.atan2(x2 - x, z2 - z), L = Math.hypot(x2 - x, z2 - z), pitch = Math.atan2(y2 - y, L);
    seg.push({ p: [(x + x2) / 2, (y + y2) / 2 + 0.6, (z + z2) / 2], s: [1.5, 1.7, L + 0.25], r: [-pitch, a, 0], c: '#A39A8B' });
    for (const sd of [-1, 1]) cren.push({ p: [(x + x2) / 2 + Math.cos(a) * 0.72 * sd, (y + y2) / 2 + 1.65, (z + z2) / 2 - Math.sin(a) * 0.72 * sd], s: [0.18, 0.5, 0.55], r: [0, a, 0], c: '#9A9182' });
    if (i % 14 === 7) { towers.push({ p: [x, y + 1.6, z], s: [3.0, 3.6, 3.0], r: [0, a, 0], c: '#9E9585' }); for (let q = 0; q < 4; q++) { const qa = a + q * Math.PI / 2; for (const o of [-0.9, 0, 0.9]) cren.push({ p: [x + Math.sin(qa) * 1.45 + Math.cos(qa) * o, y + 3.65, z + Math.cos(qa) * 1.45 - Math.sin(qa) * o], s: [0.5, 0.5, 0.2], r: [0, qa, 0], c: '#9A9182' }); } }
  }
  const segM = inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.9), seg), crenM = inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.9), cren), towM = inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 0.9), towers);
  scene.add(segM, crenM, towM);
  const mist = cloudField(30, { x: [-160, 160], z: [-260, -20], y: [0, 10], s: [8, 18], seed: 21, flat: 0.4, emissive: '#FFFFFF', ei: 0.3 }); mist.material.transparent = true; mist.material.opacity = 0.75; scene.add(mist);
  const nSeg = seg.length, nCren = cren.length, nTow = towers.length;
  return {
    scene, H, path: pts.map(([x, z]) => new THREE.Vector3(x, H(x, z) + 2.2, z)),
    reveal(k) { segM.count = Math.max(1, Math.round(nSeg * k)); crenM.count = Math.max(1, Math.round(nCren * k)); towM.count = Math.round(nTow * k); },
    update(t) { mist.position.x = t * 0.8; },
  };
}

// ═════════════════════════ 7 · CAPPADOCIA (sunrise, fairy chimneys, balloons) ═════════════════════════
function balloonTex(cols) {
  const c = document.createElement('canvas'); c.width = 512; c.height = 256; const g = c.getContext('2d'); const n = 16;
  for (let i = 0; i < n; i++) { g.fillStyle = cols[i % cols.length]; g.fillRect(i * 512 / n, 0, 512 / n + 1, 256); }
  g.fillStyle = 'rgba(255,255,255,0.18)'; g.fillRect(0, 150, 512, 14); g.fillStyle = 'rgba(0,0,0,0.12)'; g.fillRect(0, 0, 512, 40);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
function balloonGeo() {
  const pts = []; for (let k = 0; k <= 32; k++) { const v = k / 32; let r, y; if (v < 0.45) { const q = v / 0.45; y = -1.25 + q * 1.25; r = 0.22 + 0.78 * Math.sin(q * Math.PI / 2) ** 1.4; } else { const q = (v - 0.45) / 0.55, th = q * Math.PI / 2; y = Math.sin(th) * 1.05; r = Math.cos(th); } pts.push(new THREE.Vector2(Math.max(0.001, r), y)); }
  return new THREE.LatheGeometry(pts, 32);
}
export function cappadocia(E) {
  const scene = base(E, { sky: [[0, '#4A6FA8'], [0.5, '#B3A8C2'], [0.78, '#F4B183'], [1, '#FFD49A']], fog: '#EFC9A6', near: 70, far: 560, env: 0.4 });
  const S = sun(scene, { dir: [0.25, 0.1, -1], color: '#FFC690', I: 3.0, box: 60, target: [0, 0, -20], discSize: 22, discCol: '#FFE2B0' }); hemi(scene, '#D6CFF0', '#9B7258', 1.15);
  const H = (x, z) => 4 * fbm(x * 0.015, z * 0.015) + 3 * Math.sin(x * 0.05) * Math.cos(z * 0.04) + 18 * smooth(80, 200, Math.hypot(x, z + 40)) * (0.6 + 0.4 * fbm(x * 0.02, z * 0.02 + 3));
  scene.add(terrain(900, 220, H, (x, y, z, s) => { const band = (Math.sin(y * 1.3 + fbm(x * 0.05, z * 0.05) * 2) * 0.5 + 0.5); return col('#E7CDAE').lerp(col('#D4A684'), band * 0.6).lerp(col('#B88866'), Math.min(1, s * 1.2)).lerp(col('#8C9A62'), (1 - smooth(-2, 1, y)) * 0.4 * (fbm(x * 0.1, z * 0.1) > 0 ? 1 : 0)); }, { cz: -60 }));
  // fairy chimneys: tapered tuff columns with dark basalt caps
  const prof = []; for (let k = 0; k <= 16; k++) { const v = k / 16; prof.push(new THREE.Vector2(0.18 + 0.82 * Math.pow(1 - v, 1.6) + 0.06 * Math.sin(v * 9), v)); }
  const chimG = new THREE.LatheGeometry(prof, 14), chim = [], caps = [];
  for (let i = 0; i < 170; i++) {
    const a = rnd(i * 3) * TAU, r = 6 + Math.pow(rnd(i * 7), 0.7) * 110, x = Math.cos(a) * r * 1.2, z = -30 + Math.sin(a) * r, y = H(x, z); if (y > 9) continue;
    const hh = 3 + rnd(i * 11) * 7, ww = 1.0 + rnd(i * 13) * 1.4; chim.push({ p: [x, y - 0.4, z], s: [ww, hh, ww], r: [0, rnd(i) * 6, 0], c: rnd(i * 17) > 0.5 ? '#E8CFAF' : '#DDB995' });
    caps.push({ p: [x, y - 0.4 + hh + 0.1, z], s: [ww * 0.42, ww * 0.26, ww * 0.42], c: '#6B5546' });
  }
  scene.add(inst(chimG, std('#ffffff', 0.95), chim), inst(new THREE.SphereGeometry(1, 14, 10), std('#ffffff', 0.9), caps));
  // balloons
  const PAL = [['#E84A3C', '#F4C542'], ['#2F7BD8', '#F2F2F2', '#E8453C'], ['#F39C2B', '#7A3FA0'], ['#3CB371', '#F4D03F'], ['#E94F8A', '#F7E9A0'], ['#1F9AA8', '#F28C38'], ['#C0392B', '#2C3E50', '#F1C40F']];
  const mats = PAL.map((p) => std('#ffffff', 0.55, { map: balloonTex(p), emissive: '#ffffff', emissiveMap: balloonTex(p), emissiveIntensity: 0.18 }));
  const bg = balloonGeo(), basket = std('#7A5534', 0.9), flame = new THREE.MeshBasicMaterial({ color: col('#FFB04A').multiplyScalar(3) });
  const balloons = [];
  for (let i = 0; i < 70; i++) {
    const b = new THREE.Group(), env = sh(new THREE.Mesh(bg, mats[i % mats.length])), bk = sh(new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.32, 0.42), basket)), fl = new THREE.Mesh(new THREE.SphereGeometry(0.12, 8, 6), fl0());
    function fl0() { return flame; }
    bk.position.y = -1.65; fl.position.y = -1.3; b.add(env, bk, fl); b.scale.setScalar(2.2 + rnd(i * 5) * 0.8);
    const x0 = (rnd(i * 3) - 0.5) * 220, z0 = -200 + rnd(i * 7) * 225, y0 = 10 + rnd(i * 11) * 55;
    balloons.push({ g: b, x0, z0, y0, sp: 0.25 + rnd(i * 13) * 0.35, ph: rnd(i * 17) * 6, fl }); scene.add(b);
  }
  return {
    scene, sunLight: S, balloons, hero: balloons[0],
    update(t) { for (const b of balloons) { b.g.position.set(b.x0 + Math.sin(t * 0.1 + b.ph) * 2 + t * 0.15, b.y0 + t * b.sp, b.z0); b.g.rotation.y = t * 0.05 + b.ph; b.fl.visible = Math.sin(t * 1.3 + b.ph * 3) > 0.55; } },
  };
}
__EOF_WT__
cat > "$P/src/core/overlays.js" <<'__EOF_WT__'
// World Tour 2D motion graphics over the 3D frame: rank badge, fact card, gauges, traces, the closing list.
// Safe zones: top block y 230-560 (badges, cards) · captions y 1330-1630 (captions.js) · keep the middle for the landmark.
import { ctx, clamp, lerp, seg, eo, eob, eio } from './lib.js';
const Y = '#FFD43B', INK = '#101318';
const fmt = (n) => Math.round(n).toLocaleString('tr-TR');

function outlined(text, x, y, size, fill = '#fff', align = 'center', weight = 900, stroke = INK) {
  ctx.font = `${weight} ${size}px Inter`; ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
  ctx.lineWidth = size * 0.2; ctx.strokeStyle = stroke; ctx.strokeText(text, x, y); ctx.fillStyle = fill; ctx.fillText(text, x, y);
}
function glass(x, y, w, h, r, a = 0.72) { ctx.fillStyle = `rgba(12,15,22,${a})`; ctx.beginPath(); ctx.roundRect(x, y, w, h, r); ctx.fill(); ctx.strokeStyle = 'rgba(255,255,255,0.18)'; ctx.lineWidth = 3; ctx.stroke(); }

/** white flash on a cut (lt = time into the shot) */
export function flash(lt, d = 0.22) { const k = 1 - clamp(lt / d); if (k <= 0) return; ctx.fillStyle = `rgba(255,248,235,${k * k * 0.85})`; ctx.fillRect(0, 0, 1080, 1920); }
/** soft dark gradient at the top so white text always reads */
export function topShade(k = 1) { if (k <= 0) return; const g = ctx.createLinearGradient(0, 0, 0, 640); g.addColorStop(0, `rgba(0,0,0,${0.5 * k})`); g.addColorStop(1, 'rgba(0,0,0,0)'); ctx.fillStyle = g; ctx.fillRect(0, 0, 1080, 640); }

/** the countdown badge: number disc + landmark name + place. lt = seconds since it starts */
export function rankBadge(n, name, place, lt, gold = false) {
  if (lt < 0) return; topShade(clamp(lt / 0.3));
  const k1 = eob(seg(lt, 0.0, 0.35)), k2 = eo(seg(lt, 0.12, 0.5)), k3 = eo(seg(lt, 0.3, 0.7));
  const cx = 540, cy = 330, R = gold ? 118 : 100;
  ctx.save(); ctx.translate(cx, cy); ctx.scale(k1, k1); ctx.rotate((1 - k1) * -0.5);
  if (gold) { for (let i = 0; i < 16; i++) { const a = i / 16 * Math.PI * 2 + lt * 0.6; ctx.fillStyle = `rgba(255,212,59,${0.22 + 0.1 * Math.sin(lt * 4 + i)})`; ctx.beginPath(); ctx.moveTo(0, 0); ctx.arc(0, 0, R * 1.9, a, a + 0.12); ctx.fill(); } }
  ctx.shadowColor = 'rgba(0,0,0,0.45)'; ctx.shadowBlur = 30; ctx.fillStyle = Y; ctx.beginPath(); ctx.arc(0, 0, R, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
  ctx.lineWidth = 10; ctx.strokeStyle = INK; ctx.stroke(); ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.beginPath(); ctx.arc(0, 0, R - 16, 0, 7); ctx.stroke();
  ctx.font = `900 ${R * 1.25}px Inter`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = INK; ctx.fillText(String(n), 0, R * 0.06);
  ctx.restore();
  ctx.save(); ctx.globalAlpha = k2; outlined(name, cx + (1 - k2) * -60, cy + R + 82, gold ? 104 : 92, '#FFFFFF'); ctx.restore();
  if (k3 > 0) { ctx.save(); ctx.globalAlpha = k3; ctx.font = '800 46px Inter'; const w = ctx.measureText(place).width + 64, y = cy + R + 172; glass(cx - w / 2, y - 36, w, 72, 36, 0.7); ctx.fillStyle = Y; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(place, cx, y + 2); ctx.restore(); }
}

/** a fact card: small label over a big counting number + unit. lt from its start; count over dur */
export function factCard(label, value, unit, lt, { dur = 1.2, y = 330, sub = null, subAt = 99 } = {}) {
  if (lt < 0) return; topShade(clamp(lt / 0.3));
  const k = eob(seg(lt, 0, 0.35)), v = value * eio(seg(lt, 0.1, 0.1 + dur));
  ctx.save(); ctx.translate(540, y); ctx.scale(k, k);
  ctx.font = '900 150px Inter'; const num = fmt(v), nw = ctx.measureText(num).width; ctx.font = '900 72px Inter'; const uw = unit ? ctx.measureText(unit).width + 24 : 0;
  const W = Math.max(520, nw + uw + 100); glass(-W / 2, -150, W, 290, 44, 0.68);
  ctx.font = '800 42px Inter'; ctx.fillStyle = 'rgba(255,255,255,0.85)'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(label, 0, -98);
  const x0 = -(nw + uw) / 2; ctx.textAlign = 'left'; ctx.font = '900 150px Inter'; ctx.fillStyle = Y; ctx.fillText(num, x0, 22);
  if (unit) { ctx.font = '900 72px Inter'; ctx.fillStyle = '#FFFFFF'; ctx.fillText(unit, x0 + nw + 24, 46); }
  ctx.restore();
  if (sub && lt > subAt) { const ks = eob(seg(lt, subAt, subAt + 0.3)); pillAt(sub, 540, y + 205, ks); }
}
export function pillAt(text, x, y, k, fg = INK, bg = Y, size = 50) {
  if (k <= 0) return; ctx.save(); ctx.translate(x, y); ctx.scale(k, k); ctx.font = `900 ${size}px Inter`; const w = ctx.measureText(text).width + size * 1.3;
  ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 20; ctx.fillStyle = bg; ctx.beginPath(); ctx.roundRect(-w / 2, -size * 0.8, w, size * 1.6, size * 0.8); ctx.fill(); ctx.shadowBlur = 0;
  ctx.fillStyle = fg; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(text, 0, size * 0.05); ctx.restore();
}
/** vertical height ruler between two screen points, with ticks and a growing fill */
export function ruler(x, yBase, yTop, k, label) {
  if (k <= 0) return; const yk = lerp(yBase, yTop, eio(clamp(k)));
  ctx.save(); ctx.lineCap = 'round'; ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 8; ctx.beginPath(); ctx.moveTo(x, yBase); ctx.lineTo(x, yTop); ctx.stroke();
  ctx.strokeStyle = Y; ctx.lineWidth = 10; ctx.beginPath(); ctx.moveTo(x, yBase); ctx.lineTo(x, yk); ctx.stroke();
  for (let i = 0; i <= 10; i++) { const yy = lerp(yBase, yTop, i / 10); if ((yBase - yy) > (yBase - yk) + 1) continue; ctx.strokeStyle = '#fff'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(x - (i % 5 ? 14 : 26), yy); ctx.lineTo(x + (i % 5 ? 14 : 26), yy); ctx.stroke(); }
  ctx.restore(); if (label) pillAt(label, x, yk - 70, eob(clamp(k * 3)), INK, Y, 46);
}
/** dashed ellipse traced around a point (the Eiffel summit curve), progress k */
export function trace(x, y, rx, ry, k, t) {
  if (k <= 0) return; ctx.save(); ctx.lineCap = 'round'; ctx.setLineDash([2, 22]); ctx.lineDashOffset = -t * 60; ctx.strokeStyle = Y; ctx.lineWidth = 12;
  ctx.beginPath(); ctx.ellipse(x, y, rx, ry, 0, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * eio(clamp(k))); ctx.stroke();
  const a = -Math.PI / 2 + Math.PI * 2 * eio(clamp(k)); ctx.setLineDash([]); ctx.fillStyle = Y; ctx.beginPath(); ctx.arc(x + Math.cos(a) * rx, y + Math.sin(a) * ry, 16, 0, 7); ctx.fill(); ctx.restore();
}
/** leader-line label from a pill to a 3D point on screen */
export function callout(text, x, y, tx, ty, k) {
  if (k <= 0) return; ctx.save(); ctx.globalAlpha = Math.min(1, k * 1.5); ctx.strokeStyle = '#fff'; ctx.lineWidth = 6; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(lerp(x, tx, eo(clamp(k))), lerp(y, ty, eo(clamp(k)))); ctx.stroke();
  ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(tx, ty, 14 * clamp(k * 2 - 0.8), 0, 7); ctx.fill(); ctx.restore(); pillAt(text, x, y, eob(clamp(k)), '#fff', 'rgba(12,15,22,0.82)', 50);
}
/** pulsing ring drawn through screen points (e.g. the caldera rim) */
export function ring(pts, k, t) {
  if (k <= 0 || pts.length < 3) return; ctx.save(); ctx.lineJoin = 'round'; ctx.strokeStyle = `rgba(255,212,59,${0.9 * k})`; ctx.lineWidth = 10 + 4 * Math.sin(t * 6); ctx.setLineDash([30, 18]); ctx.lineDashOffset = -t * 80;
  ctx.beginPath(); const n = Math.max(2, Math.round(pts.length * eio(clamp(k)))); ctx.moveTo(...pts[0]); for (let i = 1; i < n; i++) ctx.lineTo(...pts[i]); ctx.stroke(); ctx.restore();
}
/** horizontal comparison bar (wall vs equator) */
export function compareBar(lt, frac, y = 640) {
  if (lt < 0) return; const k = eob(seg(lt, 0, 0.3)), f = frac * eio(seg(lt, 0.2, 1.2)), x0 = 140, W = 800;
  ctx.save(); ctx.globalAlpha = clamp(k); glass(x0 - 40, y - 90, W + 80, 190, 36, 0.66);
  ctx.font = '800 38px Inter'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left'; ctx.fillStyle = '#fff'; ctx.fillText('EKVATOR  40.075 km', x0, y - 46);
  ctx.fillStyle = 'rgba(255,255,255,0.22)'; ctx.beginPath(); ctx.roundRect(x0, y - 10, W, 44, 22); ctx.fill();
  ctx.fillStyle = Y; ctx.beginPath(); ctx.roundRect(x0, y - 10, Math.max(44, W * f), 44, 22); ctx.fill();
  ctx.font = '900 40px Inter'; ctx.fillStyle = INK; ctx.fillText(`ÇİN SEDDİ  %${Math.round(f * 100)}`, x0 + 22, y + 13); ctx.restore();
}
/** the closing question card: title + the seven places, staggered in */
export function finalList(lt, items) {
  if (lt < 0) return; const k = eob(seg(lt, 0, 0.35)); topShade(1);
  ctx.save(); ctx.translate(540, 250); ctx.scale(k, k); outlined('HANGİSİ?', 0, 0, 120, Y); ctx.restore();
  items.forEach((it, i) => {
    const ki = eo(seg(lt, 0.25 + i * 0.12, 0.6 + i * 0.12)); if (ki <= 0) return; const col = i < 4 ? 0 : 1, row = i < 4 ? i : i - 4, x = col ? 560 : 70, y = 400 + row * 92;
    ctx.save(); ctx.globalAlpha = ki; ctx.translate((1 - ki) * -40, 0); glass(x, y - 38, 450, 76, 38, 0.66);
    ctx.fillStyle = i === 6 ? Y : '#fff'; ctx.beginPath(); ctx.arc(x + 38, y, 26, 0, 7); ctx.fill(); ctx.font = '900 34px Inter'; ctx.fillStyle = INK; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(String(it[0]), x + 38, y + 2);
    ctx.font = '800 38px Inter'; ctx.fillStyle = i === 6 ? Y : '#fff'; ctx.textAlign = 'left'; ctx.fillText(it[1], x + 80, y + 2); ctx.restore();
  });
}
/** altitude gauge on the left edge, counting to value */
export function gauge(lt, value, unit, label, x = 120, yTop = 330, yBot = 1150) {
  if (lt < 0) return; const k = eio(seg(lt, 0.1, 1.6)), y = lerp(yBot, yTop, k);
  ctx.save(); ctx.globalAlpha = clamp(lt / 0.3); ctx.lineCap = 'round'; ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 8; ctx.beginPath(); ctx.moveTo(x, yBot); ctx.lineTo(x, yTop); ctx.stroke();
  ctx.strokeStyle = Y; ctx.lineWidth = 12; ctx.beginPath(); ctx.moveTo(x, yBot); ctx.lineTo(x, y); ctx.stroke();
  for (let i = 0; i <= 8; i++) { const yy = lerp(yBot, yTop, i / 8); ctx.strokeStyle = '#fff'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(x - 16, yy); ctx.lineTo(x + 16, yy); ctx.stroke(); }
  ctx.restore();
  if (lt > 0) { ctx.save(); ctx.globalAlpha = clamp(lt / 0.3); ctx.font = '900 64px Inter'; const txt = `${fmt(value * k)} ${unit}`, w = ctx.measureText(txt).width + 60; glass(x + 36, y - 52, w, 104, 52, 0.72); ctx.fillStyle = Y; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillText(txt, x + 66, y + 3);
    ctx.font = '800 34px Inter'; ctx.fillStyle = '#fff'; ctx.fillText(label, x + 66, y - 86); ctx.restore(); }
}
export function title(lt) {
  const k = eob(seg(lt, 0.15, 0.55)), k2 = eo(seg(lt, 0.45, 0.85)); topShade(1);
  ctx.save(); ctx.translate(540, 300); ctx.scale(k, k); outlined('ÖLMEDEN ÖNCE', 0, 0, 78, '#fff'); ctx.restore();
  ctx.save(); ctx.globalAlpha = k2; ctx.translate(540, 430); ctx.scale(0.8 + 0.2 * k2, 0.8 + 0.2 * k2); outlined('7 YER', 0, 0, 170, Y); ctx.restore();
}
__EOF_WT__
cat > "$P/src/core/captions.js" <<'__EOF_WT__'
// Captions: 1-3 words, Inter Black, white with a thick ink outline, ONE yellow word, centre lower third.
// Each script line has "caps": "WHAT IF *YOU | SWALLOW *GUM?"  ("|" = next caption, "*" = the yellow word).
// Without "caps", the line is chunked automatically (2-3 words, the longest word goes yellow).
// A chunk appears 0.05 s before its first word and stays until the next chunk (or shortly after the line ends).
import { ctx, C, clamp, lerp, seg, eob } from './lib.js';
import { T, lineWords } from './timing.js';

export const CAP = { y: 1480, size: 118, maxW: 940 };
let caps = [];

function autoChunks(text) {
  const ws = text.toLocaleUpperCase('tr').split(/\s+/).filter(Boolean), out = [];
  for (let i = 0; i < ws.length;) { const n = ws.length - i === 4 ? 2 : Math.min(3, ws.length - i); out.push(ws.slice(i, i + n)); i += n; }
  return out.map((c) => { const k = c.reduce((b, w, j) => (w.replace(/[^\p{L}]/gu, '').length > c[b].replace(/[^\p{L}]/gu, '').length ? j : b), 0); return c.map((w, j) => (j === k ? '*' + w : w)).join(' '); });
}

export function buildCaptions(script) {
  caps = [];
  script.lines.forEach((ln, i) => {
    const chunks = (ln.caps ? ln.caps.split('|') : autoChunks(ln.text)).map((s) => s.trim()).filter(Boolean);
    const ws = lineWords(i); if (!ws.length) return;
    const counts = chunks.map((c) => c.split(/\s+/).filter((w) => !w.startsWith('{')).length), N = counts.reduce((a, b) => a + b, 0);
    const nm = (w) => String(w).toLocaleLowerCase('tr').normalize('NFC').replace(/[^\p{L}\p{N}]+/gu, '');
    let acc = 0, from = 0;
    chunks.forEach((c0, j) => { let c = c0;
      // find the chunk's first word in the spoken line (from where the last chunk started); else place it by word count
      const toks = c.split(/\s+/), anc = toks[0].startsWith('{') ? toks[0].slice(1, -1) : null; if (anc) c = toks.slice(1).join(' ');
      const first = nm(anc || toks[0]);
      let idx = j === 0 ? 0 : ws.findIndex((w, k) => k > from && first && (nm(w.w) === first || (first.length > 2 && nm(w.w).startsWith(first))));
      if (idx < 0) idx = Math.max(from + (j ? 1 : 0), Math.min(ws.length - 1, Math.round(acc * ws.length / N)));
      acc += counts[j]; from = idx;
      caps.push({ line: i, s: ws[idx].s - 0.05, words: c.split(/\s+/).map((w) => ({ txt: w.replace('*', ''), hi: w.startsWith('*') })) });
    });
  });
  caps.forEach((c, k) => {
    const next = caps[k + 1], lineEnd = T.lines[c.line].end;
    c.e = next ? (next.s - lineEnd > 0.7 && next.line !== c.line ? lineEnd + 0.35 : next.s) : T.dur;
  });
  return caps;
}
export const captionList = () => caps;

export function drawCaption(t) {
  const c = caps.find((c) => t >= c.s && t < c.e); if (!c) return;
  const lt = t - c.s, size = CAP.size;
  ctx.font = `900 ${size}px Inter`; ctx.letterSpacing = '-1px';
  const sp = size * 0.26;
  c.words.forEach((w) => (w.w = ctx.measureText(w.txt).width));
  const width = (ws) => ws.reduce((a, w) => a + w.w, 0) + sp * (ws.length - 1);
  let lines = [c.words];
  if (width(c.words) > CAP.maxW && c.words.length > 1) {
    let best = null;
    for (let i = 1; i < c.words.length; i++) { const a = c.words.slice(0, i), b = c.words.slice(i), m = Math.max(width(a), width(b)); if (!best || m < best.m) best = { m, l: [a, b] }; }
    lines = best.l;
  }
  const fit = Math.min(1, CAP.maxW / Math.max(...lines.map(width)));
  const sc = (lt < 0.2 ? lerp(0.65, 1, eob(seg(lt, 0, 0.2))) : 1) * fit;
  ctx.save(); ctx.translate(540, CAP.y); ctx.scale(sc, sc);
  ctx.textBaseline = 'middle'; ctx.textAlign = 'left'; ctx.lineJoin = 'round';
  const lh = size, y0 = -(lines.length - 1) * lh / 2;
  lines.forEach((ln, li) => {
    let x = -width(ln) / 2; const y = y0 + li * lh;
    for (const w of ln) {
      ctx.lineWidth = 22; ctx.strokeStyle = '#111'; ctx.strokeText(w.txt, x, y + 6); ctx.strokeText(w.txt, x, y);
      ctx.fillStyle = w.hi ? C.yellow : C.white; ctx.fillText(w.txt, x, y); x += w.w + sp;
    }
  });
  ctx.letterSpacing = '0px'; ctx.restore();
}
__EOF_WT__
cat > "$P/src/core/timing.js" <<'__EOF_WT__'
// Timing: everything on screen is placed on the narration's clock.
//   data/lines.json  { duration, lines: [{ i, text, start, end }] }   (voice.py, or estimate.py for captions-only)
//   data/words.json  [{ w, line, s, e }]                                (words.py, or estimate.py)
// L(i) = line i start · Le(i) = line i end · Wd(word, line) = start of the first word in that line matching
// the prefix (case/punctuation ignored; throws if it isn't there, so a rewritten script can't silently drift).
export const T = { dur: 0, lines: [], words: [] };
export const norm = (w) => String(w).toLocaleLowerCase('tr').normalize('NFC').replace(/[^\p{L}\p{N}]+/gu, '');

export async function loadTiming() {
  const get = async (f) => { const r = await fetch(f, { cache: 'no-store' }); if (!r.ok) throw new Error(`missing ${f}: run voice.py + words.py (or estimate.py)`); return r.json(); };
  const lines = await get('data/lines.json'), words = await get('data/words.json');
  T.lines = lines.lines; T.words = words; T.dur = lines.duration;
  return T;
}
export const L = (i) => { const l = T.lines[i]; if (!l) throw new Error(`no line ${i}`); return l.start; };
export const Le = (i) => { const l = T.lines[i]; if (!l) throw new Error(`no line ${i}`); return l.end; };
export function Wd(word, line, which = 's') {
  const n = norm(word);
  const hit = T.words.find((w) => (line == null || w.line === line) && norm(w.w).startsWith(n));
  if (!hit) throw new Error(`word "${word}" not found${line != null ? ` in line ${line}` : ''}`);
  return hit[which];
}
export const lineWords = (i) => T.words.filter((w) => w.line === i);
__EOF_WT__
cat > "$P/tools/voice_google.py" <<'__EOF_WT__'
"""Turkish narration with Google TTS -> data/narration.wav + data/lines.json + data/words.json

  python3 tools/voice_google.py [project=.] [--engine gemini|cloud|estimate] [--voice Charon] [--model ...] [--per-line]

Engines
  gemini   (default) Google AI Studio key, Gemini TTS (free tier). ONE request for the whole script (the free tier
           allows only a few requests a minute), then the audio is split back into lines at its natural pauses.
           script.json "style" may be ONE audio tag such as "[excited]" (plain-text directions get read aloud).
           On 429 / 5xx it waits and then falls back through the other TTS models the key can use.
  cloud    Google Cloud Text-to-Speech (tr-TR voices, one request per line; needs billing on the key's project).
  estimate no voice: timing only (to preview a cut before the voice exists).

The key is read from $GOOGLE_API_KEY or ~/.faceless-shorts/google_api_key (never printed).
Lines are re-assembled with script "gap" seconds between them. Word times inside a line are spread by syllable count
(Turkish: one vowel = one syllable), which lands within a few frames of the real word. Audio is cached in data/tts/.
"""
import argparse, base64, hashlib, json, os, re, sys, time, urllib.request, urllib.error
from pathlib import Path
import numpy as np
from scipy.io import wavfile

ap = argparse.ArgumentParser()
ap.add_argument('project', nargs='?', default='.')
ap.add_argument('--engine', default=None)
ap.add_argument('--voice', default=None)
ap.add_argument('--model', default=None)
ap.add_argument('--per-line', action='store_true')
a = ap.parse_args()
P = Path(a.project); S = json.loads((P / 'script.json').read_text())
engine = a.engine or S.get('engine', 'gemini')
SR = 24000
VOWELS = set('aeıioöuüâîûAEIİOÖUÜÂÎÛ')
STYLE = S.get('style', '').strip()
TAG = STYLE if STYLE.startswith('[') else ''


def key():
    k = os.environ.get('GOOGLE_API_KEY')
    if not k:
        f = Path.home() / '.faceless-shorts/google_api_key'
        if f.exists(): k = f.read_text().strip()
    if not k: sys.exit('no Google API key: put it in ~/.faceless-shorts/google_api_key')
    return k


class Busy(Exception): pass


def post(url, body, tries=3):
    data = json.dumps(body).encode()
    for i in range(tries):
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=300) as r: return json.loads(r.read())
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors='replace')[:300]
            if e.code in (429, 500, 503):
                if i < tries - 1: wait = 25 * (i + 1); print(f'  {e.code}, retrying in {wait}s'); time.sleep(wait); continue
                raise Busy(f'{e.code}: {msg}')
            sys.exit(f'Google TTS error {e.code}: {msg}')
        except urllib.error.URLError as e:
            sys.exit(f'cannot reach Google ({e.reason}). If blocked, allow the domain in claude.ai Settings > Capabilities.')


def gemini_models(k):
    try:
        with urllib.request.urlopen(f'https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key={k}', timeout=60) as r:
            ms = [m['name'].split('/')[-1] for m in json.loads(r.read()).get('models', [])]
    except Exception: ms = []
    tts = [m for m in ms if 'tts' in m] or ['gemini-2.5-flash-preview-tts']
    ver = lambda m: float(re.search(r'(\d+\.\d+)', m).group(1)) if re.search(r'(\d+\.\d+)', m) else 0
    return sorted(tts, key=lambda m: ('lite' in m, 'pro' in m, -ver(m)))


def tts_gemini(text, voice, model, k):
    body = {'contents': [{'parts': [{'text': f'{TAG} {text}' if TAG else text}]}],
            'generationConfig': {'responseModalities': ['AUDIO'], 'speechConfig': {'voiceConfig': {'prebuiltVoiceConfig': {'voiceName': voice}}}}}
    r = post(f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={k}', body)
    part = r['candidates'][0]['content']['parts'][0]['inlineData']
    m = re.search(r'rate=(\d+)', part.get('mimeType', '')); rate = int(m.group(1)) if m else 24000
    return np.frombuffer(base64.b64decode(part['data']), dtype='<i2').astype(np.float32) / 32768, rate


def tts_cloud(text, voice, k):
    body = {'input': {'text': text}, 'voice': {'languageCode': 'tr-TR', 'name': voice},
            'audioConfig': {'audioEncoding': 'LINEAR16', 'sampleRateHertz': SR, 'speakingRate': S.get('speed', 1.0)}}
    r = post(f'https://texttospeech.googleapis.com/v1/text:synthesize?key={k}', body)
    return np.frombuffer(base64.b64decode(r['audioContent'])[44:], dtype='<i2').astype(np.float32) / 32768, SR


def resample(x, r0):
    if r0 == SR: return x
    n = int(len(x) * SR / r0); return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def envelope(x, hop=240):
    n = len(x) // hop; return np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1) + 1e-12)


def trim(x):
    e = np.convolve(np.abs(x), np.ones(240) / 240, mode='same'); thr = max(0.008, e.max() * 0.04)
    idx = np.where(e > thr)[0]
    if not len(idx): return x
    return x[max(0, idx[0] - int(0.03 * SR)):min(len(x), idx[-1] + int(0.06 * SR))]


def syl(w): return max(1, sum(ch in VOWELS for ch in w))


def split_lines(x, texts):
    """cut one long narration into len(texts) pieces at its pauses, guided by each line's syllable share"""
    hop = 240; e = envelope(x, hop); fps = SR / hop; thr = max(0.006, np.percentile(e, 90) * 0.06)
    sil = e < thr; pauses = []; i = 0
    while i < len(sil):
        if sil[i]:
            j = i
            while j < len(sil) and sil[j]: j += 1
            if (j - i) / fps >= 0.12 and i > 0 and j < len(sil): pauses.append(((i + j) / 2 / fps, (j - i) / fps))
            i = j
        else: i += 1
    voiced = np.where(~sil)[0]; t0, t1 = voiced[0] / fps, voiced[-1] / fps
    w = [sum(syl(t) for t in tx.split()) for tx in texts]; cum = np.cumsum(w)[:-1] / sum(w)
    N = len(texts) - 1; M = len(pauses)
    if M < N: sys.exit(f'only {M} pauses found for {N} line breaks: use --per-line')
    # DP over pauses: each line's length must fit its syllable count at the speaker's average rate; long pauses preferred
    rate = sum(w) / (t1 - t0); pos = [t0] + [c for c, _ in pauses] + [t1]; plen = [0] + [ln for _, ln in pauses] + [0]
    K = len(pos); INF = 1e18; D = np.full((len(texts) + 1, K), INF); B = np.zeros((len(texts) + 1, K), int); D[0, 0] = 0
    for n in range(1, len(texts) + 1):
        exp_d = w[n - 1] / rate
        for j in range(1, K):
            if n < len(texts) and j == K - 1: continue
            if n == len(texts) and j != K - 1: continue
            for i in range(0, j):
                if D[n - 1, i] >= INF: continue
                d = pos[j] - pos[i] - (plen[i] + plen[j]) * 0.5
                c = D[n - 1, i] + 4 * ((d - exp_d) / exp_d) ** 2 - 0.15 * min(plen[j], 0.8)
                if c < D[n, j]: D[n, j], B[n, j] = c, i
    j = K - 1; idx = []
    for n in range(len(texts), 0, -1): idx.append(j); j = B[n, j]
    cuts = [0.0] + [pos[q] for q in sorted(idx)[:-1]] + [len(x) / SR]
    return [trim(x[int(cuts[i] * SR):int(cuts[i + 1] * SR)]) for i in range(len(texts))]


def words_in(text, s, e):
    toks = text.split(); wts = [syl(w) + 0.6 for w in toks]
    pause = [0.45 if re.search(r'[,;:]$', w) else 0.8 if re.search(r'[.!?]$', w) and k < len(toks) - 1 else 0 for k, w in enumerate(toks)]
    unit = (e - s) / (sum(wts) + sum(pause)); t = s; out = []
    for w, wt, pa in zip(toks, wts, pause):
        d = wt * unit; out.append((w, t, t + d * 0.94)); t += d + pa * unit
    return out


says = [ln.get('say', ln['text']) for ln in S['lines']]
cache = P / 'data/tts'; cache.mkdir(parents=True, exist_ok=True)
if engine == 'estimate':
    pieces = [np.zeros(int((sum(syl(w) for w in s.split()) / (6.0 * S.get('speed', 1.0)) + 0.15 * s.count(',')) * SR), np.float32) for s in says]
else:
    k = key(); voice = a.voice or S.get('voice') or ('Charon' if engine == 'gemini' else 'tr-TR-Wavenet-E')
    if engine == 'cloud':
        pieces = []
        for s in says: pcm, r0 = tts_cloud(s, voice, k); pieces.append(trim(resample(pcm, r0)))
    elif a.per_line:
        model = a.model or gemini_models(k)[0]; pieces = []
        for i, s in enumerate(says):
            cf = cache / f'L{i:02d}_{hashlib.sha1(f"{voice}|{model}|{TAG}|{s}".encode()).hexdigest()[:12]}.npy'
            if cf.exists(): pieces.append(np.load(cf)); continue
            print(f'  line {i}: {s[:60]}'); pcm, r0 = tts_gemini(s, voice, model, k); x = trim(resample(pcm, r0)); np.save(cf, x); pieces.append(x); time.sleep(21)
    else:
        full = '\n\n'.join(says); models = [a.model] if a.model else gemini_models(k)
        h = hashlib.sha1(f'{voice}|{TAG}|{full}'.encode()).hexdigest()[:12]; cf = cache / f'ALL_{h}.npy'
        if cf.exists(): x = np.load(cf); print('cached narration')
        else:
            x = None
            for model in models:
                try: print(f'engine gemini · voice {voice} · model {model} · one request'); pcm, r0 = tts_gemini(full, voice, model, k); x = resample(pcm, r0); break
                except Busy as e: print(f'  {model} busy ({str(e)[:80]}), trying the next model')
            if x is None: sys.exit('all Gemini TTS models are rate-limited right now: try again later')
            np.save(cf, x)
        pieces = split_lines(x, says)

lead, gap, outro = float(S.get('lead', 0.35)), float(S.get('gap', 0.22)), float(S.get('outro', 1.0))
lines, words, t, chunks = [], [], lead, []
for i, (ln, x) in enumerate(zip(S['lines'], pieces)):
    d = len(x) / SR; chunks.append((t, x))
    lines.append({'i': i, 'text': ln['text'], 'start': round(t, 3), 'end': round(t + d, 3)})
    for w, s, e in words_in(ln['text'], t, t + d): words.append({'w': w, 'line': i, 's': round(s, 3), 'e': round(e, 3)})
    t += d + float(ln.get('gap', gap))
dur = t - gap + outro
out = np.zeros(int(dur * SR) + SR, np.float32)
for st, x in chunks: i0 = int(st * SR); out[i0:i0 + len(x)] += x
(P / 'data').mkdir(exist_ok=True)
if engine != 'estimate': wavfile.write(P / 'data/narration.wav', SR, (out / (np.abs(out).max() + 1e-9) * 0.89 * 32767).astype(np.int16))
else: (P / 'data/narration.wav').unlink(missing_ok=True)
(P / 'data/lines.json').write_text(json.dumps({'duration': round(dur, 3), 'lines': lines}, ensure_ascii=False, indent=1))
(P / 'data/words.json').write_text(json.dumps(words, ensure_ascii=False, indent=0))
print(f'{len(lines)} lines · {len(words)} words · {dur:.1f} s · engine {engine}')
for l in lines: print(f"  {l['i']:2d} {l['end'] - l['start']:5.2f}s  {l['text'][:50]}")
__EOF_WT__
cat > "$P/tools/mix.py" <<'__EOF_WT__'
"""Inside Out soundtrack: narration + soft procedural sound effects + a quiet music bed, all made here with numpy.
No samples, no AI audio, no downloads.

  python3 tools/mix.py [project=.]          → data/mix.wav (48 kHz stereo)

Reads data/cues.json (node tools/capture.mjs cues), data/narration.wav if it exists (voice.py or words.py --audio),
and script.json "music": "bed" (the procedural score, default) · "none" · "audio/your-track.mp3" (your own royalty-free
track, any format ffmpeg reads). The music ducks under the voice.

Sound rules (STYLE.md): every effect is soft and rounded, nothing above ~5 kHz, no ticks / hats / glitches / beeps.
Cue types: whoosh slide pop plop gulp boing bubbles sizzle sparkle thud slam tock zip alarm  (+ gain, dur)
"""
import json, subprocess, sys
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile

P = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
SR = 48000
rng = np.random.default_rng(11)
cj = json.loads((P / 'data/cues.json').read_text())
script = json.loads((P / 'script.json').read_text())
DUR = float(cj['duration'])
N = int(DUR * SR) + SR // 10


def lp(x, f, o=2): b, a = signal.butter(o, min(f, SR / 2 - 100) / (SR / 2), 'low'); return signal.lfilter(b, a, x)
def hp(x, f, o=2): b, a = signal.butter(o, f / (SR / 2), 'high'); return signal.lfilter(b, a, x)
def bp(x, f0, f1, o=2): b, a = signal.butter(o, [f0 / (SR / 2), f1 / (SR / 2)], 'band'); return signal.lfilter(b, a, x)
def db(x): return 10 ** (x / 20)
def tt(d): return np.arange(int(d * SR)) / SR
def env(n, a=0.005, r=None):
    """attack a seconds then exponential release over the rest"""
    e = np.ones(n); na = max(1, int(a * SR)); e[:na] = np.linspace(0, 1, na)
    rest = n - na; e[na:] = np.exp(-np.linspace(0, r or 5, rest)) if rest > 0 else 1; return e
def sweep(f0, f1, d, shape='exp'):
    t = tt(d); f = f0 * (f1 / f0) ** (t / d) if shape == 'exp' else f0 + (f1 - f0) * t / d
    return np.sin(2 * np.pi * np.cumsum(f) / SR)
def noise(d): return rng.standard_normal(int(d * SR))


# ---------- the effects ----------
def whoosh(d=0.38, **_):
    n = noise(d); lo, hi = lp(n, 500), lp(n, 2200)
    k = np.sin(np.pi * np.linspace(0, 1, len(n))); x = (lo * (1 - k) + hi * k) * k ** 1.5
    return x / (np.abs(x).max() + 1e-9) * 0.5
def slide(d=1.0, **_):
    n = lp(noise(d), 700); e = np.sin(np.pi * np.linspace(0, 1, len(n))) ** 2
    return n / (np.abs(n).max() + 1e-9) * e * 0.35 + sweep(260, 120, d) * e * 0.08
def pop(**_): x = sweep(560, 240, 0.11) * env(int(0.11 * SR), 0.002, 6); return lp(x, 3000) * 0.7
def plop(**_): x = sweep(700, 180, 0.14) * env(int(0.14 * SR), 0.002, 5); return lp(x, 2500) * 0.6
def gulp(**_):
    a = sweep(320, 140, 0.16) * env(int(0.16 * SR), 0.01, 4); b = sweep(240, 90, 0.2) * env(int(0.2 * SR), 0.01, 4)
    x = np.concatenate([a, np.zeros(int(0.04 * SR)), b]); return lp(x, 1800) * 0.8
def boing(**_):
    d = 0.42; t = tt(d); f = 200 * (1 + 0.6 * t / d) * (1 + 0.08 * np.sin(2 * np.pi * 18 * t))
    return lp(np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.004, 4), 2000) * 0.55
def bubbles(d=2.0, **_):
    x = np.zeros(int(d * SR))
    for _ in range(int(d * 7)):
        st = rng.integers(0, max(1, len(x) - int(0.08 * SR))); f = rng.uniform(380, 900); b = sweep(f, f * 1.6, 0.06) * env(int(0.06 * SR), 0.003, 5)
        x[st:st + len(b)] += b * rng.uniform(0.2, 0.5)
    return lp(x, 2500) * 0.5
def sizzle(d=1.0, **_):
    n = bp(noise(d), 1800, 4500); crack = (rng.random(len(n)) < 0.002).astype(float); crack = lp(crack, 300) * 40
    e = np.minimum(1, np.linspace(0, 6, len(n))) * np.linspace(1, 0.2, len(n)); return n * (0.4 + crack) * e * 0.12
def sparkle(d=1.2, **_):
    notes = [784, 880, 1047, 1175, 1319, 1568]; x = np.zeros(int(d * SR) + SR // 2)
    for k, f in enumerate(notes):
        st = int(k * d / len(notes) * SR); n = int(0.4 * SR); t = tt(0.4)
        x[st:st + n] += (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * env(n, 0.004, 6) * 0.22
    return lp(x, 4500)
def thud(**_):
    d = 0.35; t = tt(d); x = np.sin(2 * np.pi * (70 + 40 * np.exp(-t * 30)) * t) * env(len(t), 0.002, 7)
    return x * 0.9 + lp(noise(d), 220) * env(len(t), 0.001, 12) * 0.3
def slam(**_):
    d = 0.5; t = tt(d); x = np.sin(2 * np.pi * (60 + 60 * np.exp(-t * 25)) * t) * env(len(t), 0.002, 6)
    return np.tanh(1.6 * (x + lp(noise(d), 1200) * env(len(t), 0.001, 10) * 0.6)) * 0.9
def tock(**_): d = 0.09; t = tt(d); return (np.sin(2 * np.pi * 420 * t) + 0.3 * np.sin(2 * np.pi * 840 * t)) * env(len(t), 0.001, 9) * 0.35
def zip_(**_):
    d = 0.32; n = bp(noise(d), 400, 3000); k = np.linspace(0, 1, len(n))
    return (n / (np.abs(n).max() + 1e-9) * 0.35 + sweep(300, 1100, d) * 0.12) * np.sin(np.pi * k) ** 1.2
def alarm(d=2.0, **_):
    x = np.zeros(int(d * SR)); one = np.sin(2 * np.pi * 150 * tt(0.22)) * env(int(0.22 * SR), 0.02, 5)
    for st in np.arange(0, d - 0.25, 0.5): i = int(st * SR); x[i:i + len(one)] += one
    return lp(x, 900) * 0.55

def inhale(d=1.0, **_):
    n = bp(noise(d), 300, 2600); k = np.linspace(0, 1, len(n)); e = np.sin(np.pi * np.minimum(1, k * 1.15)) ** 1.5 * (0.6 + 0.4 * k)
    return n / (np.abs(n).max() + 1e-9) * e * 0.5
def heartbeat(**_):
    one = lambda d, f: np.sin(2 * np.pi * f * tt(d)) * env(int(d * SR), 0.004, 7)
    x = np.concatenate([one(0.16, 58), np.zeros(int(0.09 * SR)), one(0.2, 52) * 0.75]); return lp(x, 300) * 1.0

FX = dict(inhale=inhale, heartbeat=heartbeat, whoosh=whoosh, slide=slide, pop=pop, plop=plop, gulp=gulp, boing=boing, bubbles=bubbles, sizzle=sizzle,
          sparkle=sparkle, thud=thud, slam=slam, tock=tock, zip=zip_, alarm=alarm)
LEVEL = dict(inhale=-15, heartbeat=-8, whoosh=-17, slide=-19, pop=-14, plop=-15, gulp=-11, boing=-15, bubbles=-21, sizzle=-18, sparkle=-17,
             thud=-11, slam=-9, tock=-18, zip=-14, alarm=-17)


# ---------- the music bed: soft pad + plucked arpeggio, 100 BPM, I–vi–IV–V ----------
def music_bed():
    bpm = 100; beat = 60 / bpm; bar = beat * 4
    chords = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
    x = np.zeros(N)
    nb = int(np.ceil(DUR / bar)) + 1
    for b in range(nb):
        ch = chords[b % 4]; st = int(b * bar * SR); n = int(bar * SR)
        if st >= N: break
        t = tt(bar); e = np.minimum(1, t / 0.4) * np.minimum(1, (bar - t) / 0.4)
        pad = sum(np.sin(2 * np.pi * f / 2 * t) + 0.25 * np.sin(2 * np.pi * f * t) for f in ch) * e * 0.10
        x[st:st + n] += pad[:max(0, min(n, N - st))]
        for k in range(8):                                                       # eighth-note pluck arpeggio
            f = ch[[0, 1, 2, 1, 2, 0, 1, 2][k]] * (2 if k % 4 == 2 else 1); ps = st + int(k * beat / 2 * SR); pn = int(0.5 * SR)
            if ps + pn >= N: continue
            pt = tt(0.5); pl = (np.sin(2 * np.pi * f * pt) + 0.35 * np.sin(4 * np.pi * f * pt)) * env(pn, 0.003, 7) * 0.12
            x[ps:ps + pn] += pl
    x = lp(x, 3200)
    fade = np.ones(N); fo = int(1.2 * SR); fade[-fo:] = np.linspace(1, 0, fo)
    return x / (np.abs(x).max() + 1e-9) * fade

def music_tension():
    """low drone + slow minor pulse, for mysterious / tense explainers (script.json "music": "tension")"""
    t = np.arange(N) / SR; x = np.zeros(N)
    for f, g in [(55, 0.5), (82.4, 0.3), (110, 0.2), (130.8, 0.12)]: x += np.sin(2 * np.pi * f * t + np.sin(t * 0.3) * 0.5) * g
    x *= 0.55 + 0.45 * np.sin(2 * np.pi * t / 8) ** 2
    beat = 60 / 84; ping = lambda f: (np.sin(2 * np.pi * f * tt(1.2)) + 0.3 * np.sin(4 * np.pi * f * tt(1.2))) * env(int(1.2 * SR), 0.01, 5)
    seq = [220.0, 261.6, 196.0, 174.6]
    for k in range(int(DUR / (beat * 2))):
        i = int(k * beat * 2 * SR); pg = ping(seq[(k // 2) % 4]) * 0.35
        if i + len(pg) < N: x[i:i + len(pg)] += pg
    x = lp(x, 2200); fade = np.ones(N); fo = int(1.5 * SR); fade[-fo:] = np.linspace(1, 0, fo); fi = int(0.8 * SR); fade[:fi] *= np.linspace(0, 1, fi)
    return x / (np.abs(x).max() + 1e-9) * fade


# ---------- World Tour additions: atmospheres + motion-graphics hits ----------
def _fade(x, a=0.6, b=0.8):
    n = len(x); e = np.ones(n); na, nb = min(n // 2, int(a * SR)), min(n // 2, int(b * SR))
    if na: e[:na] = np.linspace(0, 1, na)
    if nb: e[-nb:] = np.linspace(1, 0, nb)
    return x * e
def wind(d=4.0, **_):
    n = noise(d); t = tt(d); g = 0.6 + 0.4 * np.sin(2 * np.pi * t / 3.1) * np.sin(2 * np.pi * t / 1.7 + 1)
    x = bp(n, 180, 900) * g + lp(n, 160) * 0.6; return _fade(x / (np.abs(x).max() + 1e-9))
def desert(d=4.0, **_):
    n = noise(d); t = tt(d); x = bp(n, 300, 2200) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 2.6) ** 2) * 0.5 + lp(n, 120) * 0.5
    return _fade(x / (np.abs(x).max() + 1e-9))
def waves(d=4.0, **_):
    n = noise(d); t = tt(d); sw = np.clip(np.sin(2 * np.pi * t / 3.4), 0, 1) ** 2.5 + 0.5 * np.clip(np.sin(2 * np.pi * t / 3.4 + 2.2), 0, 1) ** 3
    x = lp(n, 1400) * (0.15 + sw) + lp(n, 200) * 0.3; return _fade(x / (np.abs(x).max() + 1e-9))
def city(d=4.0, **_):
    n = noise(d); x = lp(n, 500) * 0.8 + bp(n, 600, 1800) * 0.15
    for st in np.arange(0.4, d - 1.0, 1.9):          # distant soft voices/footsteps murmur as pitched blips
        i = int(st * SR); b = sweep(300 + rng.uniform(0, 120), 260, 0.25) * env(int(0.25 * SR), 0.03, 4) * 0.25; x[i:i + len(b)] += b
    return _fade(x / (np.abs(x).max() + 1e-9))
def birds(d=4.0, **_):
    x = lp(noise(d), 300) * 0.25
    for st in np.arange(0.3, d - 0.6, 0.55):
        if rng.random() < 0.55:
            i = int(st * SR); f = rng.uniform(1800, 2600); n = int(0.09 * SR); c = sweep(f, f * 1.25, 0.09) * np.sin(np.pi * np.linspace(0, 1, n)) * 0.35
            for k in range(rng.integers(1, 3)): j = i + k * int(0.12 * SR); x[j:j + n] += c[:max(0, min(n, len(x) - j))]
    return _fade(lp(x, 4500) / (np.abs(x).max() + 1e-9))
def burner(d=1.6, **_):
    n = noise(d); x = bp(n, 120, 1600); k = np.linspace(0, 1, len(x)); e = np.minimum(1, k * 10) * np.exp(-np.maximum(0, k - 0.6) * 6)
    return x * e / (np.abs(x).max() + 1e-9)
def riser(d=0.5, **_):
    n = noise(d); k = np.linspace(0, 1, len(n)); x = bp(n, 400, 3500) * k ** 2 + sweep(200, 900, d) * k ** 2 * 0.3; return x / (np.abs(x).max() + 1e-9)
def impact(**_):
    d = 1.0; t = tt(d); x = np.sin(2 * np.pi * (48 + 70 * np.exp(-t * 18)) * t) * env(len(t), 0.002, 5)
    tail = lp(noise(d), 900) * env(len(t), 0.002, 7) * 0.35; return np.tanh(1.4 * (x + tail))
def chime(**_):
    x = np.zeros(int(1.6 * SR))
    for k, f in enumerate([1046.5, 1318.5, 1568.0]):
        st = int(k * 0.09 * SR); n = len(x) - st; tq = tt(n / SR); x[st:] += (np.sin(2 * np.pi * f * tq) + 0.25 * np.sin(4 * np.pi * f * tq)) * env(n, 0.003, 4) * 0.3
    return lp(x, 4800)
FX.update(wind=wind, desert=desert, waves=waves, city=city, birds=birds, burner=burner, riser=riser, impact=impact, chime=chime)
LEVEL.update(wind=-27, desert=-27, waves=-24, city=-30, birds=-30, burner=-20, riser=-21, impact=-12, chime=-17)

def music_travel():
    """uplifting travel bed: 108 BPM, I–V–vi–IV in D major, warm pad, plucked arpeggio, soft kick + bass"""
    bpm = 108; beat = 60 / bpm; bar = beat * 4
    roots = [146.83, 220.0, 246.94, 196.0]; chords = [[293.7, 370.0, 440.0], [277.2, 329.6, 440.0], [246.9, 293.7, 370.0], [293.7, 392.0, 493.9]]
    x = np.zeros(N); nb = int(np.ceil(DUR / bar)) + 1
    for b in range(nb):
        st = int(b * bar * SR); n = int(bar * SR)
        if st >= N: break
        ch = chords[b % 4]; t = tt(bar); e = np.minimum(1, t / 0.3) * np.minimum(1, (bar - t) / 0.3)
        pad = sum(np.sin(2 * np.pi * f * t + np.sin(2 * np.pi * 0.3 * t) * 0.4) + 0.3 * np.sin(2 * np.pi * f * 1.005 * t) for f in ch) * e * 0.07
        bass = np.sin(2 * np.pi * roots[b % 4] / 2 * t) * e * 0.22
        seg_ = (pad + bass)[:max(0, min(n, N - st))]; x[st:st + len(seg_)] += seg_
        for k in range(8):
            f = ch[[0, 1, 2, 1, 2, 0, 2, 1][k]] * 2; ps = st + int(k * beat / 2 * SR); pn = int(0.45 * SR)
            if ps + pn >= N: continue
            pt = tt(0.45); x[ps:ps + pn] += (np.sin(2 * np.pi * f * pt) + 0.3 * np.sin(4 * np.pi * f * pt)) * env(pn, 0.003, 8) * 0.07
        if b >= 1:
            for k in range(4):
                ks = st + int(k * beat * SR); kn = int(0.25 * SR)
                if ks + kn >= N: continue
                kt = tt(0.25); x[ks:ks + kn] += np.sin(2 * np.pi * (50 + 90 * np.exp(-kt * 30)) * kt) * env(kn, 0.002, 9) * 0.35
    x = lp(x, 4000); fade = np.ones(N); fo = int(1.5 * SR); fade[-fo:] = np.linspace(1, 0, fo); fi = int(0.4 * SR); fade[:fi] *= np.linspace(0, 1, fi)
    return x / (np.abs(x).max() + 1e-9) * fade

def load_audio(f):
    out = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(f), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'], capture_output=True, check=True).stdout
    a = np.frombuffer(out, dtype=np.float32).reshape(-1, 2).astype(np.float64); return a


mix = np.zeros((N, 2))
# voice
vf = P / 'data/narration.wav'
voice = None
if vf.exists():
    v = load_audio(vf)[:N]; voice = np.zeros((N, 2)); voice[:len(v)] = v
    rms = np.sqrt(np.mean(voice ** 2) + 1e-12); voice *= db(-19) / rms
    mix += voice
# music
mus = script.get('music', 'bed')
if mus and mus != 'none':
    m = music_bed() if mus == 'bed' else music_tension() if mus == 'tension' else music_travel() if mus == 'travel' else None
    if m is None:
        a = load_audio(P / mus)[:N]; m = np.zeros(N); m[:len(a)] = a.mean(1); m /= np.abs(m).max() + 1e-9
    m = np.stack([m, m], 1) * db(-24 if voice is not None else -20)
    if voice is not None:                                                        # duck under the voice
        lev = np.abs(voice.mean(1)); lev = signal.lfilter([1 - 0.9995], [1, -0.9995], lev); lev /= lev.max() + 1e-9
        m *= (1 - 0.55 * np.clip(lev * 3, 0, 1))[:, None]
    mix += m
# effects
for c in cj['cues']:
    fn = FX.get(c['type'])
    if not fn: print('unknown cue type, skipped:', c['type']); continue
    x = fn(**({'d': c['dur']} if c.get('dur') else {}))
    x = lp(x, 5000) * db(LEVEL[c['type']]) * c.get('gain', 1.0) / (np.abs(x).max() + 1e-9) * 0.9
    i = int(c['t'] * SR); n = min(len(x), N - i)
    if n > 0 and i >= 0: pan = c.get('pan', 0.0); mix[i:i + n, 0] += x[:n] * (1 - max(0, pan)); mix[i:i + n, 1] += x[:n] * (1 + min(0, pan))
# master: gentle soft-clip, peak -1 dBFS
mix = np.tanh(mix * 1.2) / 1.2
mix *= db(-1) / (np.abs(mix).max() + 1e-9)
wavfile.write(P / 'data/mix.wav', SR, (mix * 32767).astype(np.int16))
print(f"data/mix.wav: {DUR:.2f} s · voice: {'yes' if voice is not None else 'NO (captions-only)'} · music: {mus} · {len(cj['cues'])} cues")
__EOF_WT__
cat > "$P/examples/script.json" <<'__EOF_WT__'
{
  "title": "Uçak Penceresindeki Delik Ne İşe Yarar?",
  "channel": "Kokpit 360",
  "lang": "tr",
  "voice": "Fenrir",
  "style": "[excited]",
  "speed": 1.0,
  "lead": 0.3,
  "outro": 1.3,
  "gap": 0.2,
  "music": "bed",
  "sources": [
    "GlobalAir / General Aviation News, 'Why Do Airplane Windows Have Tiny Holes?' (2025): three panes; the hole is in the middle pane near the bottom; it equalizes pressure between the cabin and the gap so the outer pane carries the load, and lets moisture escape so the window does not fog; cabin about 6,000-8,000 ft",
    "TIME, 'Airplane window holes' (J. Linshi, citing pilot Mark Vanhoenacker / Slate): the hole is in the middle pane, makes sure the outer pane bears the air pressure, and releases moisture from the gap so the window stays mostly fog-free",
    "MiGFlug Afterburner, 'The Hole in Your Aircraft Window' (2026): outer pane carries the load, middle pane in reserve as backup; hole drilled through the middle pane at the bottom; about 8 psi difference at cruise",
    "Mental Floss, 'Why airplane windows have tiny holes' (2026): outer pane bears the majority of the force, the middle pane serves as backup; the hole prevents fog/condensation",
    "AFAR, 'Why airplane windows have tiny holes' (2023): hole cuts through the central pane at the bottom; equalizes pressure, prevents condensation; the middle layer protects in an emergency",
    "Webtekno (2022) and Onedio (2026), Turkish: three layers (iç/orta/dış), the hole is in the middle layer, balances pressure so the outer layer carries the load, vents moisture, middle layer is the backup; not a manufacturing defect",
    "Wikipedia 'Cabin pressurization' (citing airliner data): typical maximum cabin differential pressure 540-650 hPa (7.8-9.4 psi); cabin altitude at most 8,000 ft"
  ],
  "lines": [
    {
      "text": "Uçak penceresindeki o minik delik bir hata gibi görünür… ama aslında seni koruyor.",
      "caps": "Uçak *penceresindeki | minik *delik | hata *değil | seni *koruyor"
    },
    {
      "text": "Bir dahaki uçuşunda bak: pencerenin tam altında, iğne ucu kadar bir delik var.",
      "caps": "Pencerenin *altında | *iğne ucu kadar | bir *delik"
    },
    {
      "text": "Çünkü sen kabinde rahat nefes alırken, dışarıdaki hava çok ince.",
      "caps": "Kabinde *rahat | dışarıdaki *hava | çok *ince"
    },
    {
      "text": "Aradaki basınç farkı yaklaşık sekiz psi, yani cam sürekli dışarı doğru itiliyor.",
      "caps": "*Basınç farkı | {sekiz} *8 psi | cam *dışarı | *itiliyor"
    },
    {
      "text": "Sorun şu: tek bir cam bu yükü taşırsa, yedeği olmaz.",
      "caps": "*Sorun | tek bir *cam | yedeği *olmaz"
    },
    {
      "text": "Çözüm: pencere aslında üç katmanlı.",
      "caps": "*Çözüm | *pencere | üç *katmanlı"
    },
    {
      "text": "Dıştaki cam asıl yükü taşır, ortadaki cam ise yedekte bekler.",
      "caps": "*Dıştaki cam | yükü *taşır | *ortadaki | *yedekte"
    },
    {
      "text": "Delik tam burada devreye giriyor: kabin basıncını iki cam arasına taşıyor.",
      "caps": "*Delik | kabin *basıncını | iki cam *arasına"
    },
    {
      "text": "Böylece tüm yük dış cama biner, ortadaki cam hiç yorulmaz.",
      "caps": "Tüm *yük | dış *cama | ortadaki *rahat"
    },
    {
      "text": "Üstelik nemi de dışarı atar, o yüzden camın arası buğulanmaz ya da donmaz.",
      "caps": "Üstelik *nemi | dışarı *atar | *buğulanmaz | ya da *donmaz"
    },
    {
      "text": "Yani o delik bir kusur değil, küçük bir mühendislik zekâsı.",
      "caps": "Kusur *değil | küçük *mühendislik | *zekâsı"
    },
    {
      "text": "Sıradaki parça hangisi olsun? Yorumlara yaz.",
      "caps": "*Sıradaki parça | *hangisi? | Yorumlara *yaz",
      "gap": 0.2
    }
  ]
}
__EOF_WT__
cat > "$P/src/core/aero.js" <<'__EOF_WT__'
// Kokpit 360 sets: a cutaway high-bypass turbofan (axis = X, intake at +X, air flows toward -X) and a cooled turbine blade.
// Units ≈ metres. Casings are clipped at z > 0 so the camera (on +Z) looks inside.
import * as THREE from 'three';
import { SHADOW } from './engine.js';

const TAU = Math.PI * 2;
const std = (color, rough = 0.5, x = {}) => new THREE.MeshStandardMaterial({ color, roughness: rough, ...x });
const rnd = (i) => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
const CLIP = [new THREE.Plane(new THREE.Vector3(0, 0, -1), 0.0)];

function studio(E, { top = '#0B1424', bottom = '#04070D', grid = true, fog = '#060B14' } = {}) {
  const scene = new THREE.Scene();
  const c = document.createElement('canvas'); c.width = 4; c.height = 256; const g = c.getContext('2d'); const gr = g.createLinearGradient(0, 0, 0, 256); gr.addColorStop(0, top); gr.addColorStop(1, bottom); g.fillStyle = gr; g.fillRect(0, 0, 4, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; scene.background = t; scene.fog = new THREE.Fog(fog, 18, 60);
  scene.environment = E.envMap; scene.environmentIntensity = 0.25;
  if (grid) { const gh = new THREE.GridHelper(80, 80, '#1F6F88', '#12324A'); gh.position.y = -2.4; gh.material.transparent = true; gh.material.opacity = 0.35; scene.add(gh); }
  const k = new THREE.DirectionalLight('#DDEBFF', 1.6); k.position.set(4, 8, 10); k.castShadow = true; k.shadow.mapSize.set(SHADOW, SHADOW); Object.assign(k.shadow.camera, { left: -10, right: 10, top: 10, bottom: -10, near: 1, far: 40 }); k.shadow.camera.updateProjectionMatrix(); scene.add(k);
  const r = new THREE.DirectionalLight('#4FD1E8', 1.6); r.position.set(-8, 3, -6); scene.add(r);
  scene.add(new THREE.HemisphereLight('#9FC3FF', '#0A0F1A', 0.45));
  return scene;
}
/** a blade: thin box, twisted along its length (y), returned with its root at y = 0 */
function bladeGeo(len, chord, thick, twist, seg = 8) {
  const g = new THREE.BoxGeometry(thick, len, chord, 1, seg, 1); g.translate(0, len / 2, 0); const p = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) { v.fromBufferAttribute(p, i); const a = twist * (v.y / len - 0.3); const x = v.x * Math.cos(a) - v.z * Math.sin(a), z = v.x * Math.sin(a) + v.z * Math.cos(a); p.setXYZ(i, x, v.y, z); }
  g.computeVertexNormals(); return g;
}
/** a ring of n blades around the X axis at x, from radius r0 to r1 */
function rotor(n, x, r0, r1, chord, mat, twist = 0.9, thick = 0.04) {
  const grp = new THREE.Group(); grp.position.x = x; const geo = bladeGeo(r1 - r0, chord, thick, twist);
  const m = new THREE.InstancedMesh(geo, mat, n), o = new THREE.Object3D();
  for (let i = 0; i < n; i++) { o.position.set(0, 0, 0); o.rotation.set(i / n * TAU, 0, 0); o.updateMatrix(); const M = new THREE.Matrix4().makeTranslation(0, r0, 0); o.matrix.multiply(M); m.setMatrixAt(i, o.matrix); }
  m.castShadow = true; grp.add(m);
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(r0, r0, chord * 1.1, 32), mat); hub.rotation.z = Math.PI / 2; grp.add(hub);
  return grp;
}
function shell(profile, mat, seg = 64) { const g = new THREE.LatheGeometry(profile.map(([x, r]) => new THREE.Vector2(r, x)), seg); g.rotateZ(-Math.PI / 2); return new THREE.Mesh(g, mat); }

export function turbofan(E) {
  E.renderer.localClippingEnabled = true;
  const scene = studio(E);
  const metal = std('#9AA6B5', 0.4, { metalness: 0.8 }), dark = std('#3A4352', 0.5, { metalness: 0.6 }), ti = std('#7D8FA4', 0.35, { metalness: 0.9 });
  const nacM = std('#8E9BAD', 0.45, { metalness: 0.3, side: THREE.DoubleSide, clippingPlanes: CLIP, clipShadows: true });
  const coreM = std('#5E6A7A', 0.45, { metalness: 0.6, side: THREE.DoubleSide, clippingPlanes: CLIP, clipShadows: true });
  const cutEdge = std('#FFD43B', 0.5, { emissive: '#FFB000', emissiveIntensity: 0.3, side: THREE.DoubleSide });
  const eng = new THREE.Group(); scene.add(eng);
  // nacelle (outer cowling): thick lip, long duct
  eng.add(shell([[5.6, 1.86], [5.75, 2.0], [5.5, 2.12], [3.5, 2.15], [0.5, 2.0], [-1.0, 1.82]], nacM));
  eng.add(shell([[5.6, 1.86], [4.6, 1.74], [3.6, 1.72], [0.5, 1.62], [-1.0, 1.66]], nacM));
  // core cowl (inner wall of the bypass duct) and the core's own inner flow path
  eng.add(shell([[3.9, 0.95], [3.0, 1.12], [1.0, 1.15], [-1.5, 1.05], [-3.4, 0.8]], coreM));
  eng.add(shell([[3.9, 0.95], [3.6, 0.78], [2.6, 0.62], [1.2, 0.52], [0.4, 0.62], [-0.6, 0.66], [-2.4, 0.74], [-3.4, 0.76]], coreM));
  const fan = rotor(22, 4.7, 0.42, 1.68, 0.55, ti, 1.1, 0.05); eng.add(fan);
  const spinner = new THREE.Mesh(new THREE.ConeGeometry(0.46, 0.9, 32), metal); spinner.rotation.z = -Math.PI / 2; spinner.position.x = 5.35; eng.add(spinner);
  const spiral = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.025, 8, 24, Math.PI * 1.5), std('#FFFFFF', 0.4)); spiral.rotation.y = Math.PI / 2; spiral.position.x = 5.62; eng.add(spiral);
  const comp = []; // low + high pressure compressor: 9 stages, shrinking
  for (let s = 0; s < 9; s++) { const x = 3.5 - s * 0.32, r1 = 0.78 - s * 0.03 - (s > 3 ? 0.05 : 0), r0 = 0.3 + s * 0.012; const st = rotor(28 + s * 2, x, r0, r1 - 0.04, 0.16, metal, 0.6, 0.025); comp.push(st); eng.add(st); }
  const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 9.5, 24), dark); shaft.rotation.z = Math.PI / 2; shaft.position.x = 0.6; eng.add(shaft);
  // combustor: a glowing ring with fuel nozzles
  const flameM = new THREE.MeshStandardMaterial({ color: '#FF7A1A', emissive: '#FF5A00', emissiveIntensity: 1.4, roughness: 0.6 });
  const comb = new THREE.Mesh(new THREE.TorusGeometry(0.5, 0.12, 16, 48), flameM); comb.rotation.y = Math.PI / 2; comb.position.x = 0.3; eng.add(comb);
  const combCase = new THREE.Mesh(new THREE.TorusGeometry(0.5, 0.17, 16, 48), std('#6B7380', 0.4, { metalness: 0.7, clippingPlanes: CLIP, side: THREE.DoubleSide })); combCase.rotation.y = Math.PI / 2; combCase.position.x = 0.3; eng.add(combCase);
  // turbine: 5 stages, hot (glowing) to cooler
  const turb = []; const hotM = [0, 1, 2, 3, 4].map((s) => std('#C9A27A', 0.4, { metalness: 0.7, emissive: '#FF5A1A', emissiveIntensity: [0.6, 0.4, 0.25, 0.12, 0.05][s] }));
  for (let s = 0; s < 5; s++) { const x = -0.45 - s * 0.38, r1 = 0.66 + s * 0.02, st = rotor(34, x, 0.32, r1 - 0.03, 0.2, hotM[s], 0.5, 0.03); turb.push(st); eng.add(st); }
  const cone = new THREE.Mesh(new THREE.ConeGeometry(0.42, 1.6, 32), dark); cone.rotation.z = Math.PI / 2; cone.position.x = -3.9; eng.add(cone);
  // pylon stub on top
  const py = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.9, 0.3), std('#6E7B8C', 0.5)); py.position.set(0.8, 2.4, -0.3); eng.add(py);
  // airflow particles: bypass (cyan, outside the core) and core (cyan → white → orange through the combustor)
  const N = 520, pm = new THREE.InstancedMesh(new THREE.SphereGeometry(0.035, 6, 4), new THREE.MeshBasicMaterial({ color: '#ffffff', toneMapped: false }), N), o = new THREE.Object3D(), C = new THREE.Color();
  pm.frustumCulled = false; scene.add(pm);
  const P = []; for (let i = 0; i < N; i++) P.push({ core: i % 4 === 0, a: rnd(i) * TAU, r: rnd(i * 3), u: rnd(i * 7), sp: 0.85 + rnd(i * 11) * 0.3 });
  const coreR = (x) => (x > 3.6 ? 0.78 : x > 1.2 ? 0.3 + (0.62 - 0.3) * ((x - 1.2) / 2.4) + 0.1 : x > -2.4 ? 0.48 + 0.1 * Math.sin(x) : 0.6);
  const state = { flow: 1, show: 1, hot: 1 };
  return {
    scene, eng, fan, comp, turb, comb, state,
    update(t) {
      const w = t * 9 * state.flow; fan.rotation.x = w * 0.6; comp.forEach((c, i) => (c.rotation.x = w * (i < 3 ? 0.6 : 1.4))); turb.forEach((c, i) => (c.rotation.x = w * (i < 2 ? 1.4 : 0.6)));
      flameM.emissiveIntensity = (1.2 + 0.4 * Math.sin(t * 23) * Math.sin(t * 7)) * state.hot;
      P.forEach((p, i) => {
        const u = (p.u + t * 0.16 * p.sp * state.flow) % 1, x = 7.5 - u * 13.5; let r, col = '#7FE3F5', s = 1;
        if (p.core) { r = Math.max(0.05, coreR(x) - 0.12 - p.r * 0.12); if (x < 0.5 && x > -0.2) col = '#FFFFFF'; else if (x <= -0.2) col = x > -2.5 ? '#FF8A3D' : '#FFB070'; s = x < 0.5 ? 1.2 : 1; if (x > 4) r = 0.45 + p.r * 0.9; }
        else { r = x > 4.2 ? 0.5 + p.r * 1.1 : 1.22 + p.r * 0.36; }
        const a = p.a + (x < 4.6 && x > -3 ? 0.2 * Math.sin(u * 20) * 0 : 0);
        o.position.set(x, Math.sin(a) * r, Math.cos(a) * r); o.scale.setScalar((state.show * s) * (x < 7 && x > -6 ? 1 : 0)); o.updateMatrix(); pm.setMatrixAt(i, o.matrix); pm.setColorAt(i, C.set(col));
      });
      pm.instanceMatrix.needsUpdate = true; pm.instanceColor.needsUpdate = true;
    },
    pts: { intake: new THREE.Vector3(5.6, 0, 0), bypass: new THREE.Vector3(1.5, 1.4, 0), comp: new THREE.Vector3(2.4, 0.5, 0), comb: new THREE.Vector3(0.3, 0.5, 0), turb: new THREE.Vector3(-1.2, 0.5, 0), exhaust: new THREE.Vector3(-4.0, 0, 0) },
  };
}

/** a single cooled turbine blade in hot gas: holes breathe a cyan film over its surface */
export function bladeScene(E) {
  const scene = studio(E, { top: '#2A0E05', bottom: '#080303', grid: false, fog: '#1A0804' });
  scene.add(new THREE.PointLight('#FF7A2A', 6, 30));
  const sh = new THREE.Shape(); sh.moveTo(-0.9, 0); sh.bezierCurveTo(-0.6, 0.55, 0.4, 0.5, 0.95, 0.05); sh.bezierCurveTo(0.4, 0.22, -0.5, 0.2, -0.9, 0);
  const g = new THREE.ExtrudeGeometry(sh, { depth: 3.2, bevelEnabled: true, bevelSize: 0.03, bevelThickness: 0.03, curveSegments: 24, steps: 12 }); g.rotateX(-Math.PI / 2); // span along +Y
  const p = g.attributes.position, v = new THREE.Vector3(); for (let i = 0; i < p.count; i++) { v.fromBufferAttribute(p, i); const a = 0.35 * (v.y / 3.2); p.setXYZ(i, v.x * Math.cos(a) - v.z * Math.sin(a), v.y, v.x * Math.sin(a) + v.z * Math.cos(a)); } g.computeVertexNormals();
  const bladeM = std('#B8A082', 0.4, { metalness: 0.8, emissive: '#FF4A0A', emissiveIntensity: 0.12 });
  const blade = new THREE.Mesh(g, bladeM); blade.position.y = -1.4; scene.add(blade);
  const root = new THREE.Mesh(new THREE.BoxGeometry(2.3, 0.5, 1.0), std('#9E8B70', 0.4, { metalness: 0.8 })); root.position.y = -1.65; scene.add(root);
  // cooling holes: rows near the leading edge and on the pressure side
  const holes = [], HP = []; for (let row = 0; row < 3; row++) for (let k = 0; k < 14; k++) { const y = -1.2 + k * 0.21, x = -0.82 + row * 0.18, a = 0.35 * ((y + 1.4) / 3.2), z = 0.12 + row * 0.07; HP.push(new THREE.Vector3(x * Math.cos(a) - z * Math.sin(a), y, x * Math.sin(a) + z * Math.cos(a))); }
  const hm = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.03, 0.03, 0.05, 10), new THREE.MeshBasicMaterial({ color: '#1A0A04' }), HP.length), o = new THREE.Object3D();
  HP.forEach((q, i) => { o.position.copy(q); o.rotation.set(Math.PI / 2, 0, 0); o.updateMatrix(); hm.setMatrixAt(i, o.matrix); }); scene.add(hm);
  // hot gas streaks (orange, flowing +X → -X… we flow left to right on screen) and cyan cooling puffs from the holes
  const N = 260, gm = new THREE.InstancedMesh(new THREE.BoxGeometry(0.5, 0.025, 0.025), new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.55 }), N), C = new THREE.Color(); gm.frustumCulled = false; scene.add(gm);
  const M = 300, cm = new THREE.InstancedMesh(new THREE.SphereGeometry(0.06, 8, 6), new THREE.MeshBasicMaterial({ color: '#7FE3F5', toneMapped: false }), M); cm.frustumCulled = false; scene.add(cm);
  const state = { film: 0 };
  return {
    scene, blade, holes: HP, state,
    update(t) {
      for (let i = 0; i < N; i++) { const u = (rnd(i) + t * (0.35 + rnd(i * 3) * 0.2)) % 1, y = -1.5 + rnd(i * 5) * 3.6, z = -1.2 + rnd(i * 7) * 2.6; let x = -4 + u * 8;
        const near = Math.abs(z) < 0.5 && Math.abs(x) < 1.1; const zz = near && state.film > 0.5 ? z + Math.sign(z || 1) * 0.35 * state.film : z;
        o.position.set(x, y, zz); o.rotation.set(0, 0, 0); o.scale.setScalar(1); o.updateMatrix(); gm.setMatrixAt(i, o.matrix); gm.setColorAt(i, C.set(rnd(i * 9) > 0.5 ? '#FF7A1A' : '#FFB347')); }
      for (let i = 0; i < M; i++) { const h = HP[i % HP.length], u = (rnd(i * 13) + t * 0.6) % 1, s = state.film * (u < 0.95 ? 1 : 0);
        o.position.set(h.x + u * 2.2, h.y + Math.sin(u * 6 + i) * 0.03, h.z + 0.08 + u * 0.12); o.scale.setScalar(s * (1.2 - u * 0.6)); o.updateMatrix(); cm.setMatrixAt(i, o.matrix); }
      gm.instanceMatrix.needsUpdate = true; gm.instanceColor.needsUpdate = true; cm.instanceMatrix.needsUpdate = true;
      bladeM.emissiveIntensity = 0.18 - 0.12 * state.film;
    },
  };
}

/** "Parça Parça Uçak #2": the three-pane airliner window. Two views in one scene:
 *  front (cabin side, oval panes + sky behind, exploded layers) and section (side cut, particles = air pressure).
 *  Panes are stacked along Z (outside z<0, cabin z>0): outer -0.5 · middle 0 (with the bleed hole) · inner +0.5. */
export function windowRig(E) {
  const scene = studio(E, { top: '#0B1424', bottom: '#04070D', grid: false, fog: '#060B14' });
  scene.fog = null;
  const A = 0.46, B = 0.68, HY = -0.5, HR = 0.035; // oval half-width / half-height, hole y / radius
  const ZP = { out: -0.5, mid: 0, inn: 0.5 }, TH = { out: 0.1, mid: 0.07, inn: 0.04 };
  const ell = (a, b, hole) => { const s = new THREE.Shape(); s.absellipse(0, 0, a, b, 0, TAU, false, 0); if (hole) { const h = new THREE.Path(); h.absarc(0, HY, HR, 0, TAU, true); s.holes.push(h); } return s; };
  const ext = (shape, depth) => { const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false, curveSegments: 56 }); g.translate(0, 0, -depth / 2); return g; };
  const front = new THREE.Group(), sec = new THREE.Group(); scene.add(front, sec);
  // ---------- FRONT VIEW ----------
  const sky = document.createElement('canvas'); sky.width = 4; sky.height = 256; { const g = sky.getContext('2d'), gr = g.createLinearGradient(0, 0, 0, 256); gr.addColorStop(0, '#1E5FA8'); gr.addColorStop(0.6, '#6FB3E8'); gr.addColorStop(1, '#D8EEFF'); g.fillStyle = gr; g.fillRect(0, 0, 4, 256); }
  const skyT = new THREE.CanvasTexture(sky); skyT.colorSpace = THREE.SRGBColorSpace;
  const skyP = new THREE.Mesh(new THREE.PlaneGeometry(14, 14), new THREE.MeshBasicMaterial({ map: skyT, toneMapped: false })); skyP.position.z = -3.2; front.add(skyP);
  const cloudM = new THREE.MeshBasicMaterial({ color: '#F4F9FF', toneMapped: false });
  for (let i = 0; i < 16; i++) { const c = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 10), cloudM); c.scale.set(0.7 + rnd(i) * 0.9, 0.22 + rnd(i * 3) * 0.18, 0.4); c.position.set(-3 + rnd(i * 5) * 6, -1.9 + rnd(i * 7) * 1.1, -3.1 + rnd(i) * 0.2); front.add(c); }
  const wallShape = new THREE.Shape(); wallShape.moveTo(-1.6, -2.6); wallShape.lineTo(1.6, -2.6); wallShape.lineTo(1.6, 2.6); wallShape.lineTo(-1.6, 2.6); wallShape.closePath();
  { const h = new THREE.Path(); h.absellipse(0, 0, A + 0.16, B + 0.16, 0, TAU, true, 0); wallShape.holes.push(h); }
  const wall = new THREE.Mesh(ext(wallShape, 0.14), std('#7E8793', 0.7, { metalness: 0.1 })); wall.position.z = 0.66; front.add(wall);
  const reveal = (() => { const s = ell(A + 0.16, B + 0.16, false); const h = new THREE.Path(); h.absellipse(0, 0, A + 0.005, B + 0.005, 0, TAU, true, 0); s.holes.push(h); return new THREE.Mesh(ext(s, 1.3), std('#3C4552', 0.6, { metalness: 0.3 })); })(); reveal.position.z = 0.05; front.add(reveal);
  const acr = (col, op) => new THREE.MeshStandardMaterial({ color: col, transparent: true, opacity: op, roughness: 0.08, metalness: 0, depthWrite: false, side: THREE.DoubleSide, emissive: col, emissiveIntensity: 0.0 });
  const rim = (col) => new THREE.MeshStandardMaterial({ color: col, emissive: col, emissiveIntensity: 0.55, roughness: 0.5 });
  const mk = (k, col, withHole) => { const g = new THREE.Group(), th = TH[k]; const body = new THREE.Mesh(ext(ell(A, B, withHole), th), acr(col, 0.07)); body.renderOrder = 2; g.add(body);
    const rs = ell(A, B, false); { const h = new THREE.Path(); h.absellipse(0, 0, A - 0.022, B - 0.022, 0, TAU, true, 0); rs.holes.push(h); } const ring = new THREE.Mesh(ext(rs, th * 1.2), rim(col)); g.add(ring); g.position.z = ZP[k]; front.add(g); return { g, body, ring }; };
  const P = { out: mk('out', '#7FE3F5', false), mid: mk('mid', '#FFD43B', true), inn: mk('inn', '#B8CFE0', false) };
  const holeRing = new THREE.Mesh(new THREE.TorusGeometry(HR + 0.02, 0.008, 8, 28), rim('#FFD43B')); holeRing.position.set(0, HY, 0.045); front.add(holeRing);
  P.mid.g.add(holeRing); holeRing.position.set(0, HY, 0.045);
  // ---------- SECTION VIEW (cut through the window, seen from the side; cabin on the left of the screen) ----------
  const BX = 0.5, PH = 1.36, boxM = (col, rough = 0.4, x = {}) => std(col, rough, { metalness: 0.2, ...x });
  const sbox = (w, h, d, x, y, z, mat) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); sec.add(m); return m; };
  const secMat = (col) => new THREE.MeshStandardMaterial({ color: col, emissive: col, emissiveIntensity: 0.12, roughness: 0.2, transparent: true, opacity: 0.85 });
  const outM = secMat('#7FE3F5'), midM = secMat('#FFD43B'), innM = secMat('#E8EEF5');
  const sOut = sbox(BX, PH, TH.out, 0, 0, ZP.out, outM);
  const gapH = 0.08, topH = B - (HY + gapH / 2), botH = (HY - gapH / 2) + B;
  const sMidTop = sbox(BX, topH, TH.mid, 0, B - topH / 2, ZP.mid, midM), sMidBot = sbox(BX, botH, TH.mid, 0, -B + botH / 2, ZP.mid, midM);
  const sInn = sbox(BX, PH, TH.inn, 0, 0, ZP.inn, innM);
  const fr = boxM('#4B5563', 0.6); sbox(BX, 0.34, 1.5, 0, B + 0.17, 0, fr); sbox(BX, 0.34, 1.5, 0, -B - 0.17, 0, fr);
  const regionM = (col, op) => new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: op, depthWrite: false });
  const gCabin = sbox(BX, 2.8, 1.1, 0, 0, 1.1, regionM('#4FD1E8', 0.07)), gA = sbox(BX, PH, 0.4, 0, 0, 0.25, regionM('#4FD1E8', 0.07));
  const g1M = regionM('#4FD1E8', 0), gOne = sbox(BX, PH, 0.4, 0, 0, -0.25, g1M);
  const fogM = regionM('#FFFFFF', 0), gFog = sbox(BX * 0.98, PH * 0.98, 0.38, 0, 0, -0.25, fogM);
  const gOut = sbox(BX, 2.8, 1.6, 0, 0, -1.35, regionM('#2A6FB8', 0.5));
  // particles
  const dot = (n, col, r) => { const m = new THREE.InstancedMesh(new THREE.SphereGeometry(r, 8, 6), new THREE.MeshBasicMaterial({ color: col, toneMapped: false }), n); m.frustumCulled = false; sec.add(m); return m; };
  const cab = dot(215, '#7FE3F5', 0.022), g1p = dot(64, '#7FE3F5', 0.022), outp = dot(14, '#9AA6B5', 0.026), flow = dot(30, '#FFFFFF', 0.03), drop = dot(48, '#FFFFFF', 0.022);
  const o = new THREE.Object3D(), wob = (t, i, a = 0.025) => [Math.sin(t * 3 + i * 1.7) * a, Math.cos(t * 2.3 + i * 2.9) * a, Math.sin(t * 2.7 + i * 1.3) * a];
  const place = (m, i, x, y, z, s) => { o.position.set(x, y, z); o.scale.setScalar(s); o.rotation.set(0, 0, 0); o.updateMatrix(); m.setMatrixAt(i, o.matrix); };
  // pressure arrows (cones pointing to -Z = outward)
  const arr = new THREE.InstancedMesh(new THREE.ConeGeometry(0.07, 0.3, 12), new THREE.MeshStandardMaterial({ color: '#FF7A1A', emissive: '#FF5A00', emissiveIntensity: 0.9 }), 7); arr.frustumCulled = false; sec.add(arr);
  const state = { view: 'front', ex: 0, tilt: 0, eq: 0, vent: 0, fog: 0, arrows: 0, arrowZ: 0.9, single: 0, outGlow: 0, midGlow: 0, crack: 0, holeGlow: 0 };
  // crack lines on the single pane
  const crackG = new THREE.BufferGeometry().setFromPoints([[-0.55, 0], [-0.35, 0.11], [-0.18, -0.11], [0, 0.11], [0.2, -0.11], [0.38, 0.11], [0.55, 0]].flatMap((p, i, a) => (i ? [new THREE.Vector3(0.27, a[i - 1][0], a[i - 1][1]), new THREE.Vector3(0.27, p[0], p[1])] : [])));
  const crack = new THREE.LineSegments(crackG, new THREE.LineBasicMaterial({ color: '#FF4D4D', toneMapped: false })); crack.visible = false; sec.add(crack);
  return {
    scene, state, P, front, sec, holePt: new THREE.Vector3(0, HY, 0), HY,
    update(t) {
      const s = state, isF = s.view === 'front'; front.visible = isF; sec.visible = !isF;
      if (isF) {
        const e = s.ex; P.out.g.position.z = ZP.out - 0.7 * e; P.inn.g.position.z = ZP.inn + 0.7 * e; P.mid.g.position.z = 0; const tl = 0.18 * e; // gap grows when exploded
        wall.visible = reveal.visible = e < 0.02; holeRing.visible = true; holeRing.material.emissiveIntensity = 0.6 + 0.7 * Math.sin(t * 7) ** 2; holeRing.scale.setScalar(1 + 0.25 * Math.sin(t * 7));
        P.out.ring.material.emissiveIntensity = 0.55 + 1.4 * s.outGlow; return;
      }
      // section: single pane mode shows one pane in the middle
      const single = s.single > 0.5;
      sOut.visible = true; sOut.position.z = single ? 0 : ZP.out; sMidTop.visible = sMidBot.visible = sInn.visible = !single; gA.visible = gCabin.visible = true; gOne.visible = gFog.visible = !single; gOut.visible = true;
      outM.emissiveIntensity = 0.12 + 0.9 * s.outGlow; midM.emissiveIntensity = 0.12 + 0.5 * s.midGlow;
      outM.color.set(single ? '#FF9C9C' : '#7FE3F5'); outM.emissive.set(single ? '#FF3030' : '#7FE3F5'); if (single) outM.emissiveIntensity = 0.3 + 0.5 * Math.sin(t * 9) ** 2 * s.crack + 0.3;
      crack.visible = single && s.crack > 0.5; crack.position.z = 0;
      g1M.opacity = 0.07 * s.eq; fogM.opacity = 0.42 * s.fog;
      for (let i = 0; i < 215; i++) { const inA = i < 65, z = inA ? 0.06 + rnd(i * 3) * 0.4 : 0.56 + rnd(i * 3) * 1.05, w = wob(t, i); place(cab, i, (rnd(i) - 0.5) * 0.4 + w[0], (rnd(i * 7) - 0.5) * 1.2 + w[1], z + w[2], single && inA ? 0 : 1); }
      cab.instanceMatrix.needsUpdate = true;
      for (let i = 0; i < 64; i++) { const w = wob(t, i + 400); place(g1p, i, (rnd(i + 9) - 0.5) * 0.4 + w[0], (rnd(i * 5 + 3) - 0.5) * 1.2 + w[1], -0.43 + rnd(i * 11) * 0.38 + w[2], rnd(i * 13) < s.eq ? 1 : 0); }
      g1p.instanceMatrix.needsUpdate = true;
      for (let i = 0; i < 14; i++) { const w = wob(t, i + 800, 0.05); place(outp, i, (rnd(i + 21) - 0.5) * 0.4 + w[0], (rnd(i * 9) - 0.5) * 1.2 + w[1], -0.62 - rnd(i * 3) * 1.0 + w[2], 1); }
      outp.instanceMatrix.needsUpdate = true;
      // flow through the hole (cabin gap → outer gap), arrow-like stream
      for (let i = 0; i < 30; i++) { const u = (rnd(i) + t * 0.7) % 1, k = s.eq * (1 - s.vent * 0) * (s.eq > 0.01 && s.eq < 0.99 ? 1 : 0) + (s.holeGlow); const z = lerp(0.3, -0.3, u), y = HY + (rnd(i * 5) - 0.5) * 0.04 * (1 - Math.abs(u - 0.5) * 0); place(flow, i, 0 + (rnd(i * 7) - 0.5) * 0.1, y, z, Math.min(1, k) * (Math.abs(u - 0.5) < 0.45 ? 1 : 0.4)); }
      flow.instanceMatrix.needsUpdate = true;
      // moisture droplets in the outer gap drift to the hole and leave through it into the cabin side
      for (let i = 0; i < 48; i++) { const sy = (rnd(i + 31) - 0.5) * 1.1, sz = -0.4 + rnd(i * 3 + 1) * 0.34, sx = (rnd(i * 7) - 0.5) * 0.4; const u = s.vent > 0 ? (rnd(i * 13) + t * 0.35) % 1 : 0;
        let x = sx, y = sy, z = sz; if (s.vent > 0) { if (u < 0.6) { const k = eio3(u / 0.6); x = lerp(sx, 0, k); y = lerp(sy, HY, k); z = lerp(sz, -0.2, k); } else { const k = (u - 0.6) / 0.4; x = 0; y = HY; z = lerp(-0.2, 0.9, k); } }
        const vis = s.vent > 0 || s.fog > 0 ? 1 : 0; place(drop, i, x, y, z, vis * (s.vent > 0 && u > 0.97 ? 0 : 1) * (s.vent > 0 || rnd(i) < s.fog ? 1 : 0)); }
      drop.instanceMatrix.needsUpdate = true;
      for (let i = 0; i < 7; i++) { const y = -0.5 + i * (1.0 / 6), push = 0.07 * Math.sin(t * 6 + i); o.position.set(0, y, s.arrowZ + push); o.rotation.set(-Math.PI / 2, 0, 0); o.scale.setScalar(s.arrows); o.updateMatrix(); arr.setMatrixAt(i, o.matrix); }
      arr.instanceMatrix.needsUpdate = true;
    },
  };
}
const eio3 = (x) => (x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2);
const lerp = (a, b, k) => a + (b - a) * k;
__EOF_WT__
cat > "$HOME/faceless-shorts/system/RUNBOOK.md" <<'__EOF_WT__'
# Viral Video Factory: runbook for each automatic run

Every run makes ONE finished Turkish short (~60 s, 9:16, 3D, motion graphics, subtitles, Google TTS voice, sound designed in code), adds it to the panel, and stops. Twice a day. Everything is free: no paid servers, no AI image or video credits.

## 0. Load the system (2 min)
1. The engine lives in the **panel artifact** "Viral Video Paneli" (find it with the artifacts list tool) as `engine/bundle.txt` (save it as bundle.sh), and the list of finished videos as `data/videos.json`. Read both (artifacts `read_file`).
2. `SKILL` = the faceless-shorts skill folder (Skill tool: `anthropic-skills:faceless-shorts`). Make the project:
   `bash $SKILL/scripts/new_video.sh deep-dive <slug>` → `~/faceless-shorts/<slug>/`, then run `bash bundle.sh ~/faceless-shorts/<slug>` (from the folder where you saved it; it overwrites `src/`, `tools/voice_google.py`, `tools/mix.py` and the Turkish caption fixes).
3. Google key: `printf '%s' "$KEY" > ~/.faceless-shorts/google_api_key` (the key is in the scheduled task's prompt). Check the voice is reachable:
   `curl -s -o /dev/null -w "%{http_code}" "https://generativelanguage.googleapis.com/v1beta/models?key=$KEY"` must be 200.
   If it is 403 "blocked" → STOP. Send the user a message: "Google ses servisine erişilemiyor: claude.ai → Settings → Capabilities → allowed domains listesine generativelanguage.googleapis.com ekleyin." Do not publish a silent video.

## 1. Pick a VIRAL idea (5 min)
Niche: **merak uyandıran bilgi videoları** (world, travel, nature, space, history, science, "biliyor muydun?"). Read `data/videos.json` and never repeat a topic or the same format twice in a row.
Brainstorm 10 ideas. Score each 1-5 on: **hook** (does the first sentence stop the scroll?), **curiosity gap** (is there a reveal people wait for?), **3D potential** (can it be shown beautifully with code-built scenes?), **comment bait** (will people argue, guess or share their pick?), **Turkish relevance** (a Turkish angle or Turkish place helps). Make the highest total. Write the 10 with scores into the run log.
Rotate formats: countdown top-N (with #1 held to the end), quiz/tahmin ("3 saniyen var"), myth vs fact ("herkes yanlış biliyor"), comparison/scale ("Everest okyanusa girse"), "what if" (… olsaydı ne olurdu?), hidden place reveal.

## 2. Script (Turkish, 140-160 words ≈ 60 s)
- Line 0 = the hook: a bold claim or question, with the promise of a reveal ("…biri Türkiye'de", "sonuncusunu kimse bilmiyor").
- One line = one cut (2-4 s). Talk like a person, not like captions. Numbers are written as they are said ("üç bin sekiz yüz").
- Escalate; keep the best for last; the last line asks a question that invites comments ("Sen hangisini…? Yorumlara yaz.").
- **Every fact checked with web search** (2 reliable sources for each number). Put them in `script.json` "sources". If a claim can't be confirmed, cut it.
- `caps`: 1-3 words per chunk, exactly ONE `*yellow` word per chunk, `{spoken}` anchor before a digit chunk (e.g. `{üç} *3.800 yıl`). `say` overrides pronunciation (e.g. "Maçu Piçu").
- script.json keys: title, lang "tr", voice ("Charon" deep male · "Kore" female · "Puck" bright), style = ONE audio tag such as "[excited]", "[curious]", "[warm]" (a plain-text direction gets read aloud!), music "travel" | "tension" | "bed", lines.

## 3. Voice
`python3 tools/voice_google.py .` makes ONE Gemini TTS request for the whole script (the free tier allows only a few requests per minute and a limited number per day per model), falls back through the other TTS models on 429, and splits the audio back into lines at its pauses. It prints each line's length: every line should be ~5-6.5 syllables per second; if one is far off, re-run with `--per-line` (slow: 21 s between requests). Vary the voice between videos (Charon, Puck, Kore, Fenrir, Orus...). Style = one audio tag like "[excited]", never a sentence (it gets read aloud).

## 4. Build the shots (the main work)
- 3D sets are in `src/core/world.js`: `flight, paris, giza, taj, machu, santorini, wall, cappadocia`. Reuse them, and **add new sets in the same style** for new topics with the helpers: `base()` sky+fog, `sun()`, `hemi()`, `terrain(size, seg, heightFn, colorFn)`, `inst()` (instanced boxes/cones/etc.), `cloudField()`, `trees()`, `water()`, `merge()+strut()` for lattices. Units ≈ 10 m. Low sun, warm light, fog for depth.
- 2D motion graphics in `src/core/overlays.js`: `rankBadge(n, name, place, lt, gold)`, `factCard(label, value, unit, lt, {sub, subAt})` (counts up), `gauge`, `ruler`, `trace`, `callout(text, x, y, tx, ty, k)`, `ring(pts)`, `compareBar`, `finalList`, `pillAt`, `flash(lt)` on every cut, `title(lt)`.
- `src/shots.js`: one shot per line, `cut(i)`, `safeWd('word', i, fallback)`; the camera always moves; numbers and reveals land on their word; sound cues on every cut (whoosh, impact, pop, riser, sparkle) plus one atmosphere per place (wind, desert, waves, city, birds, burner). Shot `fov` defaults to 34; use 50-60 for wide landscapes seen from close.

## 5. QA: never ship a frame you haven't looked at
Render settings (no GPU): `SOFTWARE_GL=1 QS='&res=0.5&aa=0&shadow=1024'`.
`node tools/capture.mjs check` (CHECK OK) → `node tools/capture.mjs sheet review/all.jpg 1.5 8` → look at that ONE 4×4 grid only (engine/RUNBOOK.txt section 5 on GitHub overrides this old copy). Known traps:
- camera inside clouds/mist → white frames; camera looking into the sun over glossy water → black frames (keep water roughness ≥ 0.22); trees/props between camera and subject; narrow FOV hiding the subject below the frame; text over the caption zone (y 1330-1630).
- each caption chunk 1-3 words with one yellow word, spelled right, on the word being said.
Fix, re-check the frames you changed.

## 6. Sound + render
`node tools/capture.mjs cues && python3 tools/mix.py .` then
`FPS=24 SOFTWARE_GL=1 QS='&res=0.6&aa=0&shadow=1024' node tools/capture.mjs video renders/<slug>.mp4` (~30-45 min, run in the background and poll).
Share copy: `ffmpeg -i renders/<slug>.mp4 -c:v libx264 -crf 26 -preset slow -c:a aac -b:a 160k -movflags +faststart renders/<slug>_web.mp4` (must be < 19 MB, raise crf if not). Cover: `node tools/capture.mjs frames review/cover "<best t>"`.

## 7. Deliver
1. Panel: artifacts `publish_files` (mode patch) on "Viral Video Paneli": add `videos/<slug>.mp4` (the web copy), `videos/<slug>.jpg` (cover, scaled to 540 px wide), and the updated `data/videos.json` (append `{ slug, title, date, duration, format, file, cover, caption, hashtags, sources }`). Call `list_files` first. publish_files only attaches files under `/mnt/user-data/outputs/`, so copy them to `/mnt/user-data/outputs/panel/...` first. Panel slug: `2f566c1a-98a5-40e7-83e7-577c9d54417d`.
2. Send the MP4 to the user (SendUserFile, status proactive) with: title, a caption (2 sentences + question), 6-8 hashtags (#shorts #reels #keşfet + topic).
3. If `world.js` / `overlays.js` gained new sets or components, rebuild the bundle: `python3 ~/faceless-shorts/system/make_bundle.py <project> bundle.sh`, and publish it to the panel as `engine/bundle.txt` (plus `engine/RUNBOOK.txt` if the runbook changed), so the next run can use them.

## 8. Publish (ONLY after the user approves the video in this conversation)
The user checks every video first. When they reply "onay / yayınla / upload", publish it:
1. **Host the file (public link):** GitHub repo `ClaudeRepo620/video_repo` (public). `add_repo(owner "ClaudeRepo620", repo "video_repo", access "push")`, `git clone --depth 1 https://github.com/ClaudeRepo620/video_repo /home/claude/video_repo`, copy the MP4 to `videos/<slug>.mp4`, commit (author Claude <noreply@anthropic.com>), `git -c push.negotiate=true push`. URL: `https://raw.githubusercontent.com/ClaudeRepo620/video_repo/main/videos/<slug>.mp4` — check `curl -sSIL` gives 200 + content-length. (litterbox/catbox, Google Drive and the panel's private files do NOT work.)
2. **YouTube (Zapier):** `execute_zapier_write_action` selected_api `YouTubeV4CLIAPI`, action `upload_video`, tool_name `youtube_upload_video`, connection_id: **Rota 360** `02536dd0-8eaa-805c-ba7f-e6ab984e8f66` · **AyetBilim** `02e9bf63-ae1a-871b-bd0f-d8e34f8a3eb6` · **Kokpit 360** `02142914-48f7-8bb2-8d28-8652a495223d`. params: video (the raw URL), title, description (ends with #shorts), tags, privacy_status "public" (unless the user says otherwise), category_id 19 travel · 27 education · 28 science & tech, made_for_kids "false", notify_subscribers "true", default_language "tr", default_audio_language "tr". The result has `play_url`.
3. **Instagram:** @ayet.bilim via vidIQ: `vidiq_video_upload(url = raw URL)` → `vidiq_instagram_publish_reel(platformAccountId "29499943179599458", videoUrl, caption)` → call again with `containerId` every ~20 s until `PUBLISHED` (permalink). @rota.360tr and @kokp.it360 are not connected yet (Zapier "Instagram for Business" needs each to be a Business account linked to a Facebook Page; check `inspect_zapier_actions` enum `instagramPageId`); if they appear there, post with `instagram_for_business_publish_video`, otherwise tell the user.
4. Update the panel entry (read data/videos.json first): format "YAYINDA", add `"youtube": play_url`, `"instagram": permalink`.
__EOF_WT__
cat > "$HOME/faceless-shorts/system/RUNBOOK_AYET.md" <<'__EOF_WT__'
# Ayet ve Bilim: runbook for each daily run

Each run makes ONE Turkish 2D short (~55-60 s, 9:16) for the **Ayet ve Bilim** channel (YouTube @AyetveBilim-c6k · Instagram @ayet.bilim), sends it to the user for approval and stops. **Never upload or post anything without the user's explicit approval.** Free: Gemini TTS (AI voice), code-drawn 2D visuals, no AI images.

## 0. Load
1. In the panel artifact "Viral Video Paneli" (slug 2f566c1a-98a5-40e7-83e7-577c9d54417d) read `engine/ayet_bundle.txt` (save as bundle.sh) and `data/videos.json` (never repeat a verse or topic already there; the channel's earlier videos also covered: Hicr 15:22 / Kaf 50:9-11 lightning & nitrogen, Zâriyât 47 expanding universe, Hadîd 57:25 iron).
2. `bash $SKILL/scripts/new_video.sh deep-dive <slug>` (SKILL = anthropic-skills:faceless-shorts), then `bash bundle.sh ~/faceless-shorts/<slug>`.
3. Quran font: `curl -sSL -o /tmp/sch.zip https://github.com/silnrsi/font-scheherazade/releases/download/v4.300/ScheherazadeNew-4.300.zip && unzip -o -q /tmp/sch.zip -d /tmp/sch && cp /tmp/sch/ScheherazadeNew-4.300/ScheherazadeNew-Regular.ttf ~/faceless-shorts/<slug>/fonts/`
4. Google key → `~/.faceless-shorts/google_api_key`; check `generativelanguage.googleapis.com` answers 200 (if 403 blocked: stop and tell the user).

## 1. Topic (viral, but honest)
Brainstorm 8 verse + science pairings; score hook, curiosity, how clearly the science is established, visual potential (2D), comment bait. Prefer well-established science (astronomy, earth science, biology, physics) and verses whose plain meaning relates. Avoid weak claims (numerology, Emoto water crystals, "scientists converted"…). Rotate fields.

## 2. Script (Turkish, 120-150 words, 4 sections, each line has "sec")
KANCA (1-2 lines: a surprising fact or question) → BİLİMSEL GERÇEK (4-5 lines, every fact checked with web search, 2 sources) → AYET VE HİKMET (reference line, the Diyanet meal read verbatim, then 1-2 lines of reflection; where scholars read the verse differently, SAY SO: "bazı yorumcular… kimileri ise…") → TAKİP ET ("…beğendiysen, yorumlarda paylaş ve Ayet ve Bilim'i takip et.").
`"upper": true` (uppercase captions), `caps` with one `*yellow` word per chunk, `{spoken}` anchors before digit chunks. `script.verse = { ref, arabic, meal, arabic_sources, meal_source }`.

## 3. Quran accuracy (non-negotiable)
- Fetch the Arabic from two sources (web search → qurano.com word-by-word Uthmani + quran.com simple text). Never type Arabic from memory. Show ONLY the quoted phrase. Compare consonants of both sources.
- Meal = current Diyanet İşleri Başkanlığı wording, verbatim; reference "<Sure> Suresi <n>/<ayet>".
- Render the verse card at full size and look at every word (harakat, shadda, wasla, dagger alif). Font: Scheherazade New.
- No prophets, sacred figures or human faces. Symbols, nature, objects only.
- In the delivery message, list the Arabic and meal used and ask the user to verify.

## 4. Build (2D, the channel's look)
`src/core/ab2d.js`: `bg(t)` navy starfield, `mark()` "AYET & BİLİM", `chip(section)`, `glow`, `pill`, `bigNum`, `star`, `atom`, `bloodCell`, `earth(x,y,r,cut)`, `onion`, `verseCard(verse, k, highlight)`, `cta(lt)`. Add new 2D components there in the same style (flat shapes, soft glow, gold/yellow/cyan on navy). `src/shots.js` of the example = one shot per line with `add(i, note, drawFn)`; reveals on their words (`safeWd`); soft sound cues (whoosh per cut, pop, sparkle on the verse, chime on the reference, tock on CTA). Music "space".
Voice: `python3 tools/voice_google.py .` (one request; check the printed syllable rates, ~5-6.5/s).

## 5. QA, render, deliver
Render settings: `SOFTWARE_GL=1 QS='&res=0.3&aa=0&shadow=256'` (2D: the 3D engine is idle). `check` → `sheet review/all.jpg 1.25 8` → ONE 4×4 grid + the verse card full size (engine/RUNBOOK.txt section 5). Then `cues`, `python3 tools/mix.py .`, `FPS=30 … video renders/<slug>.mp4` (~2 min).
Deliver: add to the panel (publish_files patch; copy files to /mnt/user-data/outputs/panel first; videos.json entry with `"channel": "Ayet ve Bilim"`), SendUserFile the MP4 (status proactive) with: the verse (Arabic + meal + reference) to verify, the sources, a title, a caption ending with a question, 6-8 hashtags (#ayetvebilim #kuran #bilim #shorts #reels #keşfet …). Ask: "Onaylıyor musun? Onaylarsan paylaşıma hazırlarım." Do not upload.
__EOF_WT__
cat > "$HOME/faceless-shorts/system/RUNBOOK_KOKPIT.md" <<'__EOF_WT__'
# Kokpit 360: runbook for each daily run

Each run makes ONE Turkish 3D short (~55-60 s, 9:16) for **Kokpit 360** (YouTube @Kokpit360-j1y · Instagram @kokp.it360): fun, curious aviation engineering ("uçağın parçaları nasıl çalışır?"), sends it to the user for approval and stops. **Never upload or post anything without the user's explicit approval.** Free: Gemini TTS, code-built 3D, no AI images.

Everything in RUNBOOK.md (the travel runbook, engine/RUNBOOK.txt in the panel) applies: load, voice, QA, render, deliver. Differences:
- Engine: `engine/kokpit_bundle.txt` from the panel (it adds `src/core/aero.js`: `turbofan(E)` cutaway engine with spinning fan/compressor/turbine, glowing combustor and airflow particles; `bladeScene(E)` cooled turbine blade; plus `flight(E)` airliner over clouds from world.js). Build new aviation sets in aero.js in the same style (dark blueprint studio, cyan/yellow HUD accents, clipped cutaways with `clippingPlanes`).
- Topics: one part or one question per video, told with a hook and a reveal: wings & winglets, flaps/slats, landing gear, cockpit instruments, black box, autopilot, cabin pressure, why windows are round, contrails, lightning strikes, de-icing, APU, tyres, fuel in the wings, reverse thrust, the first jet... Never repeat a topic in data/videos.json (channel "Kokpit 360"). Prefer what viewers asked for in comments when the user passes them on.
- Tone: playful and clear (voice "Puck" or "Fenrir", style "[excited]"), numbered steps ("1 · EMER"), one "SORUN → ÇÖZÜM" turn, end with "SIRADAKİ PARÇA?" options as comment bait and `@kokp.it360`.
- Look: `LOOK = { bloom 0.3, bloomThreshold 0.9, exposure 0.85 }`; studio scenes overexpose easily: keep casings mid-grey, emissive ≤ 1.4, point lights ≤ 6. QA in ONE 4×4 grid (engine/RUNBOOK.txt section 5).
- Panel entry `"channel": "Kokpit 360"`, format ending "ONAY BEKLİYOR".
__EOF_WT__
cat > "$HOME/faceless-shorts/system/make_bundle.py" <<'__EOF_WT__'
"""Pack the World Tour engine files of a project into one self-extracting shell file (engine/bundle.sh).

  python3 make_bundle.py <project> [out=bundle.sh]
  bash bundle.sh <new-project>       (after new_video.sh deep-dive <slug>: overwrites the engine files)

The bundle also carries this script and RUNBOOK.md, so any run can rebuild it after adding new sets.
"""
import sys
from pathlib import Path

proj = Path(sys.argv[1]); out = Path(sys.argv[2] if len(sys.argv) > 2 else 'bundle.sh'); here = Path(__file__).parent
FILES = ['index.html', 'src/main.js', 'src/shots.js', 'src/core/world.js', 'src/core/overlays.js', 'src/core/captions.js', 'src/core/timing.js',
         'tools/voice_google.py', 'tools/mix.py', 'script.json']
parts = ['#!/bin/bash', '# World Tour engine bundle. usage: bash bundle.sh <project-dir>', 'set -eu', 'P="${1:?project dir}"',
         'mkdir -p "$P/src/core" "$P/tools" "$P/examples" "$HOME/faceless-shorts/system"',
         'rm -f "$P/src/sheet.js" "$P/sheet.html" "$P/src/core/human.js" "$P/src/core/sets.js" "$P/src/core/board.js"']
D = '__EOF_' + 'WT__'
def emit(dst, text):
    assert D not in text
    parts.append(f"cat > {dst} <<'{D}'\n{text.rstrip(chr(10))}\n{D}")
FILES += [f for f in ('src/core/ab2d.js', 'src/core/aero.js') if (proj / f).exists()]
for f in FILES:
    text = (proj / f).read_text()
    if f in ('src/shots.js', 'script.json'):
        emit(f'"$P/examples/{Path(f).name}"', text)          # the last video's shots/script, as a worked example
        if f == 'src/shots.js': emit('"$P/src/shots.js"', text)
    else:
        emit(f'"$P/{f}"', text)
for f in ('RUNBOOK.md', 'RUNBOOK_AYET.md', 'RUNBOOK_KOKPIT.md', 'make_bundle.py'): emit(f'"$HOME/faceless-shorts/system/{f}"', (here / f).read_text()) if (here / f).exists() else None
parts.append('echo "engine installed into $P (example shots/script in $P/examples/)"')
out.write_text('\n'.join(parts) + '\n')
print(f'{out}: {out.stat().st_size // 1024} KB, {len(FILES)} files + runbook')
__EOF_WT__
echo "engine installed into $P (example shots/script in $P/examples/)"
