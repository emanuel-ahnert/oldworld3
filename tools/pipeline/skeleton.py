"""Finds humanoid joints on an A-pose mesh by slicing, and builds the shared skeleton.

Bone names follow Godot's SkeletonProfileHumanoid, so animations can be retargeted between
bodies. The character stands on Z=0 and faces -Y, so its left side is +X.
"""

import math

import bpy
from mathutils import Vector

# Rough human proportions as fractions of the height (used where slicing gives no answer).
P = {
    "ankle": 0.045, "knee": 0.285, "neck": 0.83, "head": 0.87, "chin": 0.875,
    "upper_arm": 0.18, "fore_arm": 0.15, "hand": 0.10,
}


def _clusters(xs, gap):
    xs = sorted(xs)
    out, cur = [], [xs[0]]
    for x in xs[1:]:
        if x - cur[-1] > gap:
            out.append(cur)
            cur = []
        cur.append(x)
    out.append(cur)
    return out


class Slicer:
    """Cuts a mesh with horizontal planes (edge intersections, so long faces still count)."""

    def __init__(self, obj):
        import numpy as np
        me = obj.data
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        m = np.array(obj.matrix_world)
        co = co @ m[:3, :3].T + m[:3, 3]
        ed = np.empty(len(me.edges) * 2, dtype=np.int64)
        me.edges.foreach_get("vertices", ed)
        ed = ed.reshape(-1, 2)
        self.np, self.co, self.a, self.b = np, co, co[ed[:, 0]], co[ed[:, 1]]

    def points(self, z):
        np, a, b = self.np, self.a, self.b
        m = (a[:, 2] - z) * (b[:, 2] - z) < 0
        a, b = a[m], b[m]
        t = ((z - a[:, 2]) / (b[:, 2] - a[:, 2]))[:, None]
        return [Vector(p) for p in (a + (b - a) * t)]

    def parts(self, z, gap):
        return slice_parts(self.points(z), z, None, gap)


def slice_parts(verts, z, dz, gap):
    """Groups points into connected parts in the XY plane (grid cells of size `gap`,
    8-connected); returns [(xmin, xmax, points)] sorted by x. With dz, only points within dz
    of height z are used."""
    band = [v for v in verts if abs(v.z - z) < dz] if dz else list(verts)
    if not band:
        return []
    cells = {}
    for v in band:
        cells.setdefault((math.floor(v.x / gap), math.floor(v.y / gap)), []).append(v)
    seen, parts = set(), []
    for c in cells:
        if c in seen:
            continue
        stack, vs = [c], []
        seen.add(c)
        while stack:
            cx, cy = stack.pop()
            vs += cells[(cx, cy)]
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (cx + dx, cy + dy)
                    if n in cells and n not in seen:
                        seen.add(n)
                        stack.append(n)
        parts.append((min(v.x for v in vs), max(v.x for v in vs), vs))
    return sorted(parts, key=lambda p: p[0])


def centroid(vs):
    return sum(vs, Vector()) / len(vs)


def find_joints(obj):
    """Returns a dict of joint name -> Vector (armature space = world space)."""
    sl = Slicer(obj)
    H = float(sl.co[:, 2].max())
    gap = 0.012 * H
    steps = [i / 200 * H for i in range(1, 200)]
    big = lambda ps, w: [p for p in ps if p[1] - p[0] > w * H]

    # Crotch: lowest height (above the knees) where the legs merge into one central part.
    # Only parts near the middle count, so hands hanging beside the legs are ignored.
    central = lambda z: [p for p in big(sl.parts(z, gap), 0.02) if abs((p[0] + p[1]) / 2) < 0.15 * H]
    crotch = next((z for z in steps if z > 0.3 * H and len(central(z)) == 1), 0.47 * H)

    # Shoulder top: scanning down from the head, the first height where the middle part gets
    # much wider than the neck.
    def width(z):
        ps = sl.parts(z, gap)
        if not ps:
            return 0
        p = min(ps, key=lambda p: abs((p[0] + p[1]) / 2))
        return p[1] - p[0]
    shoulder_top = next((z for z in reversed(steps) if 0.6 * H < z < 0.9 * H and width(z) > 0.2 * H), 0.8 * H)
    armpit = shoulder_top - 0.07 * H

    def torso_at(z):
        ps = sl.parts(z, gap)
        return min(ps, key=lambda p: abs((p[0] + p[1]) / 2))

    waist = torso_at(crotch + 0.08 * H)
    hip_half = (waist[1] - waist[0]) / 2
    # Depth (Y) of the spine: from the two legs just below the crotch, where they are clean
    # cylinders. A waist slice can include belts, flaps or hands and pull the centroid off.
    legs = [p for p in sl.parts(crotch - 0.04 * H, gap) if abs((p[0] + p[1]) / 2) < 0.15 * H]
    legs = sorted(legs, key=lambda p: len(p[2]), reverse=True)[:2]
    torso_cy = (sum(centroid(p[2]).y for p in legs) / len(legs)) if legs else centroid(waist[2]).y
    torso_half = hip_half

    J = {}
    # The pelvis root and the hip joints: the hip joint sits about 5% of the height above the
    # crotch (anatomy; it used to be 2%, which made the legs pivot from mid-thigh and waddle).
    hip_z = crotch + 0.075 * H
    J["Hips"] = Vector((0, torso_cy, hip_z))
    J["Spine"] = Vector((0, torso_cy, hip_z + 0.07 * H))
    J["Chest"] = Vector((0, torso_cy, hip_z + 0.15 * H))
    J["UpperChest"] = Vector((0, torso_cy, armpit - 0.02 * H))
    J["Neck"] = Vector((0, torso_cy, P["neck"] * H))
    J["Head"] = Vector((0, torso_cy, P["head"] * H))
    J["HeadTop"] = Vector((0, torso_cy, H))

    for side, sx in (("Left", 1), ("Right", -1)):
        def leg_at(z):
            ps = [p for p in sl.parts(z, gap) if 0 < sx * (p[0] + p[1]) / 2 < hip_half * 1.3]
            if not ps:
                return Vector((sx * 0.5 * hip_half, torso_cy, z))
            p = max(ps, key=lambda p: len(p[2]))
            c = centroid(p[2])
            return Vector((c.x, c.y, z))

        knee = leg_at(P["knee"] * H)
        ankle = leg_at(P["ankle"] * H + 0.02 * H)
        J[side + "UpperLeg"] = Vector((sx * hip_half * 0.55, torso_cy, crotch + 0.05 * H))
        J[side + "LowerLeg"] = knee
        J[side + "Foot"] = Vector((ankle.x, ankle.y + 0.01 * H, P["ankle"] * H))
        foot = [v for v in (Vector(c) for c in sl.co) if v.z < 0.05 * H and sx * v.x > 0]
        tip = min(foot, key=lambda v: v.y) if foot else ankle + Vector((0, -0.12 * H, 0))
        J[side + "Toes"] = Vector((ankle.x, (tip.y + J[side + "Foot"].y) / 2, 0.015 * H))
        J[side + "ToesTip"] = Vector((ankle.x, tip.y, 0.015 * H))

        # Arms: the outer parts beyond the hips; the hand tip is the lowest point of them.
        arm_pts, line = [], []
        for z in steps:
            if z > shoulder_top:
                break
            if z < 0.3 * H:  # hands never reach below mid-thigh in an A-pose
                continue
            for p in sl.parts(z, gap):
                if sx * (p[0] + p[1]) / 2 > hip_half * 1.15:
                    arm_pts += p[2]
                    line.append(centroid(p[2]))
        sh = Vector((sx * 0.1 * H, torso_cy, shoulder_top - 0.035 * H))
        J[side + "Shoulder"] = Vector((sx * 0.025 * H, torso_cy, shoulder_top - 0.045 * H))
        J[side + "UpperArm"] = sh
        if arm_pts:
            low = min(p.z for p in arm_pts)
            tipp = [p for p in arm_pts if p.z < low + 0.01 * H]
            tip = centroid(tipp)
        else:
            tip = sh + Vector((sx * 0.3, 0, -0.3)) * H
        d = tip - sh
        total = P["upper_arm"] + P["fore_arm"] + P["hand"]
        elbow = sh + d * (P["upper_arm"] / total)
        # Where the arm first separates from the torso is about the elbow (arms close to the
        # body); use it if it is a plausible upper-arm length away from the shoulder.
        if line:
            top = max(line, key=lambda c: c.z)
            if 0.12 * H < (top - sh).length < 0.24 * H:
                elbow = top
        J[side + "LowerArm"] = elbow
        J[side + "Hand"] = tip + (elbow - tip).normalized() * P["hand"] * H * 0.85
        J[side + "HandTip"] = tip
    J["_info"] = {"H": H, "crotch": crotch, "armpit": armpit, "shoulder_top": shoulder_top,
                  "hip_half": hip_half}
    return J


