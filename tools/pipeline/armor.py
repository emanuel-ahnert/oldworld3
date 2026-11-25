"""Builds armor layer geometry (WoW style: a second mesh worn over the body) from the base body.

blender -b --python tools/pipeline/armor.py -- <body_dir> <set> <out.glb>

set "plate_shoulders": pauldrons. set "plate_legs": plate armor for the legs: a fauld (the plate skirt at the waist), tassets over
the hips, cuisses on the thighs, knee cops, greaves on the shins and sabatons on the feet. Each
piece is a shell cut from the body's own surface (so it fits), smoothed (the pants' folds are
gone), pushed out from the bone axis and given thickness; edges carry a brass trim and the skirt plates lames, drawn by
the game's shaders/armor.gdshader from per-vertex data. Every piece hangs rigidly on its bone (knee cops halfway between thigh and shin, so they
turn half as far), like real plates, so they don't stretch when the knee bends.

The result is one skinned mesh on the shared skeleton (bone names of SkeletonProfileHumanoid);
the game shows it over the body when the legs slot holds plate (humanoid.gd, "layers").
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402

a = common.args()
body_dir, which, out = Path(a[0]), a[1], Path(a[2])

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
if rig.animation_data:
    rig.animation_data.action = None
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)



def bone_line(name):
    b = rig.data.bones[name]
    return b.head_local.copy(), b.tail_local.copy()


def axis_at(line, z):
    """Point on the bone line at height z (clamped to the segment)."""
    h, t = line
    if abs(t.z - h.z) < 1e-6:
        return h.copy()
    f = min(1.0, max(0.0, (z - h.z) / (t.z - h.z)))
    return h.lerp(t, f)


# Body vertices that belong to the arms (they hang down to the hips in the rest pose).
ARM = set()
_arm_groups = {g.index for g in body.vertex_groups if "Arm" in g.name or "Hand" in g.name or "Shoulder" in g.name}
for _v in body.data.vertices:
    _arm = sum(g.weight for g in _v.groups if g.group in _arm_groups)
    if _arm > 0.5 * sum(g.weight for g in _v.groups):       # mostly arm (the thighs near the
        ARM.add(_v.index)                                   # hands carry a little arm weight)


def cut(keep_vert, z0, z1, arms=False):
    """A bmesh of the body faces whose vertices all pass keep_vert (never the arms), cut
    cleanly at z0 and z1."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    dead = [f for f in bm.faces if not all(keep_vert(v.co) and (arms or v.index not in ARM) for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    for z, keep_above in ((z0, True), (z1, False)):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1),
                               clear_inner=keep_above, clear_outer=not keep_above)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # Drop crumbs: islands of a few faces (thin strips left between the cut rules).
    seen = set()
    for f in list(bm.faces):
        if f in seen or not f.is_valid:
            continue
        island, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        if len(island) < 60:
            bmesh.ops.delete(bm, geom=island, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    return bm


def shape(bm, line, offset, smooth=24, round_=0.7, bulge=0.0, zc=None, zr=1.0):
    """Smooths the cut in the horizontal plane (no folds), rounds it toward a circle around the
    bone line and pushes it out by `offset`; `bulge` adds more in the middle height (zc ± zr).
    Vertices that end up far from where they were (spikes from thin bits) are dropped."""
    orig = {v: v.co.copy() for v in bm.verts}
    for _ in range(smooth):
        bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.6, use_axis_x=True, use_axis_y=True,
                              use_axis_z=False)
    # Mean radius per height band, to round the shell.
    bands = {}
    for v in bm.verts:
        c = axis_at(line, v.co.z)
        d = (v.co.xy - c.xy).length
        bands.setdefault(round(v.co.z / 0.02), []).append(d)
    mean = {k: sum(ds) / len(ds) for k, ds in bands.items()}
    for v in bm.verts:
        c = axis_at(line, v.co.z)
        r = v.co.xy - c.xy
        d = r.length
        if d < 1e-5:
            continue
        m = mean[round(v.co.z / 0.02)]
        extra = 0.0
        if bulge and zc is not None:
            extra = bulge * max(0.0, 1.0 - ((v.co.z - zc) / zr) ** 2)
        nd = d * (1 - round_) + max(d, m) * round_ + offset + extra
        v.co.xy = c.xy + r / d * nd
    spikes = [v for v in bm.verts if (v.co - orig[v]).length > offset + 0.06]
    bmesh.ops.delete(bm, geom=spikes, context="VERTS")


