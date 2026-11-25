"""Builds the casters' robe as a skinned layer on the base body (after Oldworld2's robes).

blender -b --python tools/pipeline/robe_layer.py -- <body_dir> <out.glb>

One garment, made here from the body's measurements (nothing generated):
- The robe: a tube from a standing collar at the base of the neck down to just above the
  ankles. Above the waist each ring hugs the torso (the body's torso, not its arms, measured per
  direction, plus a little air); below it the skirt falls around the legs, wider and wider
  toward the hem (an A-line) and in folds that deepen toward it.
- Two sleeves along the arms: snug at the shoulder, widening down the forearm in folds into bell
  sleeves.
Skinning: the bodice, collar and sleeves take their weights from the nearest body skin (like
the hood, hood_layer.py); the skirt follows the hips at the waist and more and more the thighs
toward the hem (its left half the left thigh, the right half the right one), so it swings with
the stride. The game hides the body's chest and legs under it (body_slots.gdshader `robed`), so
nothing pokes through.
UVs (shaders/robe.gdshader): the robe u around (0 at the back, 0.5 at the front), v 0 at the
collar, WAIST_V at the waist, 1 at the hem; the sleeves u around, v from 1.1 at the shoulder
to 2.0 at the cuff (UV y is 1 - v, glTF's flip).
"""

import math
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
body_dir, out = Path(a[0]), Path(a[1])
SIDES = 48
AIR = 0.010              # m between the torso and the bodice
LEG_AIR = 0.022           # m between the legs and the skirt
FLARE = 0.085            # m wider at the hem than the legs need
ANKLE = 0.11             # m above the ankle joint: the hem
WAIST_V = 0.36           # v of the waist (the belt)
COLLAR = 0.035           # m the collar stands up above the neck's base

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
if rig.animation_data:
    rig.animation_data.action = None
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)


def joint(name):
    return rig.matrix_world @ rig.data.bones[name].head_local


