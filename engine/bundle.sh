#!/bin/bash
# World Tour engine bundle. usage: bash bundle.sh <project-dir>
set -eu
P="${1:?project dir}"
mkdir -p "$P/src/core" "$P/tools" "$P/examples" "$HOME/faceless-shorts/system"
rm -f "$P/src/sheet.js" "$P/sheet.html" "$P/src/core/human.js" "$P/src/core/sets.js" "$P/src/core/board.js"
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
// HARİTADA YOK · DERİNKUYU — the shot list. One shot per narration line (sub-shots on reveals).
// cut(i) = just before line i · Wd('word', i) = when that word is said. Every camera moves.
import * as THREE from 'three';
import { W, H, clamp, lerp, seg, eo, eio, eob } from './core/lib.js';
import { L, Wd, T } from './core/timing.js';
import * as WD from './core/world.js';
import * as O from './core/overlays.js';

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
const lerpV = (a, b, k) => a.clone().lerp(b, k);
function screen(p, cam) { const v = p.clone().project(cam); return [(v.x + 1) / 2 * W, (1 - v.y) / 2 * H]; }
const safeWd = (w, i, fb) => { try { return Wd(w, i); } catch { return fb; } };

export function buildShots(E) {
  const S = [], CUES = [], cue = (t, type, o = {}) => CUES.push({ t: +Math.max(0, t).toFixed(3), type, ...o });
  const cam = WD.cameraWide(34);
  const add = (o) => { const dr = o.draw; o.draw = (lt, d, t, blit) => { const f = o.fov || 34; if (cam.fov !== f) { cam.fov = f; cam.updateProjectionMatrix(); } dr(lt, d, t, blit); O.brand(); if (t < 3.0) O.seriesTag('HARİTADA YOK', seg(t, 0.2, 0.5) * (1 - seg(t, 2.6, 3.0))); }; S.push(o); return o; };
  const cut = (i) => (i === 0 ? 0 : L(i) - 0.1), end = (i) => (i + 1 < T.lines.length ? cut(i + 1) : T.dur);
  const LOOK = { aperture: 0, bloom: 0.38, bloomThreshold: 0.8, vignette: 0.36, grain: 0.018, warm: 0.03 };
  const look = (x = {}) => ({ ...LOOK, ...x });
  const shoot = (A, B, at, k) => { cam.position.copy(lerpV(A, B, eio(clamp(k)))); cam.lookAt(at); };
  const shoot2 = (A, B, a0, a1, k) => { const e = eio(clamp(k)); cam.position.copy(lerpV(A, B, e)); cam.lookAt(lerpV(a0, a1, e)); };
  const rel = (i, w, fb) => safeWd(w, i, cut(i) + fb) - cut(i);

  const D = WD.derinkuyu(E), U = WD.tunnel(E);
  const CUTL = look({ bloom: 0.45, bloomThreshold: 0.75, exposure: 0.82 });
  const TUNL = look({ bloom: 0.5, bloomThreshold: 0.7, vignette: 0.5, exposure: 0.95 });
  const torchAt = (p) => U.torch.position.copy(p).add(V3(0.25, 0.15, 0));
  const onPath = (u, back = 0, up = 0) => { const p = U.path.getPointAt(clamp(u, 0, 1)); return p.add(V3(0, up, 0)); };
  D.people(1); U.setDoor(0);

  // 0 · HOOK: the house and its basement in cross-section, the glowing city below
  { const st = cut(0), en = end(0);
    add({ id: 'S00', at: st, note: 'cut-away: house on the surface, basement, glowing levels; camera sinks', fov: 40, draw(lt, d, t, blit) {
      D.people(1); shoot2(V3(-8, -2, 64), V3(-3, -9, 58), V3(-11, -7, -5), V3(-8, -13, -5), lt / d); E.render(D.scene, cam, CUTL); blit();
      O.hookTitle(lt, 'DUVARIN ARKASINDA', 'BİR ŞEHİR', 300, 150);
    } });
    cue(0.02, 'chime', { gain: 0.55 }); cue(st + 0.1, 'impact', { gain: 0.7 }); cue(st + 0.45, 'pop', { gain: 0.5 }); cue(st, 'wind', { dur: en - st + 0.3, gain: 0.45 }); }

  // 1 · "ama … koca bir şehir çıktı": big pull back, the whole 18-level city
  { const st = cut(1), sk = rel(1, 'şehir', 2.4);
    add({ id: 'S01', at: st, note: 'pull back from the basement to the whole city, YERALTI ŞEHRİ', fov: 36, draw(lt, d, t, blit) {
      const k = eio(clamp(lt / d)); cam.position.copy(lerpV(V3(-4, -8, 45), V3(4, -40, 172), k)); cam.lookAt(lerpV(V3(-9, -12, -5), V3(0, -42, -5), k));
      E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.topShade(1); O.pillAt('YERALTI ŞEHRİ', 540, 330, eob(seg(lt, sk - 0.05, sk + 0.3)), '#101318', '#FFD43B', 80);
    } });
    cue(st, 'whoosh'); cue(st + 0.1, 'riser', { dur: sk, gain: 0.5 }); cue(st + sk, 'impact', { gain: 0.8 }); cue(st, 'wind', { dur: end(2) - st, gain: 0.4 }); }

  // 2 · 20.000 people: people fill the rooms level by level
  { const st = cut(2), yk = rel(2, 'yirmi', 0.4);
    add({ id: 'S02', at: st, note: 'mid-levels, little people fill the rooms, 20.000 KİŞİ', fov: 38, draw(lt, d, t, blit) {
      D.people(seg(lt, yk - 0.2, d - 0.3)); shoot(V3(10, -22, 74), V3(-2, -27, 66), V3(0, -30, -5), lt / d);
      E.render(D.scene, cam, CUTL); blit(); D.people(1); O.flash(lt);
      O.factCard('KAPASİTE', 20000, 'KİŞİ', lt - yk + 0.1, { dur: 1.0 });
    } });
    cue(st, 'whoosh'); cue(st + yk, 'slide', { dur: 1.0, gain: 0.4 }); cue(st + yk + 1.1, 'impact', { gain: 0.6 }); }

  // 3 · 1963, Nevşehir, Derinkuyu: the village on the surface at golden hour
  { const st = cut(3), bk = rel(3, 'bin', 0.3), nk = rel(3, 'nevşehir', 1.8);
    add({ id: 'S03', at: st, note: 'surface village + fairy chimneys, 1963 then NEVŞEHİR · DERİNKUYU', fov: 44, draw(lt, d, t, blit) {
      shoot(V3(-2, 16, -4), V3(-10, 7, -10), V3(-24, 2, -70), lt / d); E.render(D.scene, cam, look({ exposure: 0.82 })); blit(); O.flash(lt);
      O.topShade(1); O.pillAt('1963', 540, 320, eob(seg(lt, bk - 0.05, bk + 0.25)), '#101318', '#FFD43B', 100);
      O.pillAt('NEVŞEHİR · DERİNKUYU', 540, 470, eob(seg(lt, nk - 0.05, nk + 0.3)), '#fff', 'rgba(12,15,22,0.85)', 58);
    } });
    cue(st, 'whoosh'); cue(st, 'birds', { dur: end(3) - st + 0.2, gain: 0.5 }); cue(st + bk, 'impact', { gain: 0.6 }); cue(st + nk, 'pop'); }

  // 4 · behind the wall a dark tunnel … that goes down and down
  { const st = cut(4), hk = safeWd('hep', 4, cut(4) + 1.6) - 0.12;
    add({ id: 'S04a', at: st, note: 'basement: push through the broken wall into the dark tunnel', fov: 60, draw(lt, d, t, blit) {
      const k = eio(clamp(lt / d)); cam.position.set(lerp(0.3, 0, k), lerp(1.55, 1.2, k), lerp(4.7, -0.6, k)); cam.lookAt(0, 1.1, -6); torchAt(cam.position);
      E.render(U.scene, cam, TUNL); blit(); O.flash(lt);
    } });
    add({ id: 'S04b', at: hk, note: 'descend the winding passage, lamp niches', fov: 62, draw(lt, d, t, blit) {
      const u = lerp(0.04, 0.42, eio(clamp(lt / (d + 0.3)))), p = onPath(u, 0, 0.25), q = onPath(u + 0.05, 0, 0.1); cam.position.copy(p); cam.lookAt(q); torchAt(p);
      E.render(U.scene, cam, TUNL); blit(); O.flash(lt, 0.15);
      O.pillAt('AŞAĞI, HEP AŞAĞI', 540, 330, eob(seg(lt, 0.15, 0.45)), '#101318', '#FFD43B', 62);
    } });
    cue(st, 'whoosh'); cue(st + 0.3, 'thud', { gain: 0.6 }); cue(hk, 'riser', { dur: end(4) - hk, gain: 0.5 }); cue(st, 'wind', { dur: end(4) - st + 0.2, gain: 0.6 }); }

  // 5 · carved into soft tuff (volcanic ash): close slide along the cut face
  { const st = cut(5), vk = rel(5, 'volkanik', 0.7), tk = rel(5, 'tüfe', 2.4);
    add({ id: 'S05', at: st, note: 'close slide along the carved tuff face, callout TÜF', fov: 48, draw(lt, d, t, blit) {
      shoot(V3(4, -16, 14), V3(16, -19, 12), V3(10, -20, -4), lt / d); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.topShade(1); O.pillAt('VOLKANİK KÜL', 540, 330, eob(seg(lt, vk - 0.05, vk + 0.3)), '#101318', '#FFD43B', 66);
      const [px, py] = screen(V3(12.5, -18.5, 0.02), cam); O.callout('YUMUŞAK TÜF', 540, 520, clamp(px, 120, 960), clamp(py, 640, 1200), seg(lt, tk - 0.3, tk + 0.3));
    } });
    cue(st, 'whoosh'); cue(st + vk, 'pop'); cue(st + tk, 'pop', { gain: 0.6 }); cue(st, 'wind', { dur: end(7) - st, gain: 0.4 }); }

  // 6-7 · 85 m deep and at least 18 levels: the whole cut-away with a ruler, then the level ticks
  const fullCam = (k) => { cam.position.set(lerp(6, 2, k), lerp(-40, -43, k), lerp(176, 168, k)); cam.lookAt(0, -43, -5); };
  const A6 = end(6) - cut(6), A67 = end(7) - cut(6);
  { const st = cut(6), sk = rel(6, 'seksen', 1.0);
    add({ id: 'S06', at: st, note: 'whole city, ruler 0 → 85 m', fov: 36, draw(lt, d, t, blit) {
      fullCam(lt / A67); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      const [, y0] = screen(V3(-30, 0, 0), cam), [x1, y1] = screen(V3(-30, -85, 0), cam), kr = seg(lt, sk - 0.3, sk + 0.9);
      O.ruler(clamp(x1 - 70, 90, 400), y1, y0, kr, `${Math.round(85 * eio(kr))} m`);
    } });
    cue(st, 'whoosh'); cue(st + sk - 0.2, 'slide', { dur: 1.1, gain: 0.5 }); cue(st + sk + 0.9, 'impact', { gain: 0.7 }); }
  { const st = cut(7), ok = rel(7, 'on', 0.5);
    add({ id: 'S07', at: st, note: 'same frame, 18 level ticks light up, EN AZ 18 KAT', fov: 36, draw(lt, d, t, blit) {
      fullCam((lt + A6) / A67); E.render(D.scene, cam, CUTL); blit();
      const ys = D.LV.map((l) => screen(V3(-29, l.floor + 1.5, 0), cam)[1]), n = Math.floor(lerp(0, 18.99, seg(lt, 0.05, ok + 0.45)));
      const [lx] = screen(V3(-30, 0, 0), cam); O.levelTicks(ys, n, clamp(lx - 60, 80, 400));
      O.factCard('EN AZ', 18, 'KAT', lt - ok + 0.15, { dur: 0.6, y: 330 });
    } });
    for (let i = 0; i < 18; i++) cue(st + 0.05 + i * (ok + 0.4) / 18, 'tock', { gain: 0.3 }); cue(st + ok + 0.5, 'impact', { gain: 0.6 }); }

  // 8 · stables, kitchens, wine presses, churches: one close-up per word
  { const W8 = [['ahırlar', 'AHIRLAR', D.R.stable, 0.6], ['mutfaklar', 'MUTFAKLAR', D.R.kitchen, 1.3], ['şarap', 'ŞARAP PRESLERİ', D.R.wine, 2.0], ['kiliseler', 'KİLİSELER', D.R.church, 3.0]];
    W8.forEach(([w, name, r, fb], j) => {
      const at = j === 0 ? cut(8) : safeWd(w, 8, cut(8) + fb) - 0.12, wk = safeWd(w, 8, cut(8) + fb) - at, s = j % 2 ? -1 : 1;
      add({ id: `S08${'abcd'[j]}`, at, note: `room close-up: ${name}`, fov: 50, draw(lt, d, t, blit) {
        const k = clamp(lt / Math.max(d, 0.6)); shoot(V3(r.cx + s * 3.2, r.floor + 2.2, 7.5), V3(r.cx + s * 1.2, r.floor + 1.8, 6.2), V3(r.cx, r.floor + 1.0, -6.5), k);
        E.render(D.scene, cam, look({ bloom: 0.5, bloomThreshold: 0.7, exposure: 0.85 })); blit(); O.flash(lt, 0.15);
        O.topShade(1); O.pillAt(name, 540, 330, eob(seg(lt, wk - 0.05, wk + 0.25)), '#101318', '#FFD43B', 72);
      } });
      cue(at, 'whoosh', { gain: 0.7 }); cue(at + wk, 'pop');
    }); }

  // 9 · like ask: drift over the lit rooms, BEĞEN chip
  { const st = cut(9);
    add({ id: 'S09', at: st, note: 'drift over the busy upper levels, like chip', fov: 40, draw(lt, d, t, blit) {
      shoot(V3(-14, -10, 52), V3(-4, -14, 48), V3(-6, -16, -5), lt / d); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.likeChip(lt - 0.1, 540, 1150);
    } });
    cue(st, 'whoosh'); cue(st + 0.15, 'pop', { gain: 0.7 }); cue(st + 0.55, 'sparkle', { dur: 0.8, gain: 0.6 }); }

  // 10 · 50+ air shafts: look straight up the main shaft to the sky
  { const st = cut(10), ek = rel(10, 'elliden', 0.1);
    add({ id: 'S10', at: st, note: 'rise up the main air shaft towards the daylight, 50+ HAVA BACASI', fov: 40, draw(lt, d, t, blit) {
      const k = eio(clamp(lt / d)); cam.position.set(D.shaftX, lerp(-82, -60, k), 9); cam.lookAt(D.shaftX, lerp(-30, 0, k), -5);
      E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.factCard('HAVA BACASI', 50, '+', lt - ek + 0.1, { dur: 0.9, y: 360 });
    } });
    cue(st, 'whoosh'); cue(st + 0.2, 'wind', { dur: end(10) - st, gain: 0.8 }); cue(st + ek + 1.0, 'impact', { gain: 0.5 }); }

  // 11 · each level closed from inside with giant rolling stone doors
  { const st = cut(11), tk = rel(11, 'taş', 0.6), ik = rel(11, 'içeriden', 1.6);
    add({ id: 'S11', at: st, note: 'in the passage: the millstone door rolls across, İÇERİDEN', fov: 52, draw(lt, d, t, blit) {
      const k = eio(seg(lt, tk - 0.1, ik + 0.4)); U.setDoor(k);
      const u = U.doorU + lerp(0.115, 0.1, lt / d), p = onPath(u, 0, 0.3); cam.position.copy(p); cam.lookAt(onPath(U.doorU - 0.01, 0, -0.1)); torchAt(p.clone().add(V3(0, 0.3, 0)));
      E.render(U.scene, cam, TUNL); blit(); U.setDoor(0); O.flash(lt);
      O.topShade(1); O.pillAt('DEV TAŞ KAPI', 540, 330, eob(seg(lt, tk - 0.05, tk + 0.3)), '#101318', '#FFD43B', 66);
      O.pillAt('İÇERİDEN KAPANIR', 540, 460, eob(seg(lt, ik - 0.05, ik + 0.3)), '#fff', '#D62839', 56);
    } });
    cue(st, 'whoosh'); cue(st + tk - 0.1, 'slide', { dur: ik - tk + 0.5, gain: 0.7 }); cue(st + ik + 0.4, 'slam', { gain: 0.9 }); }

  // 12 · the first rooms ~2.700 years ago, maybe the Phrygians
  { const st = cut(12), ik = rel(12, 'iki', 1.2), fk = rel(12, 'frigler', 2.6);
    add({ id: 'S12', at: st, note: 'upper levels close to the surface, 2.700 YIL ÖNCE · FRİGLER?', fov: 44, draw(lt, d, t, blit) {
      shoot2(V3(-24, -2, 40), V3(-8, -6, 44), V3(-16, -6, -5), V3(-6, -9, -5), lt / d); E.render(D.scene, cam, look({ warm: 0.08, bloom: 0.45, bloomThreshold: 0.75, exposure: 0.82 })); blit(); O.flash(lt);
      const k = seg(lt, ik - 0.1, ik + 0.9); if (k > 0) O.yearCounter(2700 * eio(k), clamp(k * 4), 320, lt > fk - 0.05 ? 'YIL ÖNCE · FRİGLER?' : 'YIL ÖNCE');
    } });
    cue(st, 'whoosh'); cue(st + ik, 'slide', { dur: 0.9, gain: 0.4 }); cue(st + ik + 0.95, 'impact', { gain: 0.5 }); cue(st + fk, 'pop'); }

  // 13-14 · an ~8 km tunnel to Kaymaklı: aerial over the plain, the glowing line runs out to the second city
  const A13 = end(13) - cut(13), A1314 = end(14) - cut(13);
  const air = (k) => { const e = eio(clamp(k)); cam.position.copy(lerpV(V3(-25, 165, -30), V3(15, 190, -130), e)); cam.lookAt(lerpV(V3(28, 0, -125), V3(58, 0, -250), e)); };
  { const st = cut(13), tk = rel(13, 'tünelle', 1.6), sk = rel(13, 'sekiz', 0.6);
    add({ id: 'S13', at: st, note: 'aerial: the tunnel line grows from Derinkuyu, 8 KM', fov: 46, draw(lt, d, t, blit) {
      D.beacons(true, false); D.tunnel(seg(lt, 0.2, A1314 - 0.4) * 1.0); air(lt / A1314);
      E.render(D.scene, cam, look({ bloom: 0.6, bloomThreshold: 0.7, exposure: 0.74 })); blit(); D.beacons(false, false); D.tunnel(0); O.flash(lt);
      O.topShade(1); O.pillAt('~8 KM TÜNEL', 540, 330, eob(seg(lt, sk - 0.05, sk + 0.3)), '#101318', '#FFD43B', 76);
      const [dx, dy] = screen(V3(5, 4, -5), cam); if (dy < 1300 && dy > 560) O.pillAt('DERİNKUYU', clamp(dx, 220, 860), dy - 90, eob(seg(lt, 0.2, 0.5)), '#fff', 'rgba(12,15,22,0.85)', 44);
    } });
    cue(st, 'whoosh'); cue(st + 0.2, 'riser', { dur: A1314 - 0.4, gain: 0.45 }); cue(st + sk, 'pop'); cue(st, 'wind', { dur: A1314 + 0.2, gain: 0.5 }); }
  { const st = cut(14), kk = rel(14, 'kaymaklı', 0.1);
    add({ id: 'S14', at: st, note: 'line reaches Kaymaklı, its beacon lights, KAYMAKLI', fov: 46, draw(lt, d, t, blit) {
      const lt2 = lt + A13; D.beacons(true, lt > kk + 0.3); D.tunnel(seg(lt2, 0.2, A1314 - 0.4)); air(lt2 / A1314);
      E.render(D.scene, cam, look({ bloom: 0.6, bloomThreshold: 0.7, exposure: 0.74 })); blit(); D.beacons(false, false); D.tunnel(0);
      O.topShade(1); O.pillAt('~8 KM TÜNEL', 540, 330, 1, '#101318', '#FFD43B', 76);
      const [kx, ky] = screen(V3(D.KAY.x, D.hf(D.KAY.x, D.KAY.z) + 6, D.KAY.z), cam); O.pillAt('KAYMAKLI', clamp(kx, 220, 860), clamp(ky - 110, 560, 1200), eob(seg(lt, kk + 0.3, kk + 0.6)), '#101318', '#FFD43B', 60);
    } });
    cue(st + kk + 0.3, 'impact', { gain: 0.7 }); cue(st + kk + 0.35, 'sparkle', { dur: 1.2, gain: 0.6 }); }

  // 15 · closing question: warm orbit over the lit city
  { const st = cut(15), yk = rel(15, 'yorumlara', 1.6);
    add({ id: 'S15', at: st, note: 'warm orbit over the city, BİR GECE KALIR MIYDIN?', fov: 38, draw(lt, d, t, blit) {
      const a = lerp(-0.3, 0.05, eio(lt / d)); cam.position.set(Math.sin(a) * 110, -30, Math.cos(a) * 110 - 5); cam.lookAt(0, -34, -5);
      E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.hookTitle(lt, 'BİR GECE', 'KALIR MIYDIN?', 300, 130);
      O.pillAt('YORUMLARA YAZ', 540, 1180, eob(seg(lt, yk - 0.05, yk + 0.3)), '#101318', '#FFD43B', 60);
    } });
    cue(st, 'whoosh'); cue(st + 0.15, 'impact', { gain: 0.5 }); cue(st + yk, 'pop'); }

  // 16 · closer + subscribe: end card over a slow rise to the surface
  { const st = cut(16);
    add({ id: 'S16', at: st, note: 'slow rise to the house on the surface, end card', fov: 44, draw(lt, d, t, blit) {
      shoot2(V3(-4, -30, 70), V3(-8, -4, 52), V3(-6, -34, -5), V3(-12, -6, -5), lt / d); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.endCard(lt - 0.1, '@rota360tr', 700);
    } });
    cue(st, 'whoosh'); [0.2, 0.35, 0.5].forEach((x) => cue(st + x, 'pop', { gain: 0.5 })); cue(T.dur - 1.3, 'chime', { gain: 0.6 }); cue(st, 'wind', { dur: T.dur - st, gain: 0.4 }); }

  return { shots: S, cues: CUES };
}
__EOF_WT__
cat > "$P/src/shots.js" <<'__EOF_WT__'
// HARİTADA YOK · DERİNKUYU — the shot list. One shot per narration line (sub-shots on reveals).
// cut(i) = just before line i · Wd('word', i) = when that word is said. Every camera moves.
import * as THREE from 'three';
import { W, H, clamp, lerp, seg, eo, eio, eob } from './core/lib.js';
import { L, Wd, T } from './core/timing.js';
import * as WD from './core/world.js';
import * as O from './core/overlays.js';

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
const lerpV = (a, b, k) => a.clone().lerp(b, k);
function screen(p, cam) { const v = p.clone().project(cam); return [(v.x + 1) / 2 * W, (1 - v.y) / 2 * H]; }
const safeWd = (w, i, fb) => { try { return Wd(w, i); } catch { return fb; } };

