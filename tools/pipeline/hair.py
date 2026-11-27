"""Hairstyles for the base body: real hair geometry worn as a skinned layer on the head (like the
headgear), one model per style, on the heroes' bald head (bald_head.py, bald.py).

blender -b --python tools/pipeline/hair.py -- <body_dir> <style> <out.glb>
style: crop, neat, swept, long, slick, messy, mohawk, knot, wild

- The scalp: the heroes' bald head (bald_head.py), found by rays toward the head's middle.
- The cap: a grid over (azimuth, elevation) from the hairline up to the crown, each vertex on the
  skull plus the style's thickness: thicker on top, clumped into locks (ridges around the head),
  tufts for messy styles, thinning to the hairline; the hem a row of points (locks' tips).
- Long styles: at the back and sides the hair goes on below the hairline and falls straight
  down (a curtain), its tips ragged.
- mohawk: only a crest along the middle from the forehead to the nape, high and spiky.
- knot: a short crop with a knot of hair at the back of the crown.
- Per vertex for shaders/hair.gdshader: UV = (around the head 0..1, along the hair 0 root .. 1
  tip); COLOR.r = depth into the hair (0 on the scalp side, 1 outside; the inside darker).
- Skinned to the head; the curtain blends into the neck.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bald_head  # noqa: E402
import common  # noqa: E402

a = common.args()
body_dir, STYLE, out = Path(a[0]), a[1], Path(a[2])

# top: m of hair on the crown, side: at the sides, ridge: lock relief (fraction), locks: locks
# round the head, tuft: m of random tufts, long: m the curtain falls at the back (0 none),
# fringe: degrees the front hairline comes down (lower = more forehead covered), hem: m the
# hem's points hang below the hairline.
STYLES = {
    "crop":   dict(top=0.011, side=0.004, ridge=0.25, locks=40, tuft=0.003, long=0.0, fringe=34, hem=0.004),
    "neat":   dict(top=0.016, side=0.009, ridge=0.35, locks=26, tuft=0.005, long=0.0, fringe=30, hem=0.008),
    "swept":  dict(top=0.022, side=0.010, ridge=0.5, locks=22, tuft=0.006, long=0.0, fringe=38, hem=0.01),
    "long":   dict(top=0.018, side=0.012, ridge=0.45, locks=24, tuft=0.006, long=0.15, fringe=36, hem=0.015),
    "slick":  dict(top=0.010, side=0.008, ridge=0.3, locks=30, tuft=0.003, long=0.10, fringe=40, hem=0.012),
    "messy":  dict(top=0.020, side=0.012, ridge=0.4, locks=20, tuft=0.022, long=0.0, fringe=26, hem=0.02),
    "wild":   dict(top=0.022, side=0.016, ridge=0.5, locks=18, tuft=0.016, long=0.17, fringe=30, hem=0.025),
    "knot":   dict(top=0.009, side=0.004, ridge=0.25, locks=40, tuft=0.003, long=0.0, fringe=38, hem=0.004),
    "mohawk": dict(top=0.0, side=0.0, ridge=0.0, locks=0, tuft=0.0, long=0.0, fringe=38, hem=0.0),
}
K = STYLES[STYLE]

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
if rig.animation_data:
    rig.animation_data.action = None
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)
# The hair sits on the bald head (bald_head.py, the heroes' body): its scalp found by rays from
# the head's middle.
_free, HC, NECK = bald_head.make_bald(body, rig)
BVH = bald_head.scalp_bvh(body)
for o in list(bpy.data.objects):
    if o is body:
        bpy.data.objects.remove(o)


def hash1(*v):
    return (math.sin(sum(x * k for x, k in zip(v, (12.9898, 78.233, 37.719)))) * 43758.5453) % 1.0


def dir_of(e, az):
    er, ar = math.radians(e), math.radians(az)
    return np.array([math.cos(er) * math.sin(ar), -math.cos(er) * math.cos(ar), math.sin(er)])


_scalp_cache = {}


def skull_r(d):
    """The bald scalp's distance from the head's middle toward direction d (Blender: x side,
    -y ahead, z up): the farthest hit of a ray from outside back toward the middle."""
    key = tuple(np.round(d, 5))
    if key in _scalp_cache:
        return _scalp_cache[key]
    from mathutils import Vector
    start = Vector(HC + d * 0.4)
    hit = BVH.ray_cast(start, Vector(-d), 0.4)
    r = 0.4 - hit[3] if hit[0] is not None else 0.12
    _scalp_cache[key] = r
    return r


def hairline(az):
    """The lowest elevation (degrees) of the hair round the head: over the forehead, above the
    ears, down to the nape at the back."""
    a_ = abs(az)
    F = K["fringe"]
    # The forehead's line (a little lower in the middle), the temples a little higher, the
    # sideburns down in front of the ear, over the ear, behind it down to the nape.
    return float(np.interp(a_, [0, 22, 42, 58, 68, 74, 80, 88, 112, 124, 150, 180],
                           [F - 2, F, F + 5, F, 12, -10, -12, 12, 12, -6, -28, -34]))


verts, uvs, rootness, faces = [], [], [], []
skin_neck = []                       # per vertex: 0 head .. 1 neck (the curtain's lower part)


def add(p, u, v, depth=1.0, neck=0.0):
    verts.append(np.asarray(p, float))
    uvs.append((u, v))
    rootness.append(depth)
    skin_neck.append(neck)
    return len(verts) - 1


def cap():
    NA, NE = 96, 22
    grid = [[0] * NA for _ in range(NE)]
    hem_rows = []
    for j in range(NA):
        az = -180 + 360 * j / NA
        e0 = hairline(az)
        for i in range(NE):
            t = i / (NE - 1)
            e = e0 + (87.0 - e0) * (t ** 0.85)
            d = dir_of(e, az)
            topw = min(max((e - 10) / 55, 0.0), 1.0)
            th = K["side"] + (K["top"] - K["side"]) * topw
            # Locks: ridges round the head, wobbling; tufts: random lumps.
            ph = math.radians(az) * K["locks"] + 1.7 * math.sin(e * 0.09 + j * 0.3)
            th *= 1.0 + K["ridge"] * (0.5 + 0.5 * math.cos(ph)) - K["ridge"] * 0.5
            th += K["tuft"] * max(0.0, hash1(i * 0.37 + 1, j * 0.61 + 2) - 0.55) * 2.2 * topw
            # Thinning at the hairline (the first rows), so it meets the scalp.
            th *= min(1.0, 0.25 + t * 3.0)
            r = skull_r(d) + th
            grid[i][j] = add(HC + d * r, j / NA, 1.0 - t, 1.0)
        hem_rows.append(e0)
    for i in range(NE - 1):
        for j in range(NA):
            j2 = (j + 1) % NA
            faces.append([grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]])
    # The crown: a fan to the top.
    top_i = add(HC + np.array([0, 0.01, 0]) + dir_of(90, 0) * (skull_r(dir_of(90, 0)) + K["top"]), 0.5, 0.0, 1.0)
    for j in range(NA):
        faces.append([grid[NE - 1][j], grid[NE - 1][(j + 1) % NA], top_i])
    # The hem: below each column a point (a lock's tip), longer where the hair is long; the long
    # styles' curtain falls straight down from the back of the head.
    last = [grid[0][j] for j in range(NA)]
    if K["long"] > 0.0:
        ROWS = 8
        cols = []
        for j in range(NA):
            az = -180 + 360 * j / NA
            # Full length at the back, shorter round the sides, none in front of the ears.
            fall = min(max((abs(az) - 70) / 60, 0.0), 1.0)
            fall = fall * fall * (3 - 2 * fall)
            L = K["long"] * fall * (0.85 + 0.3 * hash1(j * 1.3, 7))
            p0 = verts[grid[0][j]]
            out = p0 - HC
            out[2] = 0.0
            n = np.linalg.norm(out)
            out = out / n if n > 1e-6 else out
            col = [grid[0][j]]
            for k in range(1, ROWS + 1):
                s = k / ROWS
                p = p0 + np.array([0, 0, -L * s]) + out * (0.012 * math.sin(math.pi * s * 0.9) + 0.004 * s) * fall
                neck = min(max((NECK + 0.01 - p[2]) / 0.08, 0.0), 1.0)
                col.append(add(p, j / NA, 1.0 + s * 1.5 * fall, 1.0, neck))
            cols.append(col)
        for j in range(NA):
            j2 = (j + 1) % NA
            for k in range(ROWS):
                faces.append([cols[j2][k], cols[j][k], cols[j][k + 1], cols[j2][k + 1]])
        last = [cols[j][-1] for j in range(NA)]
    # Ragged tips: every other column a point hanging a little lower.
    if K["hem"] > 0.0:
        tips = []
        for j in range(NA):
            p = verts[last[j]].copy()
            hang = K["hem"] * (0.5 + hash1(j, 3.3)) * (1.0 if j % 2 == 0 else 0.35)
            d = p - HC
            d = d / np.linalg.norm(d)
            p = p + np.array([0, 0, -hang]) - d * 0.002
            u, v = uvs[last[j]]
            tips.append(add(p, u, v + 0.15, 1.0, skin_neck[last[j]]))
        for j in range(NA):
            j2 = (j + 1) % NA
            faces.append([last[j2], last[j], tips[j], tips[j2]])


def mohawk():
    """A crest from the forehead over the top to the nape: a strip a few cm wide, its middle
    high and cut into spikes."""
    NP, NW = 60, 13
    grid = [[0] * NW for _ in range(NP)]
    for i in range(NP):
        p = math.radians(62 - 200 * i / (NP - 1))       # from over the forehead back to the nape
        d0 = np.array([0.0, -math.sin(p), math.cos(p)])
        for k in range(NW):
            w = (k / (NW - 1) - 0.5) * 2.0                # -1 .. 1 across
            wa = math.radians(14) * w
            d = d0 * math.cos(wa) + np.array([1.0, 0.0, 0.0]) * math.sin(wa)
            d = d / np.linalg.norm(d)
            along = i / (NP - 1)
            hgt = 0.038 * (1 - w * w) ** 1.5 * (0.4 + 0.6 * math.sin(math.pi * min(along * 1.25, 1.0)))
            # Uneven tufts along it (not a saw's teeth).
            spike = 0.7 + 0.3 * math.sin(along * 37.0 + 2.0 * math.sin(along * 11.0)) * (0.6 + 0.4 * hash1(i * 0.5, 9))
            hgt = hgt * spike + 0.004
            r = skull_r(d) + hgt
            # Leaning back a little (combed up and back).
            pt = HC + d * r + np.array([0.0, 0.25 * (r - skull_r(d)), 0.0])
            grid[i][k] = add(pt, k / (NW - 1), 1.0 - (1 - w * w), 1.0)
    for i in range(NP - 1):
        for k in range(NW - 1):
            faces.append([grid[i][k], grid[i][k + 1], grid[i + 1][k + 1], grid[i + 1][k]])
    # The stubble round it is the base mesh's hair, cropped (body_slots.gdshader).


def knot():
    """A knot of hair at the back of the crown, on a short tie."""
    d = np.array([0.0, 0.62, 0.78])                     # up and back
    d = d / np.linalg.norm(d)
    base = HC + d * (skull_r(d) + K["top"])
    c = base + d * 0.028
    R1, R2 = 0.032, 0.026
    NU, NV = 20, 12
    ring = []
    side = np.array([1.0, 0.0, 0.0])
    fwd = np.cross(d, side)
    for iu in range(NU):
        row = []
        th = 2 * math.pi * iu / NU
        for iv in range(NV + 1):
            ph = math.pi * iv / NV
            rr = 1.0 + 0.08 * math.cos(th * 5 + ph * 3)     # twisted strands
            p = c + (side * math.cos(th) * math.sin(ph) * R1 + fwd * math.sin(th) * math.sin(ph) * R2 + d * math.cos(ph) * R2) * rr
            row.append(add(p, iu / NU, iv / NV * 0.5, 1.0))
        ring.append(row)
    for iu in range(NU):
        iu2 = (iu + 1) % NU
        for iv in range(NV):
            faces.append([ring[iu][iv], ring[iu2][iv], ring[iu2][iv + 1], ring[iu][iv + 1]])


if STYLE == "mohawk":
    mohawk()
else:
    cap()
if STYLE == "knot":
    knot()

me = bpy.data.meshes.new(STYLE)
me.from_pydata([tuple(v) for v in verts], [], faces)
me.update()
uvl = me.uv_layers.new(name="UVMap")
col = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
for v in me.vertices:
    col.data[v.index].color = (rootness[v.index], 0.0, 0.0, 1.0)
for p in me.polygons:
    p.use_smooth = True
    for li in p.loop_indices:
        uvl.data[li].uv = uvs[me.loops[li].vertex_index]
obj = bpy.data.objects.new(STYLE, me)
bpy.context.scene.collection.objects.link(obj)
# Consistent outward normals (the shader draws both sides; the light needs them out).
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me)
bm.free()
# Facing out from the head's middle: flip if most normals point in.
co = np.array([v.co for v in me.vertices])
nr = np.array([v.normal for v in me.vertices])
if np.mean(np.sum((co - HC) * nr, axis=1)) < 0:
    for p in me.polygons:
        p.flip()
    me.update()

hg = obj.vertex_groups.new(name="Head")
ng = obj.vertex_groups.new(name="Neck")
for v in me.vertices:
    t = min(max((NECK + 0.01 - v.co.z) / 0.08, 0.0), 1.0)
    t = t * t * (3 - 2 * t)
    if t < 0.999:
        hg.add([v.index], 1.0 - t, "REPLACE")
    if t > 0.001:
        ng.add([v.index], t, "REPLACE")
obj.parent = rig
mod = obj.modifiers.new("Armature", "ARMATURE")
mod.object = rig
print(f"HAIR {STYLE}: {len(me.vertices)} vertices, {len(me.polygons)} faces")
common.export_glb([rig, obj], out)
print("wrote", out)
