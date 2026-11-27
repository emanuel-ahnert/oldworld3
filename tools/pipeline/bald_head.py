"""The base body's head without its modelled hair: a bald scalp and a forehead (bald.py, hair.py).

The base mesh's hair is part of the head (a helmet of hair, the fringe hanging over the brows).
Every head vertex in the hair's place (above the hairline: the brows in front, the ears' tops at
the sides, the nape at the back; the ears themselves stay) is set free and placed anew:

- an egg around the head's middle gives the skull's rough shape;
- how far the kept skin round the hairline (brows, temples, ears, nape) lies off that egg is
  spread smoothly over the freed part (harmonic: every freed vertex the mean of its neighbours),
  so the scalp leaves the face without a step;
- the forehead: a rounded slope rising from the brow ridge (`BROW` above the eyes) back to the
  crown, a little in front of where the egg alone would put it;
- a few rounds of smoothing (the old fringe folded under itself).
"""
import math

import bmesh
import numpy as np

BROW = 0.008          # m over the eyes' line where the forehead starts (the free part's lower edge)


def head_frame(body, rig):
    """HC (the head's middle, headgear.py's), NECK, CX for the base body (rest pose)."""
    bco = np.array([body.matrix_world @ v.co for v in body.data.vertices])
    NECK = float((rig.matrix_world @ rig.data.bones["Head"].head_local).z)
    head_g = body.vertex_groups["Head"].index
    head_v = np.array([any(g.group == head_g and g.weight > 0.5 for g in v.groups) for v in body.data.vertices])
    head_y = float(np.median(bco[head_v, 1]))
    H_ = bco[head_v]
    mid_ = H_[(H_[:, 2] > NECK + 0.06) & (H_[:, 2] < NECK + 0.12)]
    low_ = H_[(H_[:, 2] > NECK - 0.05) & (H_[:, 2] < NECK + 0.02)]
    CX = float((mid_[np.argmin(mid_[:, 1]), 0] + low_[np.argmin(low_[:, 1]), 0]) / 2)
    return np.array([CX, head_y, NECK + 0.10]), NECK, CX


def _ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ear_place(up, ahead, side):
    """0..1: the ears (they stay; the hair painted over them becomes skin)."""
    return (_ss(0.068, 0.078, np.abs(side)) * (1 - _ss(0.03, 0.045, up)) * _ss(-0.06, -0.045, up)
            * _ss(-0.045, -0.03, ahead) * (1 - _ss(0.035, 0.05, ahead)))


def hair_place(up, ahead, side, brow=None):
    """0..1: how much a point (head coordinates, m) is in the modelled hair's place."""
    brow = BROW if brow is None else brow
    low = -0.09 + 0.09 * _ss(-0.06, 0.0, ahead)          # the nape at the back, the ears' top at the sides
    low = low + (brow - low) * _ss(0.03, 0.06, ahead)     # the brows in front
    w = _ss(low - 0.004, low + 0.004, up)
    return w * (1 - ear_place(up, ahead, side))   # the ears stay (their tops stand in the hair's place)


def egg_r(d):
    """The skull's rough radius toward unit directions d (n, 3: up, ahead, side)."""
    up, ah, sd = d[:, 0], d[:, 1], d[:, 2]
    ax = np.where(ah > 0, 0.118, 0.132)
    uy = np.where(up > 0, 0.124, 0.11)
    return 1.0 / np.sqrt((up / uy) ** 2 + (ah / ax) ** 2 + (sd / 0.092) ** 2)