export function buildShots(E) {
  const S = [], CUES = [], cue = (t, type, o = {}) => CUES.push({ t: +Math.max(0, t).toFixed(3), type, ...o });
  const cam = WD.cameraWide(34);
  const add = (o) => { const dr = o.draw; o.draw = (lt, d, t, blit) => { const f = o.fov || 34; if (cam.fov !== f) { cam.fov = f; cam.updateProjectionMatrix(); } dr(lt, d, t, blit); O.brand(); if (t < 3.0) O.seriesTag('HARİTADA YOK', seg(t, 0.2, 0.5) * (1 - seg(t, 2.6, 3.0))); }; S.push(o); return o; };
  const cut = (i) => (i === 0 ? 0 : L(i) - 0.1), end = (i) => (i + 1 < T.lines.length ? cut(i + 1) : T.dur);
  const LOOK = { aperture: 0, bloom: 0.38, bloomThreshold: 0.8, vignette: 0.36, grain: 0.018, warm: 0.03 };
  const look = (x = {}) => ({ ...LOOK, ...x });
  const shoot = (A, B, at, k) => { cam.position.copy(lerpV(A, B, eio(clamp(k)))); cam.lookAt(at); };
  const shoot2 = (A, B, a0, a1, k) => { const e = eio(clamp(k)); cam.position.copy(lerpV(A, B, e)); cam.lookAt(lerpV(a0, a1, e)); };
  const rel = (i, w, fb) => safeWd(w, i, cut(i) + fb) - cut(i);

  const D = WD.derinkuyu(E), U = WD.tunnel(E);
  const CUTL = look({ bloom: 0.45, bloomThreshold: 0.75, exposure: 0.82 });
  const TUNL = look({ bloom: 0.5, bloomThreshold: 0.7, vignette: 0.5, exposure: 0.95 });
  const torchAt = (p) => U.torch.position.copy(p).add(V3(0.25, 0.15, 0));
  const onPath = (u, back = 0, up = 0) => { const p = U.path.getPointAt(clamp(u, 0, 1)); return p.add(V3(0, up, 0)); };
  D.people(1); U.setDoor(0);

  // 0 · HOOK: the house and its basement in cross-section, the glowing city below
  { const st = cut(0), en = end(0);
    add({ id: 'S00', at: st, note: 'cut-away: house on the surface, basement, glowing levels; camera sinks', fov: 40, draw(lt, d, t, blit) {
      D.people(1); shoot2(V3(-8, -2, 64), V3(-3, -9, 58), V3(-11, -7, -5), V3(-8, -13, -5), lt / d); E.render(D.scene, cam, CUTL); blit();
      O.hookTitle(lt, 'DUVARIN ARKASINDA', 'BİR ŞEHİR', 300, 150);
    } });
    cue(0.02, 'chime', { gain: 0.55 }); cue(st + 0.1, 'impact', { gain: 0.7 }); cue(st + 0.45, 'pop', { gain: 0.5 }); cue(st, 'wind', { dur: en - st + 0.3, gain: 0.45 }); }

  // 1 · "ama … koca bir şehir çıktı": big pull back, the whole 18-level city
  { const st = cut(1), sk = rel(1, 'şehir', 2.4);
    add({ id: 'S01', at: st, note: 'pull back from the basement to the whole city, YERALTI ŞEHRİ', fov: 36, draw(lt, d, t, blit) {
      const k = eio(clamp(lt / d)); cam.position.copy(lerpV(V3(-4, -8, 45), V3(4, -40, 172), k)); cam.lookAt(lerpV(V3(-9, -12, -5), V3(0, -42, -5), k));
      E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.topShade(1); O.pillAt('YERALTI ŞEHRİ', 540, 330, eob(seg(lt, sk - 0.05, sk + 0.3)), '#101318', '#FFD43B', 80);
    } });
    cue(st, 'whoosh'); cue(st + 0.1, 'riser', { dur: sk, gain: 0.5 }); cue(st + sk, 'impact', { gain: 0.8 }); cue(st, 'wind', { dur: end(2) - st, gain: 0.4 }); }

  // 2 · 20.000 people: people fill the rooms level by level
  { const st = cut(2), yk = rel(2, 'yirmi', 0.4);
    add({ id: 'S02', at: st, note: 'mid-levels, little people fill the rooms, 20.000 KİŞİ', fov: 38, draw(lt, d, t, blit) {
      D.people(seg(lt, yk - 0.2, d - 0.3)); shoot(V3(10, -22, 74), V3(-2, -27, 66), V3(0, -30, -5), lt / d);
      E.render(D.scene, cam, CUTL); blit(); D.people(1); O.flash(lt);
      O.factCard('KAPASİTE', 20000, 'KİŞİ', lt - yk + 0.1, { dur: 1.0 });
    } });
    cue(st, 'whoosh'); cue(st + yk, 'slide', { dur: 1.0, gain: 0.4 }); cue(st + yk + 1.1, 'impact', { gain: 0.6 }); }

  // 3 · 1963, Nevşehir, Derinkuyu: the village on the surface at golden hour
  { const st = cut(3), bk = rel(3, 'bin', 0.3), nk = rel(3, 'nevşehir', 1.8);
    add({ id: 'S03', at: st, note: 'surface village + fairy chimneys, 1963 then NEVŞEHİR · DERİNKUYU', fov: 44, draw(lt, d, t, blit) {
      shoot(V3(-2, 16, -4), V3(-10, 7, -10), V3(-24, 2, -70), lt / d); E.render(D.scene, cam, look({ exposure: 0.82 })); blit(); O.flash(lt);
      O.topShade(1); O.pillAt('1963', 540, 320, eob(seg(lt, bk - 0.05, bk + 0.25)), '#101318', '#FFD43B', 100);
      O.pillAt('NEVŞEHİR · DERİNKUYU', 540, 470, eob(seg(lt, nk - 0.05, nk + 0.3)), '#fff', 'rgba(12,15,22,0.85)', 58);
    } });
    cue(st, 'whoosh'); cue(st, 'birds', { dur: end(3) - st + 0.2, gain: 0.5 }); cue(st + bk, 'impact', { gain: 0.6 }); cue(st + nk, 'pop'); }

  // 4 · behind the wall a dark tunnel … that goes down and down
  { const st = cut(4), hk = safeWd('hep', 4, cut(4) + 1.6) - 0.12;
    add({ id: 'S04a', at: st, note: 'basement: push through the broken wall into the dark tunnel', fov: 60, draw(lt, d, t, blit) {
      const k = eio(clamp(lt / d)); cam.position.set(lerp(0.3, 0, k), lerp(1.55, 1.2, k), lerp(4.7, -0.6, k)); cam.lookAt(0, 1.1, -6); torchAt(cam.position);
      E.render(U.scene, cam, TUNL); blit(); O.flash(lt);
    } });
    add({ id: 'S04b', at: hk, note: 'descend the winding passage, lamp niches', fov: 62, draw(lt, d, t, blit) {
      const u = lerp(0.04, 0.42, eio(clamp(lt / (d + 0.3)))), p = onPath(u, 0, 0.25), q = onPath(u + 0.05, 0, 0.1); cam.position.copy(p); cam.lookAt(q); torchAt(p);
      E.render(U.scene, cam, TUNL); blit(); O.flash(lt, 0.15);
      O.pillAt('AŞAĞI, HEP AŞAĞI', 540, 330, eob(seg(lt, 0.15, 0.45)), '#101318', '#FFD43B', 62);
    } });
    cue(st, 'whoosh'); cue(st + 0.3, 'thud', { gain: 0.6 }); cue(hk, 'riser', { dur: end(4) - hk, gain: 0.5 }); cue(st, 'wind', { dur: end(4) - st + 0.2, gain: 0.6 }); }

  // 5 · carved into soft tuff (volcanic ash): close slide along the cut face
  { const st = cut(5), vk = rel(5, 'volkanik', 0.7), tk = rel(5, 'tüfe', 2.4);
    add({ id: 'S05', at: st, note: 'close slide along the carved tuff face, callout TÜF', fov: 48, draw(lt, d, t, blit) {
      shoot(V3(4, -16, 14), V3(16, -19, 12), V3(10, -20, -4), lt / d); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.topShade(1); O.pillAt('VOLKANİK KÜL', 540, 330, eob(seg(lt, vk - 0.05, vk + 0.3)), '#101318', '#FFD43B', 66);
      const [px, py] = screen(V3(12.5, -18.5, 0.02), cam); O.callout('YUMUŞAK TÜF', 540, 520, clamp(px, 120, 960), clamp(py, 640, 1200), seg(lt, tk - 0.3, tk + 0.3));
    } });
    cue(st, 'whoosh'); cue(st + vk, 'pop'); cue(st + tk, 'pop', { gain: 0.6 }); cue(st, 'wind', { dur: end(7) - st, gain: 0.4 }); }

  // 6-7 · 85 m deep and at least 18 levels: the whole cut-away with a ruler, then the level ticks
  const fullCam = (k) => { cam.position.set(lerp(6, 2, k), lerp(-40, -43, k), lerp(176, 168, k)); cam.lookAt(0, -43, -5); };
  const A6 = end(6) - cut(6), A67 = end(7) - cut(6);
  { const st = cut(6), sk = rel(6, 'seksen', 1.0);
    add({ id: 'S06', at: st, note: 'whole city, ruler 0 → 85 m', fov: 36, draw(lt, d, t, blit) {
      fullCam(lt / A67); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      const [, y0] = screen(V3(-30, 0, 0), cam), [x1, y1] = screen(V3(-30, -85, 0), cam), kr = seg(lt, sk - 0.3, sk + 0.9);
      O.ruler(clamp(x1 - 70, 90, 400), y1, y0, kr, `${Math.round(85 * eio(kr))} m`);
    } });
    cue(st, 'whoosh'); cue(st + sk - 0.2, 'slide', { dur: 1.1, gain: 0.5 }); cue(st + sk + 0.9, 'impact', { gain: 0.7 }); }
  { const st = cut(7), ok = rel(7, 'on', 0.5);
    add({ id: 'S07', at: st, note: 'same frame, 18 level ticks light up, EN AZ 18 KAT', fov: 36, draw(lt, d, t, blit) {
      fullCam((lt + A6) / A67); E.render(D.scene, cam, CUTL); blit();
      const ys = D.LV.map((l) => screen(V3(-29, l.floor + 1.5, 0), cam)[1]), n = Math.floor(lerp(0, 18.99, seg(lt, 0.05, ok + 0.45)));
      const [lx] = screen(V3(-30, 0, 0), cam); O.levelTicks(ys, n, clamp(lx - 60, 80, 400));
      O.factCard('EN AZ', 18, 'KAT', lt - ok + 0.15, { dur: 0.6, y: 330 });
    } });
    for (let i = 0; i < 18; i++) cue(st + 0.05 + i * (ok + 0.4) / 18, 'tock', { gain: 0.3 }); cue(st + ok + 0.5, 'impact', { gain: 0.6 }); }

  // 8 · stables, kitchens, wine presses, churches: one close-up per word
  { const W8 = [['ahırlar', 'AHIRLAR', D.R.stable, 0.6], ['mutfaklar', 'MUTFAKLAR', D.R.kitchen, 1.3], ['şarap', 'ŞARAP PRESLERİ', D.R.wine, 2.0], ['kiliseler', 'KİLİSELER', D.R.church, 3.0]];
    W8.forEach(([w, name, r, fb], j) => {
      const at = j === 0 ? cut(8) : safeWd(w, 8, cut(8) + fb) - 0.12, wk = safeWd(w, 8, cut(8) + fb) - at, s = j % 2 ? -1 : 1;
      add({ id: `S08${'abcd'[j]}`, at, note: `room close-up: ${name}`, fov: 50, draw(lt, d, t, blit) {
        const k = clamp(lt / Math.max(d, 0.6)); shoot(V3(r.cx + s * 3.2, r.floor + 2.2, 7.5), V3(r.cx + s * 1.2, r.floor + 1.8, 6.2), V3(r.cx, r.floor + 1.0, -6.5), k);
        E.render(D.scene, cam, look({ bloom: 0.5, bloomThreshold: 0.7, exposure: 0.85 })); blit(); O.flash(lt, 0.15);
        O.topShade(1); O.pillAt(name, 540, 330, eob(seg(lt, wk - 0.05, wk + 0.25)), '#101318', '#FFD43B', 72);
      } });
      cue(at, 'whoosh', { gain: 0.7 }); cue(at + wk, 'pop');
    }); }

  // 9 · like ask: drift over the lit rooms, BEĞEN chip
  { const st = cut(9);
    add({ id: 'S09', at: st, note: 'drift over the busy upper levels, like chip', fov: 40, draw(lt, d, t, blit) {
      shoot(V3(-14, -10, 52), V3(-4, -14, 48), V3(-6, -16, -5), lt / d); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.likeChip(lt - 0.1, 540, 1150);
    } });
    cue(st, 'whoosh'); cue(st + 0.15, 'pop', { gain: 0.7 }); cue(st + 0.55, 'sparkle', { dur: 0.8, gain: 0.6 }); }

  // 10 · 50+ air shafts: look straight up the main shaft to the sky
  { const st = cut(10), ek = rel(10, 'elliden', 0.1);
    add({ id: 'S10', at: st, note: 'rise up the main air shaft towards the daylight, 50+ HAVA BACASI', fov: 40, draw(lt, d, t, blit) {
      const k = eio(clamp(lt / d)); cam.position.set(D.shaftX, lerp(-82, -60, k), 9); cam.lookAt(D.shaftX, lerp(-30, 0, k), -5);
      E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.factCard('HAVA BACASI', 50, '+', lt - ek + 0.1, { dur: 0.9, y: 360 });
    } });
    cue(st, 'whoosh'); cue(st + 0.2, 'wind', { dur: end(10) - st, gain: 0.8 }); cue(st + ek + 1.0, 'impact', { gain: 0.5 }); }

  // 11 · each level closed from inside with giant rolling stone doors
  { const st = cut(11), tk = rel(11, 'taş', 0.6), ik = rel(11, 'içeriden', 1.6);
    add({ id: 'S11', at: st, note: 'in the passage: the millstone door rolls across, İÇERİDEN', fov: 52, draw(lt, d, t, blit) {
      const k = eio(seg(lt, tk - 0.1, ik + 0.4)); U.setDoor(k);
      const u = U.doorU + lerp(0.115, 0.1, lt / d), p = onPath(u, 0, 0.3); cam.position.copy(p); cam.lookAt(onPath(U.doorU - 0.01, 0, -0.1)); torchAt(p.clone().add(V3(0, 0.3, 0)));
      E.render(U.scene, cam, TUNL); blit(); U.setDoor(0); O.flash(lt);
      O.topShade(1); O.pillAt('DEV TAŞ KAPI', 540, 330, eob(seg(lt, tk - 0.05, tk + 0.3)), '#101318', '#FFD43B', 66);
      O.pillAt('İÇERİDEN KAPANIR', 540, 460, eob(seg(lt, ik - 0.05, ik + 0.3)), '#fff', '#D62839', 56);
    } });
    cue(st, 'whoosh'); cue(st + tk - 0.1, 'slide', { dur: ik - tk + 0.5, gain: 0.7 }); cue(st + ik + 0.4, 'slam', { gain: 0.9 }); }

  // 12 · the first rooms ~2.700 years ago, maybe the Phrygians
  { const st = cut(12), ik = rel(12, 'iki', 1.2), fk = rel(12, 'frigler', 2.6);
    add({ id: 'S12', at: st, note: 'upper levels close to the surface, 2.700 YIL ÖNCE · FRİGLER?', fov: 44, draw(lt, d, t, blit) {
      shoot2(V3(-24, -2, 40), V3(-8, -6, 44), V3(-16, -6, -5), V3(-6, -9, -5), lt / d); E.render(D.scene, cam, look({ warm: 0.08, bloom: 0.45, bloomThreshold: 0.75, exposure: 0.82 })); blit(); O.flash(lt);
      const k = seg(lt, ik - 0.1, ik + 0.9); if (k > 0) O.yearCounter(2700 * eio(k), clamp(k * 4), 320, lt > fk - 0.05 ? 'YIL ÖNCE · FRİGLER?' : 'YIL ÖNCE');
    } });
    cue(st, 'whoosh'); cue(st + ik, 'slide', { dur: 0.9, gain: 0.4 }); cue(st + ik + 0.95, 'impact', { gain: 0.5 }); cue(st + fk, 'pop'); }

  // 13-14 · an ~8 km tunnel to Kaymaklı: aerial over the plain, the glowing line runs out to the second city
  const A13 = end(13) - cut(13), A1314 = end(14) - cut(13);
  const air = (k) => { const e = eio(clamp(k)); cam.position.copy(lerpV(V3(-25, 165, -30), V3(15, 190, -130), e)); cam.lookAt(lerpV(V3(28, 0, -125), V3(58, 0, -250), e)); };
  { const st = cut(13), tk = rel(13, 'tünelle', 1.6), sk = rel(13, 'sekiz', 0.6);
    add({ id: 'S13', at: st, note: 'aerial: the tunnel line grows from Derinkuyu, 8 KM', fov: 46, draw(lt, d, t, blit) {
      D.beacons(true, false); D.tunnel(seg(lt, 0.2, A1314 - 0.4) * 1.0); air(lt / A1314);
      E.render(D.scene, cam, look({ bloom: 0.6, bloomThreshold: 0.7, exposure: 0.74 })); blit(); D.beacons(false, false); D.tunnel(0); O.flash(lt);
      O.topShade(1); O.pillAt('~8 KM TÜNEL', 540, 330, eob(seg(lt, sk - 0.05, sk + 0.3)), '#101318', '#FFD43B', 76);
      const [dx, dy] = screen(V3(5, 4, -5), cam); if (dy < 1300 && dy > 560) O.pillAt('DERİNKUYU', clamp(dx, 220, 860), dy - 90, eob(seg(lt, 0.2, 0.5)), '#fff', 'rgba(12,15,22,0.85)', 44);
    } });
    cue(st, 'whoosh'); cue(st + 0.2, 'riser', { dur: A1314 - 0.4, gain: 0.45 }); cue(st + sk, 'pop'); cue(st, 'wind', { dur: A1314 + 0.2, gain: 0.5 }); }
  { const st = cut(14), kk = rel(14, 'kaymaklı', 0.1);
    add({ id: 'S14', at: st, note: 'line reaches Kaymaklı, its beacon lights, KAYMAKLI', fov: 46, draw(lt, d, t, blit) {
      const lt2 = lt + A13; D.beacons(true, lt > kk + 0.3); D.tunnel(seg(lt2, 0.2, A1314 - 0.4)); air(lt2 / A1314);
      E.render(D.scene, cam, look({ bloom: 0.6, bloomThreshold: 0.7, exposure: 0.74 })); blit(); D.beacons(false, false); D.tunnel(0);
      O.topShade(1); O.pillAt('~8 KM TÜNEL', 540, 330, 1, '#101318', '#FFD43B', 76);
      const [kx, ky] = screen(V3(D.KAY.x, D.hf(D.KAY.x, D.KAY.z) + 6, D.KAY.z), cam); O.pillAt('KAYMAKLI', clamp(kx, 220, 860), clamp(ky - 110, 560, 1200), eob(seg(lt, kk + 0.3, kk + 0.6)), '#101318', '#FFD43B', 60);
    } });
    cue(st + kk + 0.3, 'impact', { gain: 0.7 }); cue(st + kk + 0.35, 'sparkle', { dur: 1.2, gain: 0.6 }); }

  // 15 · closing question: warm orbit over the lit city
  { const st = cut(15), yk = rel(15, 'yorumlara', 1.6);
    add({ id: 'S15', at: st, note: 'warm orbit over the city, BİR GECE KALIR MIYDIN?', fov: 38, draw(lt, d, t, blit) {
      const a = lerp(-0.3, 0.05, eio(lt / d)); cam.position.set(Math.sin(a) * 110, -30, Math.cos(a) * 110 - 5); cam.lookAt(0, -34, -5);
      E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.hookTitle(lt, 'BİR GECE', 'KALIR MIYDIN?', 300, 130);
      O.pillAt('YORUMLARA YAZ', 540, 1180, eob(seg(lt, yk - 0.05, yk + 0.3)), '#101318', '#FFD43B', 60);
    } });
    cue(st, 'whoosh'); cue(st + 0.15, 'impact', { gain: 0.5 }); cue(st + yk, 'pop'); }

  // 16 · closer + subscribe: end card over a slow rise to the surface
  { const st = cut(16);
    add({ id: 'S16', at: st, note: 'slow rise to the house on the surface, end card', fov: 44, draw(lt, d, t, blit) {
      shoot2(V3(-4, -30, 70), V3(-8, -4, 52), V3(-6, -34, -5), V3(-12, -6, -5), lt / d); E.render(D.scene, cam, CUTL); blit(); O.flash(lt);
      O.endCard(lt - 0.1, '@rota360tr', 700);
    } });
    cue(st, 'whoosh'); [0.2, 0.35, 0.5].forEach((x) => cue(st + x, 'pop', { gain: 0.5 })); cue(T.dur - 1.3, 'chime', { gain: 0.6 }); cue(st, 'wind', { dur: T.dur - st, gain: 0.4 }); }

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

// ═════════════════════════ 8 · GÖBEKLİTEPE (golden hour on the Şanlıurfa mound) · units = 1 m ═════════════════════════
/** carved-relief textures for a T-pillar face: kind = 'fox' | 'boar' | 'vulture' | 'arms' | 'plain'. Returns { map, bump } */
export function reliefTex(kind, seed = 1) {
  const S = 512, mk = () => { const c = document.createElement('canvas'); c.width = 256; c.height = S; return c; };
  const hc = mk(), h = hc.getContext('2d');
  h.fillStyle = '#7a7a7a'; h.fillRect(0, 0, 256, S);
  for (let i = 0; i < 1400; i++) { const v = 105 + Math.floor(rnd(i * 3 + seed) * 40); h.fillStyle = `rgba(${v},${v},${v},0.25)`; h.beginPath(); h.arc(rnd(i * 5 + seed) * 256, rnd(i * 7 + seed) * S, 0.8 + rnd(i * 11) * 2.2, 0, TAU); h.fill(); }
  h.filter = 'blur(2.5px)'; h.fillStyle = '#e8e8e8'; h.strokeStyle = '#e8e8e8'; h.lineCap = 'round'; h.lineJoin = 'round';
  const P = (pts) => { h.beginPath(); h.moveTo(...pts[0]); for (const p of pts.slice(1)) h.lineTo(...p); h.closePath(); h.fill(); };
  if (kind === 'fox') { // leaping fox, head down, bushy tail up
    h.save(); h.translate(128, 300); h.rotate(-0.25);
    h.beginPath(); h.ellipse(0, 0, 70, 30, 0, 0, TAU); h.fill();
    P([[55, -10], [105, 5], [118, 25], [95, 22], [60, 20]]); P([[70, -18], [80, -45], [88, -15]]); P([[86, -12], [100, -38], [102, -6]]);
    h.lineWidth = 13; for (const [x, a] of [[-45, 0.3], [-25, -0.2], [30, 0.25], [48, -0.15]]) { h.beginPath(); h.moveTo(x, 15); h.lineTo(x + Math.sin(a) * 55, 15 + 55); h.stroke(); }
    h.lineWidth = 24; h.beginPath(); h.moveTo(-60, -10); h.quadraticCurveTo(-110, -60, -80, -120); h.stroke(); h.restore();
    h.lineWidth = 6; for (let k = 0; k < 4; k++) { h.beginPath(); h.moveTo(70 + k * 30, 80); h.lineTo(85 + k * 30, 100); h.stroke(); }
  } else if (kind === 'boar') { // bristly boar
    h.save(); h.translate(125, 300);
    h.beginPath(); h.ellipse(0, 0, 82, 42, 0, 0, TAU); h.fill(); P([[60, -30], [112, -5], [118, 18], [70, 30]]);
    h.lineWidth = 8; h.beginPath(); h.moveTo(100, 12); h.quadraticCurveTo(112, -12, 98, -24); h.stroke();
    for (let k = 0; k < 9; k++) P([[-62 + k * 14, -34], [-56 + k * 14, -58 - (k % 2) * 8], [-50 + k * 14, -36]]);
    h.lineWidth = 15; for (const x of [-55, -32, 35, 55]) { h.beginPath(); h.moveTo(x, 25); h.lineTo(x, 80); h.stroke(); }
    P([[-80, -5], [-104, -18], [-96, 4]]); h.restore();
  } else if (kind === 'vulture') { // spread-wing vulture with a disc
    h.save(); h.translate(128, 230);
    h.beginPath(); h.ellipse(0, 20, 26, 60, 0, 0, TAU); h.fill();
    for (const s of [-1, 1]) P([[s * 18, -10], [s * 110, -60], [s * 118, -30], [s * 100, 10], [s * 70, 40], [s * 22, 40]]);
    h.lineWidth = 5; h.strokeStyle = '#7a7a7a'; for (const s of [-1, 1]) for (let k = 0; k < 5; k++) { h.beginPath(); h.moveTo(s * (30 + k * 16), -12 - k * 7); h.lineTo(s * (40 + k * 16), 30 - k * 2); h.stroke(); }
    h.beginPath(); h.arc(0, -42, 16, 0, TAU); h.fill(); P([[8, -48], [30, -36], [10, -30]]);
    P([[-20, 75], [0, 120], [20, 75]]); h.beginPath(); h.arc(60, 150, 26, 0, TAU); h.fill(); h.restore();
  } else if (kind === 'arms') { // the central pillars: arms, hands over a belt, a fox stole
    h.lineWidth = 30; for (const x of [40, 216]) { h.beginPath(); h.moveTo(x, 70); h.lineTo(x, 300); h.quadraticCurveTo(x, 330, 128 + (x < 128 ? -10 : 10), 336); h.stroke(); }
    h.lineWidth = 10; for (let k = 0; k < 5; k++) { h.beginPath(); h.moveTo(98 - k * 2, 322 + k * 4); h.lineTo(120, 340 + k); h.stroke(); h.beginPath(); h.moveTo(158 + k * 2, 322 + k * 4); h.lineTo(136, 340 + k); h.stroke(); }
    h.fillRect(20, 360, 216, 28); for (let k = 0; k < 8; k++) { h.beginPath(); h.moveTo(30 + k * 28, 392); h.lineTo(44 + k * 28, 392); h.lineTo(37 + k * 28, 412); h.fill(); }
    P([[110, 400], [146, 400], [138, 480], [118, 480]]);
  }
  h.filter = 'none';
  const cc = mk(), c = cc.getContext('2d');
  const g = c.createLinearGradient(0, 0, 0, S); g.addColorStop(0, '#E9DCC2'); g.addColorStop(1, '#CDBB9A'); c.fillStyle = g; c.fillRect(0, 0, 256, S);
  c.globalAlpha = 0.35; c.globalCompositeOperation = 'multiply'; c.drawImage(hc, 0, 0); c.globalAlpha = 0.6; c.filter = 'brightness(0.55)'; c.drawImage(hc, 5, 6); c.filter = 'none'; c.globalCompositeOperation = 'screen'; c.globalAlpha = 0.55; c.drawImage(hc, -2, -2); c.globalCompositeOperation = 'source-over'; c.globalAlpha = 1;
  for (let i = 0; i < 60; i++) { c.fillStyle = `rgba(120,100,70,${0.04 + rnd(i * 13 + seed) * 0.06})`; c.beginPath(); c.ellipse(rnd(i * 17 + seed) * 256, rnd(i * 19 + seed) * S, 6 + rnd(i) * 18, 3 + rnd(i * 3) * 8, rnd(i * 5) * 3, 0, TAU); c.fill(); }
  const map = new THREE.CanvasTexture(cc); map.colorSpace = THREE.SRGBColorSpace; const bump = new THREE.CanvasTexture(hc);
  return { map, bump };
}
/** a T-pillar (shaft + head). Broad faces = ±x, narrow front = +z. face = relief kind on both broad faces */
export function tPillar(h = 4, face = 'plain', seed = 1) {
  const g = new THREE.Group(), R = reliefTex(face, seed), plainM = std('#D9C9A8', 0.95, { flatShading: false });
  const side = new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 0.95, map: R.map, bumpMap: R.bump, bumpScale: 6 });
  const shaftW = h * 0.12, shaftD = h * 0.24, headH = h * 0.2, headD = h * 0.44;
  const shaft = sh(new THREE.Mesh(new THREE.BoxGeometry(shaftW, h - headH, shaftD), [side, side, plainM, plainM, plainM, plainM])); shaft.position.y = (h - headH) / 2; g.add(shaft);
  const head = sh(new THREE.Mesh(new THREE.BoxGeometry(shaftW * 1.15, headH, headD), plainM)); head.position.set(0, h - headH / 2, headD * 0.18); g.add(head);
  return g;
}
export function gobekli(E) {
  const scene = base(E, { sky: [[0, '#3C5E98'], [0.5, '#A8B0C4'], [0.8, '#F2BE8C'], [1, '#FFD9A6']], fog: '#E8C49C', near: 90, far: 900, env: 0.38 });
  const S = sun(scene, { dir: [-0.8, 0.22, -0.55], color: '#FFCB92', I: 3.4, box: 40, target: [-8, 10, -4], discSize: 22, discCol: '#FFE6BE' }); hemi(scene, '#D7DDF2', '#9C7A55', 1.0);
  // excavated enclosures (centre x,z, radius, n ring pillars) on the mound top; floor 4 m under the surface
  const ENC = [{ x: 0, z: 0, r: 10, n: 12, name: 'D' }, { x: -23, z: 5, r: 8.5, n: 10, name: 'C' }, { x: -10, z: -21, r: 6.5, n: 8, name: 'B' }, { x: -29, z: -15, r: 5.5, n: 7, name: 'A' }];
  const mound = (x, z) => 15 * Math.exp(-((x + 10) ** 2 + (z + 5) ** 2) / (130 * 130)) + 2.0 * fbm(x * 0.01, z * 0.01) + 1.2 * fbm(x * 0.05, z * 0.05);
  ENC.forEach((e) => { e.top = mound(e.x, e.z); e.floor = e.top - 4; });
  const hf = (x, z) => { let y = mound(x, z); for (const e of ENC) { const d = Math.hypot(x - e.x, z - e.z); const k = 1 - smooth(e.r + 0.4, e.r + 4.5, d); y = lerp(y, e.floor - 0.2, k); } return y; };
  function lerp(a, b, k) { return a + (b - a) * k; }
  scene.add(terrain(1400, 260, hf, (x, y, z, s) => {
    const n = fbm(x * 0.03, z * 0.03), dirt = col('#B98E62'), grass = col('#CDAA6A').lerp(col('#A88B4F'), 0.5 + 0.5 * n).lerp(col('#E0C185'), 0.3 * fbm(x * 0.2, z * 0.2) + 0.15);
    let pit = 0; for (const e of ENC) pit = Math.max(pit, 1 - smooth(e.r + 2, e.r + 6, Math.hypot(x - e.x, z - e.z)));
    return grass.lerp(dirt, Math.max(pit, Math.min(1, s * 2.2)));
  }, { cx: -10, cz: -5 }));
  // dry-stone ring walls + T-pillars set into them, two big central pillars in each
  const stones = [], pillars = [], soil = [];
  ENC.forEach((e, ei) => {
    const per = Math.floor(TAU * e.r / 0.7);
    for (let L = 0; L < 9; L++) for (let k = 0; k < per; k++) { const a = (k + (L % 2) * 0.5) / per * TAU, y = e.floor + 0.22 + L * 0.42; if (y > e.top - 0.2) continue; stones.push({ p: [e.x + Math.cos(a) * (e.r + 0.55), y, e.z + Math.sin(a) * (e.r + 0.55)], s: [0.62 + rnd(k * 3 + L) * 0.2, 0.36 + rnd(k + L * 7) * 0.08, 0.9], r: [0, -a, 0], c: rnd(k * 5 + L * 3 + ei) > 0.5 ? '#C9B28C' : '#B39A74' }); }
    for (let k = 0; k < e.n; k++) {
      const a = k / e.n * TAU + ei, kinds = ['fox', 'boar', 'vulture', 'plain', 'plain'], p = tPillar(3.6 + rnd(k * 9 + ei) * 0.6, kinds[(k + ei) % 5], k + ei * 20);
      p.position.set(e.x + Math.cos(a) * (e.r - 0.2), e.floor - 0.2, e.z + Math.sin(a) * (e.r - 0.2)); p.rotation.y = -a - Math.PI / 2 + Math.PI; p.lookAt(e.x, p.position.y, e.z); p.rotateY(0);
      scene.add(p); pillars.push({ g: p, enc: ei, kind: kinds[(k + ei) % 5] });
    }
    const cH = ei === 0 ? 5.5 : 4.6;
    for (const s of [-1, 1]) { const p = tPillar(cH, 'arms', 99 + s + ei); p.position.set(e.x + s * e.r * 0.2, e.floor - 0.2, e.z); p.rotation.y = 0; scene.add(p); pillars.push({ g: p, enc: ei, kind: 'center', h: cH }); }
    const f = new THREE.Mesh(new THREE.CircleGeometry(e.r + 0.9, 48), std('#B58C60', 1)); f.rotation.x = -Math.PI / 2; f.position.set(e.x, e.floor, e.z); f.receiveShadow = true; f.visible = false; scene.add(f); soil.push(f);
  });
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), std('#ffffff', 1, { flatShading: true }), stones));
  // scattered limestone rubble + a few lone pistachio trees on the plain
  const rub = []; for (let i = 0; i < 220; i++) { const x = -60 + rnd(i * 3) * 100, z = -50 + rnd(i * 5) * 90; rub.push({ p: [x, hf(x, z) + 0.1, z], s: [0.3 + rnd(i) * 0.6, 0.25, 0.3 + rnd(i * 7) * 0.5], r: [0, rnd(i) * 3, 0], c: '#D2BE98' }); }
  scene.add(inst(new THREE.DodecahedronGeometry(1, 0), std('#ffffff', 1, { flatShading: true }), rub));
  const tr = []; for (let i = 0; i < 40; i++) { const a = rnd(i * 31) * TAU, r = 120 + rnd(i * 37) * 260, x = Math.cos(a) * r, z = Math.sin(a) * r; tr.push({ p: [x, hf(x, z), z], w: 3 + rnd(i) * 2, h: 5 + rnd(i * 3) * 2, c: '#8C9A55' }); }
  scene.add(trees(tr));
  // buried enclosures known from geophysics (for overlay rings): 16 more on the mound
  const buried = []; for (let i = 0; buried.length < 16 && i < 4000; i++) { const x = -62 + rnd(i * 7 + 1) * 90, z = -52 + rnd(i * 11 + 2) * 80, r = 5 + rnd(i * 3) * 4;
    if ([...ENC, ...buried].some((e) => Math.hypot(e.x - x, e.z - z) < e.r + r + 4)) continue; buried.push({ x, z, r, y: mound(x, z) }); }
  const D = ENC[0];
  return {
    scene, sunLight: S, ENC, pillars, buried, hf, center: new THREE.Vector3(D.x, D.floor + 2.5, D.z),
    /** fill the pits with soil up to k (0 = excavated, 1 = only the pillar tops show, as in 1963) */
    fill(k) { soil.forEach((f, i) => { const e = ENC[i]; f.visible = k > 0.001; f.position.y = e.floor + k * 3.3; }); },
    update() {},
  };
}

