"""kb.py - Kokpit 360 Blender kit (bpy >= 4.2; pip install --break-system-packages bpy).

Series "SIFIRDAN UÇAK": we build one light aircraft from scratch, one part per episode, in a dark blueprint studio.
Units: metres. Axes: +X = right wing, +Y = nose (forward), +Z = up.

Typical episode script (scene.py in the project folder):
    import sys; sys.path.insert(0, ENGINE_DIR); import kb
    T = kb.Timeline(PROJECT)              # reads data/lines.json -> T.line(i).start/.end, T.word('kanat', i)
    kb.setup(T.duration)                  # empty scene, Cycles, 24 fps, 540x960, studio + lights
    plane = kb.light_aircraft(stage=3)    # dict of parts already built in earlier episodes (stage = episode no.)
    ... animate: kb.fly_in(obj, t0, t1, offset), kb.fade(obj, t0, t1, 0, 1), kb.spin(obj, t0, t1, 'Y', turns),
                 kb.glow(obj, t), kb.flow_lines(...), kb.hinge(obj, axis, t0, t1, deg)
    shots: kb.shot(t0, pos0, pos1, target, lens=35, target_to=None)  (one camera per line, cut at t0)
    kb.render_cli()                       # handles: python3 scene.py --render START END  /  --still t out.png
Every frame is rendered to frames/f_####.png; existing frames are skipped (resume-safe, chunked).
"""
import bpy, bmesh, math, json, os, sys
from mathutils import Vector, Euler

FPS = 24
PAL = dict(
    bg=(0.0024, 0.0042, 0.0080),        # #070C14 (linear)
    teal=(0.024, 0.45, 0.53),           # #2BB3C0
    teal_lt=(0.21, 0.77, 0.83),         # #7FE3EC
    teal_dk=(0.0047, 0.043, 0.064),     # #0E3B47
    orange=(1.0, 0.147, 0.035),         # #FF6B35
    yellow=(0.91, 0.56, 0.007),         # #F5C518
    alu=(0.70, 0.72, 0.75),
    white=(0.85, 0.87, 0.9),
)


# ----------------------------------------------------------------------------------------------- timing
class Line:
    def __init__(self, d): self.i = d['i']; self.text = d['text']; self.start = d['start']; self.end = d['end']


class Timeline:
    def __init__(self, project):
        self.P = project
        lj = json.load(open(os.path.join(project, 'data/lines.json')))
        self.duration = lj['duration']; self.lines = [Line(l) for l in lj['lines']]
        wp = os.path.join(project, 'data/words.json')
        self.words = json.load(open(wp)) if os.path.exists(wp) else []

    def line(self, i): return self.lines[i]

    def cut(self, i):  # picture changes a hair before the line is spoken
        return max(0.0, self.lines[i].start - 0.12) if i > 0 else 0.0

    def word(self, w, i, fallback=None):
        w = w.lower()
        for x in self.words:
            if x['line'] == i and w in x['w'].lower(): return x['s']
        return fallback if fallback is not None else self.lines[i].start


def F(t): return round(t * FPS) + 1  # seconds -> frame number


# ----------------------------------------------------------------------------------------------- scene
def setup(duration, res=(540, 960), samples=10):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS; sc.frame_start = 1; sc.frame_end = F(duration)
    sc.render.resolution_x, sc.render.resolution_y = res; sc.render.resolution_percentage = 100
    sc.render.engine = 'CYCLES'
    c = sc.cycles
    c.device = 'CPU'; c.samples = samples; c.use_adaptive_sampling = True; c.adaptive_threshold = 0.03
    c.use_denoising = True; c.denoiser = 'OPENIMAGEDENOISE'
    try: c.denoising_prefilter = 'FAST'
    except Exception: pass
    c.max_bounces = 4; c.diffuse_bounces = 2; c.glossy_bounces = 2; c.transmission_bounces = 3; c.transparent_max_bounces = 6
    c.caustics_reflective = False; c.caustics_refractive = False; c.blur_glossy = 1.0
    sc.render.use_persistent_data = True
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGB'
    try:
        sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
    except Exception: pass
    sc.view_settings.exposure = 0.0
    w = bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
    bgn = w.node_tree.nodes['Background']; bgn.inputs[0].default_value = PAL['bg'] + (1,); bgn.inputs[1].default_value = 1.0
    studio()
    return sc


