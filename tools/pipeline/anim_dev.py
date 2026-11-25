"""Animation work loop: opens the base body (spike/body/body.blend), rebuilds all animations
with the current skeleton.py, renders review strips and, with --export, writes body.glb and
the .blend again (no remesh or bakes, so it takes seconds, not minutes).

blender -b --python tools/pipeline/anim_dev.py -- <out_dir> <action[:view]>... [--export]
views: side, front, q (three-quarter). Example:
blender -b --python tools/pipeline/anim_dev.py -- /tmp/a run:side run:front walk:side
"""
import math
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402
import skeleton  # noqa: E402

import json  # noqa: E402

import motion_retarget  # noqa: E402

root = Path(__file__).resolve().parents[2]
a = common.args()
export = "--export" in a
a = [x for x in a if x != "--export"]
motion_dir = None
if "--motion" in a:
    i = a.index("--motion")
    motion_dir = Path(a[i + 1])
    del a[i:i + 2]
LOOPS = ("run", "walk", "idle")
sword = "--sword" in a
a = [x for x in a if x != "--sword"]
armor = []
while "--armor" in a:                 # an armor layer (armor.py's .blend) worn in the renders
    i = a.index("--armor")
    armor.append(Path(a[i + 1]))
    del a[i:i + 2]
out = Path(a[0])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(root / "spike/body/body.blend"))
rig = bpy.data.objects["Skeleton"]
body = bpy.data.objects["Body"]
for o in list(bpy.data.objects):          # leftovers (a preview sword saved by an earlier run)
    if o not in (rig, body):
        bpy.data.objects.remove(o)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for pb in rig.pose.bones:
    pb.location = (0, 0, 0)
skeleton.make_animations(rig)
# Pose experiments: ANIM_TEST=<dir> runs <dir>/anim_test.py's add(rig), which can add clips to
# render next to the real ones (e.g. variants of one key).
if os.environ.get("ANIM_TEST"):
    sys.path.insert(0, os.environ["ANIM_TEST"])
    import anim_test
    anim_test.add(rig)
# Generated motion: chosen clips (spike/motion/<clip>.npy) replace the hand-keyed ones; with
# --motion DIR every variant there (run_0, run_1, ...) is added for review.
chosen = sorted((root / "spike/motion").glob("*.npy")) if (root / "spike/motion").exists() else []
calib = root / "spike/motion/calibration_idle.npy"
if not calib.exists() and motion_dir and (motion_dir / "idle_0.npy").exists():
    calib = motion_dir / "idle_0.npy"
if calib.exists():
    motion_retarget.calibrate(rig, np.load(calib))
chosen = [c for c in chosen if c.name != "calibration_idle.npy"]
review = sorted(motion_dir.glob("*.npy")) if motion_dir else []
for f in chosen + review:
    name = f.stem
    if name in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[name])
    base = name.rsplit("_", 1)[0] if name[-1].isdigit() else name
    _, info = motion_retarget.make_action(rig, name, np.load(f), loop=base.rstrip("abcd") in LOOPS)
    print("MOTION", json.dumps(info))

for path in armor:
    with bpy.data.libraries.load(str(path)) as (src, dst):
        dst.objects = [n for n in src.objects if n != "Skeleton"]
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
        o.parent = rig
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = rig
        for ms in o.material_slots:
            ms.material.diffuse_color = (0.62, 0.64, 0.7, 1.0)    # workbench shows this

sword_obj = None
sword_offset = None
if sword:
    # The warrior's sword in the right hand, placed like the game does (humanoid.gd HOLD:
    # offset (0, -0.075, 0.01) and 90 degrees about X in Godot's character space, which is
    # Blender (x, -z, y)); it follows the hand bone each frame (see place_sword).
    from mathutils import Matrix
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(root / "game/assets/characters/warrior/sword.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    sword_obj = [o for o in new if o.type == "MESH"][0]
    for o in new:
        if o is not sword_obj:
            bpy.data.objects.remove(o)
    sword_obj.parent = None
    hand = rig.data.bones["RightHand"]
    want = Matrix.Translation(hand.head_local + Vector((0, -0.01, -0.075))) @ Matrix.Rotation(math.radians(90), 4, "X")
    sword_offset = hand.matrix_local.inverted() @ want


def place_sword():
    if sword_obj is not None:
        sword_obj.matrix_world = rig.matrix_world @ rig.pose.bones["RightHand"].matrix @ sword_offset


sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x, sc.render.resolution_y = 260, 400
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
sc.collection.objects.link(cam)
cam.data.type, cam.data.ortho_scale = "ORTHO", 2.3
sc.camera = cam
for spec in a[1:]:
    name, _, view = spec.partition(":")
    view = view or "side"
    gif = view.endswith("+gif")
    view = view.removesuffix("+gif")
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    start, end = act.frame_range
    n = 8 if name.split("_")[0] in ("walk", "run") else 10
    if gif:
        n = max(2, int(round(end - start)))          # every frame (24 fps)
    r = math.radians({"side": 90, "front": 0, "q": 40, "back": 180, "rside": -90, "rq": -40}[view])
    cam.location = Vector((6 * math.sin(r), -6 * math.cos(r), 0.95))
    cam.rotation_euler = (math.radians(90), 0, r)
    tmp = []
    for k in range(n):
        f = start + (end - start) * k / n
        sc.frame_set(int(f), subframe=f - int(f))
        place_sword()
        p = out / f"_{name}_{view}_{k}.png"
        sc.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        tmp.append(str(p))
    # Lowest point of the body at the last frame (0 = on the ground; for sitting/landing poses).
    sc.frame_set(int(end))
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    ps = [ev.matrix_world @ v.co for v in ev.data.vertices]
    low = min(ps, key=lambda q: q.z)
    hips = (rig.matrix_world @ rig.pose.bones["Hips"].head)
    seat = min((q for q in ps if (q.xy - hips.xy).length < 0.2), key=lambda q: q.z, default=low)
    print("GROUND", name, "last frame: lowest z", round(low.z, 3), "at", [round(c, 2) for c in low],
          "seat z", round(seat.z, 3), "hips", [round(c, 2) for c in hips])
    if gif:
        # Two loops at 24 fps; delay is in 1/100 s.
        dst = out / f"{name}_{view}.gif"
        subprocess.run(["magick", "-delay", "4.17", "-loop", "0", *(tmp * 2), "-layers", "Optimize", str(dst)], check=True)
    else:
        dst = out / f"{name}_{view}.png"
        subprocess.run(["magick", *tmp, "+append", str(dst)], check=True)
    for p in tmp:
        Path(p).unlink()
    print("STRIP", dst)

if export:
    rig.animation_data.action = bpy.data.actions["walk"]
    for o in list(bpy.data.objects):          # armor layers are reviewed here, not exported
        if o not in (rig, body) and o.type == "MESH" and o is not sword_obj:
            bpy.data.objects.remove(o)
    if sword_obj is not None:
        bpy.data.objects.remove(sword_obj)
        sword_obj = None
    for o in [c for c in bpy.data.objects if c.name == "c"]:
        bpy.data.objects.remove(o)
    common.export_glb([rig, body], root / "spike/body/body.glb", animations=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(root / "spike/body/body.blend"))
    print("EXPORTED", root / "spike/body/body.glb")