// ═════════════════════════ 9 · THE TIME ROAD: a glowing timeline into the past (dusk) · 1.000 yıl = 40 m ═════════════════════════
function textSprite(txt, { size = 96, color = '#FFFFFF', bg = null, w = 512, h = 160 } = {}) {
  const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d');
  if (bg) { g.fillStyle = bg; g.beginPath(); g.roundRect(8, 8, w - 16, h - 16, (h - 16) / 2); g.fill(); }
  g.font = `900 ${size}px Inter`; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = color; g.fillText(txt, w / 2, h / 2 + 4);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false, fog: false })); s.scale.set(w / 100, h / 100, 1); return s;
}
export const YR = 0.04; // metres of road per year
export function timeRoad(E) {
  const scene = base(E, { sky: [[0, '#0E1633'], [0.55, '#2D3460'], [0.82, '#B0607A'], [1, '#FFB27A']], fog: '#3A2F4E', near: 40, far: 420, env: 0.25 });
  const S = sun(scene, { dir: [0, 0.08, -1], color: '#FFB27A', I: 2.4, box: 40, target: [0, 0, -200], discSize: 30, discCol: '#FFC48E', dist: 2500 }); hemi(scene, '#7C86C8', '#3A2A30', 1.1);
  const gc = document.createElement('canvas'); gc.width = gc.height = 256; const g = gc.getContext('2d'); g.fillStyle = '#211B2C'; g.fillRect(0, 0, 256, 256); g.strokeStyle = 'rgba(160,150,220,0.25)'; g.lineWidth = 3; g.strokeRect(0, 0, 256, 256);
  const gt = new THREE.CanvasTexture(gc); gt.wrapS = gt.wrapT = THREE.RepeatWrapping; gt.repeat.set(200, 200); gt.colorSpace = THREE.SRGBColorSpace;
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(1600, 1600), std('#ffffff', 0.9, { map: gt })); ground.rotation.x = -Math.PI / 2; ground.position.z = -300; ground.receiveShadow = true; scene.add(ground);
  const glow = (c, k = 2.5) => new THREE.MeshBasicMaterial({ color: col(c).multiplyScalar(k) });
  const END = 12500 * YR, road = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.06, END + 20), glow('#FFD43B', 1.6)); road.position.set(0, 0.03, -END / 2 + 10); scene.add(road);
  const ticks = []; for (let y = 500; y <= 12000; y += 500) ticks.push({ p: [0, 0.05, -y * YR], s: [y % 1000 ? 1.6 : 3.2, 0.08, 0.22] });
  scene.add(inst(new THREE.BoxGeometry(1, 1, 1), glow('#FFE68A', 1.4), ticks, false));
  for (let y = 1000; y <= 12000; y += 1000) { const s = textSprite(`${(y / 1000).toFixed(0)}.000`, { size: 92, color: '#FFE9A8' }); s.position.set(-3.6, 0.9, -y * YR); s.scale.multiplyScalar(0.55); scene.add(s); }
  const now = textSprite('BUGÜN', { size: 84, color: '#101318', bg: '#FFD43B' }); now.position.set(0, 1.6, 0); now.scale.multiplyScalar(0.6); scene.add(now);
  // landmarks beside the road
  const sand = std('#D9AE72', 0.9, { flatShading: true }), grey = std('#9A9AA6', 0.95, { flatShading: true }), clay = std('#B07A4E', 0.95);
  const pyr = new THREE.Group(); const P1 = sh(new THREE.Mesh(new THREE.ConeGeometry(5.2, 6.2, 4), sand)); P1.position.y = 3.1; P1.rotation.y = Math.PI / 4; pyr.add(P1);
  const P2 = sh(new THREE.Mesh(new THREE.ConeGeometry(3, 3.6, 4), sand)); P2.position.set(-6, 1.8, -5); P2.rotation.y = Math.PI / 4; pyr.add(P2); pyr.position.set(8, 0, -4500 * YR); scene.add(pyr);
  const st = new THREE.Group(); for (let k = 0; k < 10; k++) { const a = k / 10 * TAU, r = 4; for (const s of [-0.45, 0.45]) { const u = sh(new THREE.Mesh(new THREE.BoxGeometry(0.7, 2.6, 0.5), grey)); u.position.set(Math.cos(a + s * 0.12) * r, 1.3, Math.sin(a + s * 0.12) * r); u.rotation.y = -a; st.add(u); }
    if (k % 1 === 0) { const l = sh(new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.45, 1.9), grey)); l.position.set(Math.cos(a) * r, 2.82, Math.sin(a) * r); l.rotation.y = -a; st.add(l); } }
  st.position.set(-8, 0, -5000 * YR); scene.add(st);
  const tc = document.createElement('canvas'); tc.width = 256; tc.height = 320; const tg = tc.getContext('2d'); tg.fillStyle = '#7a7a7a'; tg.fillRect(0, 0, 256, 320); tg.fillStyle = '#303030';
  for (let r = 0; r < 9; r++) for (let k = 0; k < 7; k++) { if (rnd(r * 9 + k) < 0.25) continue; const x = 24 + k * 32, y = 30 + r * 32; tg.beginPath(); tg.moveTo(x, y); tg.lineTo(x + 14, y + 6); tg.lineTo(x, y + 12); tg.fill(); tg.fillRect(x + 12, y + 4, 10, 3); }
  const tb = new THREE.CanvasTexture(tc), tab = new THREE.Group();
  const slab = sh(new THREE.Mesh(new THREE.BoxGeometry(2.2, 2.8, 0.45), [clay, clay, clay, clay, new THREE.MeshStandardMaterial({ color: '#C08A5C', roughness: 0.9, bumpMap: tb, bumpScale: 8 }), clay])); slab.position.y = 2.6; slab.rotation.x = -0.25; tab.add(slab);
  const ped = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.9, 1.1, 1.2, 8), grey)); ped.position.y = 0.6; tab.add(ped); tab.position.set(6.5, 0, -5200 * YR); tab.rotation.y = -0.5; scene.add(tab);
  const gob = new THREE.Group(); const hero = tPillar(5.5, 'arms', 7); gob.add(hero); for (let k = 0; k < 9; k++) { const a = k / 9 * TAU, p = tPillar(3.4, ['fox', 'boar', 'vulture'][k % 3], k); p.position.set(Math.cos(a) * 7, 0, Math.sin(a) * 7); p.lookAt(0, 0, 0); gob.add(p); }
  gob.position.set(0, 0, -11500 * YR - 4); scene.add(gob);
  const spot = new THREE.PointLight('#FFC27A', 60, 40, 1.6); spot.position.set(3, 7, -11500 * YR + 4); scene.add(spot);
  return { scene, sunLight: S, at: (yrs) => -yrs * YR, pyr: pyr.position, sth: st.position, tab: tab.position, gob: gob.position, update() {} };
}

