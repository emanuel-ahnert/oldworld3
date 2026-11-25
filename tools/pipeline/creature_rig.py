"""Rigs and animates a prepared creature (tools/pipeline/creature.py output, static mesh):
finds legs, body, head and tail from the geometry, builds a skeleton, skins the mesh with
distance-based weights (smoothed over the surface) and keys the clips the game plays:
idle, walk, run (loops), attack, hit, death, death2 (one-shots).

blender -b --python tools/pipeline/creature_rig.py -- <in.glb> <out.glb> <family> [key=value ...]

family: quad  (four legs: wolf, boar, bear)     style=bite|swipe|gore, lie=side (dies onto
              its side instead of the belly)
        bug   (many legs radiating from a body: spider, crab, scorpion, scarab)
              limbs=N (legs + claws + tail: how many limbs to find), claws=N (the N biggest
              front limbs are claws), tail=1 (a raised back limb)
        snake (coiled body with a raised neck: cobra, sand snake)
options: turn=deg (rotate first: the crab's claws pointed sideways), preview=<dir> (strips of
every clip), blend=<path> (save the .blend).
Writes <out>.json beside the glb: the walk and run speeds (m/s at playback rate 1).
Conventions as everywhere: Blender Z up, front -Y, left +X; a rotation about +X pitches the
front down (and swings a hanging leg backward).
"""

import heapq
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import common  # noqa: E402

FPS = 24
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)

a = common.args()
SRC, DST, FAMILY = a[0], a[1], a[2]
OPT = dict(s.split("=", 1) for s in a[3:] if "=" in s)

common.reset()
bpy.context.scene.render.fps = FPS
mesh_obj = common.import_glb(SRC, "Creature")
if float(OPT.get("turn", 0)):
    mesh_obj.data.transform(Matrix.Rotation(math.radians(float(OPT["turn"])), 4, "Z"))
    mesh_obj.data.update()
CO = np.array([v.co[:] for v in mesh_obj.data.vertices])
LO, HI = CO.min(axis=0), CO.max(axis=0)
H = HI[2]
LEN = HI[1] - LO[1]
WID = HI[0] - LO[0]

# --- welded surface graph (glTF splits vertices at UV seams) ---------------------------------
_keys = np.round(CO / 1e-4).astype(np.int64)
_, WELD, _inv_counts = np.unique(_keys, axis=0, return_inverse=True, return_counts=True)
WELD = WELD.ravel()
NW = WELD.max() + 1
WCO = np.zeros((NW, 3))
WCO[WELD] = CO
_e = np.array([e.vertices[:] for e in mesh_obj.data.edges])
E0, E1 = WELD[_e[:, 0]], WELD[_e[:, 1]]
_m = E0 != E1
E0, E1 = E0[_m], E1[_m]
ADJ = [[] for _ in range(NW)]
for i, j in zip(E0, E1):
    ADJ[i].append(j)
    ADJ[j].append(i)


def components(mask):
    """Connected components of the welded vertices where mask is True."""
    comp = -np.ones(NW, int)
    out = []
    for s in np.nonzero(mask)[0]:
        if comp[s] >= 0:
            continue
        stack, members = [s], []
        comp[s] = len(out)
        while stack:
            v = stack.pop()
            members.append(v)
            for n in ADJ[v]:
                if mask[n] and comp[n] < 0:
                    comp[n] = len(out)
                    stack.append(n)
        out.append(np.array(members))
    return out


def geodesic(members, sources):
    """Dijkstra distances inside `members` from the `sources` (welded ids)."""
    inside = np.zeros(NW, bool)
    inside[members] = True
    dist = np.full(NW, np.inf)
    heap = []
    for s in sources:
        dist[s] = 0.0
        heap.append((0.0, s))
    heapq.heapify(heap)
    while heap:
        d, v = heapq.heappop(heap)
        if d > dist[v]:
            continue
        for n in ADJ[v]:
            if inside[n]:
                nd = d + np.linalg.norm(WCO[n] - WCO[v])
                if nd < dist[n]:
                    dist[n] = nd
                    heapq.heappush(heap, (nd, n))
    return dist[members]


# --- skeleton and skin -----------------------------------------------------------------------