def make_bald(body, rig, slot_name="slot"):
    """Moves the base body's hair vertices (in place) onto a bald scalp. Returns the free mask."""
    HC, NECK, CX = head_frame(body, rig)
    me = body.data
    mw = np.array(body.matrix_world)
    inv = np.linalg.inv(mw)
    co = np.array([body.matrix_world @ v.co for v in me.vertices])
    slot = np.array([d.color[0] for d in me.color_attributes[slot_name].data])
    head = np.abs(slot - 0.0625) < 0.02
    rel = co - HC
    hc = np.stack([rel[:, 2], -rel[:, 1], rel[:, 0]], axis=1)       # up, ahead, side
    w = hair_place(hc[:, 0], hc[:, 1], hc[:, 2]) * head
    free = w > 0.5
    # Neighbours.
    nb = [[] for _ in me.vertices]
    for e in me.edges:
        a_, b_ = e.vertices
        nb[a_].append(b_)
        nb[b_].append(a_)
    r = np.linalg.norm(hc, axis=1)
    d = hc / np.maximum(r, 1e-6)[:, None]
    off = r - egg_r(d)                    # kept skin: how far off the egg
    # Harmonic spread of the offset over the freed part (kept vertices fixed).
    idx = np.where(free)[0]
    off[idx] = 0.0
    for _ in range(400):
        new = off.copy()
        for i in idx:
            n = nb[i]
            if n:
                new[i] = sum(off[j] for j in n) / len(n)
        off = new
    target = d * (egg_r(d) + off)[:, None]
    # The forehead: from the brow ridge sloping back (no further forward than this).
    fa = 0.1 - 0.34 * np.maximum(target[:, 0] - BROW, 0.0) - 7.0 * target[:, 2] ** 2
    front = _ss(0.02, 0.05, target[:, 1]) * (1 - _ss(0.09, 0.12, target[:, 0]))
    target[:, 1] = np.where(free, target[:, 1] - np.maximum(target[:, 1] - fa, 0.0) * front, target[:, 1])
    new_hc = np.where(free[:, None], target, hc)
    # Smoothing the freed part (the fringe's folded underside got crumpled).
    for _ in range(25):
        sm = new_hc.copy()
        for i in idx:
            n = nb[i]
            if n:
                sm[i] = new_hc[i] * 0.4 + np.mean(new_hc[n], axis=0) * 0.6
        # Back onto the scalp's radius (smoothing shrinks it).
        rr = np.linalg.norm(sm[idx], axis=1)
        dd = sm[idx] / rr[:, None]
        want = np.linalg.norm(target[idx], axis=1)
        sm[idx] = dd * (rr * 0.5 + want * 0.5)[:, None]
        new_hc = sm
    world = HC + np.stack([new_hc[:, 2], -new_hc[:, 1], new_hc[:, 0]], axis=1)
    for i in idx:
        p = inv @ np.append(world[i], 1.0)
        me.vertices[i].co = p[:3]
    me.update()
    return free, HC, NECK