CHAIN = [
    # bone, head joint, tail joint, parent
    ("Hips", "Hips", "Spine", None),
    ("Spine", "Spine", "Chest", "Hips"),
    ("Chest", "Chest", "UpperChest", "Spine"),
    ("UpperChest", "UpperChest", "Neck", "Chest"),
    ("Neck", "Neck", "Head", "UpperChest"),
    ("Head", "Head", "HeadTop", "Neck"),
]
for s in ("Left", "Right"):
    CHAIN += [
        (s + "Shoulder", s + "Shoulder", s + "UpperArm", "UpperChest"),
        (s + "UpperArm", s + "UpperArm", s + "LowerArm", s + "Shoulder"),
        (s + "LowerArm", s + "LowerArm", s + "Hand", s + "UpperArm"),
        (s + "Hand", s + "Hand", s + "HandTip", s + "LowerArm"),
        (s + "UpperLeg", s + "UpperLeg", s + "LowerLeg", "Hips"),
        (s + "LowerLeg", s + "LowerLeg", s + "Foot", s + "UpperLeg"),
        (s + "Foot", s + "Foot", s + "Toes", s + "LowerLeg"),
        (s + "Toes", s + "Toes", s + "ToesTip", s + "Foot"),
    ]


def build_armature(J, name="Skeleton"):
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, h, t, parent in CHAIN:
        eb = arm.edit_bones.new(bone)
        eb.head, eb.tail = J[h], J[t]
        if (eb.tail - eb.head).length < 1e-3:
            eb.tail = eb.head + Vector((0, 0, 0.02))
        # Roll: keep each bone's Z axis pointing forward (-Y) or up, for predictable rotations.
        eb.align_roll(Vector((0, -1, 0)) if abs((eb.tail - eb.head).normalized().y) < 0.7 else Vector((0, 0, 1)))
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def bind(mesh, armature):
    """Parents mesh to armature with automatic (bone heat) weights; returns unweighted vert count."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    unweighted = sum(1 for v in mesh.data.vertices if not any(g.weight > 0.01 for g in v.groups))
    return unweighted


# --- gear slots ------------------------------------------------------------------------------

# Texture slots on the base body (design/asset-pipeline.md, section 3). The dominant bone of a
# vertex decides its slot.
SLOTS = ["head", "chest", "hands", "legs", "feet"]
SLOT_OF_BONE = {"Head": 0, "Neck": 0, "Spine": 1, "Chest": 1, "UpperChest": 1, "Hips": 3}
for _s in ("Left", "Right"):
    SLOT_OF_BONE.update({_s + "Shoulder": 1, _s + "UpperArm": 1, _s + "LowerArm": 2, _s + "Hand": 2,
                         _s + "UpperLeg": 3, _s + "LowerLeg": 3, _s + "Foot": 4, _s + "Toes": 4})


def assign_slots(mesh):
    """Stores each vertex's slot in a color attribute `slot` (R = slot / 8), which the game's
    shader uses to pick the slot's texture. Returns vertex counts per slot."""
    names = {g.index: g.name for g in mesh.vertex_groups}
    attr = mesh.data.color_attributes.new("slot", "FLOAT_COLOR", "POINT")
    counts = [0] * len(SLOTS)
    for v in mesh.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        slot = SLOT_OF_BONE.get(names.get(best.group), 1) if best else 1
        counts[slot] += 1
        attr.data[v.index].color = (slot / 8 + 1 / 16, 0, 0, 1)
    mesh.data.color_attributes.active_color = attr
    return dict(zip(SLOTS, counts))


def fit_onto(rig, target):
    """Poses `rig` so every bone lies on the same-named bone of `target` (stretched to its
    length). A mesh bound to `rig` is then wrapped onto the target body."""
    from mathutils import Matrix
    order = []

    def walk(b):
        order.append(b.name)
        for c in b.children:
            walk(c)
    for b in rig.data.bones:
        if b.parent is None:
            walk(b)
    for name in order:
        pb = rig.pose.bones[name]
        tb = target.data.bones[name]
        stretch = tb.length / max(rig.data.bones[name].length, 1e-6)
        pb.matrix = tb.matrix_local @ Matrix.Diagonal((1, stretch, 1, 1))
        bpy.context.view_layer.update()


# --- animation -------------------------------------------------------------------------------

def _rot(armature, bone, axis_world, deg):
    """Local quaternion rotating `bone` by deg around a world-space axis (rest frame)."""
    b = armature.data.bones[bone]
    a = (b.matrix_local.to_3x3().inverted() @ Vector(axis_world)).normalized()
    from mathutils import Quaternion
    return Quaternion(a, math.radians(deg))


def keyframe_pose(armature, frame, pose):
    """pose: {bone: [(axis_world, deg), ...]}; bones not listed go back to rest."""
    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"
        q = None
        for axis, deg in pose.get(pb.name, []):
            r = _rot(armature, pb.name, axis, deg)
            q = r if q is None else r @ q
        from mathutils import Quaternion
        pb.rotation_quaternion = q or Quaternion()
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if pb.name == "Hips":
            pb.keyframe_insert("location", frame=frame)


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)


def _new_action(armature, name):
    armature.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    armature.animation_data.action = act
    return act


