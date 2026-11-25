"""Renders an animation of a base body as a strip of frames from the side, for review.

blender -b --python tools/pipeline/anim_strip.py -- <body.blend> <action> <out.png> [frames] [view]
view: side (default) or front or q
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
blend, action, out = a[0], a[1], Path(a[2])
n = int(a[3]) if len(a) > 3 else 8
view = a[4] if len(a) > 4 else "side"
bpy.ops.wm.open_mainfile(filepath=blend)
rig = bpy.data.objects["Skeleton"]
act = bpy.data.actions[action]
rig.animation_data.action = act
start, end = act.frame_range
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x, sc.render.resolution_y = 300, 420
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
sc.collection.objects.link(cam)
cam.data.type, cam.data.ortho_scale = "ORTHO", 2.3
ang = {"side": 90, "front": 0, "q": 40}[view]
r = math.radians(ang)
cam.location = Vector((6 * math.sin(r), -6 * math.cos(r), 0.95))
cam.rotation_euler = (math.radians(90), 0, r)
sc.camera = cam
tmp = []
for k in range(n):
    f = start + (end - start) * k / n
    sc.frame_set(int(f), subframe=f - int(f))
    p = out.with_name(f"{out.stem}_{k}.png")
    sc.render.filepath = str(p)
    bpy.ops.render.render(write_still=True)
    tmp.append(str(p))
subprocess.run(["magick", *tmp, "+append", str(out)], check=True)
for p in tmp:
    Path(p).unlink()
print("REPORT", out)
