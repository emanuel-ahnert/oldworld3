"""Draws the skeleton found on a body over its front render, for checking joint placement.

blender -b --python tools/pipeline/debug_joints.py -- <body.glb> <out.png>
Needs ImageMagick (`magick`) to draw the overlay.
"""

import math
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402

a = common.args()
common.reset()
bpy.ops.import_scene.gltf(filepath=a[0])
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.data.pose_position = "REST"
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = False

sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
size, ortho = 800, 2.2
sc.render.resolution_x = sc.render.resolution_y = size
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
sc.collection.objects.link(cam)
cam.data.type, cam.data.ortho_scale = "ORTHO", ortho
cam.location, cam.rotation_euler = Vector((0, -5, 0.95)), (math.radians(90), 0, 0)
sc.camera = cam
sc.render.filepath = a[1]
bpy.ops.render.render(write_still=True)


def px(p):
    return (size / 2 + p.x / ortho * size, size / 2 - (p.z - 0.95) / ortho * size)


draw = []
for b in rig.data.bones:
    h, t = rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local
    (x1, y1), (x2, y2) = px(h), px(t)
    draw += ["-stroke", "red", "-strokewidth", "3", "-draw", f"line {x1:.0f},{y1:.0f} {x2:.0f},{y2:.0f}",
             "-fill", "yellow", "-stroke", "none", "-draw", f"circle {x1:.0f},{y1:.0f} {x1 + 4:.0f},{y1:.0f}"]
subprocess.run(["magick", a[1], *draw, a[1]], check=True)
