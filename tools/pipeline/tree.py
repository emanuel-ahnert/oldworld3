"""A procedural tree: trunk, limbs and branches as tubes, leaves as sprig cards rooted on the
branches, bark and leaf textures drawn here. Replaces generated tree models whose leaves floated
in the air (a generated tree is a cloud of leaf flakes without the twigs holding them).

blender -b --python tools/pipeline/tree.py -- <species> <out.glb> [seed]
species: beech, linden, birch, olive, cypress, bush (SPECIES below)

- The skeleton: the trunk grows up (a leader into the crown for most species), limbs leave it
  in a spiral (137.5 degrees apart) at the species' angle, as long as the crown's outline
  allows at that height (`profile`), branches leave the limbs. Every segment bends a little at
  random, toward the light (`up`) or under its weight (`droop`).
- Leaves: cards with a sprig texture (a twig with leaves on it, four variants in a 2x2 atlas),
  their base on a branch, pointing away from it. Each card is two quads back to back (single
  sided, so both faces get the same normal); the normals are bent out of the crown's middle, so
  the crown shades like one volume instead of a thousand flat cards. Cards deep inside the crown
  take the darker atlas cells (cheap ambient occlusion).
- Two materials: bark (opaque, a tiling texture) and leaves (alpha clip, glTF MASK via a Round
  node). One mesh, two surfaces: what scatter.gd expects.
Sizes are in meters for a full-grown tree; the game scales trees to their height anyway.
"""
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common  # noqa: E402

a = common.args()
SPECIES_NAME, OUT = a[0], Path(a[1])
SEED = int(a[2]) if len(a) > 2 else 1

# height m; trunk: share of the height bare / where the leader ends / radius at the base;
# limbs: count, angle from vertical (deg), spread of it, crown radius (m), outline profile;
# branches per limb, their angle, length share; card size m, cards per branch;
# leaf: shape, colors; bark: kind, color.
SPECIES = {
    "beech": dict(height=14.0, bare=0.3, leader=0.82, trunk_r=0.32, flare=1.5, wiggle=0.12,
                  limbs=16, limb_angle=55, limb_spread=14, crown_r=5.6, profile=(0.7, 0.8),
                  up=0.10, droop=0.02, branches=10, branch_angle=48, branch_len=0.42,
                  card=1.3, cards=10, limb_cards=6,
                  leaf="oval", leaf_rgb=(0.25, 0.43, 0.12), leaf_var=0.12,
                  bark="smooth", bark_rgb=(0.50, 0.49, 0.45)),
    "linden": dict(height=12.0, bare=0.25, leader=0.7, trunk_r=0.36, flare=1.6, wiggle=0.14,
                   limbs=14, limb_angle=58, limb_spread=14, crown_r=5.6, profile=(0.6, 0.95),
                   up=0.08, droop=0.03, branches=9, branch_angle=50, branch_len=0.45,
                   card=1.35, cards=9, limb_cards=6,
                   leaf="heart", leaf_rgb=(0.29, 0.46, 0.13), leaf_var=0.12,
                   bark="furrowed", bark_rgb=(0.33, 0.29, 0.25)),
    "birch": dict(height=13.0, bare=0.22, leader=0.97, trunk_r=0.18, flare=1.3, wiggle=0.08,
                  limbs=20, limb_angle=42, limb_spread=10, crown_r=2.9, profile=(0.45, 0.7),
                  up=0.12, droop=0.14, branches=7, branch_angle=40, branch_len=0.5,
                  card=1.0, cards=8, limb_cards=5,
                  leaf="birch", leaf_rgb=(0.33, 0.49, 0.16), leaf_var=0.14,
                  bark="birch", bark_rgb=(0.86, 0.85, 0.80)),
    "olive": dict(height=6.0, bare=0.3, leader=0.0, trunk_r=0.36, flare=1.7, wiggle=0.22,
                  leaders=3, limbs=13, limb_angle=62, limb_spread=14, crown_r=3.6, profile=(0.5, 0.7),
                  up=0.03, droop=0.06, branches=9, branch_angle=55, branch_len=0.5,
                  card=0.85, cards=12, limb_cards=7,
                  leaf="lance", leaf_rgb=(0.40, 0.47, 0.30), leaf_var=0.10, leaf_under=(0.62, 0.66, 0.56),
                  bark="gnarled", bark_rgb=(0.42, 0.40, 0.36), gnarl=0.22),
    "bush": dict(height=1.8, bare=0.04, leader=0.0, trunk_r=0.05, flare=1.2, wiggle=0.2,
                 leaders=6, leader_angle=(30, 55), leader_len=(0.45, 0.6), limbs=12, limb_angle=60,
                 limb_spread=15, crown_r=1.25, profile=(0.35, 0.6),
                 up=0.08, droop=0.05, branches=5, branch_angle=50, branch_len=0.6,
                 card=0.55, cards=8, limb_cards=6,
                 leaf="oval", leaf_rgb=(0.22, 0.40, 0.12), leaf_var=0.14,
                 bark="smooth", bark_rgb=(0.32, 0.27, 0.22)),
    "cypress": dict(height=13.0, bare=0.04, leader=1.0, trunk_r=0.22, flare=1.25, wiggle=0.03,
                    limbs=60, limb_angle=24, limb_spread=6, crown_r=1.05, profile=(1.0, 0.35),
                    up=0.25, droop=0.0, branches=4, branch_angle=30, branch_len=0.55,
                    card=0.95, cards=5, limb_cards=4, column=True,
                    leaf="spray", leaf_rgb=(0.15, 0.27, 0.11), leaf_var=0.08,
                    bark="furrowed", bark_rgb=(0.36, 0.27, 0.21)),
}
S = SPECIES[SPECIES_NAME]
rng = random.Random(SEED)
nrng = np.random.default_rng(SEED)
H = S["height"]
UP = Vector((0, 0, 1))


