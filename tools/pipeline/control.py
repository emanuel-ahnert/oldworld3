"""Renders control images of a base body for ControlNet (design/asset-pipeline.md, 6.2).

blender -b --python tools/pipeline/control.py -- <body.blend> <out_dir> [size]

Writes <out_dir>/depth.png: front orthographic view, near = white, far = dark, background
black, the body filling the frame vertically with a margin (same framing for every body, so
generated outfits line up with it). Writes framing.json with the camera parameters.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402

a = common.args()
blend, out = a[0], Path(a[1])
size = int(a[2]) if len(a) > 2 else 1024
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=blend)
body = bpy.data.objects["Body"]
rig = bpy.data.objects.get("Skeleton")
if rig:
    rig.data.pose_position = "REST"
for o in bpy.data.objects:
    o.hide_render = o is not body

lo, hi = common.bounds(body)
# Depth material: emission = 1 at the front-most point, falling to 0.1 at 25 cm behind it (clamped).
mat = bpy.data.materials.new("depth")
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
geo = nt.nodes.new("ShaderNodeNewGeometry")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
rng = nt.nodes.new("ShaderNodeMapRange")
rng.inputs["From Min"].default_value = lo.y
rng.inputs["From Max"].default_value = lo.y + 0.25
rng.clamp = True
rng.inputs["To Min"].default_value = 1.0
rng.inputs["To Max"].default_value = 0.1
em = nt.nodes.new("ShaderNodeEmission")
outn = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
nt.links.new(sep.outputs["Y"], rng.inputs["Value"])
nt.links.new(rng.outputs["Result"], em.inputs["Color"])
nt.links.new(em.outputs["Emission"], outn.inputs["Surface"])
body.data.materials.clear()
body.data.materials.append(mat)

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 8
sc.view_settings.view_transform = "Raw"
sc.render.resolution_x = sc.render.resolution_y = size
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("black")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
height = hi.z - lo.z
ortho = height * 1.12
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.data.type, cam.data.ortho_scale = "ORTHO", ortho
cam.location = Vector((0, -5, lo.z + height / 2))
cam.rotation_euler = (1.5707963, 0, 0)
sc.camera = cam
sc.render.filepath = str(out / "depth.png")
bpy.ops.render.render(write_still=True)
(out / "framing.json").write_text(json.dumps(
    {"view": "front, orthographic", "ortho_scale": ortho, "center_z": lo.z + height / 2,
     "size": size, "body_height": height}, indent=1))
print("REPORT", out / "depth.png")