// ═════════════════════════ 10 · DERİNKUYU: the underground city as a cut-away "ant farm" · units = 1 m ═════════════════════════
// The earth is cut open along the plane z = 0: 1 m tuff voxels (z -10…0) with the 18 carved levels, stairs and the air shaft as voids,
// a warm-lit back wall at z = -9.5, the Cappadocian village on the surface (y = 0) behind the cut, Kaymaklı far away (z ≈ -330).
export function derinkuyu(E) {
  const scene = base(E, { sky: [[0, '#3F63A0'], [0.5, '#A9AFC8'], [0.8, '#F3BE8E'], [1, '#FFDAA8']], fog: '#E2BC96', near: 520, far: 2600, env: 0.22 });
  const S = sun(scene, { dir: [-0.35, 0.75, 0.75], color: '#FFD3A0', I: 3.1, box: 75, target: [0, -40, -5], discSize: 22, discCol: '#FFE6BE', dist: 2500, disc: false });
  hemi(scene, '#C9C2E0', '#6E4E38', 0.5);
  const X0 = -30, X1 = 30, Y0 = -90, ZB = -9.5;
  const NX = X1 - X0, NY = -Y0;
  const grid = new Uint8Array(NX * NY); // 1 = carved
  const id = (x, y) => (x - X0) + (-y - 1) * NX; // cell (x … x+1, y-1 … y)
  const carve = (xa, xb, ya, yb) => { for (let x = Math.min(xa, xb); x < Math.max(xa, xb); x++) for (let y = Math.max(ya, yb); y > Math.min(ya, yb); y--) if (x >= X0 && x < X1 && y <= 0 && y > Y0) grid[id(x, y)] = 1; };
  // 18 levels: floor of level i at y = -5 - 4.5 i (rounded), rooms 3 m high, corridors 2 m
  const LV = [], ROOMS = [];
  for (let i = 0; i < 18; i++) {
    const fl = -Math.round(5 + i * 4.5), lv = { i, floor: fl, rooms: [] };
    let x = -27 + Math.floor(rnd(i * 7 + 1) * 4); const xs = [];
    while (x < 24) { const w = 4 + Math.floor(rnd(i * 13 + x) * 6); if (x + w > 27) break; xs.push([x, x + w]); x += w + 3 + Math.floor(rnd(i * 5 + x) * 6); }
    xs.forEach(([a, b], k) => { carve(a, b, fl, fl + 3); const r = { lv: i, x0: a, x1: b, floor: fl, cx: (a + b) / 2, k }; lv.rooms.push(r); ROOMS.push(r); if (k) carve(xs[k - 1][1], a, fl, fl + 2); });
    LV.push(lv);
  }
  // stairs between levels: a diagonal 1-wide, 2-high passage from the end of level i to level i+1
  for (let i = 0; i < 17; i++) { const a = LV[i], b = LV[i + 1], dir = i % 2 ? -1 : 1, r = dir > 0 ? a.rooms[a.rooms.length - 1] : a.rooms[0];
    let x = dir > 0 ? r.x1 - 1 : r.x0, y = a.floor; const tgt = b.floor;
    for (let s = 0; y > tgt && s < 12; s++) { y -= 1; x -= dir; carve(x, x + 1, y, y + 3); }
    carve(Math.min(x, x - dir * 3), Math.max(x + 1, x + 1 - dir * 3), tgt, tgt + 2); }
  // the house basement + entrance stair from the surface (house at x ≈ -15)
  carve(-17, -12, -3, 0); for (let s = 0; s < 3; s++) carve(-12 + s, -11 + s, -3 - s, -s);
  // main ventilation shaft (2 m) from the surface to the bottom, plus a second one
  carve(4, 6, Y0 + 6, 0); carve(-23, -22, -50, 0);
  // voxels: instanced boxes with tuff colours (bands + noise, darker with depth)
  const cells = [], front = [];
  const tuff = (x, y) => { const band = 0.5 + 0.5 * Math.sin(y * 0.55 + fbm(x * 0.06, y * 0.06) * 3); const d = Math.min(1, -y / 90);
    return col('#EAD2B2').lerp(col('#D9AE88'), band * 0.55).lerp(col('#C79A80'), 0.25 * (fbm(x * 0.2, y * 0.2) + 0.5)).lerp(col('#9C7A64'), d * 0.45); };
  for (let x = X0; x < X1; x++) for (let y = 0; y > Y0; y--) {
    const c = tuff(x, y), j = 0.96 + rnd(x * 31 + y * 17) * 0.08; c.multiplyScalar(j);
    if (!grid[id(x, y)]) cells.push({ p: [x + 0.5, y - 0.5, (-10 + -1) / 2], s: [1, 1, 9], c: '#' + c.getHexString() });
    front.push({ p: [x + 0.5, y - 0.5, -0.5], s: [1, 1, 1], c: '#' + c.clone().multiplyScalar(0.92).getHexString() });
  }
  const box = new THREE.BoxGeometry(1, 1, 1), tm = std('#ffffff', 0.97);
  const vox = inst(box, tm, cells); scene.add(vox);
  // the front 1 m layer (z -1…0), carved like the rest — it reads as the cut face
  const frontCarved = front.filter((f, k) => { const x = Math.floor(f.p[0]), y = Math.ceil(f.p[1]); return !grid[id(x, y)]; });
  scene.add(inst(box, tm, frontCarved));
  // the solid earth around the cut-away block
  const earth = std('#C9A585', 0.98);
  for (const [cx, w] of [[X0 - 100, 200], [X1 + 100, 200]]) { const m = sh(new THREE.Mesh(new THREE.BoxGeometry(w, 120, 10), earth), false); m.position.set(cx, -60, -5); scene.add(m); }
  const bot = sh(new THREE.Mesh(new THREE.BoxGeometry(460, 100, 10), earth), false); bot.position.set(0, Y0 - 50, -5); scene.add(bot);
  // warm back wall of the rooms (fake lamplight) + oil-lamp glows
  const bw = new THREE.Mesh(new THREE.PlaneGeometry(NX, NY), std('#9C6E4E', 0.95, { emissive: '#8A4A1A', emissiveIntensity: 0.42 })); bw.position.set(0, Y0 / 2, ZB); bw.receiveShadow = true; scene.add(bw);
  const lamps = []; ROOMS.forEach((r, k) => { lamps.push({ p: [r.x0 + 0.6, r.floor + 2.1, -8.8], s: 0.13 }); if (r.x1 - r.x0 > 6) lamps.push({ p: [r.x1 - 0.6, r.floor + 2.1, -8.8], s: 0.13 }); });
  const lampM = inst(new THREE.SphereGeometry(1, 10, 8), new THREE.MeshBasicMaterial({ color: col('#FFB45A').multiplyScalar(4) }), lamps, false); scene.add(lampM);
  // floors a touch darker (trodden), so each level reads
  const floors = ROOMS.map((r) => ({ p: [(r.x0 + r.x1) / 2, r.floor + 0.02, -5], s: [r.x1 - r.x0, 0.04, 8.9], c: '#9E7658' }));
  scene.add(inst(box, std('#ffffff', 1), floors, false));
  // people (tiny figures) in the rooms: count = how many are shown
  const ppl = []; ROOMS.forEach((r, k) => { const n = Math.max(1, Math.floor((r.x1 - r.x0) / 2.2)); for (let j = 0; j < n; j++) ppl.push({ p: [r.x0 + 0.8 + rnd(k * 7 + j) * (r.x1 - r.x0 - 1.6), r.floor + 0.8, -2.5 - rnd(k * 3 + j * 5) * 5.5], s: [0.32, 0.8, 0.32], c: ['#7A3B2E', '#3E5C7A', '#6B5A2E', '#5A3E6B', '#2E5A4A'][(k + j) % 5] }); });
  ppl.sort((a, b) => b.p[1] - a.p[1]);
  const pplM = inst(new THREE.CapsuleGeometry(1, 1, 4, 8), std('#ffffff', 0.8), ppl); pplM.count = 0; scene.add(pplM);
  const heads = inst(new THREE.SphereGeometry(1, 10, 8), std('#E2B48C', 0.7), ppl.map((p) => ({ p: [p.p[0], p.p[1] + 1.05, p.p[2]], s: 0.27 }))); heads.count = 0; scene.add(heads);
  // furnished rooms for the close-ups: stable (level 1), kitchen (level 3), wine press (level 2), church (level 4)
  const pick = (lv, k = 0) => LV[lv].rooms[Math.min(k, LV[lv].rooms.length - 1)];
  const R = { stable: pick(1, 0), kitchen: pick(3, 1), wine: pick(2, 1), church: pick(4, 0) };
  { const r = R.stable, y = r.floor; // troughs + two animals
    scene.add(inst(box, std('#A98463', 1), [{ p: [r.cx, y + 0.3, -8.4], s: [r.x1 - r.x0 - 1, 0.6, 0.7] }]));
    for (const [dx, c] of [[-1.2, '#6B4A30'], [1.4, '#E8E0D0']]) { const g = new THREE.Group(); const bd = sh(new THREE.Mesh(new THREE.CapsuleGeometry(0.45, 1.1, 4, 10), std(c, 0.9))); bd.rotation.z = Math.PI / 2; bd.position.y = 0.95; g.add(bd);
      const hd = sh(new THREE.Mesh(new THREE.SphereGeometry(0.3, 10, 8), std(c, 0.9))); hd.position.set(0.95, 1.2, 0); g.add(hd);
      for (const lx of [-0.5, 0.5]) for (const lz of [-0.22, 0.22]) { const l = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.7, 6), std(c, 0.9))); l.position.set(lx, 0.35, lz); g.add(l); }
      g.position.set(r.cx + dx, y, -6.8); g.rotation.y = dx < 0 ? 0.3 : Math.PI - 0.3; scene.add(g); } }
  { const r = R.kitchen, y = r.floor; // tandır oven with glowing mouth + jars
    const ov = sh(new THREE.Mesh(new THREE.CylinderGeometry(0.75, 0.9, 0.8, 18), std('#9B6B4A', 0.95))); ov.position.set(r.cx, y + 0.4, -6.5); scene.add(ov);
    const fire = new THREE.Mesh(new THREE.CircleGeometry(0.55, 18), new THREE.MeshBasicMaterial({ color: col('#FF8A2A').multiplyScalar(4) })); fire.rotation.x = -Math.PI / 2; fire.position.set(r.cx, y + 0.81, -6.5); scene.add(fire);
    scene.add(inst(new THREE.SphereGeometry(1, 12, 10), std('#B5714A', 0.8), [-1.6, -2.1, 1.7, 2.2].map((dx) => ({ p: [r.cx + dx, y + 0.45, -8.3], s: [0.32, 0.45, 0.32] })))); }
  { const r = R.wine, y = r.floor; // treading basin + channel + collecting pit with dark red wine
    scene.add(inst(box, std('#C9A27E', 1), [{ p: [r.cx - 0.8, y + 0.35, -6.5], s: [2.4, 0.7, 2.4] }, { p: [r.cx + 1.4, y + 0.2, -6.5], s: [1.2, 0.4, 1.2] }]));
    const wn = new THREE.Mesh(new THREE.PlaneGeometry(2.0, 2.0), std('#5A0F22', 0.3, { emissive: '#3A0612', emissiveIntensity: 0.5 })); wn.rotation.x = -Math.PI / 2; wn.position.set(r.cx - 0.8, y + 0.72, -6.5); scene.add(wn);
    const g2 = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.9), std('#5A0F22', 0.3)); g2.rotation.x = -Math.PI / 2; g2.position.set(r.cx + 1.4, y + 0.41, -6.5); scene.add(g2); }
  { const r = R.church, y = r.floor; // carved apse niches + a glowing cross
    const ap = new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.1, 2.6, 20, 1, true, 0, Math.PI), std('#E6CDAE', 0.95, { side: THREE.DoubleSide })); ap.rotation.y = Math.PI / 2; ap.position.set(r.cx, y + 1.3, -9.35); scene.add(ap);
    const cr = new THREE.MeshBasicMaterial({ color: col('#FFD08A').multiplyScalar(3) });
    const v = new THREE.Mesh(new THREE.BoxGeometry(0.16, 1.0, 0.05), cr); v.position.set(r.cx, y + 1.75, -8.6); const hz = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.16, 0.05), cr); hz.position.set(r.cx, y + 1.95, -8.6); scene.add(v, hz);
    scene.add(inst(box, std('#D4B693', 1), [-2.2, -1.3, 1.3, 2.2].filter((dx) => Math.abs(dx) < (r.x1 - r.x0) / 2).map((dx) => ({ p: [r.cx + dx, y + 0.25, -5], s: [0.5, 0.5, 4] })))); }
  for (const r of [R.stable, R.kitchen, R.wine, R.church]) { const L = new THREE.PointLight('#FFB066', 7, 9, 1.6); L.position.set(r.cx, r.floor + 2.4, -4.5); scene.add(L); }
  // surface: rolling tuff plain, flat-roofed stone village behind the cut, fairy chimneys in the distance
  const hf = (x, z) => { const k = smooth(-4, -40, z); return k * (3 * fbm(x * 0.012, z * 0.012) + 1.5 * fbm(x * 0.05, z * 0.05) + 14 * smooth(160, 420, Math.hypot(x, z + 150))); };
  const ground = terrain(1600, 240, hf, (x, y, z, s) => col('#CFAE84').lerp(col('#B08460'), 0.5 + 0.5 * fbm(x * 0.03, z * 0.03)).lerp(col('#8C8C50'), 0.9 * smooth(0.05, 0.2, fbm(x * 0.02 + 5, z * 0.02))).lerp(col('#B88866'), Math.min(1, s * 1.5)), { cz: -790 });
  scene.add(ground);
  const houses = []; for (let i = 0; i < 70; i++) { const x = -70 + rnd(i * 3) * 140, z = -14 - rnd(i * 7) * 110; if (Math.abs(x + 14.5) < 7 && z > -24) continue; const w = 4 + rnd(i * 11) * 4, d = 4 + rnd(i * 13) * 4, h = 3 + rnd(i * 17) * 3.5; houses.push({ p: [x, hf(x, z) + h / 2 - 0.2, z], s: [w, h, d], r: [0, (rnd(i * 19) - 0.5) * 0.4, 0], c: rnd(i * 23) > 0.5 ? '#E3C9A4' : '#D2B08A' }); }
  houses.push({ p: [-14.5, 2.2, -5.6], s: [7, 4.4, 7.4], r: [0, 0, 0], c: '#E6CCA6' }); // the house above the basement
  scene.add(inst(box, std('#ffffff', 0.95), houses));
  const doors = houses.map((h) => ({ p: [h.p[0], h.p[1] - h.s[1] / 2 + 1.0, h.p[2] + h.s[2] / 2 + 0.03], s: [1.0, 2.0, 0.08], r: h.r, c: '#5A3E2C' }));
  scene.add(inst(box, std('#ffffff', 0.9), doors, false));
  const prof = []; for (let k = 0; k <= 16; k++) { const v = k / 16; prof.push(new THREE.Vector2(0.18 + 0.82 * Math.pow(1 - v, 1.6) + 0.06 * Math.sin(v * 9), v)); }
  const chim = [], caps = []; for (let i = 0; i < 120; i++) { const x = -260 + rnd(i * 5) * 520, z = -150 - rnd(i * 9) * 260, y = hf(x, z), hh = 8 + rnd(i * 11) * 16, ww = 2.5 + rnd(i * 13) * 3; chim.push({ p: [x, y - 0.5, z], s: [ww, hh, ww], c: rnd(i * 17) > 0.5 ? '#E8CFAF' : '#DDB995' }); caps.push({ p: [x, y - 0.5 + hh, z], s: [ww * 0.42, ww * 0.26, ww * 0.42], c: '#6B5546' }); }
  scene.add(inst(new THREE.LatheGeometry(prof, 12), std('#ffffff', 0.95), chim), inst(new THREE.SphereGeometry(1, 12, 8), std('#ffffff', 0.9), caps));
  // shaft collar on the surface
  const collar = sh(new THREE.Mesh(new THREE.CylinderGeometry(2.0, 2.2, 0.8, 18, 1, true), std('#C9AE8A', 0.95, { side: THREE.DoubleSide }))); collar.position.set(5, 0.4, -5); scene.add(collar);
  // Kaymaklı, far away, and the tunnel between the two cities (glowing line drawn under the plain)
  const KAY = new THREE.Vector3(70, 0, -330), DER = new THREE.Vector3(5, 0, -5);
  const curve = new THREE.CatmullRomCurve3([DER.clone().setY(0.6), new THREE.Vector3(30, 0, -90), new THREE.Vector3(38, 0, -200), KAY.clone().setY(0)].map((p) => p.setY(hf(p.x, p.z) + 0.8)));
  const tg = new THREE.TubeGeometry(curve, 160, 1.6, 8, false), tube = new THREE.Mesh(tg, new THREE.MeshBasicMaterial({ color: col('#FFD43B').multiplyScalar(2.2), fog: false, transparent: true, opacity: 0.95 })); tube.geometry.setDrawRange(0, 0); scene.add(tube);
  const beacon = (p, c) => { const m = new THREE.Mesh(new THREE.CylinderGeometry(4, 4, 90, 20, 1, true), new THREE.MeshBasicMaterial({ color: col(c), transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false, fog: false, blending: THREE.AdditiveBlending })); m.position.set(p.x, hf(p.x, p.z) + 45, p.z); m.visible = false; scene.add(m); return m; };
  const bD = beacon(DER, '#FFD43B'), bK = beacon(KAY, '#FFD43B');
  return {
    scene, sunLight: S, LV, ROOMS, R, hf, KAY, DER, curve, shaftX: 5, house: new THREE.Vector3(-14.5, 0, -5.6),
    people(k) { const n = Math.round(ppl.length * Math.max(0, Math.min(1, k))); pplM.count = n; heads.count = n; },
    tunnel(k) { const n = tg.index.count; tube.geometry.setDrawRange(0, Math.floor(n * Math.max(0, Math.min(1, k)) / 48) * 48); },
    beacons(a, b) { bD.visible = a; bK.visible = b; },
    update() {},
  };
}

