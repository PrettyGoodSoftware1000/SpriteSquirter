"""Rigs the owner's Meshy raven for the game, with finger bones.

Run from the project folder:
    blender -b --factory-startup --python tools/raven_rig.py [-- render_dir]

Reads:
    assets/creature/RavenMeshyRig.glb   the owner's Meshy model and rig
                                        (Nov 2026), unchanged

Writes:
    assets/creature/raven.blend         the rig to look at, edit and animate:
                                        the model's own size (1.7 m), bones
                                        lying along the limbs
    assets/creature/raven.glb           what the game loads: the same rig 8
                                        times as big (13.6 m, like the old
                                        raven), every bone pointing up with
                                        no roll, which is what the game's
                                        procedural animation expects (see
                                        creature.gd), and the texture

What it changes from Meshy's rig:
    Names       the bones get the game's names (pelvis, spine, chest, neck,
                head, arm_upper_l, thigh_r, tail1 ...; see NAMES). As with
                the other creatures, "_l" is the -X side and "_r" the +X.
    Fingers     Meshy gave each hand one bone for all three fingers and a
                thumb bone hung from the upper arm. Each hand now has a
                thumb and three fingers (index, middle, ring, front to
                back), three bones each (knuckle, middle, claw), found from
                the mesh: each finger is followed from its claw tip back to
                where it joins the palm, its bones run down its middle, and
                its skin is weighted along them with soft joints.
    Symmetry    Meshy's rig was lopsided: the -X wing had one chain of
                bones where the +X has two, so its long feathers were bound
                to the shoulder, the arm and even the fingers. The +X side
                is now mirrored onto the -X side, bones and skin weights
                both (the mesh is symmetric to about a millimetre).
    Wings       a "wing" bone (no skin of its own) at the shoulder carries
                the wing, so the game can beat the wings without swinging
                the arms, which hang from the same joint. Each wing is a fan
                of ten bones (see "Wings" below), which the game opens out
                wide to fly.
    Legs        the thighs hang from the pelvis (Meshy hung them from the
                middle of the spine).

Blender space: +Z up, the raven faces -Y.
"""
import bpy, sys, os, math, heapq
from mathutils import Vector, Matrix, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets", "creature"))
SRC = os.path.join(ASSETS, "RavenMeshyRig.glb")
OUT_BLEND = os.path.join(ASSETS, "raven.blend")
OUT_GLB = os.path.join(ASSETS, "raven.glb")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER_DIR = ARGS[0] if ARGS else None
GAME_SCALE = 8.0

# Meshy's bones on the +X side and the middle, and their new names. The -X
# side's bones are thrown away and made again as mirrors of these.
NAMES = {
    "Bone_000": "pelvis", "Bone_001": "spine_lower", "Bone_003": "spine", "Bone_002": "spine_upper",
    "Bone_009": "chest", "Bone_008": "chest_upper", "Bone_021": "neck", "Bone_020": "head",
    "Bone_007": "tail1", "Bone_006": "tail2", "Bone_005": "tail3", "Bone_004": "tail4",
    "Bone_024": "clavicle_r", "Bone_023": "shoulder_r", "Bone_022": "wing_root_r",
    "Bone_038": "arm_upper_r", "Bone_052": "arm_lower_r", "Bone_051": "hand_r",
    "Bone_041": "wing_inner1_r", "Bone_040": "wing_inner2_r", "Bone_039": "wing_inner3_r",
    "Bone_044": "wing_outer1_r", "Bone_043": "wingtip_r", "Bone_042": "wing_outer3_r",
    "Bone_014": "thigh_r", "Bone_013": "shin_r", "Bone_012": "foot_r", "Bone_011": "foot_ball_r",
    "Bone_010": "toe_root_r", "Bone_030": "toe_back1_r", "Bone_029": "toe_back2_r", "Bone_028": "toe_back3_r",
    "Bone_032": "toe_front1_r", "Bone_031": "toe_front2_r",
}
# Meshy's finger bones on the +X hand (replaced by the new fingers).
OLD_FINGERS = ["Bone_050", "Bone_049", "Bone_055", "Bone_054", "Bone_053"]
# Front (-Y) to back; the thumb is found first, as the tip nearest the front.
FINGERS = ["thumb", "index", "middle", "ring"]
# Where along each finger (0 knuckle, 1 claw tip) its three bones start.
JOINTS = {"thumb": (0.0, 0.42, 0.7), "index": (0.0, 0.38, 0.66), "middle": (0.0, 0.38, 0.66), "ring": (0.0, 0.38, 0.66)}
WELD = 0.0015      # points this close are the same point (Meshy splits the mesh along its UV seams)
BAND = 0.01        # half width of the slices a finger is followed by
STEP = 0.005
JOINT_BLEND = 0.007
SAME_FINGER = 0.06 # see the claw tips below