def mat(name, color, metal=0.0, rough=0.4, emit=None, emit_k=0.0, alpha=1.0, coat=0.0, transmission=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = color + (1,)
    b.inputs['Metallic'].default_value = metal; b.inputs['Roughness'].default_value = rough
    if coat: b.inputs['Coat Weight'].default_value = coat
    if transmission: b.inputs['Transmission Weight'].default_value = transmission
    if emit is not None:
        b.inputs['Emission Color'].default_value = emit + (1,); b.inputs['Emission Strength'].default_value = emit_k
    b.inputs['Alpha'].default_value = alpha
    return m


MATS = {}


def M(key):
    if key in MATS: return MATS[key]
    spec = dict(
        alu=dict(color=PAL['alu'], metal=1.0, rough=0.28),
        alu_dark=dict(color=(0.35, 0.37, 0.40), metal=1.0, rough=0.35),
        paint=dict(color=PAL['white'], metal=0.0, rough=0.25, coat=0.6),
        teal=dict(color=PAL['teal'], metal=0.2, rough=0.3, coat=0.4),
        teal_lt=dict(color=PAL['teal_lt'], metal=0.1, rough=0.3),
        orange=dict(color=PAL['orange'], metal=0.1, rough=0.35, emit=PAL['orange'], emit_k=0.0),
        rubber=dict(color=(0.02, 0.02, 0.022), rough=0.6),
        glass=dict(color=(0.6, 0.85, 0.95), rough=0.05, transmission=1.0, alpha=1.0),
        wood=dict(color=(0.45, 0.25, 0.10), rough=0.55),
        glow_teal=dict(color=PAL['teal_lt'], emit=PAL['teal_lt'], emit_k=6.0),
        glow_orange=dict(color=PAL['orange'], emit=PAL['orange'], emit_k=8.0),
        glow_yellow=dict(color=PAL['yellow'], emit=PAL['yellow'], emit_k=12.0),
        # cinematic look (2026-11-26): canary-yellow livery + colour-coded flows (fuel yellow, air blue, hot red)
        livery=dict(color=(1.0, 0.31, 0.0), metal=0.0, rough=0.4, coat=0.15),
        livery_red=dict(color=(0.60, 0.03, 0.02), metal=0.0, rough=0.35, coat=0.5),
        glow_blue=dict(color=(0.12, 0.45, 1.0), emit=(0.12, 0.45, 1.0), emit_k=7.0),
        glow_red=dict(color=(1.0, 0.06, 0.02), emit=(1.0, 0.06, 0.02), emit_k=8.0),
        orange_flat=dict(color=(1.0, 0.09, 0.0), emit=(1.0, 0.09, 0.0), emit_k=0.9, rough=0.5),
        cloud=dict(color=(0.95, 0.96, 0.98), rough=1.0, emit=(0.75, 0.85, 1.0), emit_k=0.18),
        cloud_storm=dict(color=(0.30, 0.33, 0.38), rough=1.0, emit=(0.2, 0.25, 0.35), emit_k=0.05),
    )[key]
    MATS[key] = mat(key, **spec); return MATS[key]


def studio(floor=True):
    if floor:
        bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0)); fl = bpy.context.object; fl.name = 'floor'
        m = bpy.data.materials.new('blueprint'); m.use_nodes = True; nt = m.node_tree; N = nt.nodes; L = nt.links
        b = N['Principled BSDF']; b.inputs['Base Color'].default_value = (0.006, 0.012, 0.02, 1)
        b.inputs['Roughness'].default_value = 0.62; b.inputs['Metallic'].default_value = 0.0
        tc = N.new('ShaderNodeTexCoord'); sep = N.new('ShaderNodeSeparateXYZ'); L.new(tc.outputs['Object'], sep.inputs[0])
        def grid(axis):
            m1 = N.new('ShaderNodeMath'); m1.operation = 'PINGPONG'; m1.inputs[1].default_value = 0.5
            L.new(sep.outputs[axis], m1.inputs[0])
            m2 = N.new('ShaderNodeMath'); m2.operation = 'LESS_THAN'; m2.inputs[1].default_value = 0.012
            L.new(m1.outputs[0], m2.inputs[0]); return m2
        gx, gy = grid('X'), grid('Y')
        mx = N.new('ShaderNodeMath'); mx.operation = 'MAXIMUM'; L.new(gx.outputs[0], mx.inputs[0]); L.new(gy.outputs[0], mx.inputs[1])
        # fade the grid out with distance from the centre
        ln = N.new('ShaderNodeVectorMath'); ln.operation = 'LENGTH'; L.new(tc.outputs['Object'], ln.inputs[0])
        fd = N.new('ShaderNodeMapRange'); fd.inputs[1].default_value = 4; fd.inputs[2].default_value = 22
        fd.inputs[3].default_value = 1; fd.inputs[4].default_value = 0; L.new(ln.outputs['Value'], fd.inputs[0])
        mm = N.new('ShaderNodeMath'); mm.operation = 'MULTIPLY'; L.new(mx.outputs[0], mm.inputs[0]); L.new(fd.outputs[0], mm.inputs[1])
        mk = N.new('ShaderNodeMath'); mk.operation = 'MULTIPLY'; mk.inputs[1].default_value = 0.22; L.new(mm.outputs[0], mk.inputs[0])
        b.inputs['Emission Color'].default_value = PAL['teal'] + (1,); L.new(mk.outputs[0], b.inputs['Emission Strength'])
        fl.data.materials.append(m)
    area('key', (4, -5, 7), 900, (1.0, 0.95, 0.9), size=5)
    area('rim_teal', (-7, 4, 3), 700, PAL['teal_lt'], size=4)
    area('rim_orange', (7, 5, 2.5), 250, (1.0, 0.45, 0.2), size=3)
    area('fill', (0, -9, 2), 90, (0.6, 0.75, 1.0), size=8)


def area(name, loc, energy, color, size=3, target=(0, 0, 1)):
    bpy.ops.object.light_add(type='AREA', location=loc); o = bpy.context.object; o.name = name
    o.data.energy = energy; o.data.color = color; o.data.size = size
    look_at(o, Vector(target)); return o


def look_at(o, target):
    d = Vector(target) - o.location
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def empty(name, loc=(0, 0, 0)):
    o = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(o); o.location = loc; return o


def parent(child, par):
    child.parent = par; child.matrix_parent_inverse = par.matrix_world.inverted()


# ----------------------------------------------------------------------------------------------- geometry
def mesh_obj(name, verts, faces, material=None, smooth=True):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    if material: me.materials.append(material if not isinstance(material, str) else M(material))
    return o


def naca4(code='2412', n=40):
    m = int(code[0]) / 100; p = int(code[1]) / 10; t = int(code[2:]) / 100
    up, lo = [], []
    for k in range(n + 1):
        x = (1 - math.cos(math.pi * k / n)) / 2
        yt = 5 * t * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 - 0.1036 * x ** 4)
        if p and x < p: yc = m / p ** 2 * (2 * p * x - x * x); dy = 2 * m / p ** 2 * (p - x)
        elif p: yc = m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x * x); dy = 2 * m / (1 - p) ** 2 * (p - x)
        else: yc, dy = 0, 0
        th = math.atan(dy)
        up.append((x - yt * math.sin(th), yc + yt * math.cos(th)))
        lo.append((x + yt * math.sin(th), yc - yt * math.cos(th)))
    return up[::-1] + lo[1:-1]  # closed loop: TE -> upper -> LE -> lower


def loft(name, sections, material, cap=True, smooth=True):
    """sections: list of equal-length point loops (3D). Quads between consecutive loops."""
    n = len(sections[0]); verts = [v for s in sections for v in s]; faces = []
    for j in range(len(sections) - 1):
        for i in range(n):
            a = j * n + i; b = j * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    if cap:
        faces.append(tuple(range(n))[::-1]); faces.append(tuple(range((len(sections) - 1) * n, len(sections) * n)))
    return mesh_obj(name, verts, faces, material, smooth)


def wing_section(af, span_x, chord, le_y, z, twist_deg=0.0):
    tw = math.radians(twist_deg); out = []
    for x, y in af:
        cx, cz = x * chord, y * chord
        # twist about the quarter chord
        dx = cx - 0.25 * chord
        rx = dx * math.cos(tw) + cz * math.sin(tw); rz = -dx * math.sin(tw) + cz * math.cos(tw)
        out.append((span_x, le_y - (0.25 * chord + rx), z + rz))
    return out


def wing(name='kanat', span=10.0, root=1.6, tip=1.2, le_y=0.5, z=1.55, dihedral=1.5, code='2412', sweep=0.0,
         material='paint', side=1, stations=9, twist=-2.0):
    af = naca4(code); secs = []
    for k in range(stations):
        f = k / (stations - 1); x = side * f * span / 2
        c = root + (tip - root) * f
        secs.append(wing_section(af, x, c, le_y - sweep * f - (root - c) * 0.25, z + math.tan(math.radians(dihedral)) * abs(x), twist * f))
    o = loft(name, secs, material); return o


def ribs(span=10.0, root=1.6, tip=1.2, le_y=0.5, z=1.55, dihedral=1.5, n=9, side=1, code='2412', thick=0.025, material='alu'):
    af = naca4(code, 30); out = []
    for k in range(n):
        f = (k + 0.3) / n; x = side * f * span / 2; c = root + (tip - root) * f
        s = wing_section([(px, py * 0.86) for px, py in af], x, c * 0.97, le_y - (root - c) * 0.25 - 0.01 * c, z + math.tan(math.radians(dihedral)) * abs(x))
        s2 = [(p[0] + thick, p[1], p[2]) for p in s]
        out.append(loft(f'rib_{side}_{k}', [s, s2], material, smooth=False))
    return out


def box(name, center, size, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=center); o = bpy.context.object; o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        md = o.modifiers.new('bev', 'BEVEL'); md.width = bevel; md.segments = 2
    o.data.materials.append(M(material) if isinstance(material, str) else material); return o


