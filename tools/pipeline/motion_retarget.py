"""Retargets generated motion (MoMask / HumanML3D joint positions) onto the base body's skeleton.

Input: a .npy of shape (frames, 22, 3), SMPL joint order, Y up, the person facing +Z, 20 fps.
For each of our bones the direction between the matching joints is taken, and the bone is
turned so its rest direction points there (shortest rotation, in world space), then converted
to a local rotation through the parent chain. The pelvis gets a full orientation from the hip
line and the spine. Loops (walk, run) lose their root translation and are cut to the best
repeating cycle; one-shots keep their timing.

Used from Blender (anim_dev.py, rerig.py) through make_action(); not a command line tool.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

FPS_IN = 20.0
FPS_OUT = 24.0

# SMPL / HumanML3D joints.
J = {"pelvis": 0, "l_hip": 1, "r_hip": 2, "spine1": 3, "l_knee": 4, "r_knee": 5, "spine2": 6,
     "l_ankle": 7, "r_ankle": 8, "spine3": 9, "l_foot": 10, "r_foot": 11, "neck": 12,
     "l_collar": 13, "r_collar": 14, "head": 15, "l_shoulder": 16, "r_shoulder": 17,
     "l_elbow": 18, "r_elbow": 19, "l_wrist": 20, "r_wrist": 21}

# Our bone -> (from joint, to joint): the bone points along that segment.
SEGMENTS = {
    "Spine": ("spine1", "spine2"), "Chest": ("spine2", "spine3"), "UpperChest": ("spine3", "neck"),
    "Neck": ("neck", "head"), "Head": ("neck", "head"),
}
for s, k in (("Left", "l"), ("Right", "r")):
    SEGMENTS.update({
        s + "Shoulder": (k + "_collar", k + "_shoulder"),
        s + "UpperArm": (k + "_shoulder", k + "_elbow"), s + "LowerArm": (k + "_elbow", k + "_wrist"),
        s + "Hand": (k + "_elbow", k + "_wrist"),
        s + "UpperLeg": (k + "_hip", k + "_knee"), s + "LowerLeg": (k + "_knee", k + "_ankle"),
        s + "Foot": (k + "_ankle", k + "_foot"), s + "Toes": (k + "_ankle", k + "_foot"),
    })


def to_blender(p):
    """HumanML3D (x, y up, z forward) -> Blender (x, -z, y): Z up, the body facing -Y."""
    return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1)


def _basis(lft, up):
    """Rotation whose X axis is `lft` (made perpendicular to `up`) and Z axis `up`."""
    u = up.normalized()
    x = (lft - u * lft.dot(u)).normalized()
    return Matrix((x, u.cross(x), u)).transposed()


def _swing(a, b):
    """Shortest rotation turning direction a into direction b."""
    a, b = a.normalized(), b.normalized()
    return a.rotation_difference(b)


def find_loop(pos, min_len, max_len):
    """A repeating cycle in the steady part of a locomotion clip: frames moving at least 60% of
    the clip's median speed (generated clips start and stop), the period from the left foot's
    height oscillation (autocorrelation), then the start whose pose (relative to the pelvis)
    best matches the pose one period later. Returns (error_m, start, end)."""
    n = len(pos)
    root = pos[:, J["pelvis"], :2]
    v = np.r_[0, np.linalg.norm(np.diff(root, axis=0), axis=1)]
    moving = v >= 0.6 * np.median(v[v > 1e-4]) if np.any(v > 1e-4) else np.ones(n, bool)
    # Longest run of moving frames.
    best_run, run_start = (0, 0, n), None
    for i, m in enumerate(list(moving) + [False]):
        if m and run_start is None:
            run_start = i
        elif not m and run_start is not None:
            if i - run_start > best_run[0]:
                best_run = (i - run_start, run_start, i)
            run_start = None
    lo, hi = best_run[1], best_run[2]
    # Period from the left ankle height (relative to the pelvis).
    h = pos[lo:hi, J["l_ankle"], 2] - pos[lo:hi, J["pelvis"], 2]
    h = h - h.mean()
    period = None
    best_c = -1e9
    for lag in range(min_len, min(max_len, len(h) - 2) + 1):
        c = float(np.dot(h[:-lag], h[lag:]) / max(len(h) - lag, 1))
        if c > best_c:
            best_c, period = c, lag
    period = period or min_len
    rel = pos - pos[:, :1, :]
    best = (1e9, lo, min(lo + period, n - 1))
    for a in range(lo, max(lo + 1, hi - period)):
        for b in range(a + period - 2, a + period + 3):
            if b >= hi or b >= n:
                continue
            d = float(np.mean(np.linalg.norm(rel[a] - rel[b], axis=-1)))
            if d < best[0]:
                best = (d, a, b)
    return best


# Bones whose segment is defined differently in the motion's skeleton than in ours (MoMask's
# head joint sits in front of the neck, its spine joints follow the back's curve, its foot joint
# is the ball of the foot): they get a constant correction from a neutral standing pose.
CALIBRATED = ("Spine", "Chest", "UpperChest", "Neck", "Head", "LeftFoot", "RightFoot", "LeftToes", "RightToes")
_calib = {}


def calibrate(rig, standing):
    """Per-bone rotation taking the motion's segment direction in a neutral standing pose
    (a generated idle, frames averaged) to our bone's rest direction."""
    pos = to_blender(np.asarray(standing, dtype=np.float64)).mean(axis=0)
    hip = pos[J["l_hip"]] - pos[J["r_hip"]]
    turn = math.atan2(hip[1], hip[0])          # face the motion forward (-Y) like our rest
    c, s = math.cos(-turn), math.sin(-turn)
    pos = pos @ np.array([[c, s, 0], [-s, c, 0], [0, 0, 1]])
    _calib.clear()
    for bn in CALIBRATED:
        a, b = SEGMENTS[bn]
        motion_dir = Vector(pos[J[b]] - pos[J[a]])
        rest_dir = rig.data.bones[bn].matrix_local.to_3x3() @ Vector((0, 1, 0))
        # Only the forward/back difference: a standing pose leans its weight to one side,
        # and correcting that sideways would tilt every clip (the "always leaning" look).
        motion_dir.x = 0.0
        rest_dir.x = 0.0
        _calib[bn] = _swing(motion_dir, rest_dir).to_matrix()