// ═════════════════════════ 11 · INSIDE THE TUNNEL: basement with a broken wall, then a narrow carved passage down · units = 1 m ═════════════════════════
export function tunnel(E) {
  const scene = new THREE.Scene(); scene.background = col('#0B0806'); scene.fog = new THREE.Fog('#0B0806', 4.5, 17); scene.environment = E.envMap; scene.environmentIntensity = 0.12;
  hemi(scene, '#6E5848', '#24160E', 0.35);
  const rock = (x, y, z) => col('#C9A27E').lerp(col('#A97F5E'), 0.5 + 0.5 * fbm(x * 0.7 + z * 0.3, y * 0.9)).lerp(col('#E0C29C'), 0.3 * Math.max(0, Math.sin(y * 3 + fbm(x, z) * 2)));
  // basement room: x -2…2, y 0…2.6, z 0…5 (camera end at z = 5), broken far wall at z = 0
  const room = new THREE.Mesh(new THREE.BoxGeometry(4, 2.6, 5, 8, 6, 8), std('#ffffff', 0.95, { side: THREE.BackSide, vertexColors: true }));
  { const g = room.geometry, p = g.attributes.position, C = []; for (let i = 0; i < p.count; i++) { const c = rock(p.getX(i), p.getY(i) + 1.3, p.getZ(i) + 2.5); C.push(c.r, c.g, c.b); } g.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); }
  room.position.set(0, 1.3, 2.5); room.material.side = THREE.BackSide; scene.add(room);
  // hide the room's far face: cover it with a wall that has a jagged hole
  const sh2 = new THREE.Shape(); sh2.moveTo(-2.05, -0.05); sh2.lineTo(2.05, -0.05); sh2.lineTo(2.05, 2.65); sh2.lineTo(-2.05, 2.65); sh2.closePath();
  const hole = new THREE.Path(); const N = 22; for (let k = 0; k < N; k++) { const a = k / N * TAU, r = 0.95 + 0.22 * Math.sin(k * 2.7) + 0.12 * rnd(k); const x = Math.cos(a) * r * 0.85, y = 1.15 + Math.sin(a) * r; k ? hole.lineTo(x, Math.max(0.02, y)) : hole.moveTo(x, Math.max(0.02, y)); } hole.closePath(); sh2.holes.push(hole);
  const wallG = new THREE.ExtrudeGeometry(sh2, { depth: 0.35, bevelEnabled: false }); const wall = sh(new THREE.Mesh(wallG, std('#B89270', 0.95))); wall.position.set(0, 0, -0.2); scene.add(wall);
  // rubble on the floor in front of the hole
  const rub = []; for (let i = 0; i < 26; i++) rub.push({ p: [(rnd(i * 3) - 0.5) * 2.6, 0.08, 0.3 + rnd(i * 5) * 1.4], s: 0.08 + rnd(i * 7) * 0.16, r: [rnd(i), rnd(i * 2), rnd(i * 3)], c: rnd(i * 11) > 0.5 ? '#C29A76' : '#A88360' });
  scene.add(inst(new THREE.DodecahedronGeometry(1, 0), std('#ffffff', 1, { flatShading: true }), rub));
  // the passage: from the hole (z -0.2) straight back, then winding down 16 m
  const pts = [V(0, 1.1, 0.2), V(0, 1.1, -3), V(0.4, 0.6, -7), V(-0.6, -0.8, -11), V(-1.8, -2.6, -14.5), V(-1.2, -4.6, -18), V(0.8, -6.4, -21), V(2.2, -8.2, -24.5), V(1.4, -10.2, -28), V(0, -12, -31)];
  function V(x, y, z) { return new THREE.Vector3(x, y, z); }
  const path = new THREE.CatmullRomCurve3(pts), tg = new THREE.TubeGeometry(path, 220, 1.05, 14, false);
  { const p = tg.attributes.position, C = []; for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i), z = p.getZ(i); const n = fbm(x * 1.3 + 7, z * 1.3 + y * 0.7); p.setXYZ(i, x + n * 0.18, y + n * 0.14, z); const c = rock(x, y, z); C.push(c.r, c.g, c.b); }
    tg.computeVertexNormals(); tg.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); }
  const tube = sh(new THREE.Mesh(tg, std('#ffffff', 0.97, { side: THREE.BackSide, vertexColors: true })), false); scene.add(tube);
  // oil-lamp niches along the passage: glow + a few real point lights
  const lampsAt = [0.12, 0.3, 0.48, 0.66, 0.84], glows = [];
  lampsAt.forEach((u, k) => { const p = path.getPointAt(u), tn = path.getTangentAt(u), side = new THREE.Vector3(0, 1, 0).cross(tn).normalize().multiplyScalar(k % 2 ? 0.85 : -0.85);
    const q = p.clone().add(side).add(V(0, 0.35, 0)); const m = new THREE.Mesh(new THREE.SphereGeometry(0.07, 10, 8), new THREE.MeshBasicMaterial({ color: col('#FFB45A').multiplyScalar(5) })); m.position.copy(q); scene.add(m); glows.push(q);
    const L = new THREE.PointLight('#FFAA55', 3.2, 8, 1.7); L.position.copy(q.clone().sub(side.clone().multiplyScalar(0.25))); scene.add(L); });
  // the room's own lamp + the explorer's torch (moves with the camera)
  const rl = new THREE.PointLight('#FFB070', 7, 9, 1.5); rl.position.set(1.2, 2.1, 2.6); scene.add(rl);
  const torch = new THREE.PointLight('#FFC488', 2.0, 10, 1.6); scene.add(torch);
  // a rolling stone door (millstone) in a side slot near u = 0.55
  const u0 = 0.55, dp = path.getPointAt(u0), dt = path.getTangentAt(u0), dside = new THREE.Vector3(0, 1, 0).cross(dt).normalize();
  const door = new THREE.Group();
  const mc = document.createElement('canvas'); mc.width = mc.height = 256; { const g = mc.getContext('2d'); const gr = g.createRadialGradient(128, 128, 20, 128, 128, 128); gr.addColorStop(0, '#D9BC98'); gr.addColorStop(1, '#B8946E'); g.fillStyle = gr; g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 900; i++) { g.fillStyle = `rgba(90,60,40,${0.05 + rnd(i) * 0.12})`; g.beginPath(); g.arc(rnd(i * 3) * 256, rnd(i * 7) * 256, 1 + rnd(i * 5) * 3, 0, TAU); g.fill(); }
    g.strokeStyle = 'rgba(70,45,30,0.7)'; g.lineWidth = 7; for (const r of [118, 84]) { g.beginPath(); g.arc(128, 128, r, 0, TAU); g.stroke(); } g.fillStyle = '#2A1C12'; g.beginPath(); g.arc(128, 128, 14, 0, TAU); g.fill(); }
  const mt = new THREE.CanvasTexture(mc); mt.colorSpace = THREE.SRGBColorSpace; const capM = std('#ffffff', 0.9, { map: mt, emissive: '#3A2414', emissiveIntensity: 0.35 }), sideM = std('#B38D68', 0.95);
  const disc = sh(new THREE.Mesh(new THREE.CylinderGeometry(1.15, 1.15, 0.42, 40), [sideM, capM, capM]));
  disc.rotation.x = Math.PI / 2; door.add(disc); 
  scene.add(door);
  const doorPos = (k) => dp.clone().add(dside.clone().multiplyScalar(lerpN(2.3, 0, k))).add(V(0, 0.0, 0));
  function lerpN(a, b, k) { return a + (b - a) * k; }
  return {
    scene, path, torch, door, doorU: u0,
    /** k = 0 open (door in its side slot) … 1 closed (rolled across the passage) */
    setDoor(k) { door.position.copy(doorPos(k)); door.lookAt(door.position.clone().add(dt)); disc.rotation.y = 0; door.rotateZ(-k * 2.0); },
    update() {},
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

/** two-line hook title: small white line a, big yellow line b */
export function hookTitle(lt, a, b, y = 300, sb = 150) {
  const k = eob(seg(lt, 0.1, 0.45)), k2 = eob(seg(lt, 0.35, 0.75)); topShade(1);
  ctx.save(); ctx.translate(540, y); ctx.scale(k, k); outlined(a, 0, 0, 80, '#fff'); ctx.restore();
  ctx.save(); ctx.globalAlpha = clamp(k2); ctx.translate(540, y + 140); ctx.scale(k2, k2); outlined(b, 0, 0, sb, Y); ctx.restore();
}
/** big "N YIL ÖNCE" counter for the time road (value already animated by the caller) */
export function yearCounter(value, alpha = 1, y = 300, label = 'YIL ÖNCE') {
  if (alpha <= 0) return; topShade(alpha); ctx.save(); ctx.globalAlpha = alpha;
  outlined(fmt(value), 540, y, 170, Y); ctx.font = '800 50px Inter'; outlined(label, 540, y + 120, 60, '#fff', 'center', 900); ctx.restore();
}
/** a row of icons (pot, tablet, wheel) that pop in on their times and get a red strike */
export function crossIcons(lt, times, y = 420) {
  const xs = [220, 540, 860], names = ['ÇÖMLEK', 'YAZI', 'TEKERLEK']; topShade(1);
  xs.forEach((x, i) => {
    const k = eob(seg(lt, times[i] - 0.1, times[i] + 0.25)); if (k <= 0) return; const ks = eo(seg(lt, times[i] + 0.25, times[i] + 0.55));
    ctx.save(); ctx.translate(x, y); ctx.scale(k, k); glass(-130, -130, 260, 260, 50, 0.7);
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#fff'; ctx.lineWidth = 12; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    if (i === 0) { ctx.beginPath(); ctx.moveTo(-30, -60); ctx.lineTo(30, -60); ctx.quadraticCurveTo(20, -30, 55, 0); ctx.quadraticCurveTo(70, 50, 30, 65); ctx.lineTo(-30, 65); ctx.quadraticCurveTo(-70, 50, -55, 0); ctx.quadraticCurveTo(-20, -30, -30, -60); ctx.closePath(); ctx.stroke(); }
    else if (i === 1) { ctx.strokeRect(-48, -66, 96, 132); for (let r = 0; r < 4; r++) for (let c = 0; c < 3; c++) { const xx = -30 + c * 28, yy = -44 + r * 30; ctx.beginPath(); ctx.moveTo(xx, yy); ctx.lineTo(xx + 14, yy + 6); ctx.lineTo(xx, yy + 12); ctx.fill(); } }
    else { ctx.beginPath(); ctx.arc(0, 0, 62, 0, TAU2); ctx.stroke(); ctx.beginPath(); ctx.arc(0, 0, 12, 0, TAU2); ctx.fill(); for (let s = 0; s < 6; s++) { const a = s / 6 * TAU2; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.cos(a) * 62, Math.sin(a) * 62); ctx.stroke(); } }
    if (ks > 0) { ctx.strokeStyle = '#E5383B'; ctx.lineWidth = 22; ctx.beginPath(); ctx.moveTo(-95, -95); ctx.lineTo(lerp(-95, 95, ks), lerp(-95, 95, ks)); ctx.stroke(); }
    ctx.restore();
    ctx.save(); ctx.globalAlpha = clamp(k); outlined(names[i], x, y + 180, 46, ks > 0.5 ? '#FF6B6E' : '#fff'); ctx.restore();
  });
}
const TAU2 = Math.PI * 2;
/** a progress bar with a counting percent (excavated share) */
export function percentBar(lt, frac, label, y = 330) {
  if (lt < 0) return; topShade(1); const k = eob(seg(lt, 0, 0.3)), f = frac * eio(seg(lt, 0.25, 1.3)), x0 = 140, Wd = 800;
  ctx.save(); ctx.globalAlpha = clamp(k); glass(x0 - 40, y - 120, Wd + 80, 250, 40, 0.7);
  ctx.font = '800 40px Inter'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#fff'; ctx.fillText(label, x0, y - 62);
  ctx.fillStyle = 'rgba(255,255,255,0.2)'; ctx.beginPath(); ctx.roundRect(x0, y - 20, Wd, 56, 28); ctx.fill();
  ctx.fillStyle = Y; ctx.beginPath(); ctx.roundRect(x0, y - 20, Math.max(56, Wd * f), 56, 28); ctx.fill();
  ctx.font = '900 72px Inter'; ctx.textAlign = 'right'; ctx.fillStyle = Y; ctx.fillText(`%${Math.round(f * 100)}`, x0 + Wd, y - 62); ctx.restore();
}
/** dashed ellipse ring at screen points with a soft fill (buried enclosure) */
export function ghostRing(pts, k, colr = 'rgba(255,255,255,0.9)', fill = 'rgba(255,212,59,0.0)') {
  if (k <= 0 || pts.length < 3) return; ctx.save(); ctx.globalAlpha = clamp(k); ctx.beginPath(); ctx.moveTo(...pts[0]); for (const p of pts.slice(1)) ctx.lineTo(...p); ctx.closePath();
  ctx.fillStyle = fill; ctx.fill(); ctx.setLineDash([16, 12]); ctx.lineWidth = 7; ctx.strokeStyle = colr; ctx.stroke(); ctx.restore();
}

