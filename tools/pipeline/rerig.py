"""Re-rigs the base body without touching its mesh or UVs (so every baked outfit stays valid):
detects the joints again, rebuilds the skeleton, re-weights, recomputes the gear slots and the
animations, and writes spike/body/body.blend and body.glb.

blender -b --python tools/pipeline/rerig.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402

import common  # noqa: E402
import skeleton  # noqa: E402

root = Path(__file__).resolve().parents[2]
out = root / "spike/body"
bpy.ops.wm.open_mainfile(filepath=str(out / "body.blend"))
body = bpy.data.objects["Body"]
old = bpy.data.objects["Skeleton"]
# Free the mesh from the old rig.
mw = body.matrix_world.copy()
body.parent = None
body.matrix_world = mw
for m in list(body.modifiers):
    if m.type == "ARMATURE":
        body.modifiers.remove(m)
body.vertex_groups.clear()
if "slot" in body.data.color_attributes:
    body.data.color_attributes.remove(body.data.color_attributes["slot"])
bpy.data.objects.remove(old)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for a in list(bpy.data.armatures):
    if a.users == 0:
        bpy.data.armatures.remove(a)

J = skeleton.find_joints(body)
info = J.pop("_info")
rig = skeleton.build_armature(J)
unweighted = skeleton.bind(body, rig)
slots = skeleton.assign_slots(body)
skeleton.make_animations(rig)
common.export_glb([rig, body], out / "body.glb", animations=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out / "body.blend"))
print("REPORT", json.dumps({"unweighted": unweighted, "slots": slots, "info": info,
      "hip": [round(v, 3) for v in J["LeftUpperLeg"]], "knee": [round(v, 3) for v in J["LeftLowerLeg"]]}))