def spar(span=10.0, y=0.05, z=1.56, h=0.16, w=0.05, dihedral=1.5, side=1, material='alu_dark'):
    half = span / 2; L = half * 0.97
    o = box(f'spar_{side}', (side * L / 2, y, z + math.tan(math.radians(dihedral)) * L / 2), (L, w, h), material, 0.008)
    o.rotation_euler = (0, -side * math.radians(dihedral), 0); return o


def fuselage_stations():
    # (y, half-width, half-height, centre z)  - simple light aircraft, nose at y=+2.6, tail at y=-4.6
    return [(2.6, 0.18, 0.18, 1.05), (2.35, 0.42, 0.40, 1.08), (1.9, 0.55, 0.55, 1.12), (1.1, 0.58, 0.68, 1.22),
            (0.0, 0.57, 0.70, 1.25), (-1.2, 0.47, 0.55, 1.25), (-2.6, 0.30, 0.38, 1.30), (-3.9, 0.16, 0.24, 1.38),
            (-4.6, 0.07, 0.14, 1.42)]


def ellipse(y, a, b, zc, n=32, x0=0.0):
    return [(x0 + a * math.cos(2 * math.pi * i / n), y, zc + b * math.sin(2 * math.pi * i / n)) for i in range(n)]


def fuselage_skin(material='paint'):
    st = fuselage_stations(); secs = []
    # interpolate for smoothness
    for k in range(len(st) - 1):
        for s in range(4):
            f = s / 4; a = st[k]; b = st[k + 1]
            f2 = f * f * (3 - 2 * f)
            secs.append(ellipse(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f2, a[2] + (b[2] - a[2]) * f2, a[3] + (b[3] - a[3]) * f2))
    secs.append(ellipse(*st[-1]))
    o = loft('govde_kaplama', secs, material); return o


def curve_obj(name, pts, bevel=0.02, material='alu', closed=False, res=4):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = bevel; cu.bevel_resolution = res
    sp = cu.splines.new('POLY'); sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts): p.co = (c[0], c[1], c[2], 1)
    sp.use_cyclic_u = closed
    o = bpy.data.objects.new(name, cu); bpy.context.collection.objects.link(o)
    o.data.materials.append(M(material) if isinstance(material, str) else material); return o


def fuselage_frames(material='alu'):
    out = []
    for k, s in enumerate(fuselage_stations()[1:-1]):
        out.append(curve_obj(f'frame_{k}', ellipse(s[0], s[1] * 0.92, s[2] * 0.92, s[3], 48), 0.03, material, True))
    return out


def stringers(n=12, material='alu_dark'):
    st = fuselage_stations()[1:-1]; out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        pts = [(s[1] * 0.89 * math.cos(a), s[0], s[3] + s[2] * 0.89 * math.sin(a)) for s in st]
        out.append(curve_obj(f'stringer_{i}', pts, 0.018, material))
    return out


def tail(material='paint'):
    af = naca4('0010')
    hs = []
    for side in (1, -1):
        secs = [wing_section(af, side * f * 1.7, 0.95 - 0.35 * f, -3.75 - 0.18 * f, 1.42) for f in (0, 0.5, 1)]
        hs.append(loft(f'yatay_kuyruk_{side}', secs, material))
    # vertical fin: sections stacked in z (rotate airfoil into the XZ->YZ plane)
    secs = []
    for f in (0, 0.5, 1):
        c = 1.1 - 0.5 * f; le = -3.55 - 0.55 * f; z = 1.5 + 1.25 * f
        secs.append([(y * c, le - x * c, z) for x, y in af])
    vf = loft('dikey_kuyruk', secs, material)
    return hs + [vf]


def propeller(y=2.68, z=1.05, r=0.95, material='wood'):
    hub = empty('pervane', (0, y, z))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, y + 0.02, z)); sp = bpy.context.object; sp.name = 'spinner'
    sp.scale = (1, 1.6, 1); sp.data.materials.append(M('orange')); bpy.ops.object.shade_smooth(); parent(sp, hub)
    af = naca4('4412', 16)
    for k in range(2):
        secs = []
        for f in (0.12, 0.4, 0.7, 1.0):
            c = 0.18 - 0.08 * f; pitch = math.radians(38 - 26 * f); rr = r * f
            loop = []
            for x, yy in af:
                px, pz = (x - 0.3) * c, yy * c
                ry = px * math.cos(pitch) - pz * math.sin(pitch); rz = px * math.sin(pitch) + pz * math.cos(pitch)
                loop.append((-ry, -rz, rr))  # local: x tangential, y axial, z radial
            secs.append([(p[0], p[1], p[2]) for p in loop])
        bl = loft(f'pala_{k}', secs, material)
        bl.location = (0, y, z); bl.rotation_euler = (0, math.pi * k, 0); parent(bl, hub)
    return hub


def engine_block(y=2.0, z=1.08, material='alu_dark'):
    g = empty('motor', (0, y, z)); parts = []
    for side in (1, -1):
        for k in range(2):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.34, location=(side * 0.26, y - 0.12 - k * 0.26, z), rotation=(0, math.pi / 2, 0))
            c = bpy.context.object; c.name = f'silindir_{side}_{k}'; c.data.materials.append(M('alu'))
            md = c.modifiers.new('bev', 'BEVEL'); md.width = 0.02; md.segments = 2; parent(c, g); parts.append(c)
    b = box('karter', (0, y - 0.25, z - 0.04), (0.36, 0.62, 0.3), material, 0.03); parent(b, g)
    return g


def landing_gear(material='alu_dark'):
    out = []
    for side in (1, -1):
        leg = curve_obj(f'ayak_{side}', [(side * 0.45, 0.25, 0.85), (side * 1.05, 0.15, 0.32)], 0.04, material)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.14, location=(side * 1.12, 0.15, 0.28), rotation=(0, math.pi / 2, 0))
        w = bpy.context.object; w.name = f'teker_{side}'; w.data.materials.append(M('rubber')); bpy.ops.object.shade_smooth()
        out += [leg, w]
    leg = curve_obj('burun_ayak', [(0, 1.95, 0.75), (0, 2.1, 0.25)], 0.035, material)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.1, location=(0, 2.1, 0.2), rotation=(0, math.pi / 2, 0))
    w = bpy.context.object; w.name = 'burun_teker'; w.data.materials.append(M('rubber')); bpy.ops.object.shade_smooth()
    return out + [leg, w]


def canopy():
    secs = []
    for y, a, b in ((1.45, 0.36, 0.18), (0.9, 0.5, 0.42), (0.2, 0.5, 0.42), (-0.5, 0.36, 0.22)):
        n = 24; loop = [(a * math.cos(math.pi * i / (n - 1)), y, 1.78 + b * math.sin(math.pi * i / (n - 1))) for i in range(n)]
        secs.append(loop)
    return loft('kabin_cami', secs, 'glass', cap=False)


LIVERY = 'livery'   # canary yellow since 2026-11-26 (was white 'paint')


