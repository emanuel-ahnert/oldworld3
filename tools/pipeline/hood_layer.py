"""Fits a generated hood-with-cape model onto the base body as a skinned layer, the cape cut off.

blender -b --python tools/pipeline/hood_layer.py -- <body_dir> <hood.glb> <out.glb> [scale]

The model (batch 13: a hood with a short cape over the shoulders) was worn rigidly on the head
bone, so the cape was shrunk to head size and turned with the head. Here it is fitted to the
body instead, like the armor layers (armor.py):
- Scaled so the model is `scale` m tall (the hood's head part then fits a head and the cape the
  shoulders), its top a few cm above the head, its hood centered over the head.
- Pushed out of the body (radius maps around the torso and the head, see below), every vertex
  at least MARGIN outside it, the push spread over the cloth so both its sides move together.
- Skinned with weights from the nearest body skin, smoothed over the cloth: the hood turns with
  the head, the cape stays on the shoulders, and over the arms it follows them ARM_FOLLOW of
  the way (the elbows would push through it otherwise).

The model keeps its own texture. The game wears it as the "head" layer (humanoid.gd,
HEAD_LAYERS).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.kdtree import KDTree  # noqa: E402

import common  # noqa: E402

a = common.args()
body_dir, src, out = Path(a[0]), Path(a[1]), Path(a[2])
HEIGHT = float(a[3]) if len(a) > 3 else 1.15
MARGIN = 0.018           # m of air between skin and cloth
ABOVE = 0.06             # m from the top of the head to the top of the hood
BONES = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder",
         "LeftUpperArm", "RightUpperArm"]
## The forearms and hands count as their upper arm (the cape over a hanging arm).
ALIAS = {"LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftUpperArm",
         "RightLowerArm": "RightUpperArm", "RightHand": "RightUpperArm"}
ARM_FOLLOW = 0.6         # share of the arm's motion the cape over it follows (the rest: chest)

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
if rig.animation_data:
    rig.animation_data.action = None
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)

# --- the hood, welded (glTF splits vertices at UV seams) and fitted ---------------------------
bpy.ops.import_scene.gltf(filepath=str(src))
parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
hood = common.join(parts) if len(parts) > 1 else parts[0]
hood.name = "Hood"
hood.parent = None
common.apply_transforms(hood)
bm = bmesh.new()
bm.from_mesh(hood.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(hood.data)
bm.free()

me = hood.data
co = np.array([v.co for v in me.vertices])
lo, hi = co.min(0), co.max(0)
s = HEIGHT / (hi[2] - lo[2])
co = (co - np.array([(lo[0] + hi[0]) / 2, 0, hi[2]])) * s      # top center at the origin

bco = np.array([body.matrix_world @ v.co for v in body.data.vertices])
head_g = body.vertex_groups["Head"].index
head_v = np.array([any(g.group == head_g and g.weight > 0.5 for g in v.groups) for v in body.data.vertices])
head_top = bco[:, 2].max()
head_y = float(np.median(bco[head_v, 1]))
# The hood's head part: the top quarter of the model; its middle over the head's middle.
top = co[co[:, 2] > -0.25 * HEIGHT]
co += np.array([0.0, head_y - (top[:, 1].min() + top[:, 1].max()) / 2, head_top + ABOVE])
for v, c in zip(me.vertices, co):
    v.co = Vector(c)
print(f"HOOD scale {s:.3f}, top {co[:, 2].max():.3f}, bottom {co[:, 2].min():.3f}, "
      f"width {np.ptp(co[:, 0]):.3f}")

# The generated mesh is decimated: faces up to 25 cm across, which a fitted cloth can't bend
# around an elbow or a hand. Edges longer than EDGE are split (the UVs are interpolated).
EDGE = 0.05
bm = bmesh.new()
bm.from_mesh(me)
for _ in range(4):
    long_ = [e for e in bm.edges if e.calc_length() > EDGE]
    if not long_:
        break
    bmesh.ops.subdivide_edges(bm, edges=long_, cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
bm.to_mesh(me)
bm.free()
me.update()
print(f"SPLIT to {len(me.vertices)} vertices, {len(me.polygons)} faces")

# Only the hood and a short collar: the cape below clipped through arms, weapons, shields and
# shoulder armor in every swing. Faces below CUT under the head's base go.
CUT = 0.07
neck_z = float((rig.matrix_world @ rig.data.bones["Head"].head_local).z)
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < neck_z - CUT], context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(me)
bm.free()
me.update()
print(f"CUT below {neck_z - CUT:.2f} m: {len(me.polygons)} faces left")

# --- out of the body ----------------------------------------------------------------------------
# The body (arms hanging in the rest pose included) as two smooth radius maps: around the torso's
# vertical axis per height and angle, around the head's center per direction. Every cloth vertex
# moves outward from the axis (or the head's center) to at least the map's radius plus MARGIN;
# the move is spread over the cloth so its inner and outer side and the folds move together.
# (Pushing each point to the nearest skin instead got lost in creases like the armpit, and made
# the cloth bumpy.)
NECK = float((rig.matrix_world @ rig.data.bones["Head"].head_local).z)
HC = np.array([0.0, head_y, NECK + 0.11])                  # about the middle of the head
AX = np.array([0.0, float(np.median(bco[:, 1]))])          # the torso's vertical axis (x, y)
ZB, TB = 0.02, 72                                          # 2 cm in height, 5 degrees around


def blur_max(R, rz, rt, wrap_rows=False):
    """Max over a window (fills the gaps between vertices), then a light average."""
    out = R.copy()
    for dz in range(-rz, rz + 1):
        for dt in range(-rt, rt + 1):
            sh = np.roll(np.roll(R, dt, axis=1), dz, axis=0)
            if not wrap_rows:
                if dz > 0:
                    sh[:dz] = 0
                elif dz < 0:
                    sh[dz:] = 0
            out = np.maximum(out, sh)
    sm = out.copy()
    for dt in (-1, 1):
        sm += np.roll(out, dt, axis=1)
    return sm / 3


low = bco[bco[:, 2] < NECK + 0.02]
zr = int(np.ceil((NECK + 0.02) / ZB)) + 1
R_cyl = np.zeros((zr, TB))
d = low[:, :2] - AX
rb = np.hypot(d[:, 0], d[:, 1])
tb = ((np.arctan2(d[:, 1], d[:, 0]) + np.pi) / (2 * np.pi) * TB).astype(int) % TB
np.maximum.at(R_cyl, ((low[:, 2] / ZB).astype(int), tb), rb)
R_cyl = blur_max(R_cyl, 1, 2)

up = bco[bco[:, 2] > NECK - 0.06] - HC
EB = 36                                                    # 5 degrees of elevation
R_sph = np.zeros((EB, TB))
rs = np.linalg.norm(up, axis=1)
el = ((np.arcsin(np.clip(up[:, 2] / np.maximum(rs, 1e-6), -1, 1)) + np.pi / 2) / np.pi * EB).astype(int).clip(0, EB - 1)
az = ((np.arctan2(up[:, 1], up[:, 0]) + np.pi) / (2 * np.pi) * TB).astype(int) % TB
np.maximum.at(R_sph, (el, az), rs)
R_sph = blur_max(R_sph, 1, 1)


def need_move(c):
    """The outward move that clears the body for a cloth point c."""
    best = np.zeros(3)
    if c[2] < NECK + 0.02:
        dxy = c[:2] - AX
        r = float(np.hypot(*dxy))
        zi = min(max(int(c[2] / ZB), 0), zr - 1)
        ti = int((np.arctan2(dxy[1], dxy[0]) + np.pi) / (2 * np.pi) * TB) % TB
        want = R_cyl[zi, ti] + MARGIN if R_cyl[zi, ti] > 0 else 0.0
        if r < want and r > 1e-4:
            best = np.array([dxy[0], dxy[1], 0.0]) / r * (want - r)
    if c[2] > NECK - 0.06:
        v = c - HC
        r = float(np.linalg.norm(v))
        e = min(max(int((np.arcsin(np.clip(v[2] / max(r, 1e-6), -1, 1)) + np.pi / 2) / np.pi * EB), 0), EB - 1)
        t = int((np.arctan2(v[1], v[0]) + np.pi) / (2 * np.pi) * TB) % TB
        want = R_sph[e, t] + MARGIN if R_sph[e, t] > 0 else 0.0
        if r < want and want - r > np.linalg.norm(best):
            best = v / r * (want - r)
    return best


nbr = [[] for _ in me.vertices]
for e in me.edges:
    i, j = e.vertices
    nbr[i].append(j)
    nbr[j].append(i)
N = len(me.vertices)
co = np.array([v.co for v in me.vertices])
req = np.array([need_move(c) for c in co])
need = np.linalg.norm(req, axis=1) > 1e-5
push = req.copy()
for _ in range(10):
    avg = np.array([push[nb].mean(0) if nb else push[i] for i, nb in enumerate(nbr)])
    push = np.where(need[:, None], np.where((np.linalg.norm(avg, axis=1) > np.linalg.norm(req, axis=1))[:, None], avg, req), avg)
for v, p in zip(me.vertices, push):
    v.co += Vector(p)
print(f"PUSHED {int(need.sum())} of {N} vertices out of the body (deepest {np.linalg.norm(req, axis=1).max():.3f} m)")

# --- weights from the nearest skin --------------------------------------------------------------
gi = {body.vertex_groups[b].index: k for k, b in enumerate(BONES)}
gi.update({body.vertex_groups[a].index: BONES.index(b) for a, b in ALIAS.items()})
bw = np.zeros((len(bco), len(BONES)))
for v in body.data.vertices:
    for g in v.groups:
        if g.group in gi:
            bw[v.index, gi[g.group]] += g.weight
ok = np.nonzero(bw.sum(1) > 0.6)[0]           # torso and head skin (not the arms and legs)
kd = KDTree(len(ok))
for k, i in enumerate(ok):
    kd.insert(Vector(bco[i]), k)
kd.balance()
W = np.zeros((N, len(BONES)))
for v in me.vertices:
    for c, k, d in kd.find_n(v.co, 8):
        w = bw[ok[k]]
        W[v.index] += w / w.sum() / max(d, 0.01)
W /= W.sum(1, keepdims=True)
# Over the arms the cape follows them part of the way (it lifts when they swing or strike, instead
# of the elbows pushing through it), the rest stays with the chest.
arm = [BONES.index("LeftUpperArm"), BONES.index("RightUpperArm")]
share = W[:, arm].sum(1)
W[:, arm] *= ARM_FOLLOW
W[:, BONES.index("UpperChest")] += (1 - ARM_FOLLOW) * share
for _ in range(12):
    W = 0.5 * W + 0.5 * np.array([W[nb].mean(0) if nb else W[i] for i, nb in enumerate(nbr)])
W[W < np.sort(W, 1)[:, -4:-3]] = 0.0          # four bones at most
W /= W.sum(1, keepdims=True)
groups = [hood.vertex_groups.new(name=b) for b in BONES]
for i in range(N):
    for k, g in enumerate(groups):
        if W[i, k] > 0.01:
            g.add([i], float(W[i, k]), "REPLACE")
for k, b in enumerate(BONES):
    print(f"  {b}: {W[:, k].sum() / N:.2f}")

hood.parent = rig
mod = hood.modifiers.new("Armature", "ARMATURE")
mod.object = rig
for p in me.polygons:
    p.use_smooth = True
common.export_glb([rig, hood], out)
print("wrote", out)