def log(*a):
    print("RAVEN", *a)


# --- Load ---------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.data.objects):
    if o.type not in ('ARMATURE', 'MESH') or o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
ob = next(o for o in bpy.data.objects if o.type == 'MESH')
arm.name = arm.data.name = "Raven"
ob.name = "RavenMesh"
me = ob.data


def weights_of(v):
    return {ob.vertex_groups[g.group].name: g.weight for g in v.groups}


def set_weights(vi, ws):
    for g in list(me.vertices[vi].groups):
        ob.vertex_groups[g.group].remove([vi])
    for n, w in ws.items():
        if w > 1e-4:
            if n not in ob.vertex_groups:
                ob.vertex_groups.new(name=n)
            ob.vertex_groups[n].add([vi], w, 'REPLACE')


# --- Names ----------------------------------------------------------------------
for old, new in NAMES.items():
    arm.data.bones[old].name = new
    if old in ob.vertex_groups:
        ob.vertex_groups[old].name = new
    elif new not in ob.vertex_groups:
        ob.vertex_groups.new(name=new)

# --- Fingers (on the +X hand) -----------------------------------------------------
HAND_FAMILY = ["hand_r"] + OLD_FINGERS
hand_w = {}
for v in me.vertices:
    if v.co.x <= 0.0:
        continue
    ws = weights_of(v)
    w = sum(ws.get(n, 0.0) for n in HAND_FAMILY)
    if w > 0.3:
        hand_w[v.index] = w
hand = list(hand_w)
kd = kdtree.KDTree(len(hand))
for k in hand:
    kd.insert(me.vertices[k].co, k)
kd.balance()
rep = {}
for k in hand:
    if k in rep:
        continue
    for co, j, d in kd.find_range(me.vertices[k].co, WELD):
        rep.setdefault(j, k)
reps = sorted(set(rep.values()))
P = {r: me.vertices[r].co.copy() for r in reps}
adj = {r: {} for r in reps}
for e in me.edges:
    a, b = e.vertices
    if a in rep and b in rep:
        ra, rb = rep[a], rep[b]
        if ra != rb:
            d = (P[ra] - P[rb]).length
            adj[ra][rb] = d
            adj[rb][ra] = d


def dijkstra(seeds):
    dist = {s: 0.0 for s in seeds}
    prev = {}
    heap = [(0.0, s) for s in seeds]
    while heap:
        d, x = heapq.heappop(heap)
        if d > dist.get(x, 1e9):
            continue
        for y, w in adj[x].items():
            nd = d + w
            if nd < dist.get(y, 1e9):
                dist[y] = nd
                prev[y] = x
                heapq.heappush(heap, (nd, y))
    return dist, prev


ztop = max(P[r].z for r in reps)
seeds = [r for r in reps if P[r].z > ztop - 0.02]
dw, prev = dijkstra(seeds)
reps = [r for r in reps if r in dw]


def band_component(level, start):
    inside = {r for r in reps if abs(dw[r] - level) <= BAND}
    if start not in inside:
        return set()
    seen = {start}
    stack = [start]
    while stack:
        x = stack.pop()
        for y in adj[x]:
            if y in inside and y not in seen:
                seen.add(y)
                stack.append(y)
    return seen


# Claw tips: the points furthest round the hand from the wrist (the palm's
# bumps are much nearer). A finger can end in more than one: the ring
# finger's claw hooks round past the end of the finger. Tips whose branches
# meet well before the palm (within SAME_FINGER of the nearer tip) are one
# finger's.
def path_of(t):
    out = [t]
    while out[-1] in prev:
        out.append(prev[out[-1]])
    return out