def light_aircraft(stage=99, skin=True):
    """Builds the series aircraft. stage = how far the build has come (episode number). Returns dict name->obj/list.
    1 kanat profili · 2 kanat iskeleti (spar+ribs) · 3 kanat kaplama · 4 gövde iskeleti · 5 gövde kaplama · 6 kuyruk ·
    7 motor + pervane · 8 iniş takımı · 9+ kabin/cam (complete). Parts of stages > `stage` are not built."""
    P = {}
    if stage >= 2:
        P['spar'] = [spar(side=1), spar(side=-1)]
        P['ribs'] = ribs(side=1) + ribs(side=-1)
    if stage >= 3 and skin:
        P['wing'] = [wing('kanat_R', side=1, material=LIVERY), wing('kanat_L', side=-1, material=LIVERY)]
    if stage >= 4:
        P['frames'] = fuselage_frames(); P['stringers'] = stringers()
    if stage >= 5 and skin: P['fuselage'] = fuselage_skin(LIVERY)
    if stage >= 6: P['tail'] = tail(LIVERY)
    if stage >= 7: P['engine'] = engine_block(); P['prop'] = propeller()
    if stage >= 8: P['gear'] = landing_gear()
    if stage >= 9: P['canopy'] = canopy()
    return P


def airfoil_slab(name='profil', chord=3.0, depth=0.6, code='2412', center=(0, 0, 1.6), material='teal'):
    """A big extruded airfoil for 'how does a wing make lift' shots (chord along -Y)."""
    af = naca4(code, 60); cx, cy, cz = center
    s1 = [(cx - depth / 2, cy + chord / 2 - x * chord, cz + y * chord) for x, y in af]
    s2 = [(cx + depth / 2, p[1], p[2]) for p in s1]
    return loft(name, [s1, s2], material)


# ----------------------------------------------------------------------------------------------- animation
def _key(o, path, t, value, interp='BEZIER'):
    setattr(o, path, value) if not isinstance(value, (tuple, list)) else setattr(o, path, value)
    o.keyframe_insert(path, frame=F(t))
    ad = o.animation_data
    if ad and ad.action:
        try:
            fcs = ad.action.fcurves
        except AttributeError:  # Blender 5 layered actions
            fcs = [fc for layer in ad.action.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]
        for fc in fcs:
            for kp in fc.keyframe_points:
                if kp.co[0] == F(t): kp.interpolation = interp


def each(objs):
    if isinstance(objs, dict): objs = list(objs.values())
    if not isinstance(objs, (list, tuple)): objs = [objs]
    out = []
    for o in objs: out += each(o) if isinstance(o, (list, tuple, dict)) else [o]
    return out


def fly_in(objs, t0, t1, offset=(0, 0, 3), stagger=0.0, hide_before=True):
    for k, o in enumerate(each(objs)):
        a = t0 + k * stagger; b = t1 + k * stagger; home = tuple(o.location)
        _key(o, 'location', a, tuple(h + d for h, d in zip(home, offset)))
        _key(o, 'location', b, home)
        if hide_before: show(o, a)


def show(objs, t, visible=True):
    """Object appears (visible=True) or disappears at time t (render visibility is keyed, constant)."""
    for o in each(objs):
        f = F(t)
        if f <= 1:
            o.hide_render = not visible; o.keyframe_insert('hide_render', frame=1); continue
        o.hide_render = visible; o.keyframe_insert('hide_render', frame=f - 1)
        o.hide_render = not visible; o.keyframe_insert('hide_render', frame=f)


def hide(objs, t): show(objs, t, False)


def scale_in(objs, t0, t1, stagger=0.0):
    for k, o in enumerate(each(objs)):
        s = tuple(o.scale); a = t0 + k * stagger
        _key(o, 'scale', a, (0.001, 0.001, 0.001)); _key(o, 'scale', t1 + k * stagger, s); show(o, a)


def spin(o, t0, t1, axis='Y', turns=1.0, interp='LINEAR'):
    i = 'XYZ'.index(axis); r0 = list(o.rotation_euler); r1 = list(r0); r1[i] += 2 * math.pi * turns
    _key(o, 'rotation_euler', t0, tuple(r0), interp); _key(o, 'rotation_euler', t1, tuple(r1), interp)


def hinge(o, axis, t0, t1, deg):
    i = 'XYZ'.index(axis); r0 = list(o.rotation_euler); r1 = list(r0); r1[i] += math.radians(deg)
    _key(o, 'rotation_euler', t0, tuple(r0)); _key(o, 'rotation_euler', t1, tuple(r1))


def fade(o, t0, t1, a0=0.0, a1=1.0):
    """Per-object alpha fade (copies the material so other objects are not affected)."""
    for ob in each(o):
        if not ob.data or not hasattr(ob.data, 'materials') or not ob.data.materials: continue
        m = ob.data.materials[0].copy(); ob.data.materials[0] = m
        b = m.node_tree.nodes['Principled BSDF']; inp = b.inputs['Alpha']
        inp.default_value = a0; inp.keyframe_insert('default_value', frame=F(t0))
        inp.default_value = a1; inp.keyframe_insert('default_value', frame=F(t1))


def glow(objs, t, color='orange', k=6.0, dur=1.2):
    """Make objects light up (emission pulse) around time t - used to point at the part being explained."""
    for ob in each(objs):
        if not ob.data or not hasattr(ob.data, 'materials') or not ob.data.materials: continue
        m = ob.data.materials[0].copy(); ob.data.materials[0] = m
        b = m.node_tree.nodes['Principled BSDF']
        b.inputs['Emission Color'].default_value = PAL[color] + (1,)
        s = b.inputs['Emission Strength']
        for tt, v in ((t - 0.25, 0.0), (t + 0.15, k), (t + dur, k * 0.35), (t + dur + 0.6, 0.0)):
            s.default_value = v; s.keyframe_insert('default_value', frame=max(1, F(tt)))


def flow_lines(paths, t0, t1, color='glow_teal', n_dash=6, r=0.025, speed=1.0):
    """Glowing dashes travelling along polylines (airflow, forces). paths = list of point lists."""
    out = []
    for pi_, pts in enumerate(paths):
        L = [0.0]
        for a, b in zip(pts, pts[1:]): L.append(L[-1] + (Vector(b) - Vector(a)).length)
        total = L[-1]
        def at(d):
            d = d % total
            for k in range(len(pts) - 1):
                if L[k + 1] >= d:
                    f = (d - L[k]) / max(1e-6, L[k + 1] - L[k]); return Vector(pts[k]).lerp(Vector(pts[k + 1]), f)
            return Vector(pts[-1])
        for j in range(n_dash):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=10, ring_count=6); o = bpy.context.object
            o.name = f'flow_{pi_}_{j}'; o.scale = (1, 3.5, 1); o.data.materials.append(M(color))
            ph = j / n_dash * total; steps = max(2, int((t1 - t0) * 8))
            for s in range(steps + 1):
                t = t0 + (t1 - t0) * s / steps; d = ph + speed * (t - t0) * 2.0
                p = at(d); p2 = at(d + 0.05)
                o.location = p; o.keyframe_insert('location', frame=F(t))
                dirv = (p2 - p)
                if dirv.length > 1e-6:
                    o.rotation_euler = dirv.to_track_quat('Y', 'Z').to_euler(); o.keyframe_insert('rotation_euler', frame=F(t))
            show(o, t0); hide(o, t1); out.append(o)
    return out


