"""Step 2 of the new raven: rigs the two prepared models (see
tools/raven_new_prep.py) and saves them as

    assets/creature/raven_walk.blend   the raven on the ground
    assets/creature/raven_fly.blend    the raven flying, level

    blender -b --factory-startup --python tools/raven_new_rig.py -- walk|fly [render_dir]

Both get the same skeleton (the same bone names), fitted to their own pose:

  root > pelvis > spine > chest > chest_upper > neck1 > neck2 > head
  legs     thigh > shin > tarsus > foot > toes (three in front, one behind,
           three bones each, the back one two). The knee bends forward like
           a man's; between it and the ankle is the reverse knee (the hock),
           which bends the other way.
  arms     clavicle > arm_upper > arm_lower > hand > fingers (four, three
           bones each)
  tail     tail1 > tail2 > five tail feathers fanned out (two bones each)
  wings    wing_root (the shoulder blade) > wing_upper (humerus) > wing_fore
           (forearm) > wing_hand, with the flight feathers as a real wing
           carries them: five primaries on the hand, four secondaries on the
           forearm, two tertials by the body (two bones each, so they bend).

Sides: "_r" is +X, "_l" is -X (as the old raven). Blender space: +Z up, the
raven faces -Y. The flying model comes upright from Meshy; it is pitched
forward to fly level, its head raised to look ahead, and that is its rest.

Hinges (elbows, knees, reverse knees, wing elbows and wrists, fingers,
toes) are rolled so their bone's X axis is the hinge: a positive X rotation
closes the joint. Each has a Limit Rotation constraint: it closes no
further than its HINGES limit, never opens past straight, and hardly turns
any other way. The animations (tools/raven_new_anim.py) keep inside them.
"""
import heapq
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector, kdtree

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "art_sources", "raven")
OUT = os.path.join(ROOT, "assets", "creature")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["walk"]
MODEL = ARGS[0]
RENDER_DIR = ARGS[1] if len(ARGS) > 1 else ""

# The body's joints, read off grid pictures of each model (+X side and the
# middle; the -X side is the mirror). Limb joints are then moved to the
# middle of the limb where they are (see centre_of()).
JOINTS = {
    "walk": {
        "root": (0.0, -0.18, 0.0), "pelvis": (0.0, -0.18, 0.76), "spine": (0.0, -0.17, 0.95),
        "chest": (0.0, -0.19, 1.10), "chest_upper": (0.0, -0.22, 1.24), "neck1": (0.0, -0.27, 1.32),
        "neck2": (0.0, -0.35, 1.42), "head": (0.0, -0.42, 1.50), "beak": (0.0, -0.79, 1.47),
        "hip": (0.17, -0.20, 0.73), "knee": (0.22, -0.35, 0.49), "hock": (0.23, -0.15, 0.31),
        "ankle": (0.26, -0.22, 0.10),
        "clavicle": (0.07, -0.24, 1.25), "shoulder": (0.28, -0.24, 1.20), "elbow": (0.43, -0.20, 0.93),
        "wrist": (0.45, -0.46, 0.73),
        "tail_base": (0.0, 0.0, 0.76), "tail_mid": (0.0, 0.12, 0.55),
    },
    "fly": {
        "root": (0.0, -0.07, 0.0), "pelvis": (0.0, -0.07, 0.86), "spine": (0.0, -0.07, 1.05),
        "chest": (0.0, -0.07, 1.24), "chest_upper": (0.0, -0.07, 1.40), "neck1": (0.0, -0.08, 1.52),
        "neck2": (0.0, -0.11, 1.64), "head": (0.0, -0.14, 1.78), "beak": (0.0, -0.47, 2.00),
        "hip": (0.17, -0.07, 0.83), "knee": (0.24, -0.20, 0.60), "hock": (0.26, 0.08, 0.44),
        "ankle": (0.30, 0.05, 0.20),
        "clavicle": (0.08, -0.07, 1.42), "shoulder": (0.40, -0.05, 1.37), "elbow": (0.59, -0.10, 1.16),
        "wrist": (0.45, -0.33, 0.98),
        "tail_base": (0.0, 0.08, 0.93), "tail_mid": (0.0, 0.12, 0.75),
    },
}
# Closing limits, degrees from straight: how far each hinge closes.
HINGES = {
    "shin": 150, "tarsus": 150, "foot": 110, "arm_lower": 150, "hand": 80,
    "wing_fore": 160, "wing_hand": 150, "finger": 100, "toe": 100,
}
FINGERS = ["thumb", "index", "middle", "ring"]
TOES = ["toe_back", "toe_in", "toe_mid", "toe_out"]


def log(*a):
    print("RIG", *a)


def mirror(p):
    return Vector((-p.x, p.y, p.z))


# --- Mesh helpers ----------------------------------------------------------------

