"""Headgear built around the base body's real head, worn as skinned layers at the head's full
size (no shrinking the head to fit a model: the shrunken head showed inside open helmets).

blender -b --python tools/pipeline/headgear.py -- <body_dir> <kind> <out.glb>
kind: hood (cloth), coif (mail), cowl (leather cap), helm (plate)

- The head's outline: around a point in the middle of the head, for every direction (elevation
  x azimuth bins), the farthest body vertex of the head and the top of the neck (hair, nose,
  ears and chin included). Blurred wide, so the shell is round like WoW's headgear instead of
  following every bump; then OFFSET m outward.
- A grid shell on that outline, the face opening cut out (an oval per kind; the helm only gets
  an eye slit), the bottom cut off along the neck (lower at the back), never down to the
  shoulders, so it goes with any chest armor.
- Thickness by Solidify (the inside darker); per vertex for shaders/headgear.gdshader:
  UV = (azimuth 0..1 from the back, elevation 0..1), COLOR = (inside, distance to the nearest
  edge / 0.1 m, 0, 1).
- Skinned to the head, the part below the head's base blends to the neck.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import common  # noqa: E402

a = common.args()
body_dir, KIND, out = Path(a[0]), a[1], Path(a[2])

# offset m, thickness m, face opening (center elevation, half height, half width in degrees; None:
# closed), open below the opening's middle (leather cap: the cheeks free), bottom cut below the head
# base at the front / back (m), ridge on top (m).
KINDS = {
    "hood": dict(offset=0.012, thick=0.007, face=(-17, 36, 54), arch=1.6, open_below=False, cut=(0.055, 0.075), ridge=0.0, blur=3,
                 snug=0.9, tip=0.06, tube=-56, shown=0.62),
    "coif": dict(offset=0.010, thick=0.005, face=(-15, 33, 50), arch=1.7, open_below=False, cut=(0.095, 0.10), ridge=0.0, blur=2,
                 snug=0.88, tube=-56, shown=0.7),
    "cowl": dict(offset=0.010, thick=0.006, face=(-12, 28, 74), arch=1.8, open_below=True, cut=(0.0, 0.045), ridge=0.0, blur=2,
                 snug=0.88, tube=-56, shown=0.26),
    "helm": dict(offset=0.026, thick=0.007, face=None, open_below=False, cut=(0.06, 0.085), ridge=0.012, blur=3,
                 snug=0.92, tube=-56, shown=2.0),
}
K = KINDS[KIND]

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
if rig.animation_data:
    rig.animation_data.action = None
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)

bco = np.array([body.matrix_world @ v.co for v in body.data.vertices])
NECK = float((rig.matrix_world @ rig.data.bones["Head"].head_local).z)
head_g = body.vertex_groups["Head"].index
head_v = np.array([any(g.group == head_g and g.weight > 0.5 for g in v.groups) for v in body.data.vertices])
head_y = float(np.median(bco[head_v, 1]))
# The face's center line: the head mesh sits ~3 cm to the side of the head bone (x = 0), and its
# hair is lopsided; the nose tip and the chin tip give the line the shells are centered on
# (centered on the bone, one side bulged out and the other sat tight).
H_ = bco[head_v]
mid_ = H_[(H_[:, 2] > NECK + 0.06) & (H_[:, 2] < NECK + 0.12)]
low_ = H_[(H_[:, 2] > NECK - 0.05) & (H_[:, 2] < NECK + 0.02)]
CX = float((mid_[np.argmin(mid_[:, 1]), 0] + low_[np.argmin(low_[:, 1]), 0]) / 2)
neck_pts = bco[(bco[:, 2] > NECK - 0.1) & (bco[:, 2] < NECK) & (np.abs(bco[:, 0] - CX) < 0.09)]
AXY = np.array([float(np.median(neck_pts[:, 0])), float(np.median(neck_pts[:, 1]))])
HC = np.array([CX, head_y, NECK + 0.10])
print(f"CENTER face line x {CX:.3f}, neck axis {AXY[0]:.3f}, {AXY[1]:.3f}")
# The head and the neck (not the shoulders: only points near the neck's axis below the head).
near_axis = np.hypot(bco[:, 0] - AXY[0], bco[:, 1] - AXY[1]) < 0.085
pts = bco[(bco[:, 2] > NECK - 0.02) | ((bco[:, 2] > NECK - 0.16) & near_axis)]
d = pts - HC
rr = np.linalg.norm(d, axis=1)
EL = np.degrees(np.arcsin(np.clip(d[:, 2] / rr, -1, 1)))
AZ = np.degrees(np.arctan2(d[:, 0], -d[:, 1]))        # 0 = straight ahead (-y), +90 = left (+x)

NE, NA = 46, 96                                        # elevation -85..90, azimuth -180..180
E0, E1 = -85.0, 86.0
ei = np.clip(((EL - E0) / (E1 - E0) * (NE - 1)).round().astype(int), 0, NE - 1)
ai = (((AZ + 180) / 360 * NA).round().astype(int)) % NA
R = np.zeros((NE, NA))
np.maximum.at(R, (ei, ai), rr)
# Fill bins without points (straight down, small gaps) from their neighbours.
for _ in range(30):
    empty = R == 0
    if not empty.any():
        break
    nb = np.maximum.reduce([np.roll(R, 1, 1), np.roll(R, -1, 1), np.roll(R, 1, 0), np.roll(R, -1, 0)])
    R[empty] = nb[empty]
# Round: an egg around the head (its own extent ahead, behind, to the sides, up and down; the
# hair's top by a high percentile, so single strands don't make a peak), the local outline only
# where something still pokes out of it; under the chin and around the neck the outline itself.
hp = d[pts[:, 2] > NECK - 0.01]
EX = np.percentile(np.abs(hp[:, 0]), 99.5)
EF = np.percentile(-hp[:, 1], 99.5)
EB = np.percentile(hp[:, 1], 99.5)
EU = np.percentile(hp[:, 2], 96.0)
ED = -np.percentile(hp[:, 2], 0.5)
print(f"EGG side {EX:.3f} front {EF:.3f} back {EB:.3f} up {EU:.3f} down {ED:.3f}")


def egg(e, az, kx=1.0, kb=1.0, ku=1.0, jaw=0.0):
    """The egg's radius toward (e, az); kx, kb, ku scale its sides, back and top; `jaw` narrows
    the sides below the temples toward the jaw (a head is widest at the temples)."""
    er, ar = math.radians(e), math.radians(az)
    x, y, z = math.cos(er) * math.sin(ar), -math.cos(er) * math.cos(ar), math.sin(er)
    sy = EF if y < 0 else EB * kb
    sz = EU * ku if z > 0 else ED
    sx = EX * kx * (1 - jaw * min(max((0.15 - z) / 0.75, 0.0), 1.0))
    return 1.0 / math.sqrt((x / sx) ** 2 + (y / sy) ** 2 + (z / sz) ** 2)


bw = K["blur"]
M = R.copy()
for de in range(-bw, bw + 1):
    for da in range(-bw * 2, bw * 2 + 1):
        sh = np.roll(np.roll(R, da, 1), de, 0)
        if de > 0:
            sh[:de] = 0
        elif de < 0:
            sh[de:] = 0
        M = np.maximum(M, sh)
for _ in range(6):
    M = (M * 2 + np.roll(M, 1, 1) + np.roll(M, -1, 1) + np.vstack([M[:1], M[:-1]]) + np.vstack([M[1:], M[-1:]])) / 6
M = np.maximum(M, R + 0.004)                           # the averaging must not cut into the head
elev0 = np.linspace(E0, E1, NE)
azim0 = np.linspace(-180, 180, NA, endpoint=False)
EGG = np.array([[egg(e, az) for az in azim0] for e in elev0])
w = np.clip((elev0[:, None] + 50) / 25, 0, 1)          # 0 under the chin and below .. 1 from the jaw up
w = w * w * (3 - 2 * w)
# Where the head pokes out of the egg (ears, a hair tuft): its outline averaged wide, so single
# strands don't raise a spike.
avg = R.copy()
for _ in range(8):
    avg = (avg * 2 + np.roll(avg, 1, 1) + np.roll(avg, -1, 1) + np.vstack([avg[:1], avg[:-1]]) + np.vstack([avg[1:], avg[-1:]])) / 6
local = np.maximum(EGG, avg + 0.006)
# Above the brow only the egg: the hair there isn't drawn under headgear (body_slots.gdshader,
# hide_hair), so its tufts mustn't shape the shell.
top_w = np.clip((elev0[:, None] - 20) / 20, 0, 1)
local = local * (1 - top_w) + EGG * top_w
for _ in range(3):
    local = (local * 2 + np.roll(local, 1, 1) + np.roll(local, -1, 1) + np.vstack([local[:1], local[:-1]]) + np.vstack([local[1:], local[-1:]])) / 6
M = M * (1 - w) + local * w

# Snug (the hood): under headgear only the face and the neck are drawn (hide_hair), so away from
# them the shell may hug the head inside the hair's outline: SNUG of the egg, the face (within the
# opening, below the brow) and chin and neck kept clear. Mirrored left to right (the hair's bangs
# made it lopsided). A soft point at the back, up a little (a hood's tip).
if K.get("snug"):
    # What the game draws under the hood (body_slots.gdshader hide_hair, FACE_SHOWN of the hood):
    # the face below the brow and within ~57 degrees of ahead, the neck.
    up_ = d[:, 2] - 0.0
    flat_ = d[:, :2]
    ahead = -flat_[:, 1] / np.maximum(np.linalg.norm(flat_, axis=1), 1e-6)
    near_neck = np.hypot(pts[:, 0] - AXY[0], pts[:, 1] - AXY[1]) < 0.075
    # The face below the eyes (above them the opening is free; the bangs mustn't push a visor
    # out), the neck near its axis (not the hair strands hanging beside it).
    shown = ((up_ < 0.0) & (ahead > K["shown"])) | ((up_ < -0.12) & near_neck)
    RF = np.zeros((NE, NA))
    np.maximum.at(RF, (ei[shown], ai[shown]), rr[shown])
    RF = np.maximum(RF, RF[:, (NA - np.arange(NA)) % NA])
    keep = RF.copy()
    for de in (-1, 0, 1):
        for da in (-1, 0, 1):
            sh = np.roll(np.roll(RF, da, 1), de, 0)
            if de > 0:
                sh[:de] = 0                  # rows don't wrap (the neck's rows onto the top)
            elif de < 0:
                sh[de:] = 0
            keep = np.maximum(keep, sh)
    keep = np.where(keep > 0, keep + 0.006, 0.0)
    # The ears and the hair at the sides aren't drawn under headgear: the sides narrowest.
    sn = K["snug"]
    # Head-shaped, not a ball: narrower than deep, a little taller, the skull reaching back
    # further than the face forward, the sides narrowing from the temples to the jaw.
    SNUG = np.array([[egg(e, az, kx=sn * 0.82, kb=sn * 1.08, ku=sn * 1.12, jaw=0.24) for az in azim0] for e in elev0])
    tight = np.maximum(SNUG, keep)
    S2 = tight
    # Smoothed wide, so the face swells the shell gently instead of raising lips at the opening;
    # the face may then reach a few mm into the shell's thickness at most.
    for _ in range(10):
        S2 = (S2 * 2 + np.roll(S2, 1, 1) + np.roll(S2, -1, 1) + np.vstack([S2[:1], S2[:-1]]) + np.vstack([S2[1:], S2[-1:]])) / 6
    S2 = np.maximum(S2, keep - 0.004)
    M = np.maximum(S2, S2[:, (NA - np.arange(NA)) % NA])
    if K.get("tip"):
        tip_dir = np.array([0.0, math.cos(math.radians(32)), math.sin(math.radians(32))])   # behind (+y), up
        for i, e in enumerate(elev0):
            for j, az in enumerate(azim0):
                er, ar = math.radians(e), math.radians(az)
                dv = np.array([math.cos(er) * math.sin(ar), -math.cos(er) * math.cos(ar), math.sin(er)])
                ang = math.degrees(math.acos(max(-1.0, min(1.0, float(dv @ tip_dir)))))
                f = max(0.0, 1 - ang / 40.0)
                M[i, j] += K["tip"] * f ** 3.0

# --- the grid shell -------------------------------------------------------------------------------
def cut_z(az):
    back = (1 - math.cos(math.radians(az))) / 2               # 0 ahead .. 1 behind
    return NECK - (K["cut"][0] + (K["cut"][1] - K["cut"][0]) * back)


elev = np.linspace(E0, E1, NE)
azim = np.linspace(-180, 180, NA, endpoint=False)
verts, uvs = [], []
for i, e in enumerate(elev):
    for j, az in enumerate(azim):
        r = M[i, j] + K["offset"]
        if K["ridge"] and e > 20:
            # A ridge over the top from front to back (the helm's comb).
            r += K["ridge"] * math.exp(-(math.sin(math.radians(az)) * math.cos(math.radians(e)) / 0.06) ** 2) * min(1, (e - 20) / 25)
        er, ar = math.radians(e), math.radians(az)
        dv = np.array([math.cos(er) * math.sin(ar), -math.cos(er) * math.cos(ar), math.sin(er)])
        verts.append(HC + dv * r)
        uvs.append(((az + 180) / 360, (e - E0) / (E1 - E0)))
verts = np.array(verts)

# Below the chin (the hood): the rows below elevation `tube` run down along the neck instead of
# out along rays from the head's middle (those go down inside the neck): each column from its
# join-row vertex down to the cut, its distance from the neck's axis easing to the neck's own
# radius there (chin and neck, not the hair beside them) plus the offset. The last row is the
# bottom edge.
if K.get("tube"):
    EJ = K["tube"]
    ij = int(np.argmax(elev >= EJ))
    rel = bco[:, :2] - AXY
    rad = np.hypot(rel[:, 0], rel[:, 1])
    # One radius for the neck (the shirt's collar flaps below it would crumple the cloth).
    nsel = (bco[:, 2] > NECK - 0.05) & (bco[:, 2] < NECK - 0.01) & (rad < 0.08)
    RN = float(np.percentile(rad[nsel], 85))
    print(f"NECK radius {RN:.3f}")

    for j, az in enumerate(azim):
        J = verts[ij * NA + j]
        hj = J[:2] - AXY
        ar = math.radians(az)
        dirh = np.array([math.sin(ar), -math.cos(ar)])
        zbot = cut_z(az) + 0.002
        ahead = (1 + math.cos(ar)) / 2                       # 1 ahead .. 0 behind
        z_in = NECK - 0.035 * ahead ** 2                      # below the chin in front, at the head's base behind
        for i in range(ij):
            t = (elev[ij] - elev[i]) / (elev[ij] - E0)
            z = J[2] + (zbot - J[2]) * t
            h = dirh * (RN + K["offset"] + 0.006)
            w_ = min(max((z_in + 0.005 - z) / 0.025, 0.0), 1.0)
            w_ = w_ * w_ * (3 - 2 * w_)
            hh = hj * (1 - w_) + h * w_
            verts[i * NA + j] = np.array([AXY[0] + hh[0], AXY[1] + hh[1], z])
    # The seam between the head part and the tube: the rows around it smoothed (no crease under
    # the chin), the bottom row and the rows far from it kept.
    G = verts[:NE * NA].reshape(NE, NA, 3)
    band = range(max(1, ij - 7), min(NE - 1, ij + 6))
    for _ in range(12):
        Gn = G.copy()
        for i in band:
            Gn[i] = (G[i] * 2 + G[i - 1] + G[i + 1] + np.roll(G[i], 1, 0) + np.roll(G[i], -1, 0)) / 6
        G = Gn
    verts[:NE * NA] = G.reshape(-1, 3)


def vid(i, j):
    return i * NA + (j % NA)


def is_open(e, az):
    """The face opening (or the helm's eye slit)."""
    if K["face"] is None:
        return abs(az) < 50 and -9 < e < 3                      # the helm's eye slit
    ec, eh, aw = K["face"]
    if K["open_below"] and abs(az) < aw and e < ec:
        return True
    return _oval(az / aw, (e - ec) / eh) < 1.0


def _oval(x, y):
    """The opening's shape: an ellipse, its upper half arched (a superellipse, `arch` < 2)."""
    p = K.get("arch", 2.0) if y > 0 else 2.0
    return (abs(x) ** p + abs(y) ** p) ** (1.0 / p)



faces = []
for i in range(NE - 1):
    for j in range(NA):
        q = [vid(i, j), vid(i, j + 1), vid(i + 1, j + 1), vid(i + 1, j)]
        c = verts[q].mean(0)
        e = (elev[i] + elev[i + 1]) / 2
        az = azim[j] + 180 / NA
        if is_open(e, az if az <= 180 else az - 360):
            continue
        if c[2] < cut_z(az):
            continue
        faces.append(q)
# Smooth edges: the vertices on the edge of the face opening move onto its oval (in elevation and
# azimuth, at the shell's radius there), those on the bottom edge onto the cut line; otherwise the
# edges step along the grid.
used = set(v for f in faces for v in f)
opening_v = set()
bottom_v = set()
for i in range(NE - 1):
    for j in range(NA):
        q = [vid(i, j), vid(i, j + 1), vid(i + 1, j + 1), vid(i + 1, j)]
        e = (elev[i] + elev[i + 1]) / 2
        az = azim[j] + 180 / NA
        az = az if az <= 180 else az - 360
        if is_open(e, az):
            opening_v.update(v for v in q if v in used)
        elif verts[q].mean(0)[2] < cut_z(az):
            bottom_v.update(v for v in q if v in used)


def radius_at(e, az):
    fi = (e - E0) / (E1 - E0) * (NE - 1)
    fj = (az + 180) / 360 * NA
    i0, j0 = int(np.clip(np.floor(fi), 0, NE - 2)), int(np.floor(fj)) % NA
    ti, tj = min(max(fi - i0, 0.0), 1.0), fj - np.floor(fj)
    m = (M[i0, j0] * (1 - tj) + M[i0, (j0 + 1) % NA] * tj) * (1 - ti) + (M[i0 + 1, j0] * (1 - tj) + M[i0 + 1, (j0 + 1) % NA] * tj) * ti
    return m + K["offset"]


if K["face"] is not None:
    ec, eh, aw = K["face"]
    for v in opening_v:
        i, j = divmod(v, NA)
        e, az = elev[i], azim[j]
        if K["open_below"] and e < ec:
            # The cap's cheek edge: straight down at the opening's width.
            az = math.copysign(aw, az) if abs(az) < aw else az
        else:
            k = _oval(az / aw, (e - ec) / eh)
            if k < 1e-6:
                continue
            az, e = az / k, ec + (e - ec) / k
        er, ar = math.radians(e), math.radians(az)
        dv = np.array([math.cos(er) * math.sin(ar), -math.cos(er) * math.cos(ar), math.sin(er)])
        verts[v] = HC + dv * radius_at(e, az)
for v in bottom_v:
    if v in opening_v:
        continue
    i, j = divmod(v, NA)
    verts[v][2] = max(verts[v][2], cut_z(azim[j]))

# The top pole: a fan.
top = len(verts)
last = verts[(NE - 1) * NA:(NE) * NA]
verts = np.vstack([verts, np.array([HC[0], HC[1], last[:, 2].max() + 0.004]) + np.array([0, last[:, 1].mean() - HC[1], 0])])
uvs.append((0.5, 1.0))
for j in range(NA):
    faces.append([vid(NE - 1, j), vid(NE - 1, j + 1), top])

_v = verts[verts[:, 2] > NECK]
print(f"DIMS width {np.ptp(_v[:, 0]):.3f} depth {np.ptp(_v[:, 1]):.3f} height {np.ptp(verts[:, 2]):.3f} "
      f"(x {(_v[:, 0].min() - CX):.3f}..{(_v[:, 0].max() - CX):.3f})")
me = bpy.data.meshes.new(KIND)
me.from_pydata([tuple(v) for v in verts], [], faces)
me.update()
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(me)
bm.free()
# Distance (m) of every vertex to the nearest edge of the shell (opening or bottom), for the trim.
co = np.array([v.co for v in me.vertices])
edge_count = {}
for p in me.polygons:
    for k in range(len(p.vertices)):
        ek = tuple(sorted((p.vertices[k], p.vertices[(k + 1) % len(p.vertices)])))
        edge_count[ek] = edge_count.get(ek, 0) + 1
bverts = sorted({v for ek, n in edge_count.items() if n == 1 for v in ek})
bco_e = co[bverts] if bverts else co[:1] + 10
dist = np.array([np.min(np.linalg.norm(bco_e - c, axis=1)) for c in co])
# UVs follow the vertices (the grid's own), looked up by nearest original grid vertex.
uv_arr = np.array(uvs)
grid = np.array([tuple(v) for v in verts])
nearest = [int(np.argmin(np.linalg.norm(grid - c, axis=1))) for c in co]
uvl = me.uv_layers.new(name="UVMap")
col = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
for v in me.vertices:
    col.data[v.index].color = (0.0, min(dist[v.index] / 0.1, 1.0), 0.0, 1.0)
for p in me.polygons:
    p.use_smooth = True
    for li in p.loop_indices:
        uvl.data[li].uv = uv_arr[nearest[me.loops[li].vertex_index]]
obj = bpy.data.objects.new(KIND, me)
bpy.context.scene.collection.objects.link(obj)

# Thickness: the shell inward; the inner side and the rim marked inside (COLOR.r = 1).
inner = obj.vertex_groups.new(name="inner")
sol = obj.modifiers.new("Solidify", "SOLIDIFY")
sol.thickness = K["thick"]
sol.offset = -1.0
sol.use_rim = True
sol.shell_vertex_group = "inner"
common.select_only([obj])
bpy.ops.object.modifier_apply(modifier="Solidify")
me = obj.data
gi = obj.vertex_groups["inner"].index
for v in me.vertices:
    if any(g.group == gi and g.weight > 0.5 for g in v.groups):
        c = list(col_data := me.color_attributes["Color"].data[v.index].color)
        c[0] = 1.0
        me.color_attributes["Color"].data[v.index].color = c
obj.vertex_groups.remove(obj.vertex_groups["inner"])

# --- skinning: the head; below its base blending into the neck ----------------------------------
hg = obj.vertex_groups.new(name="Head")
ng = obj.vertex_groups.new(name="Neck")
for v in me.vertices:
    z = v.co.z
    t = min(max((NECK + 0.01 - z) / 0.08, 0.0), 1.0)
    t = t * t * (3 - 2 * t)
    if t < 0.999:
        hg.add([v.index], 1.0 - t, "REPLACE")
    if t > 0.001:
        ng.add([v.index], t, "REPLACE")
obj.parent = rig
mod = obj.modifiers.new("Armature", "ARMATURE")
mod.object = rig
print(f"HEADGEAR {KIND}: {len(me.vertices)} vertices, {len(me.polygons)} faces, "
      f"head {M.min():.3f}..{M.max():.3f} m from its middle")
common.export_glb([rig, obj], out)
print("wrote", out)