// ── Rota 360 distinctive assets: brand mark, like chip, end card ──
function heart(x, y, s, fill) { ctx.save(); ctx.translate(x, y); ctx.scale(s / 40, s / 40); ctx.beginPath(); ctx.moveTo(0, 14); ctx.bezierCurveTo(-40, -12, -18, -38, 0, -20); ctx.bezierCurveTo(18, -38, 40, -12, 0, 14); ctx.closePath(); ctx.fillStyle = fill; ctx.fill(); ctx.restore(); }
function bubble(x, y, s, fill) { ctx.save(); ctx.translate(x, y); ctx.scale(s / 40, s / 40); ctx.fillStyle = fill; ctx.beginPath(); ctx.roundRect(-22, -18, 44, 30, 10); ctx.fill(); ctx.beginPath(); ctx.moveTo(-8, 10); ctx.lineTo(-14, 22); ctx.lineTo(4, 10); ctx.fill(); ctx.restore(); }
function bell(x, y, s, fill) { ctx.save(); ctx.translate(x, y); ctx.scale(s / 40, s / 40); ctx.fillStyle = fill; ctx.beginPath(); ctx.moveTo(-16, 10); ctx.quadraticCurveTo(-14, -20, 0, -20); ctx.quadraticCurveTo(14, -20, 16, 10); ctx.lineTo(20, 14); ctx.lineTo(-20, 14); ctx.closePath(); ctx.fill(); ctx.beginPath(); ctx.arc(0, 18, 5, 0, 7); ctx.fill(); ctx.restore(); }
/** small fixed brand mark, top-left (every frame) */
export function brand(alpha = 1) {
  ctx.save(); ctx.globalAlpha = 0.9 * alpha; ctx.font = '900 34px Inter'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
  const w = ctx.measureText('ROTA 360').width; ctx.fillStyle = 'rgba(12,15,22,0.55)'; ctx.beginPath(); ctx.roundRect(48, 70, w + 82, 58, 29); ctx.fill();
  ctx.fillStyle = Y; ctx.beginPath(); ctx.arc(80, 99, 13, 0, 7); ctx.fill(); ctx.fillStyle = INK; ctx.beginPath(); ctx.arc(80, 99, 5, 0, 7); ctx.fill();
  ctx.fillStyle = '#fff'; ctx.fillText('ROTA 360', 104, 101); ctx.restore();
}
/** the series tag under the brand mark (first seconds) */
export function seriesTag(text, k) { if (k <= 0) return; ctx.save(); ctx.globalAlpha = clamp(k); ctx.font = '900 30px Inter'; const w = ctx.measureText(text).width + 44; ctx.fillStyle = '#D62839'; ctx.beginPath(); ctx.roundRect(48, 140, w, 50, 25); ctx.fill(); ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillText(text, 70, 166); ctx.restore(); }
/** animated like chip (mid-video ask) */
export function likeChip(lt, x = 540, y = 1150) {
  if (lt < 0) return; const k = eob(seg(lt, 0, 0.35)), pulse = 1 + 0.08 * Math.max(0, Math.sin((lt - 0.4) * 9)) * (lt > 0.4 && lt < 1.3 ? 1 : 0);
  ctx.save(); ctx.translate(x, y); ctx.scale(k * pulse, k * pulse); ctx.font = '900 62px Inter'; const w = ctx.measureText('BEĞEN').width + 170;
  ctx.shadowColor = 'rgba(0,0,0,0.4)'; ctx.shadowBlur = 24; ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.roundRect(-w / 2, -58, w, 116, 58); ctx.fill(); ctx.shadowBlur = 0;
  heart(-w / 2 + 72, 4, 64, '#E8384F'); ctx.fillStyle = INK; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillText('BEĞEN', -w / 2 + 126, 4); ctx.restore();
}
/** end card: BEĞEN · YORUM YAP · ABONE OL / TAKİP ET + handle */
export function endCard(lt, handle = '@rota360tr', y0 = 700) {
  if (lt < 0) return; const items = [['BEĞEN', heart, '#E8384F', '#fff', INK], ['YORUM YAP', bubble, '#2F7BD8', '#fff', INK], ['ABONE OL · TAKİP ET', bell, '#fff', '#D62839', '#fff']];
  ctx.save(); ctx.globalAlpha = clamp(lt / 0.3); ctx.fillStyle = 'rgba(8,10,16,0.45)'; ctx.fillRect(0, y0 - 120, 1080, 610); ctx.restore();
  items.forEach(([t, ic, icc, bg, fg], i) => { const k = eob(seg(lt, 0.1 + i * 0.15, 0.45 + i * 0.15)); if (k <= 0) return; const y = y0 + i * 140;
    ctx.save(); ctx.translate(540, y); ctx.scale(k, k); ctx.font = '900 56px Inter'; const w = Math.max(560, ctx.measureText(t).width + 170);
    ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 20; ctx.fillStyle = bg; ctx.beginPath(); ctx.roundRect(-w / 2, -52, w, 104, 52); ctx.fill(); ctx.shadowBlur = 0;
    ic(-w / 2 + 66, 2, 56, icc); ctx.fillStyle = fg; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(t, 40, 4); ctx.restore(); });
  const kh = eo(seg(lt, 0.6, 0.9)); if (kh > 0) { ctx.save(); ctx.globalAlpha = kh; outlined(handle, 540, y0 + 400, 64, Y); ctx.restore(); }
}
/** level ticks down the left side: n levels lit, ys = screen y of each level */
export function levelTicks(ys, n, x = 150) {
  ys.forEach((y, i) => { if (i >= n) return; ctx.save(); ctx.fillStyle = Y; ctx.beginPath(); ctx.roundRect(x - 50, y - 22, 100, 44, 22); ctx.fill(); ctx.font = '900 30px Inter'; ctx.fillStyle = INK; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(`-${i + 1}`, x, y + 2); ctx.restore(); });
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
        tp = float(S.get('tempo', 1.0))
        if abs(tp - 1) > 1e-3:
            import subprocess, tempfile
            with tempfile.TemporaryDirectory() as td:
                wavfile.write(f'{td}/a.wav', SR, (x / (np.abs(x).max() + 1e-9) * 0.9 * 32767).astype(np.int16))
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', f'{td}/a.wav', '-af', f'atempo={tp}', '-ar', str(SR), f'{td}/b.wav'], check=True)
                x = wavfile.read(f'{td}/b.wav')[1].astype(np.float32) / 32767
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
 "title": "Evinin Duvarını Yıktı, Yeraltı Şehri Buldu: Derinkuyu",
 "lang": "tr",
 "voice": "Charon",
 "style": "[curious]",
 "speed": 1.0,
 "lead": 0.35,
 "outro": 1.6,
 "gap": 0.16,
 "music": "none",
 "sources": [
  "Wikipedia 'Derinkuyu underground city': rediscovered in 1963 when a resident renovating his home knocked through a basement wall; approx. 85 m deep; up to 20,000 people with their livestock and food stores; carved into tuff (compacted volcanic ash); stables, cellars, storage rooms, refectories, chapels, wine and oil presses, kitchens with tandoor ovens; each floor could be closed separately from the inside with large rolling stone doors; first tunnels possibly cut by the Phrygians in the 8th-7th century BC; connected with Kaymaklı through 8-9 km of tunnels",
  "History.com 'Derinkuyu': discovered in 1963 by a man knocking down a wall in his basement; about 280 feet deep; at least 18 levels; up to 20,000 people; more than 50 ventilation shafts; stables, churches; volcanic tuff soft enough to carve; origins may date to around the 8th century BC",
  "Habertürk (2025) 'Binlerce insan yerin 18 kat altına saklandı': 1963, a man knocking down his house wall; 85 m; 18 floors; up to 20,000 people; more than 50 air shafts; soft tuff; stables and wine-press rooms; Phrygians 8th-7th c. BC",
  "Wikipedia 'Kaymaklı underground city' and Culture Trip: Kaymaklı is linked to Derinkuyu by a tunnel of about 8 km (described as believed / reported)"
 ],
 "lines": [
  {
   "text": "Kapadokya'da bir adam, evinin duvarını yıktı,",
   "caps": "*Kapadokya'da | bir *adam | evinin *duvarını | *yıktı"
  },
  {
   "text": "ama duvarın arkasından, yerin altında koca bir şehir çıktı.",
   "caps": "ama *duvarın | *arkasından | yerin *altında | koca bir *şehir | *çıktı"
  },
  {
   "text": "Hem de yirmi bin kişiyi barındıracak kadar büyük!",
   "caps": "*Hem de | {yirmi} *20.000 | *kişiyi | *barındıracak | kadar *büyük!"
  },
  {
   "text": "Yıl bin dokuz yüz altmış üç, yer Nevşehir, Derinkuyu.",
   "caps": "*Yıl | {bin} *1963 | yer *Nevşehir | *Derinkuyu"
  },
  {
   "text": "Duvarın ardındaki karanlık tünel, hep daha aşağı iniyordu.",
   "caps": "Duvarın *ardındaki | *karanlık tünel | hep daha *aşağı | *iniyordu"
  },
  {
   "text": "Bütün şehir, volkanik külden oluşan yumuşak tüfe oyulmuş.",
   "caps": "Bütün *şehir | *volkanik külden | oluşan *yumuşak | *tüfe oyulmuş"
  },
  {
   "text": "Derinliği yaklaşık seksen beş metre,",
   "caps": "*Derinliği | *yaklaşık | {seksen} *85 metre"
  },
  {
   "text": "ve en az on sekiz kata yayılıyor.",
   "caps": "ve en *az | {on} *18 kata | *yayılıyor"
  },
  {
   "text": "İçinde ahırlar, mutfaklar, şarap presleri ve hatta kiliseler var.",
   "caps": "İçinde *ahırlar | *mutfaklar | *şarap | *presleri | ve *hatta | *kiliseler var"
  },
  {
   "text": "Bilmiyorduysan, bir beğeni bırak.",
   "caps": "*Bilmiyorduysan | bir *beğeni | *bırak"
  },
  {
   "text": "Elliden fazla hava bacası, derinlere temiz hava taşıyor.",
   "caps": "{elliden} *50'den fazla | hava *bacası | *derinlere | *temiz hava | *taşıyor"
  },
  {
   "text": "Her kat, dev taş kapılarla içeriden kapatılabiliyordu.",
   "caps": "Her *kat | dev *taş kapılarla | *içeriden | *kapatılabiliyordu"
  },
  {
   "text": "İlk odaları belki de iki bin yedi yüz yıl önce, Frigler oydu.",
   "caps": "İlk *odaları | *belki de | {iki} *2.700 yıl önce | *Frigler oydu"
  },
  {
   "text": "Üstelik, sekiz kilometrelik bir tünelle,",
   "caps": "*Üstelik | {sekiz} *8 km'lik | bir *tünelle"
  },
  {
   "text": "Kaymaklı yeraltı şehrine bağlandığı düşünülüyor.",
   "caps": "*Kaymaklı | *yeraltı şehrine | *bağlandığı | *düşünülüyor"
  },
  {
   "text": "Sen orada bir gece kalır mıydın? Yorumlara yaz.",
   "caps": "Sen *orada | bir *gece | *kalır mıydın? | *Yorumlara | *yaz"
  },
  {
   "text": "Rota'yı kaydet, abone ol; gitmeden önce lazım olacak.",
   "caps": "*Rota'yı kaydet | *abone ol | *gitmeden önce | lazım *olacak"
  }
 ],
 "tempo": 1.07
}
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
FILES = ['src/main.js', 'src/shots.js', 'src/core/world.js', 'src/core/overlays.js', 'src/core/captions.js', 'src/core/timing.js',
         'tools/voice_google.py', 'tools/mix.py', 'script.json']