class Graph:
    """A mesh as a graph of its points, with Meshy's split seams welded."""

    def __init__(self, obj, keep=None):
        me = obj.data
        self.P = {}
        rep = {}
        kd = kdtree.KDTree(len(me.vertices))
        idx = [v.index for v in me.vertices if keep is None or keep(v.co)]
        for i in idx:
            kd.insert(me.vertices[i].co, i)
        kd.balance()
        for i in idx:
            if i in rep:
                continue
            for co, j, d in kd.find_range(me.vertices[i].co, 1e-5):
                rep.setdefault(j, i)
        self.rep = rep
        for r in set(rep.values()):
            self.P[r] = me.vertices[r].co.copy()
        self.adj = {r: {} for r in self.P}
        for e in me.edges:
            a, b = e.vertices
            if a in rep and b in rep:
                ra, rb = rep[a], rep[b]
                if ra != rb:
                    d = (self.P[ra] - self.P[rb]).length
                    self.adj[ra][rb] = d
                    self.adj[rb][ra] = d

    def dijkstra(self, seeds, start=None):
        dist = dict(start) if start else {s: 0.0 for s in seeds}
        prev = {}
        heap = [(d, s) for s, d in dist.items()]
        heapq.heapify(heap)
        while heap:
            d, x = heapq.heappop(heap)
            if d > dist.get(x, 1e9):
                continue
            for y, w in self.adj[x].items():
                nd = d + w
                if nd < dist.get(y, 1e9):
                    dist[y] = nd
                    prev[y] = x
                    heapq.heappush(heap, (nd, y))
        return dist, prev


def centre_of(obj, p, axis, slab=0.025, reach=0.16):
    """The middle of the limb through `p` (across `axis`): the mean of the
    points in a thin slice there, near enough to `p`."""
    axis = axis.normalized()
    pts = [v.co for v in obj.data.vertices
           if abs((v.co - p).dot(axis)) < slab and ((v.co - p) - axis * (v.co - p).dot(axis)).length < reach]
    if len(pts) < 8:
        return p
    c = sum(pts, Vector()) / len(pts)
    return p + ((c - p) - axis * (c - p).dot(axis))


# --- Fingers and toes ----------------------------------------------------------------