paths = {}
cands = []
for r in sorted(reps, key=lambda r: -dw[r]):
    if any((P[r] - P[t]).length < 0.025 for t in cands):
        continue
    if all(dw[y] <= dw[r] for y in reps if (P[y] - P[r]).length < 0.03):
        cands.append(r)
cands = [c for c in cands if dw[c] > 0.5 * dw[cands[0]]]
for c in cands:
    paths[c] = path_of(c)


def components_at(level, tips_here):
    """The slice at `level` through the branches that end in `tips_here`."""
    out = set()
    for t in tips_here:
        if dw[t] < level - BAND:
            continue
        start = min(paths[t], key=lambda r: abs(dw[r] - level))
        out |= band_component(level, start)
    return out


def meet(a, b):
    """The level (distance from the wrist) where b's branch joins a's."""
    level = dw[a] - BAND
    while level > 0.0:
        if components_at(level, [a]) & set(paths[b]):
            return level
        level -= STEP
    return 0.0


group = {c: c for c in cands}
for i, x in enumerate(cands):
    for y in cands[i + 1:]:
        if meet(x, y) >= min(dw[x], dw[y]) - SAME_FINGER:
            gy = group[y]
            for k in group:
                if group[k] == gy:
                    group[k] = group[x]
digits = {}
for c in cands:
    digits.setdefault(group[c], []).append(c)
log("tips", [[(tuple(round(v, 3) for v in P[t]), round(dw[t], 3)) for t in d] for d in digits.values()])
assert len(digits) == 4, len(digits)

traced = []
for own in digits.values():
    t = max(own, key=lambda r: dw[r])
    others = set()
    for o in cands:
        if o not in own:
            others.update(paths[o])
    levels = []
    level = dw[t] - 0.5 * BAND
    while level > 0.0:
        comp = components_at(level, own)
        if not comp or comp & others:
            break
        main = components_at(level, [t])
        levels.append((level, comp, main))
        level -= STEP
    assert len(levels) > 4, P[t]
    knuckle_dw = levels[-1][0]
    # The middle of the finger (along its longest branch), from the knuckle
    # out to the claw tip.
    line = [sum((P[r] for r in main), Vector()) / len(main) for level, comp, main in reversed(levels)]
    line.append(P[t])
    # The knuckle sits a little further into the palm than the web between
    # the fingers.
    back = (line[0] - line[min(3, len(line) - 1)]).normalized()
    line.insert(0, line[0] + back * 0.015)
    arc = [0.0]
    for i in range(1, len(line)):
        arc.append(arc[-1] + (line[i] - line[i - 1]).length)
    traced.append({"tip": t, "levels": levels, "knuckle_dw": knuckle_dw, "line": line, "arc": arc})
# The thumb is the shortest; the fingers then run front (-Y) to back.
traced.sort(key=lambda f: f["arc"][-1])
traced = traced[:1] + sorted(traced[1:], key=lambda f: f["line"][0].y)
finger = {}
for name, f in zip(FINGERS, traced):
    finger[name] = f
    log(name, "length", round(f["arc"][-1], 3), "knuckle", tuple(round(c, 3) for c in f["line"][0]),
        "tip", tuple(round(c, 3) for c in P[f["tip"]]), "slices", len(f["levels"]))


def at_arc(f, a):
    line, arc = f["line"], f["arc"]
    a = min(max(a, 0.0), arc[-1])
    for i in range(1, len(arc)):
        if arc[i] >= a:
            u = (a - arc[i - 1]) / max(arc[i] - arc[i - 1], 1e-9)
            return line[i - 1].lerp(line[i], u)
    return line[-1].copy()


# Bones: three for each finger, hung from the hand.
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for name, f in finger.items():
    total = f["arc"][-1]
    starts = [s * total for s in JOINTS[name]] + [total]
    f["joints"] = starts
    pts = [at_arc(f, s) for s in starts]
    # The finger curls about the normal of the plane it bends in.
    curl = Vector()
    line = f["line"]
    for i in range(1, len(line) - 1):
        curl += (line[i] - line[i - 1]).cross(line[i + 1] - line[i])
    if curl.length < 1e-6:
        curl = (pts[-1] - pts[0]).cross(Vector((0, 1, 0)))
    curl.normalize()
    f["curl"] = curl
    parent = eb["hand_r"]
    for i in range(3):
        b = eb.new("%s%d_r" % (name, i + 1))
        b.head, b.tail = pts[i], pts[i + 1]
        b.align_roll(curl.cross((b.tail - b.head).normalized()))
        b.parent = parent
        b.use_connect = i > 0
        b.use_deform = True
        parent = b