def arrow(name, start, end, color='glow_orange', r=0.05):
    s, e = Vector(start), Vector(end); d = e - s
    shaft = curve_obj(name, [s, e - d.normalized() * 0.25], r, color)
    bpy.ops.mesh.primitive_cone_add(radius1=r * 3, radius2=0, depth=0.3, location=e - d.normalized() * 0.15)
    cone = bpy.context.object; cone.name = name + '_uc'; cone.data.materials.append(M(color))
    cone.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return [shaft, cone]


# ----------------------------------------------------------------------------------------------- cameras
SHOTS = []


def shot(t0, pos0, pos1, target=(0, 0, 1.3), lens=35, t1=None, target_to=None, dof=True, fstop=2.8, shake=0.0):
    """One camera per shot; the scene cuts to it at t0 (timeline marker). Camera eases pos0 -> pos1 until t1
    (default: next shot start or end). Target can move too (target_to).
    shake = hand-held / turbulence jitter in metres (0.03 cockpit idle, 0.08 chase cam, 0.2 storm)."""
    cam = bpy.data.cameras.new(f'cam{len(SHOTS)}'); cam.lens = lens; cam.sensor_width = 24
    o = bpy.data.objects.new(f'cam{len(SHOTS)}', cam); bpy.context.collection.objects.link(o)
    tg = empty(f'tgt{len(SHOTS)}', target)
    c = o.constraints.new('TRACK_TO'); c.target = tg; c.track_axis = 'TRACK_NEGATIVE_Z'; c.up_axis = 'UP_Y'
    if dof:
        cam.dof.use_dof = True; cam.dof.focus_object = tg; cam.dof.aperture_fstop = fstop
    SHOTS.append(dict(t0=t0, t1=t1, cam=o, tg=tg, pos0=pos0, pos1=pos1, target=target, target_to=target_to, shake=shake))
    return o


def _jit(seed, t, amp):
    """Smooth deterministic 3D jitter (sum of sines) for camera shake / turbulence."""
    s = seed * 1.618
    return Vector((amp * (0.6 * math.sin(7.1 * t + s) + 0.4 * math.sin(13.7 * t + 2 * s)),
                   amp * 0.5 * (0.6 * math.sin(5.3 * t + 3 * s) + 0.4 * math.sin(11.9 * t + s)),
                   amp * (0.6 * math.sin(6.7 * t + 5 * s) + 0.4 * math.sin(15.1 * t + 4 * s))))


def finalize_shots():
    sc = bpy.context.scene; SHOTS.sort(key=lambda s: s['t0'])
    end_t = (sc.frame_end - 1) / FPS
    for k, s in enumerate(SHOTS):
        t1 = s['t1'] or (SHOTS[k + 1]['t0'] if k + 1 < len(SHOTS) else end_t)
        o = s['cam']
        if s.get('shake'):
            n = max(2, int((t1 + 0.1 - s['t0']) * 12)); p0, p1 = Vector(s['pos0']), Vector(s['pos1'])
            for j in range(n + 1):
                f = j / n; t = s['t0'] + (t1 + 0.1 - s['t0']) * f
                _key(o, 'location', t, tuple(p0.lerp(p1, f) + _jit(k + 1, t, s['shake'])), 'LINEAR')
        else:
            _key(o, 'location', s['t0'], tuple(s['pos0']), 'LINEAR'); _key(o, 'location', t1 + 0.1, tuple(s['pos1']), 'LINEAR')
        if s['target_to']:
            _key(s['tg'], 'location', s['t0'], tuple(s['target'])); _key(s['tg'], 'location', t1, tuple(s['target_to']))
        mk = sc.timeline_markers.new(f'S{k}', frame=F(s['t0'])); mk.camera = o
    if SHOTS: sc.camera = SHOTS[0]['cam']


def orbit_points(center, radius, h, a0, a1):
    cx, cy, cz = center
    return ((cx + radius * math.cos(math.radians(a0)), cy + radius * math.sin(math.radians(a0)), cz + h),
            (cx + radius * math.cos(math.radians(a1)), cy + radius * math.sin(math.radians(a1)), cz + h))


# ----------------------------------------------------------------------------------------------- render
def render_cli(project):
    """python3 scene.py --render START END   (seconds; renders missing frames only)
       python3 scene.py --still T out.png     (one QA frame)
       python3 scene.py --hero out.png        (transparent hero render of the episode's part, for thumbkit.py)"""
    finalize_shots(); sc = bpy.context.scene; a = sys.argv
    fr = os.path.join(project, 'frames'); os.makedirs(fr, exist_ok=True)
    if '--still' in a:
        i = a.index('--still'); t = float(a[i + 1]); sc.frame_set(F(t))
        _set_cam(sc, F(t)); sc.render.filepath = a[i + 2]; bpy.ops.render.render(write_still=True); return
    if '--render' in a:
        i = a.index('--render'); f0 = F(float(a[i + 1])); f1 = min(sc.frame_end, F(float(a[i + 2])))
        for f in range(f0, f1 + 1):
            out = os.path.join(fr, f'f_{f:04d}.png')
            if os.path.exists(out): continue
            sc.frame_set(f); _set_cam(sc, f); sc.render.filepath = out
            bpy.ops.render.render(write_still=True)
        print('RENDERED', f0, f1)


def _set_cam(sc, f):
    cam = None
    for m in sorted(sc.timeline_markers, key=lambda m: m.frame):
        if m.frame <= f and m.camera: cam = m.camera
    if cam: sc.camera = cam


