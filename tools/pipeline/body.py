"""Turns a TRELLIS model of a person in A-pose into a rigged, animated base body.

blender -b --python tools/pipeline/body.py -- <in.glb> <out_dir> [height_m]

Writes <out_dir>/body.glb (mesh + skeleton + walk), body_color.png, joints.json and
preview renders (rest pose and walk frames) for review.
"""

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402
import skeleton  # noqa: E402


def render_views(objs, out, frames, prefix, size=512):
    """Workbench renders from the front and 3/4 for each frame; returns the paths."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("w")
    cam = bpy.data.objects.get("PreviewCam")
    if not cam:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        sc.collection.objects.link(cam)
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 2.2
    sc.camera = cam
    paths = []
    for f in frames:
        sc.frame_set(f)
        for name, ang in (("front", 0), ("side", 90), ("q", 35)):
            a = math.radians(ang)
            cam.location = Vector((5 * math.sin(a), -5 * math.cos(a), 0.95))
            cam.rotation_euler = (math.radians(90), 0, a)
            p = out / f"{prefix}_{name}_f{f:02d}.png"
            sc.render.filepath = str(p)
            bpy.ops.render.render(write_still=True)
            paths.append(p)
    return paths


def main():
    a = common.args()
    src_path, out = Path(a[0]), Path(a[1])
    height = float(a[2]) if len(a) > 2 else 1.85
    out.mkdir(parents=True, exist_ok=True)
    common.reset()

    src = common.import_glb(src_path, "Source")
    common.normalize(src, height)
    n_parts = common.largest_part(src)
    common.normalize(src, height)

    body = src.copy()
    body.data = src.data.copy()
    body.name = "Body"
    bpy.context.scene.collection.objects.link(body)
    common.remesh(body, voxel=0.008, target_tris=24000)
    common.largest_part(body)
    common.smart_uv(body)
    img = common.new_image_material(body, "body_color", 2048)
    common.bake_color(src, body, extrusion=0.02, max_ray=0.05)
    common.save_image(img, out / "body_color.png")
    img.pack()
    nrm = common.bake_normal(src, body, 2048, extrusion=0.02, max_ray=0.05)
    common.save_image(nrm, out / "body_normal.png")
    mr = common.bake_mr(src, body, 2048, extrusion=0.02, max_ray=0.05)
    common.save_image(mr, out / "body_mr.png")
    bpy.data.objects.remove(src)

    J = skeleton.find_joints(body)
    info = J.pop("_info")
    rig = skeleton.build_armature(J)
    unweighted = skeleton.bind(body, rig)
    slots = skeleton.assign_slots(body)
    skeleton.make_animations(rig)

    common.export_glb([rig, body], out / "body.glb", animations=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "body.blend"))
    render_views([rig, body], out, frames=[1, 9, 17, 25], prefix="body")
    report = {
        "source": str(src_path), "height": height, "loose_parts_removed": n_parts - 1,
        "tris": sum(len(p.vertices) - 2 for p in body.data.polygons),
        "unweighted_verts": unweighted, "slots": slots, "info": info,
        "joints": {k: [round(c, 4) for c in v] for k, v in J.items()},
    }
    (out / "joints.json").write_text(json.dumps(report, indent=1))
    print("REPORT", json.dumps({k: report[k] for k in ("tris", "unweighted_verts", "slots", "info", "loose_parts_removed")}))


main()