def make_gait(armature, name, frames, leg, knee, arm, elbow, lean=0.0, bob=0.0, arm_down=6, keys=8):
    """A walk or run cycle on the shared skeleton. Forward is -Y; a positive rotation about +X
    swings a leg backward, so forward swing is negative. `leg`, `knee`, `arm`, `elbow` and
    `lean` are degrees, `bob` is the hip's up-down movement in meters (twice per cycle)."""
    act = _new_action(armature, name)
    for i in range(keys + 1):
        ph = i / keys * 2 * math.pi            # 0..2pi over the cycle
        f = 1 + round(i / keys * frames)
        s = math.sin(ph)
        pose = {
            "LeftUpperLeg": [(Y, 4), (X, -leg * s)],
            "RightUpperLeg": [(Y, -4), (X, leg * s)],
            "LeftLowerLeg": [(X, knee * max(0, math.sin(ph + 1.2)) + 4)],
            "RightLowerLeg": [(X, knee * max(0, math.sin(ph + 1.2 + math.pi)) + 4)],
            "LeftFoot": [(X, -0.3 * knee * max(0, math.sin(ph + 0.6)))],
            "RightFoot": [(X, -0.3 * knee * max(0, math.sin(ph + 0.6 + math.pi)))],
            # arms: bring them down from the A-pose (about the forward axis), then swing
            "LeftUpperArm": [(Y, arm_down), (X, arm * s)],
            "RightUpperArm": [(Y, -arm_down), (X, -arm * s)],
            "LeftLowerArm": [(X, -elbow)],
            "RightLowerArm": [(X, -elbow)],
            "Spine": [(Z, 5 * s), (X, lean)],
            "Chest": [(Z, -8 * s)],
        }
        keyframe_pose(armature, f, pose)
        if bob:
            hips = armature.pose.bones["Hips"]
            hips.location = (0, -bob * abs(math.cos(ph)), 0)
            hips.keyframe_insert("location", frame=f)
    return act


def curve(points, p):
    """Periodic smooth curve through [(phase 0..1, value)] (Catmull-Rom), evaluated at p."""
    p %= 1.0
    pts = sorted(points)
    n = len(pts)
    for i in range(n):
        p0, v0 = pts[i]
        p1, v1 = pts[(i + 1) % n]
        span = (p1 - p0) % 1.0 or 1.0
        t = (p - p0) % 1.0
        if t <= span:
            vm = pts[(i - 1) % n][1]
            v2 = pts[(i + 2) % n][1]
            u = t / span
            # Catmull-Rom (uniform), smooth through the keys.
            return 0.5 * ((2 * v0) + (-vm + v1) * u + (2 * vm - 5 * v0 + 4 * v1 - v2) * u * u
                          + (-vm + 3 * v0 - 3 * v1 + v2) * u * u * u)
    return pts[0][1]


# Joint angles over one cycle of one leg (degrees; phase 0 = this foot touches the ground).
# thigh: forward from vertical (world); knee: bend; ankle: toes up (dorsiflexion) positive.
# From human gait data (walking: heel strike, loading, push-off at 62%, swing; running at
# ~7 m/s: short stance, toe-off at 22%, long flight, high heel recovery).
RUN_LEG = {
    "thigh": [(0.0, 28), (0.1, 12), (0.22, -18), (0.32, -20), (0.55, 18), (0.8, 50), (0.93, 38)],
    "knee": [(0.0, 22), (0.08, 38), (0.22, 20), (0.42, 105), (0.55, 110), (0.75, 65), (0.92, 14)],
    "ankle": [(0.0, 4), (0.08, 18), (0.22, -32), (0.38, -18), (0.7, 6), (0.9, 8)],
}
RUN_STANCE = 0.22
WALK_LEG = {
    "thigh": [(0.0, 24), (0.15, 18), (0.5, -13), (0.62, -6), (0.75, 14), (0.88, 27)],
    "knee": [(0.0, 4), (0.15, 17), (0.4, 5), (0.62, 38), (0.72, 58), (0.85, 30), (0.95, 3)],
    "ankle": [(0.0, 0), (0.08, -7), (0.4, 9), (0.55, 4), (0.62, -16), (0.72, -6), (0.85, 1)],
}


def make_cycle(armature, name, frames, keys, leg, stance, arm_swing, arm_center, elbow_base,
               elbow_swing, pelvis_tilt, trunk_lean, pelvis_turn, chest_turn, adduct, shin_in,
               flight=0.0, arm_out=6.0, obliquity=0.0, hand=35.0):
    """A locomotion cycle from per-joint curves (see RUN_LEG / WALK_LEG). Rotation signs on this
    skeleton: about +X a positive angle moves a leg, foot tip or hand backward/downward and tips
    the spine forward. The pelvis tips forward with the trunk (no bending at the waist only, which
    pushed the backside out), the legs compensate so the thigh angles stay world angles. The
    body is lowered each key so the standing foot touches the ground; in the flight phase
    (no foot in stance) it follows an arc `flight` m high between push-off and landing."""
    act = _new_action(armature, name)
    hips = armature.pose.bones["Hips"]
    drops = []
    # Knee hinge: the shin rotates in the thigh's frame, which is turned inward by `adduct`, so a
    # plain X axis would tilt the bending plane and swing the heel out to the side. This axis is
    # X turned back by the adduction, so the knee bends in a vertical plane (heel straight up).
    ad = math.radians(adduct)
    knee_l = (math.cos(ad), 0, math.sin(ad))
    knee_r = (math.cos(ad), 0, -math.sin(ad))
    for i in range(keys + 1):
        p = i / keys
        f = 1 + round(p * frames)
        w = 2 * math.pi * p
        lp, rp = p, (p + 0.5) % 1.0
        lt, lk, la = (curve(leg[k], lp) for k in ("thigh", "knee", "ankle"))
        rt, rk, ra = (curve(leg[k], rp) for k in ("thigh", "knee", "ankle"))
        # Arms swing opposite to the legs: the left arm is forward when the right thigh is.
        al = arm_center + arm_swing * math.cos(2 * math.pi * (p - 0.35))
        ar = arm_center + arm_swing * math.cos(2 * math.pi * (p + 0.5 - 0.35))
        el = elbow_base + elbow_swing * math.cos(2 * math.pi * (p - 0.35))
        er = elbow_base + elbow_swing * math.cos(2 * math.pi * (p + 0.5 - 0.35))
        turn = math.sin(w + 0.3)                 # pelvis turns with the forward-swinging leg
        pose = {
            "Hips": [(X, pelvis_tilt), (Z, -pelvis_turn * turn), (Y, obliquity * math.sin(2 * w))],
            # Thighs relative to the tipped pelvis: world angle + tilt. Adduction brings the feet
            # under the body (the A-pose stands wide).
            "LeftUpperLeg": [(Y, adduct), (X, -(lt + pelvis_tilt))],
            "RightUpperLeg": [(Y, -adduct), (X, -(rt + pelvis_tilt))],
            "LeftLowerLeg": [(Y, shin_in), (knee_l, lk)], "RightLowerLeg": [(Y, -shin_in), (knee_r, rk)],
            "LeftFoot": [(Y, -adduct - shin_in), (X, -la)], "RightFoot": [(Y, adduct + shin_in), (X, -ra)],
            "Spine": [(X, trunk_lean * 0.5), (Z, pelvis_turn * 0.4 * turn)],
            "Chest": [(X, trunk_lean * 0.5), (Z, chest_turn * turn)],
            "Neck": [(Z, -chest_turn * 0.5 * turn)],
            "Head": [(X, -(pelvis_tilt + trunk_lean) * 0.85), (Z, -chest_turn * 0.4 * turn)],
            "LeftUpperArm": [(Y, arm_out), (X, -al)], "RightUpperArm": [(Y, -arm_out), (X, -ar)],
            "LeftLowerArm": [(X, -el)], "RightLowerArm": [(X, -er)],
            # The sword hand: blade down-forward, held steady (the wrist takes back most of the
            # forearm's swing, or the blade waves around and cuts through the leg).
            "LeftHand": [(X, -8)], "RightHand": [(X, hand + 0.8 * ((ar + er) - (arm_center + elbow_base)))],
        }
        keyframe_pose(armature, f, pose)
        hips.location = (0, 0, 0)
        hips.keyframe_insert("location", frame=f)
        bpy.context.scene.frame_set(f)
        drops.append((f, p, ground_offset(armature)))
    # Body height: the standing foot on the ground; in flight an arc between push-off and landing.
    in_stance = [(p % 1.0) < stance or ((p + 0.5) % 1.0) < stance for _, p, _ in drops]
    n = len(drops)
    for i, (f, p, d) in enumerate(drops):
        h = -d
        if not in_stance[i] and flight > 0.0:
            a = i
            while not in_stance[a % n]:
                a -= 1
            b = i
            while not in_stance[b % (n - 1)]:
                b += 1
            s_ = (i - a) / max(b - a, 1)
            ha, hb = -drops[a % n][2], -drops[b % (n - 1)][2]
            h = ha + (hb - ha) * s_ + 4 * flight * s_ * (1 - s_)
        hips.location = (0, h, 0)
        hips.keyframe_insert("location", frame=f)
    return act