TORSO = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "LeftShoulder", "RightShoulder"]
LEGS = ["Hips", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"]
ARM = {s: [f"{s}Shoulder", f"{s}UpperArm", f"{s}LowerArm", f"{s}Hand"] for s in ("Left", "Right")}
BONES = sorted(set(TORSO + LEGS + ARM["Left"] + ARM["Right"]))
gidx = {g.index: g.name for g in body.vertex_groups}

bco = np.array([body.matrix_world @ v.co for v in body.data.vertices])
main = []          # the strongest bone per vertex
weights = []       # {bone: weight}
for v in body.data.vertices:
    weights.append({gidx[g.group]: g.weight for g in v.groups if gidx[g.group] in BONES and g.weight > 0.0})
    main.append(gidx[max(v.groups, key=lambda g: g.weight).group] if v.groups else "")
main = np.array(main)


def subset(names):
    return np.isin(main, names)


z_waist = joint("Hips").z + 0.04
z_neck = joint("Neck").z - 0.01
z_hem = joint("LeftFoot").z + ANKLE
left_x = joint("LeftUpperLeg").x
center = np.array([0.0, joint("Hips").y])
# Ring directions from the back (+Y; the body faces -Y) around: u = k / SIDES, 0.5 at the front.
ang = math.pi / 2 + np.linspace(0, 2 * math.pi, SIDES, endpoint=False)


def ring_radius(pts, margin):
    """Per direction around `center`: the farthest of `pts` there, smoothed, plus margin."""
    dx, dy = pts[:, 0] - center[0], pts[:, 1] - center[1]
    th = np.arctan2(dy, dx)
    d = np.hypot(dx, dy)
    r = np.zeros(SIDES)
    for k in range(SIDES):
        diff = np.abs((th - ang[k] + math.pi) % (2 * math.pi) - math.pi)
        m = d[diff < 2.5 * math.pi / SIDES]
        r[k] = m.max() if len(m) else 0.0
    r = np.maximum(r, r.max() * 0.55)
    for _ in range(3):
        r = 0.5 * r + 0.25 * (np.roll(r, 1) + np.roll(r, -1))
    return r + margin


# --- the robe's rings: collar, bodice, skirt -----------------------------------------------------
torso_pts = bco[subset(TORSO)]
leg_pts = bco[subset(LEGS)]
levels = []        # [z, v, radii, part]
n_top = 12
for i in range(n_top + 1):                  # the base of the neck to the waist
    t = i / n_top
    z = z_neck - (z_neck - z_waist) * t
    sl = torso_pts[np.abs(torso_pts[:, 2] - z) < 0.025]
    levels.append([z, WAIST_V * t, ring_radius(sl, AIR) if len(sl) > 10 else None, "top"])
n_skirt = 16
for i in range(1, n_skirt + 1):             # the waist to the hem
    t = i / n_skirt
    z = z_waist - (z_waist - z_hem) * t
    sl = leg_pts[np.abs(leg_pts[:, 2] - z) < 0.03]
    r = ring_radius(sl, LEG_AIR) if len(sl) > 10 else None
    levels.append([z, WAIST_V + (1 - WAIST_V) * t, r, "skirt"])
for i, lv in enumerate(levels):
    if lv[2] is None:
        lv[2] = levels[i - 1][2].copy() if i else levels[i + 1][2].copy()
R = np.array([lv[2] for lv in levels])
for _ in range(2):
    R[1:-1] = 0.5 * R[1:-1] + 0.25 * (R[:-2] + R[2:])
# Below the chest it only widens (no waist pinched in under the ribs, no skirt narrower than
# the hips); then the skirt's flare and folds.
k_chest = int(n_top * 0.45)
for i in range(k_chest + 1, len(R)):
    R[i] = np.maximum(R[i], R[i - 1] * (0.97 if i <= n_top else 1.0))
for i, lv in enumerate(levels):
    if lv[3] == "skirt":
        t = (lv[1] - WAIST_V) / (1 - WAIST_V)
        R[i] = R[i] + FLARE * t ** 1.3 + (0.003 + 0.016 * t ** 1.2) * np.sin(ang * 11 + 0.6 + 2.0 * t)
# The standing collar above the neck's base, a little narrower than the ring below.
levels.insert(0, [z_neck + COLLAR, 0.0, None, "top"])
for lv in levels[1:]:
    lv[1] = 0.03 + lv[1] * 0.97
R = np.vstack([R[0] * 0.9, R])

bm = bmesh.new()
uv = bm.loops.layers.uv.new("UVMap")
part = {}
rows = []
for i, lv in enumerate(levels):
    row = []
    for k in range(SIDES + 1):
        kk = k % SIDES
        v = bm.verts.new((center[0] + R[i, kk] * math.cos(ang[kk]), center[1] + R[i, kk] * math.sin(ang[kk]), lv[0]))
        part[v] = lv[3]
        row.append(v)
    rows.append(row)
for i in range(len(rows) - 1):
    for k in range(SIDES):
        f = bm.faces.new((rows[i][k], rows[i + 1][k], rows[i + 1][k + 1], rows[i][k + 1]))
        for loop, (ii, kk) in zip(f.loops, ((i, k), (i + 1, k), (i + 1, k + 1), (i, k + 1))):
            loop[uv].uv = (kk / SIDES, 1.0 - levels[ii][1])

# --- sleeves ---------------------------------------------------------------------------------------
SS = SIDES // 2
for s in ("Left", "Right"):
    sh, el, wr = joint(f"{s}UpperArm"), joint(f"{s}LowerArm"), joint(f"{s}Hand")
    arm_pts = bco[subset(ARM[s][1:])]
    path = []           # (center, axis, bell flare, v)
    n_up, n_fore = 6, 9
    for i in range(n_up + 1):
        t = i / n_up
        path.append((sh.lerp(el, -0.12 + 1.08 * t), (el - sh).normalized(), 0.0, 1.1 + 0.4 * t))
    for i in range(1, n_fore + 1):
        t = i / n_fore
        path.append((el.lerp(wr, -0.04 + 0.96 * t), (wr - el).normalized(), 0.028 * t ** 1.4, 1.5 + 0.5 * t))
    srows = []
    for c, d, flare, vv in path:
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        e1 = d.cross(up).normalized()
        e2 = d.cross(e1).normalized()
        # The arm's thickness here: the farthest arm skin near this point, across the axis.
        rel = arm_pts - np.array(c)
        along = rel @ np.array(d)
        near = rel[np.abs(along) < 0.03]
        across = near - np.outer(near @ np.array(d), np.array(d))
        # (85th percentile, not the farthest: skin near the shoulder counts toward the arm too)
        base = float(np.percentile(np.linalg.norm(across, axis=1), 85)) if len(near) else 0.05
        r0 = min(max(base, 0.035), 0.068) + 0.009 + flare
        row = []
        for k in range(SS + 1):
            th = 2 * math.pi * k / SS
            fold = (0.002 + 0.1 * flare) * math.sin(5 * th)
            v = bm.verts.new(c + (e1 * math.cos(th) + e2 * math.sin(th)) * (r0 + fold))
            part[v] = s
            row.append(v)
        srows.append((row, vv))
    for i in range(len(srows) - 1):
        ra, va = srows[i]
        rb, vb = srows[i + 1]
        for k in range(SS):
            f = bm.faces.new((ra[k], rb[k], rb[k + 1], ra[k + 1]))
            for loop, (vv, kk) in zip(f.loops, ((va, k), (vb, k), (vb, k + 1), (va, k + 1))):
                loop[uv].uv = (kk / SS, 1.0 - vv)

# Normals outward (from the body's axis, or the arm's).
bm.normal_update()
by_part = {"robe": [], "Left": [], "Right": []}
for f in bm.faces:
    p = part[f.verts[0]]
    by_part["robe" if p in ("top", "skirt") else p].append(f)
for key, fs in by_part.items():
    score = 0.0
    for f in fs:
        c = f.calc_center_median()
        if key == "robe":
            m = Vector((center[0], center[1], c.z))
        else:
            sh, el, wr = joint(f"{key}UpperArm"), joint(f"{key}LowerArm"), joint(f"{key}Hand")
            a0, a1 = (el, wr) if (c - el).dot(wr - el) > 0 else (sh, el)
            d = (a1 - a0).normalized()
            m = a0 + d * (c - a0).dot(d)
        score += f.normal.dot(c - m)
    if score < 0:
        bmesh.ops.reverse_faces(bm, faces=fs)

me = bpy.data.meshes.new("Robe")
bm.to_mesh(me)
parts = [part[v] for v in bm.verts]
bm.free()
robe = bpy.data.objects.new("Robe", me)
bpy.context.scene.collection.objects.link(robe)
me.materials.append(bpy.data.materials.new("robe"))
for p in me.polygons:
    p.use_smooth = True

# --- skinning ----------------------------------------------------------------------------------------
kd = {}
for name, allowed in (("top", TORSO), ("Left", ARM["Left"]), ("Right", ARM["Right"])):
    idx = np.nonzero(subset(allowed))[0]
    tree = KDTree(len(idx))
    for vi in idx:
        tree.insert(Vector(bco[vi]), int(vi))
    tree.balance()
    kd[name] = tree
vg = {b: robe.vertex_groups.new(name=b) for b in BONES}
for i, (v, p) in enumerate(zip(me.vertices, parts)):
    w = {}
    if p == "skirt":
        t = (z_waist - v.co.z) / (z_waist - z_hem)
        hips = 1.0 - 0.9 * min(1.0, max(0.0, t / 0.45)) ** 1.1
        side = (v.co.x - center[0]) * (1.0 if left_x > center[0] else -1.0)     # + on the body's left
        wl = max(0.0, min(1.0, 0.5 + side / 0.12))
        # Toward the hem the shins take a share too: a trailing foot kicked up behind stays
        # under the cloth.
        shin = 0.4 * max(0.0, min(1.0, (t - 0.5) / 0.5)) ** 1.5
        thigh = (1 - hips) * (1 - shin)
        w = {"Hips": hips, "LeftUpperLeg": thigh * wl, "RightUpperLeg": thigh * (1 - wl),
             "LeftLowerLeg": (1 - hips) * shin * wl, "RightLowerLeg": (1 - hips) * shin * (1 - wl)}
    else:
        for co, vi, dist in kd[p].find_n(v.co, 8):
            for b, x in weights[vi].items():
                w[b] = w.get(b, 0.0) + x / (0.01 + dist)
    tot = sum(w.values()) or 1.0
    w = {b: x / tot for b, x in w.items() if x / tot > 0.02}
    tot = sum(w.values()) or 1.0
    for b, x in w.items():
        vg[b].add([i], x / tot, "REPLACE")

robe.parent = rig
mod = robe.modifiers.new("Armature", "ARMATURE")
mod.object = rig
print(f"robe: collar z {z_neck + COLLAR:.2f}, waist z {z_waist:.2f}, hem z {z_hem:.2f}, "
      f"hem radius {R[-1].min():.2f}..{R[-1].max():.2f} m, {len(me.vertices)} vertices")
common.export_glb([rig, robe], out)
print("wrote", out)