bpy.ops.object.mode_set(mode='OBJECT')


# Weights: the finger's share of each point's hand weight goes along its
# bones, blended across the joints; the palm keeps the hand.
def ramp(x, edge):
    return min(max((x - edge) / (2 * JOINT_BLEND) + 0.5, 0.0), 1.0)


new_w = {}
for name, f in finger.items():
    levels = f["levels"]
    # Each point's place along the finger: the slice it is in, measured
    # along the middle line.
    level_arc = {}
    for i, (level, comp, main) in enumerate(reversed(levels)):
        level_arc[level] = f["arc"][i + 1]
    for level, comp, main in levels:
        for r in comp:
            if r in new_w and abs(new_w[r][1] - dw[r]) <= abs(level - dw[r]):
                continue
            new_w[r] = (name, level, level_arc[level])
# Spread the weld groups back to every point.
members = {}
for k, r in rep.items():
    members.setdefault(r, []).append(k)
for r, (name, level, a) in new_w.items():
    j = finger[name]["joints"]
    w2 = ramp(a, j[1])
    w3 = ramp(a, j[2])
    w1 = 1.0 - w2
    w2 = w2 - w3
    # Into the palm: a soft knuckle.
    knuckle = min(max(a / 0.02, 0.0), 1.0) * 0.6 + 0.4
    for k in members[r]:
        ws = weights_of(me.vertices[k])
        share = sum(ws.pop(n, 0.0) for n in HAND_FAMILY)
        ws["hand_r"] = share * (1.0 - knuckle)
        ws["%s1_r" % name] = share * knuckle * w1
        ws["%s2_r" % name] = share * knuckle * w2
        ws["%s3_r" % name] = share * knuckle * w3
        set_weights(k, ws)
# Every other point Meshy's finger bones held goes to the hand.
for v in me.vertices:
    if v.co.x <= 0.0:
        continue
    ws = weights_of(v)
    moved = sum(ws.pop(n, 0.0) for n in OLD_FINGERS)
    if moved > 0.0:
        ws["hand_r"] = ws.get("hand_r", 0.0) + moved
        set_weights(v.index, ws)
log("finger points", sum(len(members[r]) for r in new_w))

# --- Wings: a fan of bones ---------------------------------------------------------
# Meshy's outer wing chain ran down the wing's outer edge, so the wing could
# only swing as one stiff piece. It is replaced by a wing built like a
# bird's: an upper arm and a forearm along the leading edge to the wrist,
# three primary feathers fanning from the wrist (two bones each, so their
# tips can trail a wingbeat) and two secondaries hanging from the arm. The
# game opens the fan to fly (see creature.gd, "wing_spread"). Meshy's inner
# chain (the feathers hanging down the back of the arm) stays. Points are
# (x, z) on the +X wing; each bone lies in the middle of the wing's
# thickness there.
OLD_WING = ["wing_outer1_r", "wingtip_r", "wing_outer3_r"]
WING_POINTS = {
    "shoulder": None,           # the wing's root (Meshy's wing joint)
    "elbow": (0.80, 1.28), "wrist": (1.00, 1.05),
    "prim1": (1.07, 0.55), "prim2": (0.93, 0.20), "prim3": (0.80, 0.20),
    "sec1": (0.62, 0.62), "sec2": (0.72, 0.50),
}
# name: (head, tail, parent, connected); "mid:a:b" is halfway from a to b.
WING_BONES = [
    ("wing_arm1", "shoulder", "elbow", "wing", False),
    ("wing_arm2", "elbow", "wrist", "wing_arm1", True),
    ("wing_prim1a", "wrist", "mid:wrist:prim1", "wing_arm2", False),
    ("wing_prim1b", "mid:wrist:prim1", "prim1", "wing_prim1a", True),
    ("wing_prim2a", "wrist", "mid:wrist:prim2", "wing_arm2", False),
    ("wing_prim2b", "mid:wrist:prim2", "prim2", "wing_prim2a", True),
    ("wing_prim3a", "wrist", "mid:wrist:prim3", "wing_arm2", False),
    ("wing_prim3b", "mid:wrist:prim3", "prim3", "wing_prim3a", True),
    ("wing_sec1", "mid:shoulder:elbow", "sec1", "wing_arm1", False),
    ("wing_sec2", "elbow", "sec2", "wing_arm2", False),
]
wing_verts = [v.index for v in me.vertices if v.co.x > 0.0
              and sum(weights_of(v).get(n, 0.0) for n in OLD_WING) > 0.0]