def _leg_pose(side, thigh, knee, ankle, adduct=9.0, shin_out=-8.0):
    """One leg: thigh forward (deg), knee bend, ankle up; aligned under the hip like the cycles
    (thigh in, shin back out, knee hinge kept horizontal)."""
    sx = 1 if side == "Left" else -1
    ad = math.radians(adduct)
    axis = (math.cos(ad), 0, sx * math.sin(ad))
    return {
        side + "UpperLeg": [(Y, sx * adduct), (X, -thigh)],
        side + "LowerLeg": [(Y, sx * shin_out), (axis, knee)],
        side + "Foot": [(Y, sx * (-adduct - shin_out)), (X, -ankle)],
    }


def make_jump(armature):
    """(arm_out: negative raises the arms to the sides on this skeleton.) Jump: push-off with straight legs and arms swinging up, tuck at the top (leading leg
    high, trailing leg folded), opening up for the landing; the last pose holds while falling."""
    def pose(lt, lk, la, rt, rk, ra, arm_f, arm_out, elbow, lean):
        p = {"Spine": [(X, lean * 0.5)], "Chest": [(X, lean * 0.5)], "Head": [(X, -lean * 0.8)],
             "LeftUpperArm": [(Y, arm_out), (X, -arm_f)], "RightUpperArm": [(Y, -arm_out), (X, -arm_f)],
             "LeftLowerArm": [(X, -elbow)], "RightLowerArm": [(X, -elbow)]}
        p.update(_leg_pose("Left", lt, lk, la))
        p.update(_leg_pose("Right", rt, rk, ra))
        return p
    return [make_clip(armature, "jump", [
        # The push-off is short: the game starts the clip the moment the hero leaves the
        # ground, so the legs have to tuck right away or the jump looks late.
        (1, pose(-5, 8, -28, -8, 12, -30, 30, -6, 45, 4), 0.0),
        (4, pose(58, 85, -10, 22, 100, -20, 14, -18, 45, 8), -0.12),
        (11, pose(42, 48, 0, 8, 62, -8, 6, -24, 35, 4), -0.08),
        (16, pose(32, 30, 5, 12, 38, 0, 2, -20, 25, 2), -0.04),
    ])]


def make_sit(armature):
    """Camp: sitting down on the ground by the fire (0.5 s, the last pose holds): the seat on
    the ground, legs out in front with the knees a little up and apart, the upper body leaning
    back slightly, hands resting on the knees, the sword hand with the blade down."""
    def pose(t, lean):
        p = {"Spine": [(X, lean)], "Chest": [(X, 4 * t)], "Head": [(X, -8 * t)],
             "LeftUpperArm": [(Y, 6), (X, -26 * t)], "RightUpperArm": [(Y, -6), (X, -26 * t)],
             "LeftLowerArm": [(X, -12 - 30 * t)], "RightLowerArm": [(X, -12 - 30 * t)],
             "RightHand": [(X, 35 + 45 * t)]}
        p.update(_leg_pose("Left", 120 * t, 3 + 40 * t, -15 * t, adduct=9 - 16 * t, shin_out=-1))
        p.update(_leg_pose("Right", 116 * t, 3 + 34 * t, -15 * t, adduct=9 - 14 * t, shin_out=-1))
        return p
    # Halfway the knees bend more (lowering the body), then the legs slide out in front.
    mid = pose(0.55, 20)
    mid.update(_leg_pose("Left", 85, 95, 10, adduct=0, shin_out=-1))
    mid.update(_leg_pose("Right", 85, 95, 10, adduct=0, shin_out=-1))
    return [make_clip(armature, "sit", [(1, pose(0.0, 0), 0.0), (7, mid, SIT_DROP * 0.6),
                                        (13, pose(1.0, -6), SIT_DROP)])]


SIT_DROP = 0.8


def make_run(armature, name="run", frames=17, keys=34):
    """Run at ~7 m/s (the hero's speed): short stance, flight, forward lean from the ankles."""
    return make_cycle(armature, name, frames, keys, RUN_LEG, RUN_STANCE, arm_swing=34, arm_center=-6,
                      elbow_base=88, elbow_swing=14, pelvis_tilt=7, trunk_lean=6, pelvis_turn=7,
                      chest_turn=10, adduct=9, shin_in=-1, flight=0.05, arm_out=7, hand=95)


def make_walk(armature, name="walk", frames=22, keys=32):
    """Walk at ~1.6 m/s: heel strike, roll-over, push-off; arms swing loosely."""
    return make_cycle(armature, name, frames, keys, WALK_LEG, 0.62, arm_swing=17, arm_center=-2,
                      elbow_base=18, elbow_swing=8, pelvis_tilt=2, trunk_lean=1, pelvis_turn=5,
                      chest_turn=6, adduct=8, shin_in=-2, flight=0.0, arm_out=8, obliquity=2.5)


def ground_offset(armature):
    """How far (m) the lowest foot point is above its rest height in the current pose."""
    best = None
    for side in ("Left", "Right"):
        for bone, end in ((side + "Foot", "head"), (side + "Toes", "tail")):
            pb = armature.pose.bones[bone]
            rest = getattr(armature.data.bones[bone], end + "_local").z
            d = getattr(pb, end).z - rest
            best = d if best is None else min(best, d)
    return best