def push_normals(bm, offset, smooth=6):
    for _ in range(smooth):
        bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True,
                              use_axis_z=True)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * offset


def finish(bm, name, weights, thickness=0.007, lames=0.0, trim=0.012):
    """Object from bm: thickness, brass trim along the top and bottom edges (the straight cuts),
    dark inside, smooth shading, bone weights. weights(co) -> {bone: w}."""
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    # Weights per vertex (rigid pieces).
    groups = {}
    for v in me.vertices:
        for bone, w in weights(v.co).items():
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, "REPLACE")
    obj.vertex_groups.new(name="shell")
    sol = obj.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = thickness
    sol.offset = -1.0
    sol.use_rim = True
    sol.use_even_offset = False         # even offset spikes on thin slivers
    sol.shell_vertex_group = "shell"
    common.select_only([obj])
    bpy.ops.object.modifier_apply(modifier=sol.name)
    # Data for the game's armor shader (shaders/armor.gdshader): UV.x = height above the piece's
    # bottom edge (m), color = (inside, lame spacing / 0.1 m, trim width / 0.05 m, piece height
    # in m). The shader draws the trim and the lames as crisp lines from these.
    me = obj.data
    for ca in list(me.color_attributes):      # the body's slot colors came along with the cut
        me.color_attributes.remove(ca)
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    sg = obj.vertex_groups["shell"].index
    for v in me.vertices:
        inner = any(g.group == sg and g.weight > 0.5 for g in v.groups)
        col.data[v.index].color = (1.0 if inner else 0.0, lames / 0.1, trim / 0.05, z1 - z0)
    uv = me.uv_layers[0] if me.uv_layers else me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        uv.data[loop.index].uv = (me.vertices[loop.vertex_index].co.z - z0, 0.0)
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for p in me.polygons:
        p.use_smooth = True
    obj.vertex_groups.remove(obj.vertex_groups["shell"])
    return obj


def side_of(x, sx):
    return x * sx > 0.0