def scalp_bvh(body):
    """A BVH of the (bald) body for raycasts from the head's middle (hair.py)."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.transform(body.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def add_ears(body, HC, slot_name="slot"):
    """Human ears on the bald head (the base mesh had none: its hair covered them): per side a
    cupped shell (the bowl inside, a rolled rim, a lobe below) about 6 cm tall, its front edge on
    the head behind the jaw, its back flaring out; a flat back toward the head. In the body's own
    material: UVs all on one skin texel of the cheek, slot 0 (head), weighted to the head bone."""
    from mathutils import Vector
    me = body.data
    tree = scalp_bvh(body)
    inv = body.matrix_world.inverted()
    co = np.array([body.matrix_world @ v.co for v in me.vertices])
    slot = np.array([d.color[0] for d in me.color_attributes[slot_name].data])
    rel = co - HC
    up, ah, sd = rel[:, 2], -rel[:, 1], rel[:, 0]
    # A skin texel: the loop UV of a cheek vertex.
    cheek = np.where((np.abs(slot - 0.0625) < 0.02) & (ah > 0.05) & (up > -0.035) & (up < -0.015) & (np.abs(sd) > 0.035))[0]
    uv_layer = me.uv_layers["UVMap"]
    cheek_uv = None
    for l in me.loops:
        if l.vertex_index == int(cheek[0]):
            cheek_uv = tuple(uv_layer.data[l.index].uv)
            break
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv["UVMap"]
    colv = bm.verts.layers.float_color[slot_name]
    dl = bm.verts.layers.deform.verify()
    head_g = body.vertex_groups["Head"].index
    H_HALF, W_HALF = 0.031, 0.018
    NA, NR = 24, 6
    for sgn in (-1.0, 1.0):
        # The ear's place on the head: behind the jaw at the eyes' to the nose's height.
        u0, a0 = -0.008, -0.012
        dir_ = np.array([sgn, -a0 / 0.09, u0 / 0.09])          # Blender: x side, -y ahead, z up
        dir_ = dir_ / np.linalg.norm(dir_)
        start = Vector(HC + dir_ * 0.3)
        hit = tree.ray_cast(start, Vector(-dir_), 0.3)
        surf = np.array(hit[0]) if hit[0] is not None else HC + dir_ * 0.09
        out = np.array([sgn, 0.0, 0.0])
        upv = np.array([0.0, 0.0, 1.0])
        back = np.array([0.0, 1.0, 0.0])                       # +y is behind (the body faces -y)
        # Flare: the back edge out from the head (turned about the up axis), leaning back a little.
        fl = math.radians(24.0)
        back_f = back * math.cos(fl) + out * math.sin(fl)
        out_f = np.cross(upv, back_f) * (-sgn) if sgn > 0 else np.cross(back_f, upv)
        out_f = out_f / np.linalg.norm(out_f)
        if np.dot(out_f, out) < 0:
            out_f = -out_f
        tilt = math.radians(14.0)
        up_t = upv * math.cos(tilt) + back_f * math.sin(tilt)
        back_t = np.cross(out_f, up_t)
        if np.dot(back_t, back) < 0:
            back_t = -back_t
        # The front edge (local x = -W_HALF) touches the head.
        center = surf + back_t * (W_HALF * 0.9) - out_f * 0.003
        front_rings, back_rings = [], []
        for k in range(NR + 1):
            s = k / NR
            ring_f, ring_b = [], []
            for i in range(NA):
                ang = 2 * math.pi * i / NA
                ca, sa = math.cos(ang), math.sin(ang)
                hh = H_HALF * (0.85 if sa < 0 else 1.0)            # the lobe a little shorter
                ww = W_HALF * (0.7 if sa < -0.3 else 1.0) * (1.0 + 0.12 * sa)
                x, y = ca * ww * s, sa * hh * s
                # The cup: the bowl sunk in the middle, the rim rolled up.
                depth = -0.006 * math.sin(math.pi * min(s / 0.8, 1.0)) + 0.004 * max(0.0, (s - 0.78) / 0.22) ** 2
                if ca < -0.6 and s < 0.6:
                    depth *= 0.3                                  # the front (tragus) shallow
                pf = center + back_t * x + up_t * y + out_f * (0.006 + depth)
                pb = center + back_t * x + up_t * y + out_f * (0.002 - 0.0015 * s)
                ring_f.append(pf)
                ring_b.append(pb)
            front_rings.append(ring_f)
            back_rings.append(ring_b)

        def mk(p):
            v = bm.verts.new(Vector(inv @ Vector(p)))
            v[colv] = (0.0625, 0.0, 0.0, 1.0)
            v[dl][head_g] = 1.0
            return v

        fv = [[mk(p) for p in ring] for ring in front_rings]
        bv = [[mk(p) for p in ring[:]] for ring in back_rings[:-1]] + [fv[-1]]   # the rim shared
        faces = []
        for k in range(NR):
            for i in range(NA):
                i2 = (i + 1) % NA
                faces.append(bm.faces.new((fv[k][i], fv[k][i2], fv[k + 1][i2], fv[k + 1][i])))
                faces.append(bm.faces.new((bv[k][i2], bv[k][i], bv[k + 1][i], bv[k + 1][i2])))
        for f in faces:
            f.smooth = True
            for l in f.loops:
                l[uvl].uv = cheek_uv
    bmesh.ops.remove_doubles(bm, verts=bm.verts[-((NR + 1) * NA * 4):], dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    me.update()