STRIDE = {}                    ## per clip family: stride lengthening (see make_action)
# Limb bones and the three joints whose plane holds their hinge (knee, elbow; the foot and
# lower bones share their parent's plane).
HINGES = {}
for _s, _k in (("Left", "l"), ("Right", "r")):
    HINGES.update({
        _s + "UpperLeg": (_k + "_hip", _k + "_knee", _k + "_ankle"),
        _s + "LowerLeg": (_k + "_hip", _k + "_knee", _k + "_ankle"),
        _s + "Foot": (_k + "_hip", _k + "_knee", _k + "_ankle"),
        _s + "UpperArm": (_k + "_shoulder", _k + "_elbow", _k + "_wrist"),
        _s + "LowerArm": (_k + "_shoulder", _k + "_elbow", _k + "_wrist"),
    })
_hinge_prev = {}
STANCE = {"idle": 0.6}         ## per clip family: narrower stance (sideways foot offsets)
FEET = ("l_ankle", "r_ankle", "l_foot", "r_foot")


def airborne_part(pos, clearance=0.06):
    """For jumps: the frames from just before take-off to touch-down (both feet off the ground
    at least `clearance` m above the clip's lowest foot point). The game's physics does the
    leap; the clip only plays in the air."""
    feet = pos[:, [J[f] for f in FEET], 2].min(axis=1)
    air = feet > feet.min() + clearance
    idx = np.flatnonzero(air)
    if len(idx) == 0:
        return pos
    # The longest airborne run.
    runs, start = [], idx[0]
    for a, b in zip(idx, idx[1:]):
        if b != a + 1:
            runs.append((start, a))
            start = b
    runs.append((start, idx[-1]))
    a, b = max(runs, key=lambda r: r[1] - r[0])
    return pos[max(0, a - 3): min(len(pos), b + 2)]