def leg_pieces(side):
    sx = 1 if side == "Left" else -1
    up = bone_line(side + "UpperLeg")
    low = bone_line(side + "LowerLeg")
    foot = rig.data.bones[side + "Foot"]
    knee_z = up[1].z
    ankle_z = low[1].z
    hip_z = up[0].z
    pieces = []

    # Cuisse: the thigh plate, all around but the inside, where the thighs touch. z: a hand
    # above the knee up to below the hip crease.
    def k_cuisse(co):
        if not side_of(co.x, sx):
            return False
        return abs(co.x) > 0.028              # not the band between the legs
    bm = cut(k_cuisse, knee_z + 0.07, hip_z - 0.09)
    shape(bm, up, 0.022, round_=0.6)
    pieces.append(finish(bm, side + "Cuisse", lambda co: {side + "UpperLeg": 1.0}))

    # Tasset: a plate hanging from the waist over the hip, outside and front.
    def k_tasset(co):
        if not side_of(co.x, sx):
            return False
        c = axis_at(up, co.z)
        return (co.x - c.x) * sx > -0.02 or co.y - c.y < -0.03
    bm = cut(k_tasset, hip_z - 0.15, hip_z + 0.02)
    shape(bm, up, 0.03, round_=0.4)
    pieces.append(finish(bm, side + "Tasset", lambda co: {side + "UpperLeg": 0.7, "Hips": 0.3}, lames=0.045))

    # Knee cop: a domed plate over the front of the knee, halfway between thigh and shin.
    def k_knee(co):
        if not side_of(co.x, sx):
            return False
        c = axis_at(up, co.z) if co.z > knee_z else axis_at(low, co.z)
        return co.y - c.y < 0.012
    bm = cut(k_knee, knee_z - 0.07, knee_z + 0.075)
    shape(bm, up, 0.03, round_=0.7, bulge=0.018, zc=knee_z, zr=0.07)
    pieces.append(finish(bm, side + "Knee", lambda co: {side + "UpperLeg": 0.45, side + "LowerLeg": 0.55},
                         thickness=0.008, trim=0.02))

    # Greave: the shin plate all around, from the ankle to under the knee.
    def k_greave(co):
        return side_of(co.x, sx)
    bm = cut(k_greave, ankle_z + 0.035, knee_z - 0.06)
    shape(bm, low, 0.018, round_=0.6, bulge=0.008, zc=(ankle_z + knee_z) / 2, zr=0.2)
    pieces.append(finish(bm, side + "Greave", lambda co: {side + "LowerLeg": 1.0}))

    # Sabaton: the armored shoe (no sole), toes on the toe bone.
    toes_y = foot.tail_local.y

    def k_foot(co):
        return side_of(co.x, sx) and co.z < ankle_z + 0.06
    bm = cut(k_foot, 0.004, ankle_z + 0.05)
    bm.normal_update()
    sole = [f for f in bm.faces if f.normal.z < -0.6 or sum(v.co.z for v in f.verts) / len(f.verts) < 0.012]
    bmesh.ops.delete(bm, geom=sole, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    push_normals(bm, 0.012)

    def w_foot(co):
        t = min(1.0, max(0.0, (toes_y - co.y) / 0.03 + 0.5))     # toward the toes (-y)
        return {side + "Foot": 1.0 - t, side + "Toes": t} if t > 0.0 else {side + "Foot": 1.0}
    pieces.append(finish(bm, side + "Sabaton", w_foot, thickness=0.006))
    return pieces


def fauld():
    """The plate skirt around the waist: a band from the belt down over the hip joints."""
    hips = bone_line("Hips")
    hip_z = rig.data.bones["LeftUpperLeg"].head_local.z
    axis = (Vector((0, hips[0].y, 0)), Vector((0, hips[0].y, 2)))
    # Down over the seat at the back; at the front it stops above the crotch.
    bm = cut(lambda co: co.y > hips[0].y - 0.02 or co.z > hip_z - 0.03 or abs(co.x) > 0.07,
             hip_z - 0.09, hip_z + 0.11)
    shape(bm, axis, 0.022, round_=0.5)
    # Snug at the belt (no gap to look into from above), flaring toward the bottom like a skirt.
    top = max(v.co.z for v in bm.verts)
    for v in bm.verts:
        f = max(0.0, (hip_z + 0.05 - v.co.z) / 0.14)
        g = max(0.0, 1.0 - (top - v.co.z) / 0.05)          # 1 at the top edge
        r = v.co.xy - axis[0].xy
        d = r.length
        if d > 1e-5:
            v.co.xy = axis[0].xy + r / d * (d * (1.0 + 0.08 * f) - 0.016 * g)
    return finish(bm, "Fauld", lambda co: {"Hips": 1.0}, thickness=0.008, lames=0.04)


def pauldron(side):
    """A shoulder plate: a dome over the shoulder joint in lames, wider than the arm, hanging
    over the top of the upper arm; it turns with the arm a little more than with the chest."""
    sx = 1 if side == "Left" else -1
    j = rig.data.bones[side + "UpperArm"].head_local

    def k(co):
        d = (co - j).length
        return co.x * sx > 0.09 and d < 0.17 and co.z > j.z - 0.12
    bm = cut(k, j.z - 0.12, j.z + 0.14, arms=True)
    push_normals(bm, 0.045, smooth=14)
    # Dome: push the top up and out a bit more, flare the lower edge outward.
    for v in bm.verts:
        d = v.co - j
        up = max(0.0, d.z) / 0.1
        low = max(0.0, -d.z) / 0.1
        out = Vector((d.x, d.y, 0.0))
        if out.length > 1e-5:
            v.co += out.normalized() * (0.025 * up + 0.05 * low)
        v.co.z += 0.022 * up
    return finish(bm, side + "Pauldron", lambda co: {side + "UpperArm": 0.65, "UpperChest": 0.35},
                  thickness=0.009, lames=0.045, trim=0.014)


if which == "plate_legs":
    parts = leg_pieces("Left") + leg_pieces("Right") + [fauld()]
    obj_name = "PlateLegs"
elif which == "plate_shoulders":
    parts = [pauldron("Left"), pauldron("Right")]
    obj_name = "PlateShoulders"
else:
    raise SystemExit("unknown armor set " + which)
obj = common.join(parts)
obj.name = obj_name
mat = bpy.data.materials.new(which)
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
attr = nt.nodes.new("ShaderNodeVertexColor")
attr.layer_name = "Col"
nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Metallic"].default_value = 0.85
bsdf.inputs["Roughness"].default_value = 0.38
obj.data.materials.clear()
obj.data.materials.append(mat)
obj.parent = rig
am = obj.modifiers.new("arm", "ARMATURE")
am.object = rig
print("ARMOR", obj.name, len(obj.data.vertices), "verts", len(obj.data.polygons), "faces")
common.export_glb([rig, obj], out)
bpy.ops.wm.save_as_mainfile(filepath=str(out.with_suffix(".blend")))
print("EXPORTED", out)