parts = ['#!/bin/bash', '# World Tour engine bundle. usage: bash bundle.sh <project-dir>', 'set -eu', 'P="${1:?project dir}"',
         'mkdir -p "$P/src/core" "$P/tools" "$P/examples" "$HOME/faceless-shorts/system"',
         'rm -f "$P/src/sheet.js" "$P/sheet.html" "$P/src/core/human.js" "$P/src/core/sets.js" "$P/src/core/board.js"']
D = '__EOF_' + 'WT__'
def emit(dst, text):
    assert D not in text
    parts.append(f"cat > {dst} <<'{D}'\n{text.rstrip(chr(10))}\n{D}")
for f in FILES:
    text = (proj / f).read_text()
    if f in ('src/shots.js', 'script.json'):
        emit(f'"$P/examples/{Path(f).name}"', text)          # the last video's shots/script, as a worked example
        if f == 'src/shots.js': emit('"$P/src/shots.js"', text)
    else:
        emit(f'"$P/{f}"', text)
for f in ('RUNBOOK.md', 'make_bundle.py'): emit(f'"$HOME/faceless-shorts/system/{f}"', (here / f).read_text())
parts.append('echo "engine installed into $P (example shots/script in $P/examples/)"')
out.write_text('\n'.join(parts) + '\n')
print(f'{out}: {out.stat().st_size // 1024} KB, {len(FILES)} files + runbook')
__EOF_WT__
echo "engine installed into $P (example shots/script in $P/examples/)"