def trace_digits(obj, base, out_dir, count, reach, slab=0.02, same=0.04):
    """The digits of the hand or foot whose wrist (ankle) is `base`, the hand
    pointing along `out_dir`: each a line from its knuckle to its claw tip,
    along the middle of the digit. The claw tips are the points furthest round
    the skin from the wrist; tips whose branches join near them are one
    digit's. The `count` longest are kept."""
    out_dir = out_dir.normalized()
    keep = lambda co: (co - base).length < reach and (co - base).dot(out_dir) > -slab
    g = Graph(obj, keep)
    # The slices along a digit are as thick as the mesh's edges are long.
    lengths = sorted(w for a in g.adj.values() for w in a.values())
    edge = lengths[len(lengths) // 2] if lengths else 0.01
    band = max(0.008, 0.9 * edge)
    step = max(0.004, 0.5 * edge)
    seeds = [r for r, p in g.P.items() if abs((p - base).dot(out_dir)) < slab]
    dw, prev = g.dijkstra(seeds)
    reps = [r for r in g.P if r in dw]
    P = g.P

    def path_of(t):
        out = [t]
        while out[-1] in prev:
            out.append(prev[out[-1]])
        return out

    def band_component(level, start):
        inside = {r for r in reps if abs(dw[r] - level) <= band}
        if start not in inside:
            return set()
        seen = {start}
        stack = [start]
        while stack:
            x = stack.pop()
            for y in g.adj[x]:
                if y in inside and y not in seen:
                    seen.add(y)
                    stack.append(y)
        return seen

    cands = []
    for r in sorted(reps, key=lambda r: -dw[r]):
        if any((P[r] - P[t]).length < 0.03 for t in cands):
            continue
        if all(dw[y] <= dw[r] for y in g.adj[r]) and all(dw[y] <= dw[r] + 1e-6 for y in reps if (P[y] - P[r]).length < 0.025):
            cands.append(r)
        if len(cands) > 40:
            break
    cands = [c for c in cands if dw[c] > 0.45 * dw[cands[0]]]
    paths = {c: path_of(c) for c in cands}

    def components_at(level, tips):
        got = set()
        for t in tips:
            if dw[t] < level - band:
                continue
            start = min(paths[t], key=lambda r: abs(dw[r] - level))
            got |= band_component(level, start)
        return got

    def meet(a, b):
        level = dw[a] - band
        while level > 0.0:
            if components_at(level, [a]) & set(paths[b]):
                return level
            level -= step
        return 0.0

    group = {c: c for c in cands}
    for i, x in enumerate(cands):
        for y in cands[i + 1:]:
            if group[x] == group[y]:
                continue
            if meet(x, y) >= min(dw[x], dw[y]) - same:
                gy = group[y]
                for k in group:
                    if group[k] == gy:
                        group[k] = group[x]
    digits = {}
    for c in cands:
        digits.setdefault(group[c], []).append(c)
    traced = []
    for own in digits.values():
        t = max(own, key=lambda r: dw[r])
        others = set()
        for o in cands:
            if o not in own:
                others.update(paths[o])
        levels = []
        level = dw[t] - 0.5 * band
        while level > 0.0:
            comp = components_at(level, own)
            if not comp or comp & others:
                break
            main = components_at(level, [t])
            if main:
                levels.append((level, main))
            level -= step
        if len(levels) < 4:
            continue
        line = [sum((P[r] for r in main), Vector()) / len(main) for level, main in reversed(levels)]
        line.append(P[t].copy())
        back = line[0] - line[min(3, len(line) - 1)]
        if back.length > 1e-6:
            line.insert(0, line[0] + back.normalized() * 0.01)
        traced.append(line)
    traced.sort(key=lambda l: -sum((l[i] - l[i - 1]).length for i in range(1, len(l))))
    log("digits found", len(traced), "keeping", count, [round(sum((l[i] - l[i - 1]).length for i in range(1, len(l))), 3) for l in traced])
    return traced[:count]


def trace_by_sector(obj, base, axis, count, reach, start=0.35, slab=0.02):
    """Digits split by the way each points: the points of the hand or foot
    past `start` of the way round the skin from the wrist (ankle) are split
    into `count` groups by their angle about `axis` (at the widest gaps
    between them), and each group is followed on its own from its base to
    its claw tip (the point furthest round the skin)."""
    axis = axis.normalized()
    keep = lambda co: (co - base).length < reach and (co - base).dot(axis) > -slab
    g = Graph(obj, keep)
    lengths = sorted(w for a in g.adj.values() for w in a.values())
    edge = lengths[len(lengths) // 2] if lengths else 0.01
    band = max(0.008, 1.2 * edge)
    seeds = [r for r, p in g.P.items() if abs((p - base).dot(axis)) < slab]
    dw, prev = g.dijkstra(seeds)
    far = max(dw.values())
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((0, -1, 0))
    u = (ref - axis * ref.dot(axis)).normalized()
    v = axis.cross(u)
    pts = [r for r in dw if dw[r] > start * far]

    def angle(r):
        d = g.P[r] - base
        return math.atan2(d.dot(v), d.dot(u))

    ang = sorted((angle(r), r) for r in pts)
    gaps = []
    for i in range(len(ang)):
        a0 = ang[i][0]
        a1 = ang[(i + 1) % len(ang)][0] + (2 * math.pi if i == len(ang) - 1 else 0.0)
        gaps.append((a1 - a0, i))
    cuts = sorted(i for gap, i in sorted(gaps, reverse=True)[:count])
    groups = []
    for k in range(len(cuts)):
        a, b = cuts[k], cuts[(k + 1) % len(cuts)]
        members = [ang[(a + 1 + m) % len(ang)][1] for m in range((b - a) % len(ang) or len(ang))]
        groups.append(members)
    lines = []
    for members in groups:
        if len(members) < 6:
            continue
        own = set(members)
        tip = max(members, key=lambda r: dw[r])
        lo = min(dw[r] for r in members)
        line = []
        level = lo + band * 0.5
        while level < dw[tip]:
            sl = [g.P[r] for r in members if abs(dw[r] - level) <= band]
            if sl:
                line.append(sum(sl, Vector()) / len(sl))
            level += band
        line.append(g.P[tip].copy())
        if len(line) >= 3:
            lines.append(line)
    log("digits by sector", len(lines), [round(sum((l[i] - l[i - 1]).length for i in range(1, len(l))), 3) for l in lines])
    return lines


def at_arc(line, frac):
    arc = [0.0]
    for i in range(1, len(line)):
        arc.append(arc[-1] + (line[i] - line[i - 1]).length)
    a = min(max(frac, 0.0), 1.0) * arc[-1]
    for i in range(1, len(arc)):
        if arc[i] >= a:
            u = (a - arc[i - 1]) / max(arc[i] - arc[i - 1], 1e-9)
            return line[i - 1].lerp(line[i], u)
    return line[-1].copy()



# Toes, read off grid pictures of each foot (base, knuckle, claw tip; +X
# foot). The cut-down mesh has too few points on the toes to find them by
# itself, as the fingers are.
TOE_POINTS = {
    "walk": {
        "toe_back": [(0.25, -0.22, 0.045), (0.235, -0.17, 0.028), (0.22, -0.12, 0.010)],
        "toe_in": [(0.285, -0.34, 0.040), (0.29, -0.44, 0.030), (0.30, -0.535, 0.012)],
        "toe_mid": [(0.33, -0.35, 0.040), (0.36, -0.44, 0.030), (0.39, -0.530, 0.012)],
        "toe_out": [(0.355, -0.33, 0.040), (0.40, -0.375, 0.030), (0.44, -0.410, 0.012)],
    },
    "fly": {
        "toe_back": [(0.34, 0.07, 0.200), (0.345, 0.10, 0.150), (0.345, 0.06, 0.080)],
        "toe_in": [(0.31, 0.02, 0.200), (0.27, -0.03, 0.150), (0.25, 0.00, 0.110)],
        "toe_mid": [(0.35, 0.02, 0.200), (0.37, -0.06, 0.120), (0.38, 0.02, 0.010)],
        "toe_out": [(0.39, 0.03, 0.200), (0.44, -0.02, 0.170), (0.47, 0.00, 0.125)],
    },
}
# The wing's arm bones, just inside its leading edge (+X wing; read from
# the leading edge's trace): shoulder, elbow, wrist, and the end of the hand.
WING_POINTS = {
    "walk": [(0.20, -0.13, 1.36), (0.31, -0.03, 1.53), (0.46, 0.06, 1.78), (0.72, 0.28, 1.68)],
    "fly": [(0.26, 0.14, 1.55), (0.63, 0.15, 1.60), (1.05, 0.13, 1.93), (1.50, 0.20, 2.18)],
}
# The flying model's nose is raised this much above level once it is
# pitched forward.
FLY_NOSE_UP = 6.0
# Where the walking raven's tail ends (its tail is part of its body).
TAIL_TIP = {"walk": Vector((0.0, 0.41, 0.06))}


def seg_dist(p, a, b):
    """Distance from `p` to the segment a-b, and how far along it (0..1)."""
    d = b - a
    u = min(max((p - a).dot(d) / max(d.length_squared, 1e-12), 0.0), 1.0)
    return (p - (a + d * u)).length, u


def main_points(parts):
    """The body's joints for MODEL, limb joints moved to the limb's middle."""
    body = parts["body"]
    j = {k: Vector(v) for k, v in JOINTS[MODEL].items()}
    chain = [("hip", "knee"), ("knee", "hock"), ("hock", "ankle"), ("shoulder", "elbow"), ("elbow", "wrist")]
    for a, b in chain:
        axis = j[b] - j[a]
        j[b] = centre_of(body, j[b], axis)
    return j


def level_flyer(parts, j, extra):
    """Pitches the upright flying model forward about the pelvis until its
    body (pelvis to neck) points ahead, FLY_NOSE_UP above level."""
    axis = j["neck1"] - j["pelvis"]
    now = math.atan2(axis.z, -axis.y)
    want = math.radians(FLY_NOSE_UP)
    rot = Matrix.Rotation(now - want, 4, "X")
    pivot = j["pelvis"].copy()
    m = Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot)
    for obj in parts.values():
        obj.data.transform(m)
        obj.data.update()
    for k in j:
        j[k] = m @ j[k]
    for group in extra:
        for k in group:
            group[k] = [m @ p for p in group[k]]
    # The root sits as far under the pelvis as the walking raven's does.
    j["root"] = Vector((0.0, j["pelvis"].y, j["pelvis"].z - 0.76))
    log("fly: pitched forward", round(math.degrees(now - want), 1), "degrees")
    return m


def wing_feathers(wings, arm):
    """The flight feathers of the +X wing: five primaries on the hand, four
    secondaries on the forearm, two tertials on the upper arm. Each is
    [root, tip], the tip the furthest point of the wing that way."""
    shoulder, elbow, wrist, hand_end = arm
    pts = [v.co.copy() for v in wings.data.vertices if v.co.x > 0.02]
    import numpy as np
    arr = np.array([p[:] for p in pts])
    c = arr.mean(0)
    normal = Vector(np.linalg.svd(arr - c, full_matrices=False)[2][2])
    # In the wing's plane: "out" along the hand, and "back" to the trailing edge.
    out_dir = (hand_end - wrist).normalized()
    centre = Vector(c)

    def flat(v):
        return v - normal * v.dot(normal)

    back = flat(centre - (wrist + elbow) * 0.5).normalized()
    back = (back - out_dir * back.dot(out_dir)).normalized()
    # Primaries: the angles from straight out along the hand round to straight back.
    tips = []
    for k in range(5):
        a0 = math.radians(-8 + 98 * k / 5.0)
        a1 = math.radians(-8 + 98 * (k + 1) / 5.0)
        best, best_d = None, -1.0
        for p in pts:
            d = flat(p - wrist)
            ang = math.atan2(d.dot(back), d.dot(out_dir))
            if a0 <= ang < a1 and d.length > best_d:
                best, best_d = p, d.length
        tips.append(best)
    prim = []
    for k, tip in enumerate(tips):
        root = hand_end.lerp(wrist, k / 4.0)
        if tip is None:
            tip = root + (out_dir.lerp(back, k / 4.0)).normalized() * 0.8
        prim.append([root, tip])

    def corridor(root, direction, width=0.09):
        best, best_d = None, -1.0
        for p in pts:
            d = p - root
            along = d.dot(direction)
            if along <= 0:
                continue
            if (d - direction * along).length < width and along > best_d:
                best, best_d = p, along
        return best if best is not None else root + direction * 0.5

    sec = []
    fore = (wrist - elbow).normalized()
    for k, f in enumerate([0.88, 0.62, 0.36, 0.10]):
        root = elbow.lerp(wrist, f)
        d = flat(back - fore * back.dot(fore)).normalized()
        sec.append([root, corridor(root, d)])
    ter = []
    upper = (elbow - shoulder).normalized()
    for f in [0.75, 0.35]:
        root = shoulder.lerp(elbow, f)
        d = flat(back - upper * back.dot(upper)).normalized()
        ter.append([root, corridor(root, d)])
    return prim, sec, ter, normal


def tail_fan(points, base, count=5):
    """Tail feather tips: the furthest tail points from `base` in `count`
    slices across the tail (by X)."""
    xs = [p.x for p in points]
    lo, hi = min(xs), max(xs)
    tips = []
    for k in range(count):
        a = lo + (hi - lo) * k / count
        b = lo + (hi - lo) * (k + 1) / count
        sl = [p for p in points if a <= p.x <= b]
        tips.append(max(sl, key=lambda p: (p - base).length) if sl else base + Vector((0, 0.3, -0.3)))
    return tips


class Rig:
    """Builds the armature's bones (in edit mode) and remembers each hinge."""

    def __init__(self, name):
        data = bpy.data.armatures.new(name)
        self.obj = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(self.obj)
        bpy.context.view_layer.objects.active = self.obj
        bpy.ops.object.mode_set(mode="EDIT")
        self.eb = data.edit_bones
        self.hinge = {}

    def bone(self, name, head, tail, parent=None, connect=False, deform=True, roll_to=None):
        b = self.eb.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        if roll_to is not None:
            b.align_roll(roll_to)
        else:
            b.align_roll(Vector((0, 0, 1)) if abs((b.tail - b.head).normalized().z) < 0.9 else Vector((0, -1, 0)))
        if parent:
            b.parent = self.eb[parent]
            b.use_connect = connect
        b.use_deform = deform
        return b

    def hinge_bone(self, name, head, tail, parent, kind, flex=None, connect=True):
        """A bone that bends on a hinge at its head: its X axis is the hinge,
        and a positive X turn moves its tail along `flex` (the way the joint
        closes; by default, back towards the parent's head)."""
        c = (Vector(tail) - Vector(head)).normalized()
        if flex is None:
            p = (self.eb[parent].tail - self.eb[parent].head).normalized()
            flex = -p
        f = flex - c * flex.dot(c)
        if f.length < 1e-4:
            f = c.orthogonal()
        f.normalize()
        b = self.bone(name, head, tail, parent, connect, True, roll_to=f)
        # How far from straight it is now (positive: closed that far).
        p = (self.eb[parent].tail - self.eb[parent].head).normalized()
        rest = math.degrees(p.angle(c)) if f.dot(-p) >= 0 else -math.degrees(p.angle(c))
        self.hinge[name] = {"kind": kind, "rest": rest}
        return b

    def done(self):
        bpy.ops.object.mode_set(mode="OBJECT")


def build(parts):
    j = main_points(parts)
    toes = {k: [Vector(p) for p in v] for k, v in TOE_POINTS[MODEL].items()}
    wing_arm = {"arm": [Vector(p) for p in WING_POINTS[MODEL]]}
    hand_dir = j["wrist"] - j["elbow"]
    finger_lines = trace_digits(parts["body"], j["wrist"], hand_dir, 4, 0.32)
    # The thumb is the shortest; the others go from the inside (nearest the
    # body) outwards.
    finger_lines.sort(key=lambda l: sum((l[i] - l[i - 1]).length for i in range(1, len(l))))
    finger_lines = finger_lines[:1] + sorted(finger_lines[1:], key=lambda l: l[-1].x)
    fingers = {name: [at_arc(l, f) for f in (0.0, 0.42, 0.72, 1.0)] for name, l in zip(FINGERS, finger_lines)}
    if MODEL == "fly":
        level_flyer(parts, j, [toes, wing_arm, fingers])
    shoulder, elbow, wrist, hand_end = wing_arm["arm"]
    prim, sec, ter, wing_normal = wing_feathers(parts["wings"], wing_arm["arm"])
    # The tail: the walking raven's is part of its body; the flier's apart.
    if "tail" in parts:
        tail_pts = [v.co.copy() for v in parts["tail"].data.vertices]
    else:
        # (Along the line the tail hangs down, between the legs.)
        a, b = j["tail_mid"], TAIL_TIP[MODEL]
        tail_pts = [v.co.copy() for v in parts["body"].data.vertices
                    if seg_dist(v.co, a, b)[0] < 0.11 and abs(v.co.x) < 0.13 and seg_dist(v.co, a, b)[1] > 0.3]
    fan_base = j["tail_mid"]
    fan_tips = tail_fan(tail_pts, fan_base)

    rig = Rig("raven_" + MODEL)
    B = rig.bone
    B("root", j["root"], j["root"] + Vector((0, 0, 0.3)), deform=False)
    B("pelvis", j["pelvis"], j["spine"], "root")
    B("spine", j["spine"], j["chest"], "pelvis", True)
    B("chest", j["chest"], j["chest_upper"], "spine", True)
    B("chest_upper", j["chest_upper"], j["neck1"], "chest", True)
    B("neck1", j["neck1"], j["neck2"], "chest_upper", True)
    B("neck2", j["neck2"], j["head"], "neck1", True)
    B("head", j["head"], j["head"].lerp(j["beak"], 0.55), "neck2", True)
    B("tail1", j["pelvis"], j["tail_base"], "pelvis")
    B("tail2", j["tail_base"], fan_base, "tail1", True)
    order = sorted(range(len(fan_tips)), key=lambda k: fan_tips[k].x)
    names = ["tail_fan_l2", "tail_fan_l1", "tail_fan_c", "tail_fan_r1", "tail_fan_r2"]
    for name, k in zip(names, order):
        tip = fan_tips[k]
        mid = fan_base.lerp(tip, 0.55)
        B(name + "a", fan_base, mid, "tail2")
        B(name + "b", mid, tip, name + "a", True)
    for side, s in (("_r", 1.0), ("_l", -1.0)):
        m = (lambda p: Vector(p)) if s > 0 else mirror
        # Leg: the knee bends forward, the reverse knee (hock) back.
        B("thigh" + side, m(j["hip"]), m(j["knee"]), "pelvis")
        rig.hinge_bone("shin" + side, m(j["knee"]), m(j["hock"]), "thigh" + side, "shin")
        rig.hinge_bone("tarsus" + side, m(j["hock"]), m(j["ankle"]), "shin" + side, "tarsus")
        ball = m((toes["toe_in"][0] + toes["toe_mid"][0] + toes["toe_out"][0]) / 3.0)
        rig.hinge_bone("foot" + side, m(j["ankle"]), ball, "tarsus" + side, "foot")
        for toe, pts in toes.items():
            pts = [m(p) for p in pts]
            parent = "foot" + side
            if toe == "toe_back":
                chain = [pts[0], pts[1], pts[2]]
            else:
                chain = [pts[0], pts[0].lerp(pts[1], 0.6), pts[1], pts[2]]
            for i in range(len(chain) - 1):
                name = "%s%d%s" % (toe, i + 1, side)
                rig.hinge_bone(name, chain[i], chain[i + 1], parent, "toe", flex=Vector((0, 0, -1)), connect=i > 0)
                parent = name
        # Arm.
        B("clavicle" + side, m(j["clavicle"]), m(j["shoulder"]), "chest_upper")
        B("arm_upper" + side, m(j["shoulder"]), m(j["elbow"]), "clavicle" + side, True)
        rig.hinge_bone("arm_lower" + side, m(j["elbow"]), m(j["wrist"]), "arm_upper" + side, "arm_lower")
        palm = sum((m(f[0]) for f in fingers.values()), Vector()) / len(fingers)
        B("hand" + side, m(j["wrist"]), palm, "arm_lower" + side, True)
        for name, pts in fingers.items():
            pts = [m(p) for p in pts]
            parent = "hand" + side
            curl = (pts[1] - pts[0]).cross(pts[3] - pts[1])
            for i in range(3):
                bname = "%s%d%s" % (name, i + 1, side)
                d = (pts[i + 1] - pts[i]).normalized()
                flex = curl.cross(d) if curl.length > 1e-6 else None
                rig.hinge_bone(bname, pts[i], pts[i + 1], parent, "finger", flex=flex, connect=i > 0)
                parent = bname
        # Wing: shoulder blade, then a real wing's bones.
        B("wing_root" + side, m(j["chest_upper"]), m(shoulder), "chest_upper")
        B("wing_upper" + side, m(shoulder), m(elbow), "wing_root" + side, True)
        n = m(wing_normal) if s > 0 else mirror(wing_normal)
        lead = (hand_end - wrist).cross(wing_normal)
        # The forearm closes towards the leading edge, the hand towards the back.
        up_side = m(lead) if (m(lead)).dot(m(Vector((0, 0, 1)) if MODEL == "walk" else Vector((0, -1, 0)))) > 0 else -m(lead)
        rig.hinge_bone("wing_fore" + side, m(elbow), m(wrist), "wing_upper" + side, "wing_fore",
                       flex=up_side if MODEL == "fly" else None)
        rig.hinge_bone("wing_hand" + side, m(wrist), m(hand_end), "wing_fore" + side, "wing_hand",
                       flex=-up_side if MODEL == "fly" else None)
        groups = [("prim", prim, "wing_hand"), ("sec", sec, "wing_fore"), ("tert", ter, "wing_upper")]
        for gname, feathers, parent in groups:
            for k, (root, tip) in enumerate(feathers):
                root, tip = m(root), m(tip)
                mid = root.lerp(tip, 0.55)
                a = "%s%d%sa" % (gname, k + 1, side)
                b = "%s%d%sb" % (gname, k + 1, side)
                B(a, root, mid, parent + side, roll_to=n)
                B(b, mid, tip, a, True, roll_to=n)
    rig.done()
    return rig, j


def stick_render(rig, parts, tag):
    """Pictures of the bones (as thin sticks) over the see-through model."""
    if not RENDER_DIR:
        return
    os.makedirs(RENDER_DIR, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "OBJECT"
    sc.render.resolution_x = sc.render.resolution_y = 1000
    mat_body = (0.55, 0.55, 0.6, 1.0)
    for o in parts.values():
        o.color = mat_body
    sticks = []
    arm = rig.obj
    for b in arm.data.bones:
        h, t = arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local
        me = bpy.data.meshes.new("s")
        bm = bmesh.new()
        d = (t - h)
        L = d.length
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.012, radius2=0.004, depth=L)
        bm.to_mesh(me)
        o = bpy.data.objects.new("s", me)
        o.matrix_world = Matrix.Translation((h + t) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        side = b.name.endswith("_r")
        o.color = (1.0, 0.25, 0.1, 1) if side else ((0.1, 0.6, 1.0, 1) if b.name.endswith("_l") else (1, 0.9, 0.1, 1))
        o.show_in_front = True
        sc.collection.objects.link(o)
        sticks.append(o)
    sc.display.shading.show_xray = True
    sc.display.shading.xray_alpha = 0.35
    cd = bpy.data.cameras.new("c")
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cd.type = "ORTHO"
    lo = Vector((min(v[0] for o in parts.values() for v in o.bound_box), min(v[1] for o in parts.values() for v in o.bound_box), min(v[2] for o in parts.values() for v in o.bound_box)))
    hi = Vector((max(v[0] for o in parts.values() for v in o.bound_box), max(v[1] for o in parts.values() for v in o.bound_box), max(v[2] for o in parts.values() for v in o.bound_box)))
    c = (lo + hi) / 2
    size = max(hi - lo) * 1.05
    for name, d in [("front", Vector((0, -1, 0))), ("side", Vector((1, 0, 0))), ("top", Vector((0, 0, 1))), ("three", Vector((0.6, -0.6, 0.5)))]:
        cd.ortho_scale = size
        cam.location = c + d.normalized() * 10
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(RENDER_DIR, "%s_bones_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)
    for o in sticks:
        bpy.data.objects.remove(o)
    bpy.data.objects.remove(cam)
    sc.display.shading.show_xray = False


# --- Skin weights -------------------------------------------------------------------

WING_PREFIXES = ("wing_", "prim", "sec", "tert")
FAN_PREFIX = "tail_fan"
# How much further than the nearest bone (along the skin) another may be and
# still share a point; and how many smoothing passes the weights get.
SHARE = 0.07
SMOOTH = 4


def segments(arm, names):
    return {n: (arm.data.bones[n].head_local.copy(), arm.data.bones[n].tail_local.copy()) for n in names}


def smooth_weights(graph, weights, passes):
    """Each point's weights become the average of its own and its
    neighbours' (a few times over), so joints bend softly."""
    for _ in range(passes):
        new = {}
        for r, ws in weights.items():
            acc = dict(ws)
            n = 1.0
            for y in graph.adj.get(r, {}):
                if y in weights:
                    for b, w in weights[y].items():
                        acc[b] = acc.get(b, 0.0) + w
                    n += 1.0
            new[r] = {b: w / n for b, w in acc.items()}
        weights = new
    return weights


def top4(ws):
    best = sorted(ws.items(), key=lambda kv: -kv[1])[:4]
    s = sum(w for _, w in best)
    return {b: w / s for b, w in best if w / s > 0.01} if s > 0 else {}


def write_weights(obj, graph, weights):
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {}
    me = obj.data
    for v in me.vertices:
        r = graph.rep.get(v.index)
        ws = weights.get(r)
        if not ws:
            continue
        for b, w in ws.items():
            if b not in groups:
                groups[b] = obj.vertex_groups.new(name=b)
            groups[b].add([v.index], w, "REPLACE")


def body_weights(obj, arm):
    """Each point of the body goes to the bones nearest it round the skin
    (not through the air: a hand hanging by a thigh keeps off it)."""
    names = [b.name for b in arm.data.bones if b.use_deform and not b.name.startswith(WING_PREFIXES)
             and (MODEL == "walk" or not b.name.startswith(FAN_PREFIX))]
    segs = segments(arm, names)
    g = Graph(obj)
    reps = list(g.P)
    dist = {}
    for n, (h, t) in segs.items():
        near = [(seg_dist(g.P[r], h, t)[0], r) for r in reps]
        dmin = min(d for d, r in near)
        seeds = {r: d for d, r in near if d <= dmin + 0.02}
        d, _ = g.dijkstra(None, start=seeds)
        dist[n] = d
    weights = {}
    for r in reps:
        cand = [(dist[n].get(r, 1e9), n) for n in names]
        best = min(c[0] for c in cand)
        ws = {n: 1.0 / (d + 0.012) ** 4 for d, n in cand if d < best + SHARE}
        weights[r] = top4(ws)
    weights = smooth_weights(g, weights, SMOOTH)
    weights = {r: top4(ws) for r, ws in weights.items()}
    write_weights(obj, g, weights)
    log("body weights:", len(reps), "points,", len(names), "bones")


def near_weights(obj, arm, pick, passes=2, root_bone=None, root_reach=0.0, root_at=None):
    """Weights by straight distance to the bones `pick(side)` chooses, for
    the wings and the flier's tail: the feathers between two bones are
    shared between them (by the fourth power of the distance)."""
    g = Graph(obj)
    weights = {}
    cache = {}
    for r, p in g.P.items():
        side = "_r" if p.x >= 0 else "_l"
        if side not in cache:
            cache[side] = segments(arm, pick(side))
        segs = cache[side]
        cand = sorted(((seg_dist(p, h, t)[0], n) for n, (h, t) in segs.items()))[:4]
        ws = {n: 1.0 / (d + 0.02) ** 4 for d, n in cand}
        if root_bone and root_at is not None:
            at = root_at(side)
            d = (p - at).length
            if d < root_reach:
                # Where it joins the body it holds to the body.
                share = (1.0 - d / root_reach) ** 2
                tot = sum(ws.values())
                ws = {n: w / tot * (1.0 - share) for n, w in ws.items()}
                ws[root_bone(side)] = ws.get(root_bone(side), 0.0) + share
        weights[r] = top4(ws)
    weights = smooth_weights(g, weights, passes)
    weights = {r: top4(ws) for r, ws in weights.items()}
    write_weights(obj, g, weights)
    log("%s weights:" % obj.name, len(g.P), "points")


def skin(parts, arm):
    body_weights(parts["body"], arm)
    wing_bones = lambda side: [b.name for b in arm.data.bones if b.name.startswith(WING_PREFIXES) and side in b.name and b.name != "wing_root" + side]
    shoulder = lambda side: arm.data.bones["wing_upper" + side].head_local
    near_weights(parts["wings"], arm, wing_bones, root_bone=lambda side: "wing_root" + side, root_reach=0.22, root_at=shoulder)
    if "tail" in parts:
        fan = lambda side: [b.name for b in arm.data.bones if b.name.startswith(FAN_PREFIX)] + ["tail2"]
        near_weights(parts["tail"], arm, fan)
    for obj in parts.values():
        mod = obj.modifiers.new("armature", "ARMATURE")
        mod.object = arm
        obj.parent = arm


# --- Joint limits -----------------------------------------------------------------

def add_limits(rig):
    """Limit Rotation on every hinge (local space): it closes up to its
    HINGES limit, never opens past straight, and hardly turns other ways."""
    arm = rig.obj
    for name, h in rig.hinge.items():
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        kind = h["kind"]
        most = HINGES.get(kind if kind in HINGES else "finger", 100)
        rest = h["rest"]
        c = pb.constraints.new("LIMIT_ROTATION")
        c.owner_space = "LOCAL"
        c.use_limit_x = c.use_limit_y = c.use_limit_z = True
        if kind == "foot":
            # The ankle: either way from where it is, but not past straight.
            c.min_x, c.max_x = math.radians(max(-rest, -45.0)), math.radians(45.0)
        else:
            c.min_x = math.radians(-rest)
            c.max_x = math.radians(most - rest)
        twist = 6.0 if kind in ("finger", "toe") else 4.0
        c.min_y, c.max_y = math.radians(-twist), math.radians(twist)
        c.min_z, c.max_z = math.radians(-twist), math.radians(twist)
        pb["hinge_rest_deg"] = rest
        pb["hinge_close_deg"] = most
    for pb in arm.pose.bones:
        if pb.name not in rig.hinge:
            pb.rotation_mode = "QUATERNION"


def raise_head(arm, parts, look_down):
    """The flier's head (pitched down with its body) is lifted until the beak
    points `look_down` degrees below level, and that becomes its rest pose.
    The neck and head share the turn."""
    share = {"neck1": 0.3, "neck2": 0.35, "head": 0.35}

    def beak_pitch(total):
        for n, k in share.items():
            pb = arm.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            # About the bone's X: across the body, so it nods.
            pb.rotation_quaternion = Quaternion(Vector((1, 0, 0)), math.radians(total * k))
        bpy.context.view_layer.update()
        h = arm.matrix_world @ arm.pose.bones["head"].head
        t = arm.matrix_world @ arm.pose.bones["head"].tail
        d = (t - h).normalized()
        return math.degrees(math.asin(max(-1.0, min(1.0, d.z))))

    want = -look_down
    lo, hi = -120.0, 120.0
    # (The pitch rises or falls steadily with the turn: halve the bracket.)
    rising = beak_pitch(10.0) > beak_pitch(-10.0)
    for _ in range(40):
        mid = (lo + hi) / 2
        if (beak_pitch(mid) < want) == rising:
            lo = mid
        else:
            hi = mid
    total = (lo + hi) / 2
    log("fly: head raised", round(total, 1), "degrees; beak pitch", round(beak_pitch(total), 1))
    for obj in parts.values():
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="armature")
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in parts.values():
        mod = obj.modifiers.new("armature", "ARMATURE")
        mod.object = arm


if __name__ == "__main__":
    bpy.ops.wm.open_mainfile(filepath=os.path.join(SRC, "prep_%s.blend" % MODEL))
    parts = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
    rig, j = build(parts)
    log("bones", len(rig.obj.data.bones))
    stick_render(rig, parts, MODEL)
    skin(parts, rig.obj)
    add_limits(rig)
    if MODEL == "fly":
        # (The beak points down-ahead once the body is level; this lifts it.)
        raise_head(rig.obj, parts, 12.0)
    with open(os.path.join(OUT, "raven_%s_hinges.json" % MODEL), "w") as f:
        json.dump(rig.hinge, f, indent=1)
    out = os.path.join(OUT, "raven_%s.blend" % MODEL)
    bpy.ops.wm.save_as_mainfile(filepath=out)
    log("saved", out)