def rnd(a, b):
    return rng.uniform(a, b)


def perp(d):
    p = d.cross(Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0)))
    return p.normalized()


def turned(d, angle, azimuth):
    """`d` tipped by `angle` (rad) toward the azimuth (rad) around it."""
    p = perp(d)
    p = Matrix.Rotation(azimuth, 3, d) @ p
    return (d * math.cos(angle) + p * math.sin(angle)).normalized()


# --- the skeleton -----------------------------------------------------------------------------
class Branch:
    def __init__(self, pts, radii, level):
        self.pts, self.radii, self.level = pts, radii, level

    def at(self, t):
        f = t * (len(self.pts) - 1)
        i = min(int(f), len(self.pts) - 2)
        k = f - i
        return self.pts[i].lerp(self.pts[i + 1], k), self.radii[i] + (self.radii[i + 1] - self.radii[i]) * k, \
            (self.pts[i + 1] - self.pts[i]).normalized()


def grow(start, d, length, r0, r1, level, seg=None, wiggle=None, up=None, droop=None):
    seg = seg or max(0.25, length / (10 if level == 0 else 6))
    n = max(2, int(round(length / seg)))
    step = length / n
    pts, radii = [start.copy()], [r0]
    p, d = start.copy(), d.normalized()
    wig = S["wiggle"] if wiggle is None else wiggle
    for i in range(n):
        d = (d + Vector((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))) * wig
             + UP * (S["up"] if up is None else up) * (0.3 if level == 0 else 1.0)
             - UP * (S["droop"] if droop is None else droop) * (level * level) * (i / n)).normalized()
        p = p + d * step
        pts.append(p.copy())
        radii.append(r0 + (r1 - r0) * ((i + 1) / n) ** 0.8)
    return Branch(pts, radii, level)


branches = []
crown_base = S["bare"] * H
crown_top = H
crown_mid = Vector((0, 0, (crown_base + crown_top) / 2))


