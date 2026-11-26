"""Cuts a generated model down to a triangle budget and keeps its look: the mesh is welded and
collapsed (Blender's Decimate) to about `tris` triangles, unwrapped anew, and the original is
its color baked onto it (Cycles, selected-to-active) in a new texture. A collapse can't keep the
generator's UV layout (the texture smeared across it), hence the new one. Matte (roughness
0.85, no metal).
Models already under the budget are copied unchanged.

blender -b --python tools/pipeline/reduce.py -- <in.glb> <out.glb> <tris> [texture_px]
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402

import common  # noqa: E402

a = common.args()
src, out, target = a[0], a[1], int(a[2])
size = int(a[3]) if len(a) > 3 else 1024


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def dims(obj):
    lo, hi = common.bounds(obj)
    return [round(x, 3) for x in (hi - lo)]


common.reset()
low = common.import_glb(src, "Model")
before = tri_count(low)
if before <= target * 1.1:
    common.export_glb([low], out)
    print("REDUCE", Path(src).name, before, "->", before, "(unchanged)")
    sys.exit(0)

# The original, kept for the bakes.
high = low.copy()
high.data = low.data.copy()
high.name = "High"
bpy.context.collection.objects.link(high)

# The reduced copy: no UVs or split normals to hold the collapse back, doubled vertices welded
# (generated meshes are split along their UV seams: the collapse tore them apart there).
me = low.data
while me.uv_layers:
    me.uv_layers.remove(me.uv_layers[0])
if me.has_custom_normals:
    common.select_only([low])
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
bm = bmesh.new()
bm.from_mesh(me)
lo0, hi0 = common.bounds(low)
diag = (hi0 - lo0).length
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=diag * 1e-4)
bm.to_mesh(me)
bm.free()
print("STEP welded", tri_count(low))
# Generated meshes don't collapse far: edges shared by three faces and more and hundreds of
# tiny loose fragments hold the collapse back (it stalled at about half). So the surface is
# first rebuilt as closed shells on a voxel grid (1/250 of the model's size; `voxel=` to
# change), the small loose shells dropped, and that collapses to the budget.
vox = next((float(x.split("=")[1]) for x in a if x.startswith("voxel=")), 250.0)
rm = low.modifiers.new("Remesh", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = diag / vox
common.select_only([low])
bpy.ops.object.modifier_apply(modifier=rm.name)
me = low.data
parts = common.largest_part(low, keep_frac=0.003)
print("STEP remeshed", tri_count(low), "parts", parts)
mod = low.modifiers.new("Decimate", "DECIMATE")
mod.decimate_type = "COLLAPSE"
mod.ratio = min(1.0, target / tri_count(low))
mod.use_collapse_triangulate = True
common.select_only([low])
bpy.ops.object.modifier_apply(modifier=mod.name)
after = tri_count(low)
me = low.data
if after > before * 0.8:
    # Not worth it (thin or fragmented models rebuild into many small shells, which don't
    # collapse): the original stays.
    print("REDUCE", Path(src).name, before, "->", after, "(not smaller: kept the original)")
    sys.exit(0)
for p in me.polygons:
    p.use_smooth = True

# New UVs: islands by angle, packed.
me.uv_layers.new(name="UVMap")
common.select_only([low])
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")

# The color, baked from the original onto the new UVs. (Normal and metal/roughness bakes from
# the original came out empty in Blender 5.2 here, with the same settings that bake the color:
# the result is matte, which the game prefers for its generated models anyway.)
color = common.new_image_material(low, "Model_color", size)
common.bake_color(high, low, diag * 0.012, diag * 0.04)
bsdf = low.active_material.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.85
# Into a file and back (the exporter reads it from there).
import tempfile  # noqa: E402
tmp = Path(tempfile.mkdtemp())
common.save_image(color, tmp / "Model_color.png")
color.filepath = str(tmp / "Model_color.png")
color.source = "FILE"
color.reload()
print("DIMS", dims(high), "->", dims(low))
bpy.data.objects.remove(high)
common.export_glb([low], out)
print("REDUCE", Path(src).name, before, "->", after)