def hero_render(objs, out, cam_pos=None, target=None, lens=50, res=(1000, 1000), samples=24, direction=(1.0, -1.1, 0.75)):
    """Transparent PNG of the episode's part only (other objects hidden), fully assembled, for the thumbnail (thumbkit.py).
    cam_pos/target None = automatic framing from the parts' bounding box seen from `direction`."""
    sc = bpy.context.scene; sc.frame_set(sc.frame_end); keep = set(each(objs))
    for o in sc.objects:
        if o.type in ('MESH', 'CURVE') and o not in keep:
            o.animation_data_clear(); o.hide_render = True
    for o in keep:
        if o.animation_data: o.animation_data.action = None
        o.hide_render = False
    dg = bpy.context.evaluated_depsgraph_get(); pts = []
    for o in keep:
        oe = o.evaluated_get(dg); pts += [oe.matrix_world @ Vector(c) for c in oe.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr = (lo + hi) / 2; size = (hi - lo).length
    if target is None: target = ctr
    if cam_pos is None:
        d = Vector(direction).normalized(); dist = size / 2 / math.tan(math.atan(18 / lens)) * 1.15
        cam_pos = Vector(target) + d * dist
    cam = bpy.data.cameras.new('hero'); cam.lens = lens; cam.sensor_width = 36
    co = bpy.data.objects.new('hero', cam); bpy.context.collection.objects.link(co)
    co.location = cam_pos; look_at(co, Vector(target)); sc.camera = co
    # extra light so dark parts read on the dark thumbnail background
    area('hero_key', Vector(cam_pos) + Vector((2, 0, 4)), 1500, (1, 0.97, 0.92), size=6, target=tuple(target))
    area('hero_rim', Vector(target) + Vector((-4, 6, 3)), 1200, PAL['teal_lt'], size=5, target=tuple(target))
    for o in sc.objects:
        if o.name == 'floor': o.hide_render = True
    sc.render.film_transparent = True; sc.render.image_settings.color_mode = 'RGBA'
    sc.render.resolution_x, sc.render.resolution_y = res; sc.cycles.samples = samples
    sc.render.filepath = out; bpy.ops.render.render(write_still=True)


# =============================================================================================== CINEMATIC LOOK
# The user's style references (2026-11-26):
#  * a cinematic animated flying sequence (feature-film seaplane chase): canary-yellow aircraft against a vivid
#    turquoise sea and blue sky, sweeping chase cams, low hero angles, wide lenses, prop blur, turbulence shake,
#    storm / lightning act, fast 2-4 s cutting.          -> SKY world: sky(), fly_motion(), prop_blur(), shake=
#  * "Mechanic Vision 3D" aircraft-systems shorts (fuel system, landing gear, jet engine...): realistic 3D,
#    the skin turns see-through to reveal the system inside, colour-coded glowing flows, small label pills.
#                                                         -> X-RAY in the studio: xray(), flow_lines(), label()
# Only the STYLE is borrowed: our own aircraft, no film characters, logos, shots or music.
#
# Two worlds in one video, switched per shot with look():  'sky' (the finished plane flying, hook + payoff)
# and 'studio' (dark blueprint studio where the episode's part is built / x-rayed).
# The aircraft never moves: in 'sky' the sea texture and clouds scroll backwards (speed m/s), so cameras stay
# simple (kb.shot) and the plane can roll / pitch with fly_motion().

SKY_PRESETS = dict(
    day=dict(zenith=(0.03, 0.16, 0.62), horizon=(0.55, 0.78, 0.95), sea=(0.0, 0.32, 0.36), deep=(0.0, 0.06, 0.16),
             sun=(1.0, 0.95, 0.86), sun_k=4.5, sun_dir=(-35, 0, 140), cloud='cloud', strength=1.0),
    sunset=dict(zenith=(0.08, 0.06, 0.30), horizon=(1.0, 0.42, 0.12), sea=(0.10, 0.10, 0.20), deep=(0.02, 0.02, 0.06),
                sun=(1.0, 0.55, 0.25), sun_k=3.5, sun_dir=(-80, 0, 200), cloud='cloud', strength=0.9),
    storm=dict(zenith=(0.02, 0.025, 0.04), horizon=(0.16, 0.19, 0.24), sea=(0.01, 0.05, 0.07), deep=(0.0, 0.01, 0.02),
               sun=(0.7, 0.8, 1.0), sun_k=1.2, sun_dir=(-60, 0, 160), cloud='cloud_storm', strength=0.8),
)
CINE = dict(sky=[], studio=[], world_fac=None, world_bg=None, preset=None, root=None)


def _tree_world():
    w = bpy.context.scene.world; nt = w.node_tree; return w, nt, nt.nodes, nt.links


def sky(preset='day', speed=35.0, duration=None, sea_z=-28.0, n_clouds=26, seed=3, motion_blur=True):
    """Build the outdoor world (sky gradient, sea with waves + foam, cumulus clouds, sun). Hidden until look()
    switches a shot to 'sky'. speed = how fast the world scrolls past the (static) plane, m/s."""
    P_ = SKY_PRESETS[preset]; CINE['preset'] = P_
    sc = bpy.context.scene; dur = duration or (sc.frame_end / FPS)
    # --- world: mix(studio colour, painted sky gradient) keyed per shot
    w, nt, N, L = _tree_world(); bg = N['Background']; out = N['World Output']
    tc = N.new('ShaderNodeTexCoord'); sep = N.new('ShaderNodeSeparateXYZ')
    L.new(tc.outputs['Generated'], sep.inputs[0])
    mr = N.new('ShaderNodeMapRange'); mr.inputs[1].default_value = -0.02; mr.inputs[2].default_value = 0.55
    L.new(sep.outputs['Z'], mr.inputs[0])
    ramp = N.new('ShaderNodeValToRGB'); cr = ramp.color_ramp
    cr.elements[0].color = P_['horizon'] + (1,); cr.elements[1].color = P_['zenith'] + (1,)
    cr.elements[0].position = 0.0; cr.elements[1].position = 1.0
    L.new(mr.outputs[0], ramp.inputs[0])
    mix, mA, mB, mF, mO = _mixc(N)
    mA.default_value = PAL['bg'] + (1,); L.new(ramp.outputs[0], mB)
    L.new(mO, bg.inputs['Color'])
    mF.default_value = 0.0
    CINE['world_fac'] = mF; CINE['world_bg'] = bg.inputs['Strength']
    # --- sun
    bpy.ops.object.light_add(type='SUN', location=(0, 0, 30)); sun = bpy.context.object; sun.name = 'gunes'
    sun.data.energy = P_['sun_k']; sun.data.color = P_['sun']; sun.data.angle = math.radians(2.5)
    sun.rotation_euler = tuple(math.radians(a) for a in P_['sun_dir'])
    # --- sea: big plane, turquoise near, deep blue far, wave bump + foam, texture scrolls with speed
    bpy.ops.mesh.primitive_plane_add(size=5000, location=(0, 1500, sea_z)); sea = bpy.context.object; sea.name = 'deniz'
    m = bpy.data.materials.new('deniz'); m.use_nodes = True; T_ = m.node_tree; n_, l_ = T_.nodes, T_.links
    b = n_['Principled BSDF']; b.inputs['Roughness'].default_value = 0.24; b.inputs['Coat Weight'].default_value = 0.3
    tco = n_.new('ShaderNodeTexCoord'); mp = n_.new('ShaderNodeMapping'); l_.new(tco.outputs['Object'], mp.inputs[0])
    mp.inputs['Scale'].default_value = (0.08, 0.08, 0.08)
    loc = mp.inputs['Location']
    loc.default_value = (0, 0, 0); loc.keyframe_insert('default_value', frame=1)
    loc.default_value = (0, speed * dur * 0.08, 0); loc.keyframe_insert('default_value', frame=F(dur) + 2)
    _linear_all(m.node_tree)
    wv = n_.new('ShaderNodeTexWave'); wv.inputs['Scale'].default_value = 1.2; wv.inputs['Distortion'].default_value = 6
    wv.inputs['Detail'].default_value = 3; l_.new(mp.outputs[0], wv.inputs['Vector'])
    nz = n_.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 3.0; nz.inputs['Detail'].default_value = 4
    l_.new(mp.outputs[0], nz.inputs['Vector'])
    bm = n_.new('ShaderNodeMath'); bm.operation = 'MULTIPLY'; l_.new(wv.outputs['Fac'], bm.inputs[0]); l_.new(nz.outputs['Fac'], bm.inputs[1])
    bump = n_.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = 0.35; l_.new(bm.outputs[0], bump.inputs['Height'])
    l_.new(bump.outputs[0], b.inputs['Normal'])
    # colour: sea -> deep with distance, foam where waves crest
    cd = n_.new('ShaderNodeCameraData'); dm = n_.new('ShaderNodeMapRange')
    dm.inputs[1].default_value = 40; dm.inputs[2].default_value = 900; l_.new(cd.outputs['View Distance'], dm.inputs[0])
    c1, a1, b1, f1, o1 = _mixc(n_); a1.default_value = P_['sea'] + (1,)
    b1.default_value = P_['deep'] + (1,); l_.new(dm.outputs[0], f1)
    fm = n_.new('ShaderNodeMapRange'); fm.inputs[1].default_value = 0.62; fm.inputs[2].default_value = 0.7
    l_.new(bm.outputs[0], fm.inputs[0])
    c2, a2, b2, f2, o2 = _mixc(n_); l_.new(o1, a2)
    b2.default_value = (0.85, 0.92, 0.95, 1); l_.new(fm.outputs[0], f2)
    # far haze towards the horizon colour
    hz = n_.new('ShaderNodeMapRange'); hz.inputs[1].default_value = 500; hz.inputs[2].default_value = 2400
    l_.new(cd.outputs['View Distance'], hz.inputs[0])
    c3, a3, b3, f3, o3 = _mixc(n_); l_.new(o2, a3)
    b3.default_value = P_['horizon'] + (1,); l_.new(hz.outputs[0], f3)
    l_.new(o3, b.inputs['Base Color'])
    sea.data.materials.append(m)
    # --- clouds: puffy clusters around (never on) the flight line, scrolling backwards
    import random; R = random.Random(seed); cl = []
    span = speed * dur + 300
    for k in range(n_clouds):
        while True:
            x = R.uniform(-140, 140); z = R.uniform(sea_z + 8, 45)
            if math.hypot(x, z - 1.2) > 22: break
        y = -120 + span * k / n_clouds + R.uniform(-15, 15)
        cl.append(_cloud(f'bulut_{k}', (x, y, z), R.uniform(5, 14), R, P_['cloud']))
    for o in cl:
        p0 = tuple(o.location); p1 = (p0[0], p0[1] - speed * dur, p0[2])
        _key(o, 'location', 0, p0, 'LINEAR'); _key(o, 'location', dur + 0.1, p1, 'LINEAR')
    try: sc.view_settings.look = 'AgX - Punchy'
    except Exception: pass
    if motion_blur:
        sc.render.use_motion_blur = True; sc.render.motion_blur_shutter = 0.5
    CINE['sky'] = [sun, sea] + cl
    CINE['studio'] = [o for o in sc.objects if o.name in ('floor', 'key', 'rim_teal', 'rim_orange', 'fill')]
    return CINE['sky']


def _mixc(N):
    """Colour Mix node -> (node, A, B, factor, result) picking the RGBA sockets."""
    m = N.new('ShaderNodeMix'); m.data_type = 'RGBA'
    A = [i for i in m.inputs if i.name == 'A' and i.type == 'RGBA'][0]
    B = [i for i in m.inputs if i.name == 'B' and i.type == 'RGBA'][0]
    o = [i for i in m.outputs if i.name == 'Result' and i.type == 'RGBA'][0]
    return m, A, B, m.inputs[0], o


def _linear_all(tree):
    ad = tree.animation_data
    if not ad or not ad.action: return
    try: fcs = ad.action.fcurves
    except AttributeError:
        fcs = [fc for layer in ad.action.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]
    for fc in fcs:
        for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'


def _cloud(name, c, size, R, material):
    """A cumulus = 6-9 lumpy spheres, flat-ish bottom."""
    import bmesh as _bm
    from mathutils import noise
    bm = _bm.new()
    for j in range(R.randint(6, 9)):
        r = size * R.uniform(0.35, 0.7)
        off = Vector((R.uniform(-1, 1) * size, R.uniform(-0.6, 0.6) * size, R.uniform(0, 0.5) * size))
        geom = _bm.ops.create_icosphere(bm, subdivisions=3, radius=r)
        for v in geom['verts']:
            p = v.co.copy(); n = noise.noise(p * (1.6 / r) + off) * 0.22 * r
            v.co = p + p.normalized() * n + off
            if v.co.z < -0.15 * size: v.co.z = -0.15 * size + (v.co.z + 0.15 * size) * 0.25
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o); o.location = c
    me.materials.append(M(material)); return o