def outline(t):
    """The crown's radius share at height share t (0 at its base, 1 at the top)."""
    peak, fullness = S["profile"]
    if S.get("column"):
        return max(0.08, (1 - t) ** 0.45 * min(1.0, 0.75 + t * 2.5)) * (0.9 + 0.1 * fullness)
    x = min(max(t, 0.0), 1.0) ** (1.0 / max(peak, 0.05) * 0.5)
    return max(0.12, math.sin(math.pi * x) ** fullness)


trunk_len = H * (S["leader"] if S["leader"] > 0 else S["bare"] * 1.15)
trunk = grow(Vector((0, 0, 0)), UP, trunk_len, S["trunk_r"], S["trunk_r"] * (0.12 if S["leader"] > 0.9 else 0.45), 0,
             wiggle=S["wiggle"] * 0.5)
branches.append(trunk)
# The root flare: the first ring wider.
trunk.radii[0] *= S["flare"]
trunk.radii[1] *= 1 + (S["flare"] - 1) * 0.35

sources = []      # (branch, t from, t to) limbs come from
if S["leader"] > 0:
    sources.append((trunk, S["bare"] / S["leader"], 0.97))
else:
    # Olive: the trunk forks into a few leaders spreading out, limbs come from them.
    top, rt, dt = trunk.at(1.0)
    for k in range(S["leaders"]):
        az = k * 2 * math.pi / S["leaders"] + rnd(-0.25, 0.25)
        la0, la1 = S.get("leader_angle", (24, 34))
        ll0, ll1 = S.get("leader_len", (0.4, 0.5))
        d = turned(UP, math.radians(rnd(la0, la1)), az)
        ld = grow(top, d, H * rnd(ll0, ll1), rt * 0.72, rt * 0.2, 0, wiggle=S["wiggle"])
        branches.append(ld)
        sources.append((ld, 0.25, 0.95))

limbs = []
az = rnd(0, 6.28)
for src, t0, t1 in sources:
    count = S["limbs"] // len(sources) + (1 if S["leader"] <= 0 else 0)
    for i in range(count):
        t = t0 + (t1 - t0) * (i + rnd(0.1, 0.9)) / count
        p, r, d = src.at(t)
        az += math.radians(137.5) + rnd(-0.3, 0.3)
        ht = (p.z - crown_base) / (crown_top - crown_base)
        ang = math.radians(S["limb_angle"] + rnd(-1, 1) * S["limb_spread"] - 14 * max(ht - 0.5, 0))
        dd = turned(UP if src is trunk else d, ang, az)
        reach = S["crown_r"] * outline(ht) * rnd(0.85, 1.1)
        length = reach / max(math.sin(ang), 0.35) * (1.0 if S.get("column") else 0.95)
        if length < 0.3:
            continue
        lb = grow(p, dd, length, min(r * 0.62, S["trunk_r"] * 0.5) * (0.6 if S.get("column") else 1.0), 0.02, 1)
        branches.append(lb)
        limbs.append(lb)

twigs = []
for lb in limbs:
    length = sum((lb.pts[i + 1] - lb.pts[i]).length for i in range(len(lb.pts) - 1))
    n = max(2, int(S["branches"] * min(1.3, length / (S["crown_r"] * 0.9))))
    baz = rnd(0, 6.28)
    for i in range(n):
        t = 0.25 + 0.72 * (i + rnd(0.2, 0.8)) / n
        p, r, d = lb.at(t)
        baz += math.radians(137.5) + rnd(-0.4, 0.4)
        dd = turned(d, math.radians(S["branch_angle"] + rnd(-12, 12)), baz)
        dd = (dd + UP * 0.15).normalized()
        tw = grow(p, dd, length * S["branch_len"] * (1.1 - 0.6 * t) * rnd(0.7, 1.1), max(r * 0.6, 0.015), 0.008, 2)
        branches.append(tw)
        twigs.append(tw)