# How far each bone's surface reaches beyond its line (m), for grounding lying poses.
_BODY_MARGIN = {"Hips": 0.11, "Spine": 0.12, "Chest": 0.12, "UpperChest": 0.12, "Neck": 0.06,
                "Head": 0.10, "LeftUpperLeg": 0.08, "RightUpperLeg": 0.08,
                "LeftLowerLeg": 0.06, "RightLowerLeg": 0.06, "LeftUpperArm": 0.05,
                "RightUpperArm": 0.05, "LeftLowerArm": 0.04, "RightLowerArm": 0.04}


def body_ground_offset(armature):
    """Like ground_offset, for the whole body (falling, lying): how far the lowest surface
    point (bone lines widened by _BODY_MARGIN, the feet as in ground_offset) is above the floor."""
    floor = min(armature.data.bones[s + "Toes"].tail_local.z for s in ("Left", "Right"))
    low = ground_offset(armature)
    for pb in armature.pose.bones:
        m = _BODY_MARGIN.get(pb.name)
        if m is not None:
            low = min(low, min(pb.head.z, pb.tail.z) - m - floor)
    return low


def make_idle(armature, frames=96, arm_down=8):
    """Standing (loop, 4 s): arms lowered, the sword hand with the blade down-forward, slow
    breathing in the chest, and the weight drifting from one leg to the other (the loaded leg
    straight, the other knee easing), the head following a little."""
    keys = []
    for i in range(9):
        ph = i / 8 * 2 * math.pi
        b = math.sin(2 * ph)             # two breaths per weight cycle
        w = math.sin(ph)                 # weight: +1 on the left leg, -1 on the right
        upper = {
            "LeftUpperArm": [(Y, arm_down + 1.5 * b), (X, -3)],
            "RightUpperArm": [(Y, -arm_down - 1.5 * b), (X, -3)],
            "LeftLowerArm": [(X, -12)],
            "RightLowerArm": [(X, -12)],
            "Spine": [(Y, -1.2 * w)],
            "Chest": [(X, -1.5 * b), (Y, -0.8 * w)],
            "Head": [(X, 1.0 * b), (Y, 1.5 * w), (Z, 3 * math.sin(ph + 1.0))],
            "RightHand": [(X, 35)],
        }
        p = _full(upper, twist=1.5 * w, pitch=0, left=(0, 3 + 3 * max(0, -w), 0, 5),
                  right=(0, 3 + 3 * max(0, w), 0, 5), shift=(0.018 * w, 0.0))
        p["Hips"] = p["Hips"] + [(Y, 1.5 * w)]
        keys.append((1 + round(i / 8 * frames), p, None))
    return make_clip(armature, "idle", keys)


def make_clip(armature, name, keys):
    """A one-shot clip from (frame, pose, hips_drop_m) keys; hips_drop lowers the whole body.
    hips_drop "body": the same for the whole body (falling, lying). hips_drop None: grounded, the body is lowered (or raised) until the lowest foot point is
    back on the ground (bent knees, lunges); a pose may also carry "_shift": (x, y) meters to
    move the hips sideways (+x left) and forward (-y) in world space."""
    act = _new_action(armature, name)
    hips = armature.pose.bones["Hips"]
    to_local = armature.data.bones["Hips"].matrix_local.to_3x3().inverted()
    for f, pose, drop in keys:
        shift = pose.get("_shift", (0.0, 0.0))
        keyframe_pose(armature, f, {k: v for k, v in pose.items() if k != "_shift"})
        if drop is None or drop == "body":
            hips.location = (0, 0, 0)
            bpy.context.view_layer.update()
            drop = ground_offset(armature) if drop is None else body_ground_offset(armature)
        hips.location = to_local @ Vector((shift[0], shift[1], -drop))
        hips.keyframe_insert("location", frame=f)
    return act


# Combat stance: feet apart front/back, knees bent, left arm forward for balance.
def _stance(extra=None):
    pose = {
        "LeftUpperLeg": [(Y, 3), (X, -18)], "RightUpperLeg": [(Y, -3), (X, 12)],
        "LeftLowerLeg": [(X, 18)], "RightLowerLeg": [(X, 14)],
        "LeftUpperArm": [(Y, 12), (X, -25)], "LeftLowerArm": [(X, -40)],
    }
    for k, v in (extra or {}).items():
        pose[k] = pose.get(k, []) + v if k in ("LeftUpperLeg", "RightUpperLeg") else v
    return pose


IDLE_ARMS = {"LeftUpperArm": [(Y, 8), (X, -3)], "RightUpperArm": [(Y, -8), (X, -3)],
             "LeftLowerArm": [(X, -12)], "RightLowerArm": [(X, -12)],
             "LeftLowerLeg": [(X, 3)], "RightLowerLeg": [(X, 3)]}


IDLE_LEGS = {**_leg_pose("Left", 0, 3, 0, adduct=5, shin_out=-4),
             **_leg_pose("Right", 0, 3, 0, adduct=5, shin_out=-4)}


def _full(upper, twist=0.0, pitch=0.0, left=(0, 3, 0), right=(0, 3, 0), shift=(0.0, 0.0)):
    """A whole-body pose: `upper` (arms, spine, chest, head) on a pelvis turned by `twist`
    (degrees, + to the left) and tipped forward by `pitch`, with the legs given as
    (thigh forward, knee bend, ankle up[, adduct]) per side. The legs keep their own direction in the world
    (the pelvis turns over planted feet), so the hips can drive the blow. Ground it with
    make_clip's hips_drop None."""
    p = dict(upper)
    p["Hips"] = [(X, pitch), (Z, twist)]
    # A fighting stance is wider than standing: the thighs open (adduct 5 -> 0) and the shins
    # stay under the knees, so the bent knees don't knock together.
    p.update(_leg_pose("Left", *left[:3], adduct=left[3] if len(left) > 3 else 0.0, shin_out=-1))
    p.update(_leg_pose("Right", *right[:3], adduct=right[3] if len(right) > 3 else 0.0, shin_out=-1))
    for side in ("Left", "Right"):
        p[side + "UpperLeg"] = p[side + "UpperLeg"] + [(Z, -twist), (X, -pitch)]
    p["_shift"] = shift
    return p


def _guard(breath=0.0):
    """The combat stance (sword arm): feet apart, the left foot forward, knees soft, the sword
    held in front at waist height pointing at the enemy, the left hand up for balance.
    breath: -1..1 for the ready loop."""
    b = breath
    return _full({"RightUpperArm": [(Y, -14), (X, -28 - 2 * b)], "RightLowerArm": [(X, -58)],
                  "RightHand": [(X, 52)],
                  "LeftUpperArm": [(Y, 16), (X, -22 - 2 * b)], "LeftLowerArm": [(X, -55)],
                  "Spine": [(X, 1), (Z, -4)], "Chest": [(X, -1.5 * b), (Z, -6)],
                  "Head": [(X, 1.0 * b - 3), (Z, 14)]},
                 twist=-12, pitch=0, left=(14, 22, 6, -3), right=(-8, 20, 8, -3))