def _vis_segments(objs, segs, want):
    """Key hide_render for objs so they render only inside segments whose mode == want."""
    objs = each(objs); full = []
    for o in objs:
        for x in [o] + list(o.children_recursive):
            if x not in full and not x.get('force_hidden'): full.append(x)
    for o in full:
        o.hide_render = segs[0][2] != want; o.keyframe_insert('hide_render', frame=1)
        for t0, t1, mode in segs:
            f = F(t0)
            if f <= 1: continue
            o.hide_render = mode != want; o.keyframe_insert('hide_render', frame=f)


def look(segs):
    """segs = [(t0, t1, 'sky'|'studio'), ...] covering the video, usually one per shot (cut times from T.cut(i)).
    Switches world colour, floor, studio lights, sea, clouds and sun."""
    segs = sorted(segs)
    _vis_segments(CINE['sky'], segs, 'sky'); _vis_segments(CINE['studio'], segs, 'studio')
    fac = CINE['world_fac']
    for t0, t1, mode in segs:
        fac.default_value = 1.0 if mode == 'sky' else 0.0; fac.keyframe_insert('default_value', frame=max(1, F(t0)))
    _constant_world()


def _constant_world():
    tree = bpy.context.scene.world.node_tree; ad = tree.animation_data
    if not ad or not ad.action: return
    try: fcs = ad.action.fcurves
    except AttributeError:
        fcs = [fc for layer in ad.action.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]
    for fc in fcs:
        for kp in fc.keyframe_points: kp.interpolation = 'CONSTANT'


def lightning(times, k=6.0):
    """Storm preset: world flashes at these times (put them on cuts or dramatic words)."""
    s = CINE['world_bg']
    s.default_value = 1.0; s.keyframe_insert('default_value', frame=1)
    for t in times:
        for dt, v in ((-0.05, 1.0), (0.0, k), (0.08, 1.5), (0.16, k * 0.7), (0.35, 1.0)):
            s.default_value = v; s.keyframe_insert('default_value', frame=max(1, F(t + dt)))


def aircraft_root(P, loc=(0, 0, 1.2)):
    """Parent every part of light_aircraft() to one empty 'ucak' so the whole plane can roll / pitch."""
    r = empty('ucak', loc); bpy.context.view_layer.update()
    for o in each(P):
        if o.parent is None: parent(o, r)
    CINE['root'] = r; return r


def fly_motion(t0, t1, bank=12.0, pitch=3.0, turb=0.6, bob=0.15, seed=1):
    """Gentle banking turn + turbulence on the whole aircraft between t0 and t1 (degrees, metres)."""
    r = CINE['root']; home = Vector(r.location); n = max(2, int((t1 - t0) * 8))
    for j in range(n + 1):
        f = j / n; t = t0 + (t1 - t0) * f; e = math.sin(math.pi * f)
        jt = _jit(seed, t, 1.0)
        _key(r, 'rotation_euler', t, (math.radians(pitch * e + turb * jt.x), math.radians(-bank * e + 2 * turb * jt.y),
                                       math.radians(turb * jt.z * 0.5)), 'LINEAR')
        _key(r, 'location', t, tuple(home + Vector((0, 0, bob * jt.z))), 'LINEAR')


