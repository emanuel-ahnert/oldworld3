"""Bakes a generated outfit (TRELLIS model in about the base body's pose) onto a base body.

blender -b --python tools/pipeline/outfit.py -- <body_dir> <outfit.glb> <name> [height_m] [reach_m]

reach_m (fully armored outfits): texels whose rays miss the outfit within 0.15 m get a second
bake reaching this far (e.g. 0.4) before falling back to the base body, so a sleeve that sits a
little off the arm still covers it instead of showing skin.

Reads <body_dir>/body.blend (from body.py). The outfit gets its own skeleton (same joint
finder), which is posed onto the body's skeleton so the outfit wraps onto the body; then its
colors are baked into the body's UV layout: <body_dir>/<name>_color.png. Also renders a
check image of the wrapped outfit over the body.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402

import common  # noqa: E402
import skeleton  # noqa: E402

a = common.args()
body_dir, outfit_path, name = Path(a[0]), Path(a[1]), a[2]
height = float(a[3]) if len(a) > 3 else 1.85
reach = float(a[4]) if len(a) > 4 else 0.0

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
body_rig = bpy.data.objects["Skeleton"]
body_rig.data.pose_position = "REST"
if body_rig.animation_data:
    body_rig.animation_data.action = None

outfit = common.import_glb(outfit_path, "Outfit")
common.normalize(outfit, height)
common.largest_part(outfit)
# Remesh a copy for rigging (bone heat needs a closed mesh); the original keeps its texture.
proxy = outfit.copy()
proxy.data = outfit.data.copy()
bpy.context.scene.collection.objects.link(proxy)
common.remesh(proxy, voxel=0.012, target_tris=15000)
J = skeleton.find_joints(proxy)
info = J.pop("_info")
rig = skeleton.build_armature(J, "OutfitSkeleton")
skeleton.bind(proxy, rig)
# Transfer the proxy's weights to the textured original.
outfit.parent = rig
for g in proxy.vertex_groups:
    outfit.vertex_groups.new(name=g.name)
dt = outfit.modifiers.new("dt", "DATA_TRANSFER")
dt.object = proxy
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
common.select_only([outfit])
bpy.ops.object.datalayout_transfer(modifier=dt.name)
bpy.ops.object.modifier_apply(modifier=dt.name)
am = outfit.modifiers.new("arm", "ARMATURE")
am.object = rig
bpy.data.objects.remove(proxy)

skeleton.fit_onto(rig, body_rig)
common.select_only([outfit])
bpy.ops.object.modifier_apply(modifier=am.name)
outfit.parent = None

img = common.new_image_material(body, name + "_color", 2048)
tex_node = body.active_material.node_tree.nodes.active
far = {}
if reach > 0.0:
    far["color"] = bpy.data.images.new(name + "_color_far", 2048, 2048, alpha=False)
    tex_node.image = far["color"]
    common.bake_color(outfit, body, extrusion=reach * 0.4, max_ray=reach)
    tex_node.image = img
common.bake_color(outfit, body, extrusion=0.06, max_ray=0.15)

nrm = common.bake_normal(outfit, body, 2048, extrusion=0.06, max_ray=0.15)
if reach > 0.0:
    far["normal"] = common.bake_normal(outfit, body, 2048, extrusion=reach * 0.4, max_ray=reach)
    # bake_mr rewires the outfit's materials, so the far pass works on fresh copies of them.
    keep = [s_.material.copy() for s_ in outfit.material_slots]
    far["mr"] = common.bake_mr(outfit, body, 2048, extrusion=reach * 0.4, max_ray=reach)
    for s_, m_ in zip(outfit.material_slots, keep):
        s_.material = m_
mr = common.bake_mr(outfit, body, 2048, extrusion=0.06, max_ray=0.15)

# Hit mask: bake the outfit as pure white emission; texels whose rays missed it stay black.
# Those are filled with the base body's own color, so holes show skin or clothes, not black.
for slot in outfit.material_slots:
    nt = slot.material.node_tree
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    out_node = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    nt.links.new(em.outputs["Emission"], out_node.inputs["Surface"])
mask = bpy.data.images.new(name + "_mask", 2048, 2048, alpha=False)
body.active_material.node_tree.nodes.active.image = mask
bpy.ops.object.bake(type="EMIT")
if reach > 0.0:
    far["mask"] = bpy.data.images.new(name + "_mask_far", 2048, 2048, alpha=False)
    body.active_material.node_tree.nodes.active.image = far["mask"]
    sc_ = bpy.context.scene.render.bake
    sc_.cage_extrusion, sc_.max_ray_distance = reach * 0.4, reach
    bpy.ops.object.bake(type="EMIT")
body.active_material.node_tree.nodes.active.image = img

import numpy as np  # noqa: E402
base = bpy.data.images.load(str(body_dir / "body_color.png"))
px = lambda im: np.array(im.pixels[:]).reshape(-1, 4)
c, m, b = px(img), px(mask)[:, :1], px(base)
m = (m > 0.5).astype(np.float32)
if reach > 0.0:
    # Near hits first, then the far pass, the base body only where both missed.
    mf = (px(far["mask"])[:, :1] > 0.5).astype(np.float32) * (1 - m)
    print("REPORT far pass fills", round(float(mf.mean()), 4), "of the texture")
    c = c * m + px(far["color"]) * mf
    mr_px = px(mr) * m + px(far["mr"]) * mf
    nrm_px = px(nrm) * m + px(far["normal"]) * mf
    m = m + mf
    mr.pixels[:] = mr_px.ravel()
    nrm.pixels[:] = nrm_px.ravel()
out_px = c * m + b * (1 - m)
out_px[:, 3] = 1
img.pixels[:] = out_px.ravel()
common.save_image(img, body_dir / f"{name}_color.png")
base_mr = bpy.data.images.load(str(body_dir / "body_mr.png"))
base_mr.colorspace_settings.is_data = True
r = px(mr) * m + px(base_mr) * (1 - m)
r[:, 3] = 1
mr.pixels[:] = r.ravel()
common.save_image(mr, body_dir / f"{name}_mr.png")
base_n = bpy.data.images.load(str(body_dir / "body_normal.png"))
base_n.colorspace_settings.is_data = True
r = px(nrm) * m + px(base_n) * (1 - m)
r[:, 3] = 1
nrm.pixels[:] = r.ravel()
common.save_image(nrm, body_dir / f"{name}_normal.png")
hit = float(m.mean())
bpy.ops.export_scene.gltf(filepath=str(body_dir / f"{name}_wrapped.glb"), export_format="GLB",
                          use_selection=True)
(body_dir / f"{name}_joints.json").write_text(json.dumps(
    {"info": info, "joints": {k: [round(c, 4) for c in v] for k, v in J.items()}}, indent=1))
print("REPORT", json.dumps({"info": info, "hit_fraction_of_texture": round(hit, 3)}))