# --- tubes --------------------------------------------------------------------------------------
V, N, UV, F, MAT = [], [], [], [], []      # positions, normals, uvs, faces (vertex index lists), material
SIDES = {0: 9, 1: 5, 2: 3}
## Every how many points of a branch's path its tube takes a ring: twigs (inside the crown,
## hardly seen) every other one. The path itself stays (the leaves sit on it): the same tree,
## a third of its branch triangles (they were half of the model's).
RING_EVERY = {0: 1, 1: 1, 2: 2}


def tube(b):
    sides = SIDES[b.level]
    base = len(V)
    keep = list(range(0, len(b.pts), RING_EVERY[b.level]))
    if keep[-1] != len(b.pts) - 1:
        keep.append(len(b.pts) - 1)
    b = Branch([b.pts[i] for i in keep], [b.radii[i] for i in keep], b.level)
    # Frames along the branch (parallel transport, so the tube doesn't twist).
    d0 = (b.pts[1] - b.pts[0]).normalized()
    nrm = perp(d0)
    along = 0.0
    circ0 = 2 * math.pi * max(b.radii[0], 0.02)
    for i, p in enumerate(b.pts):
        d = (b.pts[min(i + 1, len(b.pts) - 1)] - b.pts[max(i - 1, 0)]).normalized()
        nrm = (nrm - d * nrm.dot(d)).normalized()
        bin_ = d.cross(nrm)
        if i:
            along += (b.pts[i] - b.pts[i - 1]).length
        for k in range(sides + 1):
            ang = 2 * math.pi * k / sides
            out = nrm * math.cos(ang) + bin_ * math.sin(ang)
            # Bark bulges: a little noise in the radius (trunks and limbs).
            bump = 1.0 + (0.06 * math.sin(3 * ang + i * 1.7) if b.level == 0 else 0.0)
            if b.level == 0 and S.get("gnarl"):
                # Gnarled (olive): twisted ridges spiralling up and knobbly swellings.
                g = S["gnarl"]
                bump += g * math.sin(2 * ang + i * 0.9) * 0.7 + g * 0.5 * math.sin(5 * ang - i * 1.3) * (1 - i / len(b.pts))
            V.append(p + out * b.radii[i] * bump)
            N.append(out)
            UV.append((k / sides * (2 if b.level == 0 else 1), along / circ0 * (2 if b.level == 0 else 1)))
    ring = sides + 1
    for i in range(len(b.pts) - 1):
        for k in range(sides):
            a0 = base + i * ring + k
            F.append((a0, a0 + 1, a0 + ring + 1, a0 + ring))
            MAT.append(0)


for b in branches:
    tube(b)

# --- leaf cards --------------------------------------------------------------------------------
crown_r = S["crown_r"]