def prop_blur(P, t0=0.0, t1=None):
    """Spinning-propeller look for the flying plane P: its blades are hidden for good, a translucent banded disc
    is shown instead (registered as sky-only), and the spinner turns."""
    t1 = t1 or bpy.context.scene.frame_end / FPS
    bpy.context.view_layer.update(); hub = P['prop']; c = hub.matrix_world.translation.copy()
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=0.97, fill_type='NGON', location=c + Vector((0, 0.06, 0)),
                                      rotation=(math.pi / 2, 0, 0))
    d = bpy.context.object; d.name = 'pervane_disk'
    m = bpy.data.materials.new('pervane_disk'); m.use_nodes = True; nt = m.node_tree; N, L = nt.nodes, nt.links
    out = N['Material Output']; N.remove(N['Principled BSDF'])
    tc = N.new('ShaderNodeTexCoord'); ln = N.new('ShaderNodeVectorMath'); ln.operation = 'LENGTH'
    L.new(tc.outputs['Object'], ln.inputs[0])
    ramp = N.new('ShaderNodeValToRGB'); cr = ramp.color_ramp
    cr.elements[0].position = 0.15; cr.elements[0].color = (0.03, 0.03, 0.03, 1)
    cr.elements[1].position = 0.97; cr.elements[1].color = (0.25, 0.25, 0.25, 1)
    e = cr.elements.new(0.93); e.color = (0.9, 0.6, 0.05, 1)   # painted tips make a bright ring
    L.new(ln.outputs['Value'], ramp.inputs[0])
    di = N.new('ShaderNodeBsdfDiffuse'); L.new(ramp.outputs[0], di.inputs['Color'])
    tr = N.new('ShaderNodeBsdfTransparent'); mx = N.new('ShaderNodeMixShader'); mx.inputs[0].default_value = 0.28
    L.new(tr.outputs[0], mx.inputs[1]); L.new(di.outputs[0], mx.inputs[2]); L.new(mx.outputs[0], out.inputs['Surface'])
    d.data.materials.append(m)
    if CINE['root']: parent(d, CINE['root'])
    for o in hub.children:
        if o.name.startswith('pala'): o['force_hidden'] = 1; o.hide_render = True
    CINE['sky'].append(d)
    sp = [o for o in hub.children if o.name == 'spinner']
    if sp: spin(sp[0], t0, t1, 'Y', (t1 - t0) * 3)
    return d


def xray(objs, t0, t1, back=None, color=(0.25, 0.8, 1.0)):
    """Skin turns see-through glass-blue between t0 and t1 (and back again at `back`), revealing what is inside."""
    for ob in each(objs):
        if not ob.data or not hasattr(ob.data, 'materials') or not ob.data.materials: continue
        m = ob.data.materials[0].copy(); ob.data.materials[0] = m; nt = m.node_tree; N, L = nt.nodes, nt.links
        out = N['Material Output']; pb = N['Principled BSDF']
        lw = N.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = 0.35
        em = N.new('ShaderNodeEmission'); em.inputs['Color'].default_value = color + (1,); em.inputs['Strength'].default_value = 2.5
        tr = N.new('ShaderNodeBsdfTransparent')
        xm = N.new('ShaderNodeMixShader'); L.new(lw.outputs['Facing'], xm.inputs[0]); L.new(tr.outputs[0], xm.inputs[1]); L.new(em.outputs[0], xm.inputs[2])
        mx = N.new('ShaderNodeMixShader'); L.new(pb.outputs[0], mx.inputs[1]); L.new(xm.outputs[0], mx.inputs[2])
        L.new(mx.outputs[0], out.inputs['Surface'])
        f = mx.inputs[0]
        keys = [(t0, 0.0), (t1, 1.0)] + ([(back, 1.0), (back + (t1 - t0), 0.0)] if back else [])
        for tt, v in keys:
            f.default_value = v; f.keyframe_insert('default_value', frame=max(1, F(tt)))


FONT = os.path.expanduser('~/eng/fonts/Poppins-ExtraBold.ttf')


def label(text, anchor, offset, cam, t0, t1, size=0.16, color='orange'):
    """Mechanic-Vision style pill: orange rounded badge with white Turkish text + leader line to `anchor`,
    always facing `cam` (the camera object returned by kb.shot for that line). Max 3 words."""
    pos = Vector(anchor) + Vector(offset)
    cu = bpy.data.curves.new('lbl', 'FONT'); cu.body = text.upper().replace('I', 'I').replace('i', 'İ'); cu.size = size; cu.align_x = 'CENTER'; cu.align_y = 'CENTER'
    if os.path.exists(FONT): cu.font = bpy.data.fonts.load(FONT, check_existing=True)
    tx = bpy.data.objects.new('lbl_' + text, cu); bpy.context.collection.objects.link(tx); tx.location = pos
    wm = mat('lbl_white', (1, 1, 1), emit=(1, 1, 1), emit_k=1.2); cu.materials.append(wm)
    bpy.context.view_layer.update(); bb = [Vector(c) for c in tx.bound_box]
    x0, x1 = min(v.x for v in bb), max(v.x for v in bb); y0, y1 = min(v.y for v in bb), max(v.y for v in bb)
    mx_, my_ = (x0 + x1) / 2, (y0 + y1) / 2
    h = size * 1.7; r = h / 2; w = (x1 - x0) + size * 1.4; pts = []
    for cx, a0 in ((mx_ + w / 2 - r, -90), (mx_ - (w / 2 - r), 90)):          # two half-circles = stadium shape
        for j in range(13):
            a = math.radians(a0 + 180 * j / 12); pts.append((cx + r * math.cos(a), my_ + r * math.sin(a), 0))
    pc = bpy.data.curves.new('pill', 'CURVE'); pc.dimensions = '2D'; pc.fill_mode = 'BOTH'
    sp = pc.splines.new('POLY'); sp.points.add(len(pts) - 1)
    for p_, c_ in zip(sp.points, pts): p_.co = (c_[0], c_[1], 0, 1)
    sp.use_cyclic_u = True
    pill = bpy.data.objects.new('pill_' + text, pc); bpy.context.collection.objects.link(pill); pill.location = pos
    pc.materials.append(M('orange_flat') if color == 'orange' else M('glow_teal'))
    tx.parent = pill; tx.location = (0, 0, 0.01)
    for o in (pill,):
        c = o.constraints.new('TRACK_TO'); c.target = cam; c.track_axis = 'TRACK_Z'; c.up_axis = 'UP_Y'
    line = curve_obj('leader_' + text, [Vector(anchor), pos], 0.01, 'orange_flat')
    for o in (pill, tx, line): show(o, t0); hide(o, t1)
    scale_in([pill], t0, t0 + 0.25)
    return [pill, tx, line]


def sky_only(objs):
    """Objects that exist only in 'sky' shots (e.g. the finished plane while the studio shows the half-built one).
    Call BEFORE look()."""
    CINE['sky'] += each(objs)


def studio_only(objs):
    """Objects that exist only in 'studio' shots (the episode's partial build, labels...). Call BEFORE look()."""
    CINE['studio'] += each(objs)


def finished_plane():
    """The complete series aircraft for sky shots: full build + root (for fly_motion) + prop blur ready.
    Returns (P, root). Use with sky_only(P)."""
    P = light_aircraft(99); r = aircraft_root(P); return P, r