def make_action(rig, name, joints, loop=False, min_cycle=0.5, max_cycle=1.4, height=1.85, stride=None):
    """Creates action `name` on rig from joint positions (frames, 22, 3). Returns info:
    frames, seconds, ground speed (m/s at our body's size) and, for loops, the cycle error."""
    pos = to_blender(np.asarray(joints, dtype=np.float64))
    src_h = float(np.max(pos[0, :, 2]) - np.min(pos[0, :, 2])) or 1.7
    scale = height / (src_h * 1.07)               # the head joint is below the top of the head
    info = {"name": name, "source_frames": len(pos)}
    family = name.split("_")[0].rstrip("abcd")
    if family == "jump":
        pos = airborne_part(pos)
    if loop:
        err, a, b = find_loop(pos, int(min_cycle * FPS_IN), int(max_cycle * FPS_IN))
        pos = pos[a:b + 1]
        info.update({"cycle": [a, b], "cycle_error_m": round(err, 4)})
    # Ground speed (before removing it) and the facing: align the motion to face -Y.
    root = pos[:, J["pelvis"], :]
    travel = root[-1, :2] - root[0, :2]
    secs = (len(pos) - 1) / FPS_IN
    info["speed"] = round(float(np.linalg.norm(travel)) / max(secs, 1e-6) * scale, 3)
    info["seconds"] = round(secs, 3)
    if np.linalg.norm(travel) > 0.25:                         # moving: face the travel direction
        heading = math.atan2(travel[0], -travel[1])           # 0 when moving along -Y
    else:
        hip = pos[0, J["l_hip"]] - pos[0, J["r_hip"]]          # body's left, turned onto +X
        heading = math.atan2(hip[1], hip[0])
    rot = np.array([[math.cos(heading), -math.sin(heading), 0], [math.sin(heading), math.cos(heading), 0], [0, 0, 1]])
    pos = (pos - np.array([root[0, 0], root[0, 1], 0])) @ rot      # rotate by -heading
    # Upright and square: generated people often lean to one side or run with the hips turned a
    # little (it reads as "always tilted"). Remove the clip's average sideways lean of the spine
    # (about the forward axis) and its average hip yaw (about the vertical).
    spine = pos[:, J["spine3"], :] - pos[:, J["pelvis"], :]
    roll = float(np.mean(np.arctan2(spine[:, 0], spine[:, 2])))
    hipv = pos[:, J["l_hip"], :] - pos[:, J["r_hip"], :]
    yaw = float(np.mean(np.arctan2(hipv[:, 1], hipv[:, 0])))
    pivot = pos[:, J["pelvis"], :].mean(axis=0)
    cr, sr = math.cos(roll), math.sin(roll)
    r_roll = np.array([[cr, 0, -sr], [0, 1, 0], [sr, 0, cr]])     # rotate the lean back about Y
    cy, sy = math.cos(yaw), math.sin(yaw)
    r_yaw = np.array([[cy, sy, 0], [-sy, cy, 0], [0, 0, 1]])       # and the hip turn about Z
    pos = (pos - pivot) @ r_roll.T @ r_yaw.T + pivot
    info["leveled_deg"] = [round(math.degrees(roll), 1), round(math.degrees(yaw), 1)]
    # In place (the game moves the body): loops lose their steady travel (keeping bounce and
    # sway, so the cycle closes); one-shots lose the pelvis's horizontal path entirely.
    if loop:
        t = np.linspace(0, 1, len(pos))[:, None]
        drift = (pos[-1, J["pelvis"]] - pos[0, J["pelvis"]]) * t
        drift[:, 2] = 0
        pos = pos - drift[:, None, :]
    else:
        path = pos[:, J["pelvis"], :].copy()
        path[:, 2] = 0
        pos = pos - path[:, None, :]
    pos[:, :, :2] -= pos[0, J["pelvis"], :2]
    pos = pos * scale
    # Stride: the game's run is faster (7 m/s) than generated sprints (~4 m/s). Scaling the
    # forward offsets of the knees and feet from the hips lengthens the stride at the same
    # cadence (a longer, bounding game run); the foot then travels `stride` times as far per
    # step, so the speed without foot sliding grows by the same factor.
    k = stride if stride is not None else STRIDE.get(family, 1.0)
    w = STANCE.get(family, 1.0)
    if w != 1.0:
        for side in ("l", "r"):
            for jn in ("_knee", "_ankle", "_foot"):
                j = J[side + jn]
                pos[:, j, 0] = pos[:, J[side + "_hip"], 0] + (pos[:, j, 0] - pos[:, J[side + "_hip"], 0]) * w
    if family == "jump":
        # The pelvis stays at its average height; the physics lifts the body.
        pos[:, :, 2] += pos[:, J["pelvis"], 2].mean() - pos[:, J["pelvis"], 2][:, None]
    if k != 1.0:
        for side in ("l", "r"):
            hipj = pos[:, J[side + "_hip"], :].copy()
            for jn in ("_knee", "_ankle", "_foot"):
                j = J[side + jn]
                pos[:, j, 1] = hipj[:, 1] + (pos[:, j, 1] - hipj[:, 1]) * k
        info["speed"] = round(info["speed"] * k, 3)
        info["stride"] = k

    _hinge_prev.clear()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    bones = rig.data.bones
    pbs = rig.pose.bones
    for pb in pbs:
        pb.rotation_mode = "QUATERNION"
    rest_world = {b.name: b.matrix_local.to_3x3() for b in bones}
    rest_ground = hip_rest_h_ground(rig)
    ground0 = float(np.min(pos[:, [J["l_foot"], J["r_foot"], J["l_ankle"], J["r_ankle"]], 2]))
    n = len(pos)
    for i in range(n):
        f = 1 + i * FPS_OUT / FPS_IN
        P = {k: Vector(pos[i, j]) for k, j in J.items()}
        world = {}
        # Pelvis: a frame from the hip line (right hip -> left hip = our +X, the body's left)
        # and the spine (up); the rest pelvis is the identity frame, so this is the turn.
        world["Hips"] = _basis(P["l_hip"] - P["r_hip"], P["spine1"] - P["pelvis"]) @ rest_world["Hips"]
        # Every other bone: the parent's world rotation, then a swing so the bone points along
        # its motion segment.
        order = [b.name for b in bones if b.name != "Hips"]
        for bn in order:
            b = bones[bn]
            parent_w = world[b.parent.name] if b.parent and b.parent.name in world else rest_world[b.parent.name] if b.parent else Matrix.Identity(3)
            # The bone's world rotation if it kept its rest pose relative to the parent:
            carried = parent_w @ rest_world[b.parent.name].inverted() @ rest_world[bn] if b.parent else rest_world[bn]
            seg = SEGMENTS.get(bn)
            if seg is None:
                world[bn] = carried
                continue
            cur_dir = carried @ Vector((0, 1, 0))                 # bones point along local +Y
            want = P[seg[1]] - P[seg[0]]
            if bn in _calib:
                # The correction is about the body's own frame: apply it in the pelvis frame.
                pel = world["Hips"] @ rest_world["Hips"].inverted()
                want = pel @ _calib[bn] @ pel.inverted() @ want
            if want.length < 1e-5:
                world[bn] = carried
                continue
            swung = _swing(cur_dir, want).to_matrix() @ carried
            limb = HINGES.get(bn)
            if limb is None:
                world[bn] = swung
                continue
            # Limbs: the hinge (local X) is the normal of the limb's plane, so the joint bends in
            # its own plane (a swing alone lets the thigh twist and the knee bend sideways).
            a, m, c = (P[j] for j in limb)
            hinge = (m - a).cross(c - m)
            prev = _hinge_prev.get(bn)
            ref = prev if prev is not None else swung.col[0]
            y = want.normalized()
            if hinge.length < 0.02 * (m - a).length * (c - m).length:
                hinge = ref.copy()                        # nearly straight: keep the last hinge
            if hinge.dot(ref) < 0:
                hinge = -hinge
            x = (hinge - y * hinge.dot(y)).normalized()
            _hinge_prev[bn] = x.copy()
            world[bn] = Matrix((x, y, x.cross(y))).transposed()
        for bn, w in world.items():
            b = bones[bn]
            if b.parent:
                local = (rest_world[b.parent.name].inverted() @ rest_world[bn]).inverted() @ world[b.parent.name].inverted() @ w
            else:
                local = rest_world[bn].inverted() @ w
            pb = pbs[bn]
            pb.rotation_quaternion = local.to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=f)
        # Root: height above the clip's lowest foot joint against the rest height, and the
        # sideways/forward sway. Hips local axes: X = world X, Y = up, Z = -world Y.
        hips = pbs["Hips"]
        rise = 0.0 if family == "jump" else (P["pelvis"].z - ground0) - rest_ground
        hips.location = (P["pelvis"].x, rise, -P["pelvis"].y)
        hips.keyframe_insert("location", frame=f)
    # Feet on the ground: measured on our own foot bones (the motion's joints are ankle and
    # ball centres, a few cm above the soles, which made the body hover). Walk and idle keep the
    # lowest foot on the ground every frame; the run (flight phases) and the jump are lowered by
    # the clip's minimum.
    import skeleton
    drops = []
    for i in range(n):
        f = 1 + i * FPS_OUT / FPS_IN
        bpy.context.scene.frame_set(int(f), subframe=f - int(f))
        drops.append(skeleton.ground_offset(rig))
    per_frame = family in ("walk", "idle")
    low = min(drops)
    hips = pbs["Hips"]
    for i in range(n):
        f = 1 + i * FPS_OUT / FPS_IN
        bpy.context.scene.frame_set(int(f), subframe=f - int(f))
        loc = hips.location.copy()
        loc.y -= drops[i] if per_frame else low
        hips.location = loc
        hips.keyframe_insert("location", frame=f)
    info["lowered_m"] = round(low, 3)
    info["frames"] = n
    return act, info


def hip_rest_h_ground(rig):
    """Rest height of the Hips joint above the lowest foot point."""
    b = rig.data.bones
    low = min(b[s + "Toes"].tail_local.z for s in ("Left", "Right"))
    return b["Hips"].head_local.z - low