def build_armature(bones):
    """bones: [(name, head, tail, parent)] in order (parents first)."""
    arm = bpy.data.armatures.new("Skeleton")
    obj = bpy.data.objects.new("Skeleton", arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for name, h, t, parent in bones:
        eb = arm.edit_bones.new(name)
        eb.head, eb.tail = Vector(h), Vector(t)
        if (eb.tail - eb.head).length < 1e-3:
            eb.tail = eb.head + Vector((0, 0, 0.03))
        d = (eb.tail - eb.head).normalized()
        eb.align_roll(Vector((0, -1, 0)) if abs(d.y) < 0.7 else Vector((0, 0, 1)))
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def seg_dist(P, h, t):
    h, t = np.asarray(h), np.asarray(t)
    ab = t - h
    s = np.clip(((P - h) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(P - (h + s[:, None] * ab), axis=1)


def skin(rig, bones, allowed, smooth=4, power=4.0):
    """Weights per welded vertex from the distance to each bone segment (only bones the vertex
    is allowed on), the 3 strongest kept, smoothed over the surface, then written as vertex
    groups with an Armature modifier."""
    names = [b[0] for b in bones]
    D = np.stack([seg_dist(WCO, b[1], b[2]) for b in bones], axis=1)
    A = np.stack([allowed.get(n, np.ones(NW, bool)) for n in names], axis=1)
    W = np.where(A, 1.0 / (D + 0.01 * LEN) ** power, 0.0)
    for _ in range(smooth):
        S = np.zeros_like(W)
        deg = np.zeros(NW)
        np.add.at(S, E0, W[E1])
        np.add.at(S, E1, W[E0])
        np.add.at(deg, E0, 1)
        np.add.at(deg, E1, 1)
        W = 0.5 * W + 0.5 * S / np.maximum(deg, 1)[:, None]
        W = np.where(A, W, 0.0)
        W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)
    order = np.argsort(-W, axis=1)
    W[np.arange(NW)[:, None], order[:, 3:]] = 0.0
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)
    groups = {n: mesh_obj.vertex_groups.new(name=n) for n in names}
    Wv = W[WELD]
    for bi, n in enumerate(names):
        col = Wv[:, bi]
        for vi in np.nonzero(col > 0.002)[0]:
            groups[n].add([int(vi)], float(col[vi]), "REPLACE")
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    mesh_obj.parent = rig
    return W


# --- posing ----------------------------------------------------------------------------------

def rot(rig, bone, axis, deg):
    """Local quaternion turning `bone` by deg about an axis given in armature space (rest)."""
    b = rig.data.bones[bone]
    ax = (b.matrix_local.to_3x3().inverted() @ Vector(axis)).normalized()
    return Quaternion(ax, math.radians(deg))


def set_pose(rig, pose, loc=(0, 0, 0)):
    """pose: {bone: [(axis, deg), ...]} (others at rest); loc moves the root bone (armature
    space, meters)."""
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        q = Quaternion()
        for axis, deg in pose.get(pb.name, []):
            q = rot(rig, pb.name, axis, deg) @ q
        pb.rotation_quaternion = q
        pb.location = (0, 0, 0)
    root = rig.pose.bones[ROOT]
    root.location = rig.data.bones[ROOT].matrix_local.to_3x3().inverted() @ Vector(loc)
    bpy.context.view_layer.update()


def key(rig, frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    rig.pose.bones[ROOT].keyframe_insert("location", frame=frame)


GROUND_MASK = None   # vertices that rest on the ground when lying (quads: the torso, not the legs)


def mesh_min_z():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh_obj.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    z = co[2::3]
    if GROUND_MASK is not None:
        z = z[GROUND_MASK]
    ev.to_mesh_clear()
    return float(z.min())


def tails_min_z(rig, bones):
    return min(min(rig.pose.bones[b].tail.z, rig.pose.bones[b].head.z) for b in bones)


def new_action(rig, name):
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    return act


def clip(rig, name, keys, ground="feet"):
    """keys: [(frame, pose, loc)]. ground "feet": the lowest foot bone end stays where it was
    at rest (legs swinging or bending lower or raise the body); "body": the deformed mesh's
    lowest point goes to the ground (lying); None: loc as given."""
    new_action(rig, name)
    for f, pose, loc in keys:
        loc = Vector(loc)
        set_pose(rig, pose, loc)
        if ground == "feet":
            loc.z -= tails_min_z(rig, FEET) - FEET_Z
        elif ground == "body":
            loc.z -= mesh_min_z() - 0.005
        set_pose(rig, pose, loc)
        key(rig, f)


def grounded(rig, pose, loc):
    """loc with its height changed so the posed mesh's lowest point touches the ground."""
    loc = Vector(loc)
    set_pose(rig, pose, loc)
    loc.z -= mesh_min_z() - 0.005
    return tuple(loc)


def search(rig, pose, loc, bone, axis, lo, hi, measure, target, step=2.0):
    """The angle (deg) about `axis` for `bone` (added to the pose) that brings measure() closest
    to target."""
    best, best_err = 0.0, 1e9
    deg = lo
    while deg <= hi:
        p = {k: list(v) for k, v in pose.items()}
        p.setdefault(bone, []).append((axis, deg))
        set_pose(rig, p, loc)
        err = abs(measure() - target)
        if err < best_err:
            best, best_err = deg, err
        deg += step
    return best


def merge(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            out.setdefault(k, []).extend(v)
    return out


# ============================================================================================
# Four-legged animals
# ============================================================================================

def quad():
    global ROOT, FEET, FEET_Z
    cx = float(np.median(CO[:, 0]))
    band = WCO[(WCO[:, 2] > 0.03 * H) & (WCO[:, 2] < 0.14 * H)]
    ym = float(band[:, 1].min() + band[:, 1].max()) / 2
    legs = {}
    for name, sx, front in (("FL", 1, True), ("FR", -1, True), ("HL", 1, False), ("HR", -1, False)):
        m = ((band[:, 0] - cx) * sx > 0) & ((band[:, 1] < ym) == front)
        legs[name] = band[m].mean(axis=0) if m.any() else np.array([cx + sx * 0.15 * WID, ym, 0.05 * H])
    yf = (legs["FL"][1] + legs["FR"][1]) / 2
    yh = (legs["HL"][1] + legs["HR"][1]) / 2
    # Belly: the lowest well-populated height between the front and hind legs.
    mid = WCO[(WCO[:, 1] > yf + 0.3 * (yh - yf)) & (WCO[:, 1] < yh - 0.3 * (yh - yf))
              & (np.abs(WCO[:, 0] - cx) < 0.3 * WID)]
    hist, edges = np.histogram(mid[:, 2], bins=50, range=(0, H))
    zb = max(edges[np.argmax(hist > hist.max() * 0.15)], 0.3 * H)
    print(f"QUAD L={LEN:.2f} H={H:.2f} belly={zb:.2f} yf={yf:.2f} yh={yh:.2f}")

    def back_top(y):
        s = WCO[(np.abs(WCO[:, 1] - y) < 0.05 * LEN) & (np.abs(WCO[:, 0] - cx) < 0.3 * WID)]
        return float(np.quantile(s[:, 2], 0.9))

    # Track each leg from the foot up to the belly.
    track = {}
    for name, foot in legs.items():
        sx = 1 if name[1] == "L" else -1
        front = name[0] == "F"
        c = foot[:2].copy()
        pts = []
        for z in np.arange(0.04 * H, zb + 1e-6, 0.03 * H):
            s = WCO[(np.abs(WCO[:, 2] - z) < 0.02 * H) & ((WCO[:, 0] - cx) * sx > -0.02)
                    & ((WCO[:, 1] < (yf + yh) / 2) == front)]
            if len(s):
                d = np.linalg.norm(s[:, :2] - c, axis=1)
                near = s[d < 0.12 * LEN]
                if len(near):
                    c = 0.5 * c + 0.5 * near[:, :2].mean(axis=0)
            pts.append(np.array([c[0], c[1], z]))
        track[name] = np.array(pts)

    def at(name, z):
        t = track[name]
        i = int(np.argmin(np.abs(t[:, 2] - z)))
        return t[i]

    sp_f = np.array([cx, yf, zb + 0.45 * (back_top(yf) - zb)])
    sp_h = np.array([cx, yh, zb + 0.45 * (back_top(yh) - zb)])
    midp = (sp_f + sp_h) / 2
    ymin = WCO[:, 1].min()
    tip_v = WCO[WCO[:, 1] < ymin + 0.03 * LEN]
    snout = tip_v.mean(axis=0)
    hv = WCO[(WCO[:, 1] < ymin + 0.15 * LEN) & (WCO[:, 2] > 0.6 * zb)]
    hc = hv.mean(axis=0) if len(hv) else snout
    hbase = hc + (hc - snout) * 0.6
    bones = [("Hips", sp_h, midp, None), ("Chest", midp, sp_f, "Hips"),
             ("Neck", sp_f, hbase, "Chest"), ("Head", hbase, snout, "Neck")]
    tail_v = WCO[(WCO[:, 1] > yh + 0.12 * LEN) & (WCO[:, 2] > 0.6 * zb)]
    has_tail = len(tail_v) > 30
    if has_tail:
        ymax = tail_v[:, 1].max()
        tt = tail_v[tail_v[:, 1] > ymax - 0.04 * LEN].mean(axis=0)
        tb = sp_h + np.array([0, 0.06 * LEN, 0.1 * (back_top(yh) - zb)])
        tm = (tb + tt) / 2
        bones += [("Tail1", tb, tm, "Hips"), ("Tail2", tm, tt, "Tail1")]
    leg_top = {}
    for name in legs:
        top_z = zb + 0.3 * (back_top(yf if name[0] == "F" else yh) - zb)
        top = at(name, zb).copy()
        top[2] = top_z
        knee = at(name, 0.5 * zb)
        foot = at(name, 0.04 * H).copy()
        foot[2] = 0.02 * H
        parent = "Chest" if name[0] == "F" else "Hips"
        bones += [(name + "_up", top, knee, parent), (name + "_lo", knee, foot, name + "_up")]
        leg_top[name] = top
    rig = build_armature(bones)
    ROOT = "Hips"
    FEET = [n + "_lo" for n in legs]
    FEET_Z = min(b[2][2] for b in bones if b[0] in FEET)

    # Leg bones only on their own quarter of the body, below the leg's top (plus a margin).
    allowed = {}
    for name in legs:
        sx = 1 if name[1] == "L" else -1
        m = (((WCO[:, 0] - cx) * sx > -0.01) & ((WCO[:, 1] < (yf + yh) / 2) == (name[0] == "F"))
             & (WCO[:, 2] < leg_top[name][2] + 0.05 * H))
        allowed[name + "_up"] = m
        allowed[name + "_lo"] = m & (WCO[:, 2] < at(name, 0.5 * zb)[2] + 0.12 * H)
    allowed["Head"] = WCO[:, 1] < sp_f[1] - 0.02 * LEN
    allowed["Neck"] = WCO[:, 1] < midp[1]
    if has_tail:
        allowed["Tail1"] = WCO[:, 1] > sp_h[1]
        allowed["Tail2"] = WCO[:, 1] > sp_h[1]
    W = skin(rig, bones, allowed)
    # Lying, the torso rests on the ground; the folded legs (thick on generated meshes) may sink
    # into it a little (the terrain hides them) instead of propping the body up.
    global GROUND_MASK
    leg_cols = [i for i, b in enumerate(bones) if b[0][:2] in legs]
    GROUND_MASK = (W[:, leg_cols].sum(axis=1) < 0.5)[WELD]
    speeds = quad_clips(rig, has_tail, OPT.get("style", "bite"))
    return rig, speeds


def legs_pose(swing, bend, names=("FL", "FR", "HL", "HR")):
    """swing: per-leg thigh angle (+ backward), bend: per-leg lower-leg bend."""
    p = {}
    for n in names:
        p[n + "_up"] = [(X, swing.get(n, 0.0))]
        sgn = 1.0 if n[0] == "F" else -1.0       # front: the wrist folds back, hind: the hock forward
        p[n + "_lo"] = [(X, sgn * bend.get(n, 0.0) - swing.get(n, 0.0) * 0.3)]
    return p


def quad_gait(rig, name, frames, amp, lift, phases, bob, has_tail, head=3.0):
    keys = []
    for f in range(frames + 1):
        ph = f / frames
        swing, bend = {}, {}
        for leg, off in phases.items():
            x = (ph + off) % 1.0
            # Stance (first 60%): the foot moves back under the body; swing: forward, lifted.
            st = 0.6
            if x < st:
                swing[leg] = -amp + 2 * amp * (x / st)
                bend[leg] = 0.0
            else:
                s = (x - st) / (1 - st)
                swing[leg] = amp - 2 * amp * (0.5 - 0.5 * math.cos(s * math.pi))
                bend[leg] = lift * math.sin(s * math.pi)
        p = legs_pose(swing, bend)
        w = math.sin(ph * 4 * math.pi)
        p["Hips"] = [(Y, 1.5 * math.sin(ph * 2 * math.pi))]
        p["Neck"] = [(X, head * w)]
        p["Head"] = [(X, -head * 0.6 * w)]
        if has_tail:
            p["Tail1"] = [(Z, 10 * math.sin(ph * 2 * math.pi))]
            p["Tail2"] = [(Z, 12 * math.sin(ph * 2 * math.pi - 0.8))]
        keys.append((f, p, (0, 0, bob * w)))
    clip(rig, name, keys)
    # Speed: how far a planted foot travels back per second.
    set_pose(rig, keys[0][1])
    leg_len = LEG_LEN
    stride = 2 * leg_len * math.sin(math.radians(amp))
    return stride / (frames / FPS * 0.6)


def quad_clips(rig, has_tail, style):
    global LEG_LEN
    b = rig.data.bones
    LEG_LEN = (b["FL_up"].length + b["FL_lo"].length + b["HL_up"].length + b["HL_lo"].length) / 2
    tail = (lambda a1, a2=None: {"Tail1": [(Z, a1)], "Tail2": [(Z, a2 if a2 is not None else a1)]}) if has_tail \
        else (lambda a1, a2=None: {})
    # Idle: breathing, a slow look around, the tail swaying.
    keys = []
    for f in range(0, 73, 4):
        s = math.sin(f / 72 * 2 * math.pi)
        c = math.cos(f / 72 * 2 * math.pi)
        p = merge({"Chest": [(X, 1.2 * s)], "Neck": [(Z, 6 * c), (X, 2 * s)], "Head": [(Z, 4 * c)]},
                  tail(8 * s, 10 * math.sin(f / 72 * 2 * math.pi - 0.7)))
        keys.append((f, p, (0, 0, 0)))
    clip(rig, "idle", keys)
    walk = quad_gait(rig, "walk", 24, 18, 45, {"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}, 0.01 * H, has_tail)
    run = quad_gait(rig, "run", 14, 30, 70, {"FL": 0.0, "HR": 0.05, "FR": 0.5, "HL": 0.55}, 0.03 * H, has_tail, 6.0)
    L = LEN
    rest = {}
    if style == "swipe":
        # Rear up on the hind legs, swipe a front paw across, slam back down.
        rear = merge({"Hips": [(X, -28)], "Chest": [(X, -8)], "Neck": [(X, 10)], "Head": [(X, 8)]},
                     legs_pose({"HL": 30, "HR": 30, "FL": -50, "FR": -80}, {"FL": 40, "FR": 30, "HL": 20, "HR": 20}),
                     tail(0))
        swipe = merge({"Hips": [(X, -18)], "Chest": [(X, 6), (Z, 14)], "Neck": [(X, 22)], "Head": [(X, 6)]},
                      legs_pose({"HL": 20, "HR": 20, "FL": -40, "FR": -35}, {"FL": 40, "FR": 10, "HL": 15, "HR": 15}))
        swipe["FR_up"].append((Z, 35))
        slam = merge({"Hips": [(X, 3)], "Chest": [(X, 6)], "Neck": [(X, 16)], "Head": [(X, 5)]},
                     legs_pose({"FL": -8, "FR": -10, "HL": 6, "HR": 6}, {"FL": 15, "FR": 15}))
        keys = [(0, rest, (0, 0, 0)), (9, rear, (0, 0.04 * L, 0)), (13, swipe, (0, -0.06 * L, 0)),
                (17, slam, (0, -0.08 * L, 0)), (26, rest, (0, 0, 0))]
    elif style == "gore":
        # Head down, charge a step and toss the tusks up.
        down = merge({"Neck": [(X, 22)], "Head": [(X, 15)]},
                     legs_pose({"HL": -12, "HR": -12, "FL": 8, "FR": 8}, {"HL": 25, "HR": 25}))
        thrust = merge({"Neck": [(X, 18)], "Head": [(X, 10)], "Hips": [(X, 4)]},
                       legs_pose({"HL": 28, "HR": 25, "FL": -22, "FR": -18}, {"FL": 25, "FR": 20}))
        toss = merge({"Neck": [(X, -22)], "Head": [(X, -28)], "Hips": [(X, -4)]},
                     legs_pose({"HL": 15, "HR": 15, "FL": -10, "FR": -12}, {"FL": 10}))
        keys = [(0, rest, (0, 0, 0)), (5, down, (0, 0.05 * L, 0)), (9, thrust, (0, -0.14 * L, 0)),
                (12, toss, (0, -0.16 * L, 0)), (19, rest, (0, 0, 0))]
    else:
        # Bite: crouch, lunge with the head low, snap and shake.
        crouch = merge({"Hips": [(X, -5)], "Neck": [(X, -12)], "Head": [(X, -10)]},
                       legs_pose({"HL": -10, "HR": -10, "FL": -8, "FR": -8}, {"HL": 40, "HR": 40, "FL": 15, "FR": 15}),
                       tail(0, -10))
        lunge = merge({"Hips": [(X, 6)], "Chest": [(X, 4)], "Neck": [(X, 24)], "Head": [(X, 18)]},
                      legs_pose({"HL": 32, "HR": 28, "FL": -38, "FR": -30}, {"FL": 40, "FR": 30}),
                      tail(5, 15))
        snap = merge(lunge, {"Head": [(X, -14), (Z, 14)], "Neck": [(Z, 6)]})
        shake = merge(lunge, {"Head": [(X, -8), (Z, -16)], "Neck": [(Z, -6)]})
        keys = [(0, rest, (0, 0, 0)), (6, crouch, (0, 0.07 * L, 0)), (10, lunge, (0, -0.14 * L, 0)),
                (12, snap, (0, -0.15 * L, 0)), (14, shake, (0, -0.14 * L, 0)), (21, rest, (0, 0, 0))]
    clip(rig, "attack", keys)
    hit = merge({"Hips": [(Z, 4)], "Neck": [(X, -10), (Z, -8)], "Head": [(X, -12)]},
                legs_pose({"FL": -6, "FR": -6, "HL": -4, "HR": -4}, {"HL": 15, "HR": 15}), tail(-12))
    clip(rig, "hit", [(0, rest, (0, 0, 0)), (3, hit, (0, 0.05 * L, 0)), (10, rest, (0, 0, 0))])
    for name, side in (("death", 1), ("death2", -1)):
        quad_death(rig, name, side, tail)
    return {"walk": walk, "run": run}


def quad_death(rig, name, s, tail):
    """Stagger, the legs give way and fold under, the body collapses onto its belly and slumps
    a little to one side, the head sinks to the ground. (Rolled fully onto the side, the stiff
    legs stuck out like a toy's.) s = +1 slumps to the left (+X), -1 to the right."""
    L = LEN
    stagger = merge({"Neck": [(X, -18)], "Head": [(X, -14)], "Hips": [(Z, 5 * s)]},
                    legs_pose({"FL": -6, "FR": -4, "HL": 8, "HR": 6}, {}), tail(-15))
    # Lying like a dog: forelegs stretched forward flat on the ground, hind legs folded flat
    # (thigh forward, the lower leg back under it); the lower side's legs a little out.
    low = "L" if s > 0 else "R"

    def lying_legs(k):
        p = {}
        for n in ("FL", "FR", "HL", "HR"):
            out = (14 if n[1] == low else -6) * -s
            if n[0] == "F":
                p[n + "_up"] = [(X, -62 * k), (Y, out * k)]
                p[n + "_lo"] = [(X, -22 * k)]
            else:
                p[n + "_up"] = [(X, -68 * k), (Y, out * k)]
                p[n + "_lo"] = [(X, 150 * k)]
        return p
    buckle = merge({"Neck": [(X, 10)], "Head": [(X, 4)], "Hips": [(Y, 8 * s)]}, lying_legs(0.55), tail(0, 10))
    if OPT.get("lie") == "side":
        # Heavy, pillar-legged animals (the bear) slump over onto the side, legs loosely bent;
        # the upper side's legs sink onto the lower ones.
        lie_legs = lying_legs(0.4)
        for n in ("FL", "FR", "HL", "HR"):
            if n[1] != low:
                lie_legs[n + "_up"].append((Y, -s * 30))
        lie = merge({"Hips": [(Y, 70 * s)], "Chest": [(Y, 8 * s)]}, lie_legs, tail(-25 * s, -20 * s))
    else:
        lie_legs = lying_legs(1.0)
        lie = merge({"Hips": [(Y, 26 * s)], "Chest": [(Y, 6 * s)]}, lie_legs, tail(-25 * s, -20 * s))
    # Ground the body first (head at rest), then bend the neck until the head lies on that
    # ground (searching with the head included in the grounding let a long snout prop up the
    # whole body).
    lie["Neck"] = [(Z, 12 * s), (X, 15)]
    loc = grounded(rig, lie, (0, 0.02 * L, 0))
    head_low = lambda: min(rig.pose.bones["Head"].tail.z, rig.pose.bones["Head"].head.z)  # noqa: E731
    ang = search(rig, merge(lie, {"Neck": [(Z, 12 * s)]}), loc, "Neck", X, -10, 80, head_low, 0.06 * H, 3.0)
    lie["Neck"] = [(Z, 12 * s), (X, ang)]
    lie["Head"] = [(X, 10), (Y, 18 * s)]
    loc = grounded(rig, lie, loc)
    settle = merge(lie, {"Hips": [(Y, -5 * s)], "Neck": [(X, -8)]})
    clip(rig, name, [(0, {}, (0, 0, 0)), (4, stagger, grounded(rig, stagger, (0, 0.04 * L, 0))),
                     (12, buckle, grounded(rig, buckle, (0, 0.03 * L, 0))),
                     (19, settle, grounded(rig, settle, loc)), (24, lie, loc), (40, lie, loc)], ground=None)


# ============================================================================================
# Bugs and crabs: legs radiating from a body
# ============================================================================================

def thickness():
    """Per welded vertex: distance through the mesh along the inward normal (smoothed)."""
    from mathutils.bvhtree import BVHTree
    me = mesh_obj.data
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices[:] for p in me.polygons])
    t = np.full(NW, np.nan)
    for v in me.vertices:
        w = WELD[v.index]
        if not np.isnan(t[w]):
            continue
        n = -v.normal
        hit = bvh.ray_cast(v.co + n * 1e-3, n, H)
        t[w] = hit[3] if hit[0] is not None else np.nan
    t = np.where(np.isnan(t), np.nanmedian(t), t)
    for _ in range(4):
        S = np.zeros(NW)
        deg = np.zeros(NW)
        np.add.at(S, E0, t[E1])
        np.add.at(S, E1, t[E0])
        np.add.at(deg, E0, 1)
        np.add.at(deg, E1, 1)
        t = 0.5 * t + 0.5 * S / np.maximum(deg, 1)
    return t


def bug():
    global ROOT, FEET, FEET_Z
    c = np.array([np.median(WCO[:, 0]), np.median(WCO[:, 1])])
    rxy = np.linalg.norm(WCO[:, :2] - c, axis=1)
    # Limbs radiate from the body: seen from above each one keeps its direction. The body ends
    # where the vertices stop covering all directions; the limbs are the peaks of the direction
    # histogram outside it (islands and thickness both failed on the spider: its legs touch).
    az = np.arctan2(WCO[:, 1] - c[1], WCO[:, 0] - c[0])
    rmax = rxy.max()
    core_r = float(OPT["core"]) * rmax if "core" in OPT else 0.5 * rmax
    if "core" not in OPT:
        for r in np.linspace(0.1, 0.8, 36) * rmax:
            ring = (rxy > r) & (rxy < r + 0.04 * rmax)
            if ring.sum() < 10:
                continue
            cover = len(np.unique(((az[ring] + math.pi) / (2 * math.pi / 72)).astype(int))) / 72
            if cover < 0.55:
                core_r = r
                break
    # Above the body's top counts as limb too (claws raised over the shell, spider knees).
    body_top = float(np.quantile(WCO[rxy < 0.5 * core_r, 2], 0.95)) + 0.03 * H
    out = (rxy > core_r) | (WCO[:, 2] > body_top)
    nb = 90
    hist, _ = np.histogram(az[out], bins=nb, range=(-math.pi, math.pi), weights=rxy[out] - core_r)
    h = (np.roll(hist, 1) + 2 * hist + np.roll(hist, -1)) / 4
    want = int(OPT.get("limbs", 8))
    peaks = []
    for i in np.argsort(-h):
        if h[i] < max(np.roll(h, 1)[i], np.roll(h, -1)[i]):
            continue
        if all(min(abs(i - j), nb - abs(i - j)) >= 3 for j in peaks):
            peaks.append(int(i))
        if len(peaks) == want:
            break
    pang = np.array([-math.pi + (i + 0.5) * 2 * math.pi / nb for i in peaks])
    diff = np.abs((az[:, None] - pang[None, :] + math.pi) % (2 * math.pi) - math.pi)
    owner = np.argmin(diff, axis=1)
    owner[~out | (diff.min(axis=1) > math.radians(float(OPT.get("spread", 22))))] = -1
    # A limb that is its own piece outside the body goes wholly to the direction holding most
    # of it (a crab's claw arm passes over a leg's direction); pieces where several limbs touch
    # keep the split by direction.
    for comp in components(out):
        own = owner[comp]
        own = own[own >= 0]
        if len(own) == 0:
            continue
        cnt = np.bincount(own, minlength=len(peaks))
        if cnt.max() > 0.7 * len(own):
            owner[comp] = int(np.argmax(cnt))
    core = owner < 0
    print(f"BUG core radius {core_r:.2f} ({core_r / rmax:.2f}) limbs {len(peaks)} at {np.round(np.degrees(pang)).astype(int).tolist()}")
    zc = float(np.median(WCO[core & (rxy < core_r), 2]))
    body_bottom = float(np.quantile(WCO[core & (rxy < core_r), 2], 0.03))
    limbs = []
    for k in range(len(peaks)):
        isl = np.nonzero(owner == k)[0]
        if len(isl) < 10:
            continue
        r = rxy[isl]
        t = (r - core_r) / max(r.max() - core_r, 1e-6)
        # Along the surface from the body (legs that drop straight down at the end keep their
        # foot as the tip); pieces not connected inside the sector keep the radial measure.
        src = isl[t < 0.06]
        d = geodesic(isl, src if len(src) else isl[[int(np.argmin(t))]])
        ok = np.isfinite(d)
        if ok.sum() > 0.7 * len(isl):
            tg = d / max(d[ok].max(), 1e-6)
            t = np.where(ok, tg, t)
        joints = []
        for lo, hi in ((0.0, 0.08), (0.28, 0.38), (0.62, 0.72), (0.92, 1.01)):
            m = (t >= lo) & (t <= hi)
            joints.append(WCO[isl[m]].mean(axis=0) if m.any() else WCO[isl[np.argmax(t)]])
        limbs.append({"verts": isl, "t": t, "joints": joints, "size": len(isl),
                      "root": joints[0], "tip": joints[-1]})
    n_claws = int(OPT.get("claws", 0))
    for lb in limbs:
        lb["kind"] = "leg"
    if OPT.get("tail"):
        back = [lb for lb in limbs if lb["root"][1] > c[1]]
        if back:
            max(back, key=lambda lb: lb["tip"][2])["kind"] = "tail"
    front = sorted([lb for lb in limbs if lb["kind"] == "leg" and lb["tip"][1] < c[1]], key=lambda lb: -lb["size"])
    for lb in front[:n_claws]:
        lb["kind"] = "claw"
    bones = [("Body", (c[0], c[1] + 0.1 * LEN, zc), (c[0], c[1] - 0.1 * LEN, zc), None)]
    allowed = {}
    count = {"leg": 0, "claw": 0, "tail": 0}
    for lb in limbs:
        side = "L" if lb["root"][0] > c[0] else "R"
        nm = f"{lb['kind'].capitalize()}{count[lb['kind']]}{side}"
        count[lb["kind"]] += 1
        lb["name"] = nm
        lb["bones"] = [f"{nm}_{k}" for k in range(3)]
        mask = np.zeros(NW, bool)
        mask[lb["verts"]] = True
        for k in range(3):
            bones.append((lb["bones"][k], lb["joints"][k], lb["joints"][k + 1], "Body" if k == 0 else lb["bones"][k - 1]))
            allowed[lb["bones"][k]] = mask
        o = np.array([lb["root"][0] - c[0], lb["root"][1] - c[1], 0.0])
        lb["out"] = o / max(np.linalg.norm(o), 1e-6)
        lb["tan"] = np.cross((0, 0, 1), lb["out"])
    rig = build_armature(bones)
    ROOT = "Body"
    legs = [lb for lb in limbs if lb["kind"] == "leg"]
    FEET = [lb["bones"][2] for lb in legs] or ["Body"]
    FEET_Z = 0.0
    skin(rig, bones, allowed, smooth=3)
    for lb in limbs:
        print(f"  {lb['name']}: {lb['size']} verts, joints {[np.round(j, 2).tolist() for j in lb['joints']]}")
    speeds = bug_clips(rig, limbs, c, body_bottom)
    return rig, speeds


def bug_clips(rig, limbs, c, body_bottom):
    legs = [lb for lb in limbs if lb["kind"] == "leg"]
    claws = [lb for lb in limbs if lb["kind"] == "claw"]
    tails = [lb for lb in limbs if lb["kind"] == "tail"]
    # Alternating gait: along each side every other leg, opposite on the other side.
    for side in ("L", "R"):
        row = sorted([lb for lb in legs if lb["name"].endswith(side)], key=lambda lb: lb["root"][1])
        for i, lb in enumerate(row):
            lb["phase"] = ((i + (0 if side == "L" else 1)) % 2) * 0.5

    def limb(lb, swing=0.0, lift=0.0, curl=0.0):
        """swing: forward (deg), lift: up (deg) at the root, curl: the outer segments bend in/down."""
        fwd = -1.0 if lb["out"][0] > 0 else 1.0
        if abs(lb["out"][0]) < 0.3:          # pointing straight forward/back: swing sideways
            fwd = 1.0
        return {lb["bones"][0]: [(Z, fwd * swing), (tuple(lb["tan"]), -lift)],
                lb["bones"][1]: [(tuple(lb["tan"]), curl)],
                lb["bones"][2]: [(tuple(lb["tan"]), curl * 0.7)]}

    def gait(name, frames, amp, lift_deg, bob):
        keys = []
        for f in range(frames + 1):
            ph = f / frames
            p = {}
            for lb in legs:
                x = (ph + lb["phase"]) % 1.0
                if x < 0.5:
                    s = x / 0.5
                    p.update(limb(lb, amp * (1 - 2 * s), 0.0))
                else:
                    s = (x - 0.5) / 0.5
                    p.update(limb(lb, -amp + 2 * amp * (0.5 - 0.5 * math.cos(s * math.pi)), lift_deg * math.sin(s * math.pi)))
            for cl in claws:
                p.update(limb(cl, 0, 8 + 4 * math.sin(ph * 2 * math.pi), 0))
            for tl in tails:
                p.update(limb(tl, 0, 4 * math.sin(ph * 4 * math.pi), 0))
            p.setdefault("Body", []).append((Y, 2.5 * math.sin(ph * 2 * math.pi)))
            keys.append((f, p, (0, 0, bob * abs(math.sin(ph * 2 * math.pi)))))
        clip(rig, name, keys, ground=None)
        reach = np.mean([np.linalg.norm(np.array(lb["tip"][:2]) - np.array(lb["root"][:2])) for lb in legs]) if legs else 0.3
        return 2 * reach * math.sin(math.radians(amp)) / (frames / FPS * 0.5)

    keys = []
    for f in range(0, 61, 5):
        s = math.sin(f / 60 * 2 * math.pi)
        p = {}
        for lb in legs:
            p.update(limb(lb, 1.5 * math.sin(f / 60 * 2 * math.pi + lb["root"][1] * 5), 0, 0))
        for cl in claws:
            p.update(limb(cl, 3 * s, 6 + 4 * s, -6 * s))
        for tl in tails:
            p.update(limb(tl, 4 * s, 3 * s, 2 * s))
        keys.append((f, p, (0, 0, 0.01 * H * s)))
    clip(rig, "idle", keys, ground=None)
    walk = gait("walk", 20, 14, 22, 0.01 * H)
    run = gait("run", 12, 20, 30, 0.02 * H)
    L = LEN

    def all_legs(**kw):
        p = {}
        for lb in legs:
            p.update(limb(lb, **kw))
        return p
    front_legs = sorted(legs, key=lambda lb: lb["root"][1])[:2]
    # Attack: rear up (claws/front legs/tail raised), then lunge forward and strike down.
    rear = merge(all_legs(lift=-6), {"Body": [(X, -14)]})
    strike = merge(all_legs(lift=4), {"Body": [(X, 10)]})
    for cl in claws:
        rear.update(limb(cl, -12, 22, -12))
        strike.update(limb(cl, 18, -12, 12))
    if not claws:
        for lb in front_legs:
            rear.update(limb(lb, 10, 55, -20))
            strike.update(limb(lb, 15, -10, 10))
    for tl in tails:
        rear.update(limb(tl, 0, 25, 25))
        strike.update(limb(tl, 0, 55, 45))
    clip(rig, "attack", [(0, {}, (0, 0, 0)), (7, rear, (0, 0.06 * L, 0.05 * H)), (11, strike, (0, -0.12 * L, -0.02 * H)),
                         (14, strike, (0, -0.12 * L, -0.02 * H)), (21, {}, (0, 0, 0))], ground=None)
    hit = merge(all_legs(lift=10, curl=10), {"Body": [(X, -8), (Y, 5)]})
    for cl in claws:
        hit.update(limb(cl, -10, 15, 15))
    clip(rig, "hit", [(0, {}, (0, 0, 0)), (3, hit, (0, 0.05 * L, 0.03 * H)), (10, {}, (0, 0, 0))], ground=None)
    # Death: a spasm (legs jerk up), then the body drops flat onto the ground, the legs splay
    # out and lie on the ground, slightly curled; the claws and tail flop down too.
    for name, s in (("death", 1), ("death2", -1)):
        spasm = merge(all_legs(lift=25, curl=20), {"Body": [(X, -10)]})
        for cl in claws:
            spasm.update(limb(cl, 0, 12, 8))
        for cl in tails:
            spasm.update(limb(cl, 0, 30, 20))
        drop = (0, 0.02 * L, -(body_bottom - 0.02 * H))
        lie = {"Body": [(Y, 6 * s), (X, 3)]}
        set_pose(rig, lie, drop)
        for cl in claws:
            # Claws are big and stiff: they flop down (the root angle that brings their highest
            # point lowest).
            base = limb(cl, 6, 0, 10)
            top_z = lambda cl=cl: max(max(rig.pose.bones[b].tail.z, rig.pose.bones[b].head.z) for b in cl["bones"])  # noqa: E731
            ang = search(rig, merge(lie, base), drop, cl["bones"][0], tuple(cl["tan"]), -110, 110, top_z, 0.0, 4.0)
            lie.update(base)
            lie[cl["bones"][0]] = base[cl["bones"][0]] + [(tuple(cl["tan"]), ang)]
        for lb in limbs:
            if lb["kind"] == "claw":
                continue
            curl = 25 if lb["kind"] == "leg" else 10
            base = limb(lb, 4 if lb["kind"] == "leg" else 0, 0, curl)
            p = merge(lie, base)
            ang = search(rig, p, drop, lb["bones"][0], tuple(lb["tan"]), -40, 80,
                         lambda lb=lb: tails_min_z(rig, lb["bones"]), 0.015 * H, 2.0)
            lie.update(base)
            lie[lb["bones"][0]] = base[lb["bones"][0]] + [(tuple(lb["tan"]), ang)]
            set_pose(rig, lie, drop)
        bounce = merge(lie, {"Body": [(X, -3)]})
        clip(rig, name, [(0, {}, (0, 0, 0)), (4, spasm, (0, 0.03 * L, 0.06 * H)), (13, lie, drop),
                         (16, bounce, (drop[0], drop[1], drop[2] + 0.02 * H)), (20, lie, drop), (36, lie, drop)], ground=None)
    return {"walk": walk, "run": run}


# ============================================================================================
# Snakes: a coil on the ground and a raised neck
# ============================================================================================

def snake():
    global ROOT, FEET, FEET_Z
    top = int(np.argmax(WCO[:, 2]))
    raised = None
    for thr in (0.38, 0.33, 0.45, 0.28):
        for comp in components(WCO[:, 2] > thr * H):
            if top in set(comp.tolist()):
                raised = comp
                break
        if raised is not None and len(raised) < 0.6 * NW:
            break
    inside = np.zeros(NW, bool)
    inside[raised] = True
    boundary = [v for v in raised if any(not inside[n] for n in ADJ[v])]
    d = geodesic(raised, boundary)
    t = d / d.max()
    joints = [WCO[boundary].mean(axis=0)]
    for k in range(1, 5):
        m = np.abs(t - k / 4) < 0.06
        joints.append(WCO[raised[m]].mean(axis=0) if m.any() else WCO[raised[np.argmax(t)]])
    # The head: extend the last joint to the snout (farthest point from the 3rd joint).
    hv = WCO[raised[t > 0.8]]
    joints[-1] = hv[np.argmax(np.linalg.norm(hv - joints[3], axis=1))]
    coil = WCO[~inside]
    cc = np.array([np.median(coil[:, 0]), np.median(coil[:, 1]), 0.02])
    print(f"SNAKE raised {len(raised)}/{NW} joints {[np.round(j, 2).tolist() for j in joints]}")
    bones = [("Root", cc, joints[0], None)]
    names = ["N1", "N2", "N3", "Head"]
    for k, n in enumerate(names):
        bones.append((n, joints[k], joints[k + 1], "Root" if k == 0 else names[k - 1]))
    rig = build_armature(bones)
    ROOT = "Root"
    FEET = ["Root"]
    FEET_Z = 0.0
    allowed = {n: inside | (WCO[:, 2] > joints[0][2] - 0.08 * H) for n in names}
    allowed["N2"] = inside.copy()
    allowed["N3"] = inside.copy()
    allowed["Head"] = inside.copy()
    allowed["Root"] = ~inside | (WCO[:, 2] < joints[0][2] + 0.08 * H)
    skin(rig, bones, allowed, smooth=5)
    L = LEN
    keys = []
    for f in range(0, 61, 5):
        s = math.sin(f / 60 * 2 * math.pi)
        keys.append((f, {"N1": [(Z, 6 * s)], "N2": [(Z, -3 * s), (X, 2 * s)], "N3": [(Z, -5 * s)], "Head": [(Z, 4 * s)]}, (0, 0, 0)))
    clip(rig, "idle", keys, ground=None)

    def slither(name, frames, amp):
        keys = []
        for f in range(frames + 1):
            s = math.sin(f / frames * 2 * math.pi)
            c2 = math.cos(f / frames * 2 * math.pi)
            keys.append((f, {"Root": [(Z, amp * 0.5 * s)], "N1": [(Z, amp * c2)], "N2": [(Z, -amp * 0.6 * s)],
                             "N3": [(Z, -amp * 0.5 * c2)], "Head": [(Z, amp * 0.3 * s)]}, (0, 0, 0.01 * H * abs(s))))
        clip(rig, name, keys, ground=None)
    slither("walk", 24, 10)
    slither("run", 14, 14)
    back = {"N1": [(X, -16)], "N2": [(X, -10)], "N3": [(X, 6)], "Head": [(X, 8)]}
    strike = {"N1": [(X, 38)], "N2": [(X, 18)], "N3": [(X, 6)], "Head": [(X, -24)]}
    clip(rig, "attack", [(0, {}, (0, 0, 0)), (6, back, (0, 0.05 * L, 0)), (9, strike, (0, -0.1 * L, 0)),
                         (12, strike, (0, -0.1 * L, 0)), (19, {}, (0, 0, 0))], ground=None)
    clip(rig, "hit", [(0, {}, (0, 0, 0)), (3, {"N1": [(X, -12), (Z, 6)], "Head": [(X, -10)]}, (0, 0.03 * L, 0)),
                      (10, {}, (0, 0, 0))], ground=None)
    for name, s in (("death", 1), ("death2", -1)):
        rise = {"N1": [(X, -10), (Z, 8 * s)], "N3": [(X, -10)], "Head": [(X, -15)]}
        lie = {"N1": [(Z, 25 * s)], "N2": [(X, 30), (Z, 15 * s)], "N3": [(X, 25)], "Head": [(X, -10)]}
        head_low = lambda: min(rig.pose.bones["Head"].head.z, rig.pose.bones["Head"].tail.z)  # noqa: E731
        ang = search(rig, lie, (0, 0, 0), "N1", X, 0, 110, head_low, 0.07 * H, 2.0)
        lie["N1"].append((X, ang))
        bounce = merge(lie, {"N1": [(X, -6)]})
        clip(rig, name, [(0, {}, (0, 0, 0)), (5, rise, (0, 0, 0)), (15, lie, (0, 0, 0)), (18, bounce, (0, 0, 0)),
                         (22, lie, (0, 0, 0)), (36, lie, (0, 0, 0))], ground=None)
    return rig, {"walk": 1.2, "run": 2.4}


# ============================================================================================

rig, speeds = {"quad": quad, "bug": bug, "snake": snake}[FAMILY]()
# Preview strips: every clip at a few frames, side view.
if OPT.get("preview"):
    out = Path(OPT["preview"])
    out.mkdir(parents=True, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 360, 300
    sc.render.film_transparent = True
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type, cam.data.ortho_scale = "ORTHO", max(LEN, H, WID) * 1.5
    view = {"side": (1, -0.25, 0.35), "front": (0.25, -1, 0.3), "top": (0.3, -0.3, 1)}[OPT.get("view", "side")]
    target = Vector((float(np.median(CO[:, 0])), float(np.median(CO[:, 1])), H * 0.35))
    d = Vector(view).normalized()
    cam.location = target + d * 10
    cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    if OPT.get("weights"):
        # Debug: color every vertex by its strongest bone.
        rng = np.random.default_rng(3)
        cols = {g.index: rng.random(3) for g in mesh_obj.vertex_groups}
        attr = mesh_obj.data.color_attributes.new("dbg", "FLOAT_COLOR", "POINT")
        for v in mesh_obj.data.vertices:
            g = max(v.groups, key=lambda g: g.weight, default=None)
            c3 = cols[g.group] if g else (1, 1, 1)
            attr.data[v.index].color = (*c3, 1)
        mesh_obj.data.color_attributes.active_color = attr
        sc.display.shading.color_type = "VERTEX"
    for act in bpy.data.actions:
        rig.animation_data.action = act
        lo_f, hi_f = (int(x) for x in act.frame_range)
        for i, f in enumerate(np.linspace(lo_f, hi_f, 6).round().astype(int)):
            sc.frame_set(int(f))
            sc.render.filepath = str(out / f"{act.name}_{i}.png")
            bpy.ops.render.render(write_still=True)
# Export.
for pb in rig.pose.bones:
    pb.rotation_quaternion = Quaternion()
    pb.location = (0, 0, 0)
rig.animation_data.action = None
if OPT.get("blend"):
    bpy.ops.wm.save_as_mainfile(filepath=OPT["blend"])
common.select_only([rig, mesh_obj])
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", use_selection=True, export_animations=True,
                          export_yup=True, export_animation_mode="ACTIONS", export_force_sampling=True,
                          export_def_bones=False, export_tangents=True)
Path(DST).with_suffix(".json").write_text(json.dumps({k: round(v, 3) for k, v in speeds.items()}))
print("SPEEDS", speeds)
