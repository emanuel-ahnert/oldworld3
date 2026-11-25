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
    "hood": dict(offset=0.030, thick=0.008, face=(-12, 44, 60), open_below=False, cut=(0.055, 0.075), ridge=0.0, blur=3),
    "coif": dict(offset=0.014, thick=0.005, face=(-10, 38, 50), open_below=False, cut=(0.095, 0.10), ridge=0.0, blur=2),
    "cowl": dict(offset=0.013, thick=0.006, face=(-8, 30, 74), open_below=True, cut=(0.0, 0.045), ridge=0.0, blur=2),
    "helm": dict(offset=0.036, thick=0.007, face=None, open_below=False, cut=(0.06, 0.085), ridge=0.012, blur=3),
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
AXY = np.array([0.0, float(np.median(bco[(bco[:, 2] > NECK - 0.1) & (bco[:, 2] < NECK), 1]))])
HC = np.array([0.0, head_y, NECK + 0.10])
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


def egg(e, az):
    er, ar = math.radians(e), math.radians(az)
    x, y, z = math.cos(er) * math.sin(ar), -math.cos(er) * math.cos(ar), math.sin(er)
    sy = EF if y < 0 else EB
    sz = EU if z > 0 else ED
    return 1.0 / math.sqrt((x / EX) ** 2 + (y / sy) ** 2 + (z / sz) ** 2)


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

# --- the grid shell -------------------------------------------------------------------------------
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


def vid(i, j):
    return i * NA + (j % NA)


def is_open(e, az):
    """The face opening (or the helm's eye slit)."""
    if K["face"] is None:
        return abs(az) < 50 and -9 < e < 3                      # the helm's eye slit
    ec, eh, aw = K["face"]
    if K["open_below"] and abs(az) < aw and e < ec:
        return True
    return (az / aw) ** 2 + ((e - ec) / eh) ** 2 < 1.0


def cut_z(az):
    back = (1 - math.cos(math.radians(az))) / 2               # 0 ahead .. 1 behind
    return NECK - (K["cut"][0] + (K["cut"][1] - K["cut"][0]) * back)


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
            k = math.hypot(az / aw, (e - ec) / eh)
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