WING_POINTS["shoulder"] = tuple(arm.data.bones["wing_root_r"].head_local.xz)


def on_wing(xz):
    near = [me.vertices[i].co for i in wing_verts
            if (Vector((me.vertices[i].co.x, me.vertices[i].co.z)) - Vector(xz)).length < 0.06]
    y = sum(c.y for c in near) / len(near) if near else arm.data.bones["wing_root_r"].head_local.y
    return Vector((xz[0], y, xz[1]))


def wing_point(key):
    if key.startswith("mid:"):
        a, b = key.split(":")[1:]
        return (wing_point(a) + wing_point(b)) * 0.5
    return on_wing(WING_POINTS[key])


log("wing points", len(wing_verts))

# --- Bones: wings, legs, and the -X side mirrored from the +X ----------------------
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for n in OLD_FINGERS:
    eb.remove(eb[n])
for b in list(eb):
    if b.name.startswith("Bone_"):
        eb.remove(b)
eb["thigh_r"].use_connect = False
eb["thigh_r"].parent = eb["pelvis"]
root = eb["wing_root_r"]
wing = eb.new("wing_r")
wing.head = root.head.copy()
wing.tail = root.head + (eb["wing_outer1_r"].head - root.head).normalized() * 0.12
wing.align_roll(Vector((0, -1, 0)))
wing.parent = root
wing.use_deform = False
eb["wing_inner1_r"].use_connect = False
eb["wing_inner1_r"].parent = wing
for n in OLD_WING:
    eb.remove(eb[n])
for name, head, tail, parent, connected in WING_BONES:
    b = eb.new(name + "_r")
    b.head, b.tail = wing_point(head), wing_point(tail)
    # (X across the wing, Z out of its face: the fan opens about Z.)
    b.align_roll(Vector((0, -1, 0)))
    b.parent = eb[parent + "_r"]
    b.use_connect = connected
    b.use_deform = True


def flip(n):
    return n[:-2] + "_l" if n.endswith("_r") else n


right = [b for b in eb if b.name.endswith("_r")]
made = {}
for b in right:
    m = eb.new(flip(b.name))
    m.head = Vector((-b.head.x, b.head.y, b.head.z))
    m.tail = Vector((-b.tail.x, b.tail.y, b.tail.z))
    m.roll = -b.roll
    m.use_deform = b.use_deform
    made[b.name] = (m, b)
for n, (m, b) in made.items():
    if b.parent is not None:
        m.parent = eb[flip(b.parent.name)]
        m.use_connect = b.use_connect
bpy.ops.object.mode_set(mode='OBJECT')
log("bones", len(arm.data.bones))

# The wing's skin: what Meshy's outer chain held is shared among the new
# bones, most to the nearest (by the fourth power of the distance), so the
# feathers between two bones fan out between them.
def segment_distance(p, h, t):
    d = t - h
    u = min(max((p - h).dot(d) / max(d.length_squared, 1e-9), 0.0), 1.0)
    return (p - (h + d * u)).length


segments = [(name + "_r", arm.data.bones[name + "_r"].head_local, arm.data.bones[name + "_r"].tail_local)
            for name, *_ in WING_BONES]
for i in wing_verts:
    v = me.vertices[i]
    ws = weights_of(v)
    share = sum(ws.pop(n, 0.0) for n in OLD_WING)
    near = sorted(((1.0 / (segment_distance(v.co, h, t) + 0.01) ** 4, n) for n, h, t in segments), reverse=True)[:3]
    total = sum(w for w, n in near)
    for w, n in near:
        ws[n] = ws.get(n, 0.0) + share * w / total
    set_weights(i, ws)

# Skin weights on the -X side: the +X side's, mirrored.
plus = [v.index for v in me.vertices if v.co.x >= 0.0]
kdp = kdtree.KDTree(len(plus))
for i in plus:
    kdp.insert(me.vertices[i].co, i)