def make_ready(armature, frames=60):
    """Combat idle (loop): the guard stance with slow breathing; the knees give a little."""
    return make_clip(armature, "ready", [(1, _guard(0.0), None), (1 + frames // 4, _guard(1.0), None),
                                         (1 + frames // 2, _guard(0.0), None), (1 + 3 * frames // 4, _guard(-1.0), None),
                                         (1 + frames, _guard(0.0), None)])


def make_attacks(armature):
    """Sword attacks with the right hand (Oldworld3 warrior): two auto-attack swings, the heavy
    strike, a hit reaction and death. Right arm: (Y, +) raises it to the side, (X, -) swings it
    forward; chest (Z, -) turns the right shoulder back.

    The attacks use the whole body: the weight goes back onto the right leg in the wind-up, the
    pelvis turns away and then drives the blow, the left foot steps or plants forward and the
    knees bend into it. The game plays them on the whole body while standing and on the upper
    body only while moving (CharAnimator)."""
    acts = []
    # Attacks start and end in the guard (the "ready" loop the game shows in combat).
    ready = _guard()
    # attack1: diagonal slash, wind-up above the right shoulder, down across the body to the
    # left hip, follow-through, recovery (0.9 s).
    acts.append(make_clip(armature, "attack1", [
        (1, ready, None),
        (7, _full({"RightUpperArm": [(Y, 60), (X, -70)], "RightLowerArm": [(X, -110)], "RightHand": [(X, -45)],
                   "Chest": [(Z, -22)], "Spine": [(Z, -8), (X, -4)], "Head": [(Z, 38)],
                   "LeftUpperArm": [(Y, 25), (X, -35)], "LeftLowerArm": [(X, -60)]},
                  twist=-18, pitch=-2, left=(14, 18, 2), right=(4, 18, 6), shift=(-0.020, 0.015)), None),
        (10, _full({"RightUpperArm": [(Y, 35), (X, -95)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 30)],
                    "Chest": [(Z, 0), (X, 6)], "Spine": [(Z, 0), (X, 4)], "Head": [(Z, 5)],
                    "LeftUpperArm": [(Y, 20), (X, -20)], "LeftLowerArm": [(X, -50)]},
                   twist=4, pitch=6, left=(26, 30, 4, -3), right=(-12, 16, 12), shift=(0.010, -0.020)), None),
        (12, _full({"RightUpperArm": [(Y, -5), (X, -60), (Z, 25)], "RightLowerArm": [(X, -15)], "RightHand": [(X, 60)],
                    "Chest": [(Z, 20), (X, 8)], "Spine": [(Z, 8), (X, 6)], "Head": [(Z, -34)],
                    "LeftUpperArm": [(Y, 15), (X, 15)], "LeftLowerArm": [(X, -30)]},
                   twist=16, pitch=10, left=(30, 36, 6, -4), right=(-16, 20, 16), shift=(0.020, -0.030)), None),
        (16, _full({"RightUpperArm": [(Y, -15), (X, -35), (Z, 40)], "RightLowerArm": [(X, -30)], "RightHand": [(X, 75)],
                    "Chest": [(Z, 24), (X, 6)], "Spine": [(Z, 8), (X, 6)], "Head": [(Z, -38)],
                    "LeftUpperArm": [(Y, 15), (X, 20)], "LeftLowerArm": [(X, -25)]},
                   twist=18, pitch=9, left=(28, 34, 6, -4), right=(-14, 18, 14), shift=(0.020, -0.030)), None),
        (23, ready, None),
    ]))
    # attack2: horizontal slash from right to left at chest height (0.9 s): a big turn of the
    # hips from right to left with the weight shifting from the right to the left leg.
    acts.append(make_clip(armature, "attack2", [
        (1, ready, None),
        (7, _full({"RightUpperArm": [(Y, 80), (Z, -30)], "RightLowerArm": [(X, -45)], "RightHand": [(X, -10)],
                   "Chest": [(Z, -24)], "Spine": [(Z, -8)], "Head": [(Z, 44)],
                   "LeftUpperArm": [(Y, 20), (X, -45)], "LeftLowerArm": [(X, -60)]},
                  twist=-22, pitch=0, left=(8, 16, 2), right=(2, 22, 8), shift=(-0.030, 0.010)), None),
        (10, _full({"RightUpperArm": [(Y, 80), (Z, 40)], "RightLowerArm": [(X, -15)], "RightHand": [(X, 5)],
                    "Chest": [(Z, 0)], "Spine": [(Z, 0), (X, 4)], "Head": [(Z, 5)],
                    "LeftUpperArm": [(Y, 15), (X, -25)], "LeftLowerArm": [(X, -50)]},
                   twist=2, pitch=4, left=(16, 24, 4), right=(-8, 18, 10), shift=(0.000, -0.010)), None),
        (12, _full({"RightUpperArm": [(Y, 75), (Z, 95)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 10)],
                    "Chest": [(Z, 20)], "Spine": [(Z, 8), (X, 4)], "Head": [(Z, -40)],
                    "LeftUpperArm": [(Y, 15), (X, 15)], "LeftLowerArm": [(X, -30)]},
                   twist=24, pitch=6, left=(18, 28, 4), right=(-12, 22, 18), shift=(0.030, -0.015)), None),
        (16, _full({"RightUpperArm": [(Y, 60), (Z, 115)], "RightLowerArm": [(X, -40)], "RightHand": [(X, 20)],
                    "Chest": [(Z, 24)], "Spine": [(Z, 10), (X, 4)], "Head": [(Z, -48)],
                    "LeftUpperArm": [(Y, 15), (X, 20)], "LeftLowerArm": [(X, -25)]},
                   twist=28, pitch=6, left=(18, 28, 4), right=(-12, 22, 18), shift=(0.030, -0.015)), None),
        (23, ready, None),
    ]))
    # attack3: a thrust (0.8 s): the sword drawn back to the hip with the weight on the back
    # leg, then driven straight forward at chest height with a step into a lunge.
    acts.append(make_clip(armature, "attack3", [
        (1, ready, None),
        (6, _full({"RightUpperArm": [(Y, -20), (X, 25)], "RightLowerArm": [(X, -95)], "RightHand": [(X, 70)],
                   "LeftUpperArm": [(Y, 18), (X, -40)], "LeftLowerArm": [(X, -60)],
                   "Spine": [(X, 0), (Z, -10)], "Chest": [(Z, -18)], "Head": [(Z, 30)]},
                  twist=-22, pitch=0, left=(16, 22, 4, -3), right=(-2, 26, 10, -3), shift=(-0.02, 0.03)), None),
        (9, _full({"RightUpperArm": [(Y, -6), (X, -80)], "RightLowerArm": [(X, -8)], "RightHand": [(X, 40), (Z, 45), (Y, 60)],
                   "LeftUpperArm": [(Y, 22), (X, 10)], "LeftLowerArm": [(X, -30)],
                   "Spine": [(X, 8), (Z, 0)], "Chest": [(X, 4), (Z, 4)], "Head": [(X, -8), (Z, 4)]},
                  twist=6, pitch=10, left=(36, 44, 8, -4), right=(-22, 18, 16, -3), shift=(0.0, -0.08)), None),
        (12, _full({"RightUpperArm": [(Y, -6), (X, -78)], "RightLowerArm": [(X, -10)], "RightHand": [(X, 40), (Z, 45), (Y, 60)],
                    "LeftUpperArm": [(Y, 22), (X, 12)], "LeftLowerArm": [(X, -30)],
                    "Spine": [(X, 8), (Z, 0)], "Chest": [(X, 4), (Z, 4)], "Head": [(X, -8), (Z, 4)]},
                   twist=6, pitch=10, left=(36, 46, 8, -4), right=(-22, 20, 16, -3), shift=(0.0, -0.08)), None),
        (20, ready, None),
    ]))
    # strike: the heavy blow (1.1 s): rising onto the back leg with the sword high behind the
    # head and the left knee lifting, then a step forward into a deep lunge as the sword chops
    # down with the whole body falling into it.
    acts.append(make_clip(armature, "strike", [
        (1, ready, None),
        (9, _full({"RightUpperArm": [(Y, 30), (X, -170)], "RightLowerArm": [(X, -90)], "RightHand": [(X, -30)],
                   "Spine": [(X, -8), (Z, -4)], "Chest": [(X, -6), (Z, -10)], "Head": [(X, 14), (Z, 14)],
                   "LeftUpperArm": [(Y, 30), (X, -70)], "LeftLowerArm": [(X, -40)]},
                  twist=-12, pitch=-6, left=(38, 55, 10), right=(-4, 6, 4), shift=(-0.015, 0.025)), None),
        (12, _full({"RightUpperArm": [(Y, 15), (X, -110)], "RightLowerArm": [(X, -10)], "RightHand": [(X, 15)],
                    "Spine": [(X, 6)], "Chest": [(X, 6), (Z, 4)], "Head": [(X, -2)],
                    "LeftUpperArm": [(Y, 20), (X, -30)], "LeftLowerArm": [(X, -40)]},
                   twist=2, pitch=8, left=(36, 40, 4), right=(-20, 14, 14), shift=(0.000, -0.050)), None),
        (14, _full({"RightUpperArm": [(Y, 10), (X, -55)], "RightLowerArm": [(X, -10)], "RightHand": [(X, 50)],
                    "Spine": [(X, 8)], "Chest": [(X, 6), (Z, 8)], "Head": [(X, -18)],
                    "LeftUpperArm": [(Y, 20), (X, 15)], "LeftLowerArm": [(X, -30)]},
                   twist=8, pitch=16, left=(42, 62, 20, -4), right=(-24, 30, 24), shift=(0.010, -0.070)), None),
        (19, _full({"RightUpperArm": [(Y, 10), (X, -45)], "RightLowerArm": [(X, -15)], "RightHand": [(X, 55)],
                    "Spine": [(X, 6)], "Chest": [(X, 6), (Z, 8)], "Head": [(X, -16)],
                    "LeftUpperArm": [(Y, 20), (X, 15)], "LeftLowerArm": [(X, -30)]},
                   twist=8, pitch=14, left=(40, 58, 18, -4), right=(-22, 28, 22), shift=(0.010, -0.065)), None),
        (27, ready, None),
    ]))
    # cast: both hands forward, the staff hand a bit raised, the feet set apart (held while
    # casting, 0.5 s).
    cast_up = dict(IDLE_ARMS)
    cast_up.update({"RightUpperArm": [(Y, 10), (X, -70)], "RightLowerArm": [(X, -30)],
                    "LeftUpperArm": [(Y, -5), (X, -60)], "LeftLowerArm": [(X, -25)],
                    "Spine": [(X, 2)], "Chest": [(Z, 6)]})
    idle_full = dict(IDLE_ARMS)
    idle_full.update(IDLE_LEGS)
    cast = _full(cast_up, twist=-6, pitch=2, left=(12, 14, 2), right=(-6, 12, 6), shift=(0.000, 0.005))
    acts.append(make_clip(armature, "cast", [(1, idle_full, 0.0), (5, cast, None), (12, cast, None)]))

    # cast_loop: channelling a spell (looped for the whole cast time, 1 s): the staff raised
    # high in the right hand, the left hand forward at chest height, palm out, circling as it
    # gathers the spell; the body leans back a little and breathes, the head looks along the hand.
    def channel(k):
        c, sn = math.cos(2 * math.pi * k), math.sin(2 * math.pi * k)
        up = dict(IDLE_ARMS)
        up.update({"RightUpperArm": [(Y, 16 + 3 * sn), (X, -118 - 6 * c)], "RightLowerArm": [(X, -38 + 4 * sn)],
                   "RightHand": [(X, 10)],
                   "LeftUpperArm": [(Y, -2 + 8 * c), (X, -52 - 8 * sn)], "LeftLowerArm": [(X, -24 - 6 * c)],
                   "LeftHand": [(X, -25), (Z, 8 * sn)],
                   "Spine": [(X, -4)], "Chest": [(X, -4 - 1.5 * sn), (Z, 9 + 3 * c)], "Head": [(X, -7), (Z, -6)]})
        return _full(up, twist=-8, pitch=-3, left=(14, 16, 3), right=(-8, 14, 7), shift=(0.000, 0.010))
    acts.append(make_clip(armature, "cast_loop", [(1 + 6 * i, channel(i / 4), None) for i in range(5)]))
    # release: the spell is thrown: a step into a lunge, the left hand and the staff thrust at
    # the target, a short hold, then back to rest (0.6 s).
    rel = _full(dict(IDLE_ARMS, **{
        "RightUpperArm": [(Y, 10), (X, -108)], "RightLowerArm": [(X, -6)], "RightHand": [(X, 30)],
        "LeftUpperArm": [(Y, -8), (X, -112)], "LeftLowerArm": [(X, -4)], "LeftHand": [(X, -45)],
        "Spine": [(X, 8)], "Chest": [(X, 6), (Z, -4)], "Head": [(X, -6), (Z, 4)]}),
        twist=6, pitch=8, left=(28, 32, 5, -3), right=(-14, 16, 14), shift=(0.000, -0.045))
    acts.append(make_clip(armature, "release", [(1, channel(0), None), (4, rel, None), (8, rel, None),
                                                (15, idle_full, 0.0)]))
    # hit: a flinch from a blow to the chest: the body jerks back, the right foot catches the
    # weight a step back, the knees give a little.
    acts.append(make_clip(armature, "hit", [
        (1, idle_full, 0.0),
        (4, _full(dict(IDLE_ARMS, Spine=[(X, -10)], Chest=[(X, -8), (Z, 6)], Head=[(X, -14)],
                       LeftUpperArm=[(Y, 22), (X, -12)], RightUpperArm=[(Y, -24), (X, -10)]),
                  twist=6, pitch=-6, left=(8, 14, 2), right=(-12, 16, 4), shift=(0.000, 0.035)), None),
        (7, _full(dict(IDLE_ARMS, Spine=[(X, -3)], Chest=[(X, -2)], Head=[(X, -4)]),
                  twist=3, pitch=-1, left=(6, 12, 2), right=(-8, 14, 6), shift=(0.000, 0.020)), None),
        (13, idle_full, 0.0),
    ]))
    # death (1.2 s, the last pose holds): the blow throws the head and chest back, the knees
    # buckle and the body drops onto its seat, then rolls back flat with the arms flung out,
    # the head turned aside and the sword flat on the ground beside the hand.
    acts.append(make_clip(armature, "death", [
        (1, idle_full, 0.0),
        (5, _full({"Spine": [(X, -10)], "Chest": [(X, -8), (Z, 6)], "Head": [(X, -18)],
                   "LeftUpperArm": [(Y, 28), (X, -18)], "RightUpperArm": [(Y, -30), (X, -12)],
                   "LeftLowerArm": [(X, -30)], "RightLowerArm": [(X, -25)], "RightHand": [(X, 20)]},
                  twist=-6, pitch=-6, left=(4, 14, 4), right=(-6, 18, 6)), None),
        (11, _full({"Spine": [(X, 14)], "Chest": [(X, 8)], "Head": [(X, 20), (Z, -10)],
                    "LeftUpperArm": [(Y, 16), (X, -8)], "RightUpperArm": [(Y, -18), (X, -6)],
                    "LeftLowerArm": [(X, -20)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 30)]},
                   twist=-12, pitch=4, left=(48, 92, 40), right=(40, 100, 50)), None),
        (17, _full({"Spine": [(X, 10)], "Chest": [(X, 4)], "Head": [(X, 12), (Z, -10)],
                    "LeftUpperArm": [(Y, 30), (X, -15)], "RightUpperArm": [(Y, -34), (X, -10)],
                    "LeftLowerArm": [(X, -25)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 10)]},
                   twist=-14, pitch=-40, left=(80, 95, 20), right=(70, 85, 15)), "body"),
        (23, {"Hips": [(X, -84), (Z, -12)], "Spine": [(X, -4)], "Chest": [(X, -4)], "Head": [(X, -6), (Z, 30)],
              "LeftUpperArm": [(Y, 62), (X, 8)], "RightUpperArm": [(Y, -58), (X, 10)],
              "LeftLowerArm": [(X, -25)], "RightLowerArm": [(X, -20)], "RightHand": [(Z, -60), (Y, -45)],
              **_leg_pose("Left", 26, 42, -20, adduct=-6, shin_out=-1),
              **_leg_pose("Right", 8, 12, -25, adduct=-8, shin_out=-1)}, "body"),
        (30, {"Hips": [(X, -88), (Z, -12)], "Spine": [(X, -2)], "Chest": [(X, -2)], "Head": [(X, -4), (Z, 34)],
              "LeftUpperArm": [(Y, 66), (X, 20)], "RightUpperArm": [(Y, -62), (X, 20)],
              "LeftLowerArm": [(X, -12)], "RightLowerArm": [(X, -10)], "RightHand": [(Z, -90), (Y, -65)],
              **_leg_pose("Left", 18, 30, -25, adduct=-6, shin_out=-1),
              **_leg_pose("Right", 4, 8, -28, adduct=-8, shin_out=-1)}, "body"),
    ]))
    # death2 (1.3 s, the last pose holds): the blow spins the body to the right, the knees hit
    # the ground, the body sways and falls forward onto the face, arms out.
    acts.append(make_clip(armature, "death2", [
        (1, idle_full, 0.0),
        (5, _full({"Spine": [(X, 6), (Z, -14)], "Chest": [(X, 4), (Z, -12)], "Head": [(X, -10), (Z, 18)],
                   "LeftUpperArm": [(Y, 34), (X, -30)], "RightUpperArm": [(Y, -26), (X, 8)],
                   "LeftLowerArm": [(X, -50)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 20)]},
                  twist=-22, pitch=4, left=(10, 20, 6), right=(-4, 24, 10)), None),
        (11, {"Hips": [(X, 4), (Z, -18)], "Spine": [(X, 16)], "Chest": [(X, 8)], "Head": [(X, 20), (Z, 10)],
              "LeftUpperArm": [(Y, 18), (X, -10)], "RightUpperArm": [(Y, -18), (X, -6)],
              "LeftLowerArm": [(X, -25)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 30)],
              **_leg_pose("Left", 2, 92, 30, adduct=3, shin_out=-1),
              **_leg_pose("Right", -2, 95, 32, adduct=3, shin_out=-1)}, "body"),
        (15, {"Hips": [(X, 2), (Z, -14)], "Spine": [(X, 6)], "Chest": [(X, 4)], "Head": [(X, 12), (Z, 12)],
              "LeftUpperArm": [(Y, 16), (X, -14)], "RightUpperArm": [(Y, -16), (X, -10)],
              "LeftLowerArm": [(X, -25)], "RightLowerArm": [(X, -20)], "RightHand": [(X, 30)],
              **_leg_pose("Left", 2, 95, 30, adduct=3, shin_out=-1),
              **_leg_pose("Right", -2, 95, 32, adduct=3, shin_out=-1)}, "body"),
        (22, {"Hips": [(X, 50), (Z, -10)], "Spine": [(X, 10)], "Chest": [(X, 6)], "Head": [(X, -20), (Z, 20)],
              "LeftUpperArm": [(Y, 30), (X, -60)], "RightUpperArm": [(Y, -30), (X, -55)],
              "LeftLowerArm": [(X, -30)], "RightLowerArm": [(X, -25)], "RightHand": [(X, 30)],
              **_leg_pose("Left", -20, 60, 10, adduct=3, shin_out=-1),
              **_leg_pose("Right", -24, 62, 12, adduct=3, shin_out=-1)}, "body"),
        (27, {"Hips": [(X, 86), (Z, -8)], "Spine": [(X, 2)], "Chest": [(X, 0)], "Head": [(X, -30), (Z, 50)],
              "LeftUpperArm": [(Y, 76), (X, -10)], "RightUpperArm": [(Y, -68), (X, -8)],
              "LeftLowerArm": [(X, -40)], "RightLowerArm": [(X, -20)], "RightHand": [(X, -45), (Z, 60), (Y, -30)],
              **_leg_pose("Left", 2, 24, -35, adduct=-4, shin_out=-1),
              **_leg_pose("Right", -4, 10, -40, adduct=-6, shin_out=-1)}, "body"),
        (32, {"Hips": [(X, 88), (Z, -8)], "Spine": [(X, 0)], "Chest": [(X, -2)], "Head": [(X, -26), (Z, 55)],
              "LeftUpperArm": [(Y, 82), (X, 4)], "RightUpperArm": [(Y, -74), (X, 6)],
              "LeftLowerArm": [(X, -35)], "RightLowerArm": [(X, -18)], "RightHand": [(X, -45), (Z, 60), (Y, -30)],
              **_leg_pose("Left", 4, 20, -35, adduct=-4, shin_out=-1),
              **_leg_pose("Right", -2, 6, -40, adduct=-6, shin_out=-1)}, "body"),
    ]))
    return acts


def make_animations(armature):
    """All base animations: idle, walk (about 1.6 m/s), run (about 7 m/s)."""
    acts = [
        make_idle(armature),
        make_walk(armature),
        make_run(armature),
        make_ready(armature),
    ] + make_jump(armature) + make_sit(armature) + make_attacks(armature)
    armature.animation_data.action = acts[1]
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 32
    return acts
