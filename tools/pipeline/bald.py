"""The bald base body for heroes (bald_head.py): the mesh with a bald scalp and a forehead, and
its color, normal and roughness textures with the old hair painted over as skin (thin brows
over the eyes). NPCs and enemies keep the original body with its modelled hair.

blender -b --python tools/pipeline/bald.py -- <body_dir> <out_dir>
writes <out_dir>/body_bald.glb (mesh and skeleton, no clips: Humanoid swaps the mesh in) and
body_bald_color.png, body_bald_normal.png, body_bald_mr.png.
Textures: every texel of the head whose place (the head map, head_map.py) is in the hair's place
gets the skin of the forehead, a touch darker toward the crown's back; normals flat; matt.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bald_head  # noqa: E402
import common  # noqa: E402

a = common.args()
body_dir, out_dir = Path(a[0]), Path(a[1])
bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
if rig.animation_data:
    rig.animation_data.action = None
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)
free, HC, NECK = bald_head.make_bald(body, rig)
print(f"BALD {int(free.sum())} vertices moved")
bald_head.add_ears(body, HC)
common.export_glb([rig, body], out_dir / "body_bald.glb")


def load(path):
    im = bpy.data.images.load(str(path))
    im.colorspace_settings.name = "Non-Color"     # raw values in and out
    w, h = im.size
    return im, np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)


def save(px, size, path):
    im = bpy.data.images.new(path.stem, size[0], size[1], alpha=True)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(np.clip(px, 0, 1).ravel())
    im.filepath_raw = str(path)
    im.file_format = "PNG"
    im.save()


game_dir = out_dir
_, hm = load(game_dir / "body_head.png")                    # 1024: up, ahead, side, on-head
_, col = load(game_dir / "body_color.png")
H, W = col.shape[:2]
# The head map up to the texture's size (nearest).
ys = (np.arange(H) * hm.shape[0] // H)
xs = (np.arange(W) * hm.shape[1] // W)
hmb = hm[ys][:, xs]
pos = (hmb[..., :3] - 0.5) * 0.4
on = hmb[..., 3] > 0.5
# Painted over: the hair's place from a little lower than the forehead's edge (the fringe's dark
# shadow over the eyes went too), and the ears (painted with hair).
w = bald_head.hair_place(pos[..., 0], pos[..., 1], pos[..., 2], brow=0.003) * on
ear = bald_head.ear_place(pos[..., 0], pos[..., 1], pos[..., 2]) * on
# The skin: the mean of the forehead's and cheeks' clear skin texels.
skin_sel = on & (w < 0.05) & (pos[..., 1] > 0.06) & (pos[..., 0] > -0.03) & (pos[..., 0] < -0.006) & (np.abs(pos[..., 2]) > 0.03) & (np.abs(pos[..., 2]) < 0.06)
lum = col[..., :3] @ np.array([0.3, 0.59, 0.11])
skin_sel &= lum > np.percentile(lum[skin_sel], 30)
skin = col[skin_sel, :3].mean(axis=0)
print("BALD skin", skin)
rng = np.random.default_rng(3)
# Low-frequency blotches and a darker back of the head (the face's painted light came from front).
yy, xx = np.mgrid[0:H, 0:W]
blotch = (np.sin(xx * 0.05 + 1.3) * np.sin(yy * 0.043 + 0.7) * 0.5 + 0.5) * 0.03
shade = 1.0 - 0.08 * np.clip(-pos[..., 1] / 0.12, 0, 1)
paint = skin[None, None, :] * (1.0 + blotch[..., None] - 0.015) * shade[..., None]
paint += rng.normal(0, 0.008, paint.shape)
# Brows: two short arcs over the eyes, just above the forehead's lower edge.
bx = np.abs(pos[..., 2])
brow_y = 0.017 + 0.06 * (bx - 0.028) ** 2 - 0.05 * np.clip(bx - 0.03, 0, 1) ** 1 * 0.1
thick = 0.0026 * np.clip(1.2 - bx / 0.05, 0.4, 1.0)             # thinning outward
brows = (np.clip((bx - 0.01) / 0.005, 0, 1) * np.clip((0.045 - bx) / 0.006, 0, 1)
         * np.clip(1 - np.abs(pos[..., 0] - brow_y) / thick, 0, 1) * (pos[..., 1] > 0.07) * on)
# Left-over hair round the old hair's edge (dark texels of the head away from the eyes, nose and
# mouth) painted over too.
leftover = on & (lum < 0.25) & ~((pos[..., 1] > 0.05) & (pos[..., 0] < 0.012)) & (pos[..., 0] > -0.12)
ww = np.clip(np.maximum(np.maximum(w, ear), leftover), 0, 1)[..., None]
# The skin to paint: the face's own just below the old hairline (temples, brows, behind the
# jaw), one even tone; the face's skin near the line eased into it (no step), the hair's dark
# texels covered fully.
band = on & (w < 0.05) & (lum > 0.3) & (bald_head.hair_place(pos[..., 0], pos[..., 1], pos[..., 2], brow=-0.014) > 0.5)
band &= lum > np.percentile(lum[band], 45)
skin = col[band, :3].mean(axis=0)
print("BALD band skin", skin, int(band.sum()))
near = bald_head.hair_place(pos[..., 0] + 0.008, pos[..., 1], pos[..., 2], brow=0.003) * on      # 8 mm lower
eyes = (pos[..., 1] > 0.045) & (pos[..., 0] < 0.011)                 # the eyes, lids and nose stay
near = near * ~eyes
ww = np.where((lum < 0.3)[..., None], ww, np.maximum(ww, near[..., None] * 0.85))
ww = np.where(((lum < 0.32) & (near > 0.1))[..., None], 1.0, ww)            # hair strands left in the blend
paint = skin[None, None, :] * (1.0 + blotch[..., None] - 0.015) * shade[..., None]
paint += rng.normal(0, 0.006, paint.shape)
col[..., :3] = col[..., :3] * (1 - ww) + paint * ww

col[..., :3] = col[..., :3] * (1 - brows[..., None] * 0.6) + np.array([0.2, 0.14, 0.1]) * brows[..., None] * 0.6
save(col, (W, H), game_dir / "body_bald_color.png")
_, nrm = load(game_dir / "body_normal.png")
nrm[..., :3] = nrm[..., :3] * (1 - ww) + np.array([0.5, 0.5, 1.0]) * ww
save(nrm, (nrm.shape[1], nrm.shape[0]), game_dir / "body_bald_normal.png")
_, mr = load(game_dir / "body_mr.png")
mh, mwid = mr.shape[:2]
wm = np.maximum(w, ear)[(np.arange(mh) * H // mh)][:, (np.arange(mwid) * W // mwid)][..., None]
skin_mr = mr[(np.arange(mh) * H // mh)][:, (np.arange(mwid) * W // mwid)]
mr_skin = np.median(skin_mr[skin_sel[(np.arange(mh) * H // mh)][:, (np.arange(mwid) * W // mwid)]], axis=0)
mr[..., :3] = mr[..., :3] * (1 - wm) + mr_skin[:3] * wm
save(mr, (mwid, mh), game_dir / "body_bald_mr.png")
print("BALD textures written")