kdp.balance()
plus_w = {i: weights_of(me.vertices[i]) for i in plus}
for v in me.vertices:
    if v.co.x >= 0.0:
        continue
    m = Vector((-v.co.x, v.co.y, v.co.z))
    total = {}
    norm = 0.0
    for co, j, d in kdp.find_n(m, 4):
        w = 1.0 / (d + 1e-4) ** 2
        norm += w
        for n, x in plus_w[j].items():
            total[flip(n)] = total.get(flip(n), 0.0) + w * x
    set_weights(v.index, {n: x / norm for n, x in total.items()})
for g in list(ob.vertex_groups):
    if g.name not in arm.data.bones:
        ob.vertex_groups.remove(g)
# At most four bones a point (what the game reads), adding up to one.
for v in me.vertices:
    ws = sorted(weights_of(v).items(), key=lambda kv: -kv[1])[:4]
    s = sum(w for n, w in ws)
    set_weights(v.index, {n: w / s for n, w in ws} if s > 0 else {"pelvis": 1.0})
for o in bpy.data.objects:
    for mod in getattr(o, "modifiers", []):
        if mod.type == 'ARMATURE':
            mod.object = arm

# --- Look at it -------------------------------------------------------------------
def render(tag, curl=0.0):
    """Hands from the front and the side, fingers curled by `curl` radians a
    joint, with the bones drawn as thin sticks."""
    if not RENDER_DIR:
        return
    os.makedirs(RENDER_DIR, exist_ok=True)
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = (0, 0, 0)
        for f in FINGERS:
            if pb.name.startswith(f):
                pb.rotation_euler = (curl, 0, 0)
    bpy.context.view_layer.update()
    sticks = []
    for pb in arm.pose.bones:
        if not any(pb.name.startswith(f) for f in FINGERS) and not pb.name.startswith("hand"):
            continue
        h = arm.matrix_world @ pb.head
        t = arm.matrix_world @ pb.tail
        bpy.ops.mesh.primitive_cylinder_add(radius=0.0035, depth=(t - h).length, location=(h + t) / 2)
        c = bpy.context.active_object
        c.rotation_euler = (t - h).to_track_quat('Z', 'Y').to_euler()
        c.show_in_front = True
        sticks.append(c)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.display.shading.show_xray = True
    sc.display.shading.xray_alpha = 0.6
    sc.render.resolution_x = sc.render.resolution_y = 640
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cd.type = 'ORTHO'
    cd.ortho_scale = 0.5
    for side, sx in (("r", 1), ("l", -1)):
        c = Vector((0.48 * sx, -0.24, 0.6))
        for view, d in (("front", (0, 1, 0)), ("out", (-sx, 0, 0)), ("below", (0, 0.3, 1))):
            d = Vector(d).normalized()
            cam.location = c - d * 3
            cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(RENDER_DIR, "hand_%s_%s_%s.png" % (side, view, tag))
            bpy.ops.render.render(write_still=True)
    sc.display.shading.show_xray = False
    for view, d, c, s in (("body_front", (0, 1, 0), (0, 0, 0.85), 2.4), ("body_back", (0, -1, 0), (0, 0, 0.85), 2.4)):
        d = Vector(d).normalized()
        cd.ortho_scale = s
        cam.location = Vector(c) - d * 5
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(RENDER_DIR, "%s_%s.png" % (view, tag))
        bpy.ops.render.render(write_still=True)
    for o in sticks:
        bpy.data.objects.remove(o)
    bpy.data.objects.remove(cam)
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)


render("rest")
render("curled", 0.6)
render("open", -0.35)

# --- Save the rig -------------------------------------------------------------------
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
log("saved", OUT_BLEND)

# --- The game's copy: 8 times as big, every bone pointing up ---------------------------
me.transform(Matrix.Scale(GAME_SCALE, 4))
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for b in arm.data.edit_bones:
    b.use_connect = False
for b in arm.data.edit_bones:
    length = (b.tail - b.head).length * GAME_SCALE
    b.head = b.head * GAME_SCALE
    b.tail = b.head + Vector((0, 0, max(length, 0.1)))
    b.roll = 0.0
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', export_animations=False,
                          export_def_bones=False, export_materials='EXPORT')
log("exported", OUT_GLB)