def card(p, out, size, inner):
    """A sprig card from p along `out`, two quads back to back; normals bent out of the crown."""
    side = out.cross(Vector((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))).normalized())
    if side.length < 1e-3:
        side = perp(out)
    side.normalize()
    face = side.cross(out).normalized()
    if face.z < 0:
        face = -face
        side = -side
    w = size * rnd(0.8, 1.1)
    h = size * rnd(0.85, 1.15)
    rel = p + out * h * 0.5 - crown_mid
    rel.z *= crown_r / max((crown_top - crown_base) / 2, 0.1)
    sph = rel.normalized() if rel.length > 1e-3 else UP
    # Atlas cell: 0..3, darker inside the crown.
    cell = 3 if inner > 0.75 else (2 if inner > 0.5 else rng.choice((0, 1)))
    cu, cv = (cell % 2) * 0.5, (cell // 2) * 0.5
    corners = [p - side * w / 2, p + side * w / 2, p + side * w / 2 + out * h, p - side * w / 2 + out * h]
    if min(c.z for c in corners) < 0.03 * H:
        return                    # under the ground: the model's bottom must be the trunk's foot
    uvs = [(cu, cv), (cu + 0.5, cv), (cu + 0.5, cv + 0.5), (cu, cv + 0.5)]
    # One quad (the leaf material is double-sided; the game's leaf shader keeps this normal on
    # both sides: two quads back to back were half of a tree's triangles).
    for flip in (False,):
        base = len(V)
        n = (sph * 0.75 + (face if not flip else -face) * 0.25).normalized()
        for c, uv in zip(corners, uvs):
            V.append(c)
            N.append(n)
            UV.append(uv)
        F.append((base, base + 1, base + 2, base + 3) if not flip else (base + 3, base + 2, base + 1, base))
        MAT.append(1)


def place_cards(b, count, t0):
    for i in range(count):
        t = t0 + (1 - t0) * (i + rnd(0.1, 0.9)) / count
        p, r, d = b.at(t)
        out = turned(d, math.radians(rnd(25, 70)), rnd(0, 6.28))
        rel = p - crown_mid
        rel.z *= crown_r / max((crown_top - crown_base) / 2, 0.1)
        inner = 1.0 - min(rel.length / crown_r, 1.0)
        card(p, (out + rel.normalized() * 0.4 + UP * 0.15).normalized(), S["card"], inner)
    # The tip: a sprig continuing the branch.
    p, r, d = b.at(1.0)
    card(p - d * S["card"] * 0.15, d, S["card"], 0.0)


for tw in twigs:
    place_cards(tw, S["cards"], 0.2)
for lb in limbs:
    place_cards(lb, S["limb_cards"], 0.55)
if S["leader"] > 0.9:
    place_cards(trunk, S["limb_cards"] * 2, 0.85)

print(f"TREE {SPECIES_NAME}: {len(branches)} branches ({len(limbs)} limbs, {len(twigs)} twigs), "
      f"{sum(1 for m in MAT if m == 1)} leaf cards, {len(F)} faces, {len(V)} vertices")


# --- textures ---------------------------------------------------------------------------------
def periodic_noise(h, w, fy, fx, power=2.0, seed=0):
    """Tileable noise: random spectrum, falloff 1/f^power, anisotropic by (fy, fx) cutoffs."""
    g = np.random.default_rng(seed)
    ky = np.fft.fftfreq(h)[:, None] * h / fy
    kx = np.fft.fftfreq(w)[None, :] * w / fx
    k = np.sqrt(ky * ky + kx * kx)
    k[0, 0] = 1
    spec = (g.normal(size=(h, w)) + 1j * g.normal(size=(h, w))) / k ** power
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    return (n - n.mean()) / (n.std() + 1e-9)


def bark_image():
    h, w = 512, 256
    c = np.array(S["bark_rgb"])
    kind = S["bark"]
    if kind == "smooth":          # beech: smooth grey with soft lichen patches
        n = periodic_noise(h, w, 30, 30, 1.6, 1) * 0.05 + periodic_noise(h, w, 4, 8, 2.0, 2) * 0.04
        img = c[None, None, :] * (1 + n[..., None])
        lich = np.clip(periodic_noise(h, w, 10, 10, 1.8, 3) - 1.1, 0, 1)[..., None]
        img = img * (1 - lich * 0.5) + np.array([0.45, 0.5, 0.35]) * lich * 0.5
    elif kind == "birch":         # white with black horizontal lenticels and dark patches
        n = periodic_noise(h, w, 40, 20, 1.5, 1) * 0.04
        img = c[None, None, :] * (1 + n[..., None])
        dash = periodic_noise(h, w, 2.5, 40, 1.2, 4)
        mark = np.clip((dash - 1.6) * 1.5, 0, 1)
        patch = np.clip((periodic_noise(h, w, 12, 10, 2.2, 5) - 1.3) * 1.2, 0, 1)
        dark = np.clip(mark + patch, 0, 1)[..., None]
        img = img * (1 - dark) + np.array([0.08, 0.07, 0.07]) * dark
    else:                         # furrowed / gnarled: vertical ridges and cracks
        ridges = periodic_noise(h, w, 3 if kind == "furrowed" else 8, 26, 1.8, 6)
        cracks = np.clip(-ridges - 0.4, 0, 2)
        n = periodic_noise(h, w, 40, 40, 1.4, 7) * 0.05
        shade = 1 + 0.12 * ridges - 0.35 * cracks + n
        img = c[None, None, :] * shade[..., None]
    return np.clip(img, 0, 1)


def leaf_mask(u, wv, shape):
    """Leaf outline in leaf coordinates: u 0..1 base to tip, wv across (signed)."""
    u = np.clip(u, 0, 1)
    if shape == "oval":
        half = 0.42 * np.sin(np.pi * u) ** 0.85 * (1 - 0.25 * u)
    elif shape == "heart":
        half = 0.55 * np.sin(np.pi * u ** 0.75) ** 0.8 * (1 - 0.3 * u) + 0.08 * np.exp(-((u - 0.05) / 0.05) ** 2)
    elif shape == "birch":
        half = 0.5 * u ** 0.35 * (1 - u) ** 0.9 * 1.4
        half *= 1 + 0.08 * np.sin(u * 60)          # serrated edge
    elif shape == "lance":
        half = 0.14 * np.sin(np.pi * u) ** 0.6
    else:                                          # spray: scale foliage, a narrow frond
        half = 0.3 * np.sin(np.pi * u) ** 0.5 * (1 + 0.25 * np.sin(u * 40))
    return np.abs(wv) < half, half


def leaf_atlas():
    """Four sprigs (2x2) on 1024x1024, drawn at 2x and filtered down: a twig from the bottom of
    each cell, leaves alternating along it; cells 2 and 3 darker (inner crown)."""
    R = 1024
    SS = 2
    big = R * SS
    rgb = np.zeros((big, big, 3))
    alpha = np.zeros((big, big))
    shape = S["leaf"]
    base = np.array(S["leaf_rgb"])
    under = np.array(S.get("leaf_under", S["leaf_rgb"]))
    cell = big // 2
    yy, xx = np.mgrid[0:cell, 0:cell] / cell        # y down in the image
    for ci in range(4):
        r = random.Random(SEED * 10 + ci)
        tone = (1.08, 1.0, 0.86, 0.74)[ci]
        crgb = np.zeros((cell, cell, 3))
        ca = np.zeros((cell, cell))
        # Twig: from the bottom middle up, a gentle curve.
        bend = r.uniform(-0.12, 0.12)
        stem_x = lambda v: 0.5 + bend * (1 - v) ** 2 - bend
        v = 1 - yy
        twig_w = 0.012 * (1.2 - v)
        on_twig = (np.abs(xx - stem_x(v)) < twig_w) & (v < 0.88)
        crgb[on_twig] = np.array(S["bark_rgb"]) * 0.7
        ca[on_twig] = 1
        nleaves = {"oval": 9, "heart": 7, "birch": 11, "lance": 16, "spray": 22}[shape]
        size = {"oval": 0.34, "heart": 0.4, "birch": 0.26, "lance": 0.36, "spray": 0.3}[shape]
        order = list(range(nleaves))
        for li in order:
            tv = 0.08 + 0.8 * li / nleaves
            side = 1 if li % 2 else -1
            ang = side * math.radians(r.uniform(35, 70)) * (1 - 0.6 * tv)
            if li == nleaves - 1:
                ang = 0.0
                tv = 0.85
            sx, sy = stem_x(tv), 1 - tv
            L = size * r.uniform(0.8, 1.1) * (1 - 0.35 * tv)
            dx, dy = math.sin(ang), -math.cos(ang)       # leaf axis in image coords (up = -y)
            px, py = xx - sx, yy - sy
            lu = (px * dx + py * dy) / L
            lw = (px * -dy + py * dx) / L
            inside, half = leaf_mask(lu, lw, shape)
            inside &= (lu > 0) & (lu < 1)
            col = base * r.uniform(1 - S["leaf_var"], 1 + S["leaf_var"]) * tone
            # Lighter on one side of the midrib, a darker midrib and edge, the underside tone on
            # the olive's curled-up half.
            side_light = np.where(lw > 0, 1.08, 0.92)
            edge = np.clip(1 - np.abs(lw) / np.maximum(half, 1e-3), 0, 1)
            shade = side_light * (0.82 + 0.18 * edge ** 0.5) * (1 - 0.25 * np.exp(-(lw / 0.02) ** 2))
            leafc = col[None, None, :] * shade[..., None]
            if "leaf_under" in S:
                leafc = np.where((lw < 0)[..., None], under[None, None, :] * tone * shade[..., None], leafc)
            crgb[inside] = leafc[inside]
            ca[inside] = 1
        y0, x0 = (ci // 2) * cell, (ci % 2) * cell
        # Cell rows: v 0 at the bottom of the image in glTF/Blender UVs; row 0 (cells 0,1) is
        # the bottom half.
        y0 = big - y0 - cell
        rgb[y0:y0 + cell, x0:x0 + cell] = crgb
        alpha[y0:y0 + cell, x0:x0 + cell] = ca
    rgb = rgb.reshape(R, SS, R, SS, 3).mean((1, 3))
    alpha = alpha.reshape(R, SS, R, SS).mean((1, 3))
    # Transparent texels take the leaf color (no dark fringe when filtered).
    mean = (rgb * alpha[..., None]).sum((0, 1)) / max(alpha.sum(), 1)
    rgb = np.where(alpha[..., None] > 0.01, rgb / np.maximum(alpha[..., None], 1e-3), mean)
    return np.clip(rgb, 0, 1), alpha


def to_image(name, rgb, alpha=None):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=alpha is not None)
    px = np.ones((h, w, 4))
    px[..., :3] = rgb
    if alpha is not None:
        px[..., 3] = alpha
    # Blender images are bottom row first; the arrays here are top row first.
    img.pixels.foreach_set(px[::-1].ravel().astype(np.float32))
    img.file_format = "PNG"
    img.pack()
    return img


common.reset()
bark_img = to_image(f"{SPECIES_NAME}_bark", bark_image())
lrgb, la = leaf_atlas()
leaf_img = to_image(f"{SPECIES_NAME}_leaves", lrgb, la)


def material(name, img, clip):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85 if clip else 0.95
    bsdf.inputs["Metallic"].default_value = 0.0
    if clip:
        rnd_ = nt.nodes.new("ShaderNodeMath")
        rnd_.operation = "ROUND"
        nt.links.new(tex.outputs["Alpha"], rnd_.inputs[0])
        nt.links.new(rnd_.outputs[0], bsdf.inputs["Alpha"])
    m.use_backface_culling = not clip         # leaves: double-sided cards
    return m


# --- the mesh ---------------------------------------------------------------------------------
me = bpy.data.meshes.new(SPECIES_NAME)
me.from_pydata([tuple(v) for v in V], [], F)
uv = me.uv_layers.new(name="UVMap")
loop_uv = []
loop_n = []
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        loop_uv.extend(UV[vi])
        loop_n.append(tuple(N[vi]))
uv.data.foreach_set("uv", loop_uv)
for poly, m in zip(me.polygons, MAT):
    poly.material_index = m
    poly.use_smooth = True
me.materials.append(material(f"{SPECIES_NAME}_bark", bark_img, False))
me.materials.append(material(f"{SPECIES_NAME}_leaves", leaf_img, True))
me.normals_split_custom_set(loop_n)
me.update()
obj = bpy.data.objects.new(SPECIES_NAME, me)
bpy.context.scene.collection.objects.link(obj)
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", use_selection=True,
                          export_normals=True, export_materials="EXPORT")
print("wrote", OUT)
