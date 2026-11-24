"""Builds the newer balrog's animations in Blender.

Run from the project folder:
    blender -b --factory-startup --python tools/newer_balrog_anims.py [-- render_dir]

Writes:
    assets/test/NewerBalrog.blend      the model and its actions, to look at
                                       and edit (its textures are the PNGs
                                       next to it, not packed in)
    assets/test/NewerBalrog_anims.glb  the skeleton, the skinned mesh (with
                                       the chain fix below, no materials) and
                                       the clips, for Godot

Actions:
    Walk        the first walk: 1.8 s for two steps
    WalkTwo     "walk two": a longer stride (2.27 s for two steps, the same
                speed), a slower, gentler leg lift, and the torso turning
                with each step
    ClawSlash   the left claw raised and swiped down and across, the torso
                twisting into it, flowing into the same with the right claw

The walks are made in place (the game moves the body) and travel SPEED
metres a second at the model's own size (1.7 m tall), so a clip played at
that speed keeps its planted hooves still. Each frame is solved here and
keyed, so the clips play in Blender and Godot without constraints.

The chain fix: the chain belt round the waist (it hangs over the backs of
the thighs) was skinned partly to the thighs and tail, so it stretched with
every step. Its links now all follow the hips (with a little of the lower
back), so the chain moves as one piece and its texture does not stretch.

Blender space: +Z up, the balrog faces -Y, its right side is -X.
"""
import bpy, sys, math, os
import numpy as np
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets", "test"))
GLB = os.path.join(ASSETS, "NewerBalrog.glb")
OUT_BLEND = os.path.join(ASSETS, "NewerBalrog.blend")
OUT_GLB = os.path.join(ASSETS, "NewerBalrog_anims.glb")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER_DIR = ARGS[0] if ARGS else None

FPS = 30
SPEED = 0.341   # metres a second at model size, for both walks

# --- Load ---------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.gltf(filepath=GLB)
scene = bpy.context.scene
scene.render.fps = FPS
for o in list(bpy.data.objects):
    if o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh_obj = next(o for o in bpy.data.objects if o.type == 'MESH')


def pixels(name):
    img = bpy.data.images[name]
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4), w, h


def set_weights(i, weights):
    """Gives point i these weights (at most 4, as glTF keeps, summing to 1)."""
    vg = mesh_obj.vertex_groups
    m = mesh_obj.data
    top = sorted(((b, w) for b, w in weights.items() if w > 0.005), key=lambda kv: -kv[1])[:4]
    total = sum(w for _, w in top) or 1.0
    for g in list(m.vertices[i].groups):
        vg[g.group].remove([i])
    for b, w in top:
        vg[b].add([i], w / total, 'REPLACE')


# --- The chain fix ------------------------------------------------------------------
# Chain faces: shiny (metal map), silver rather than gold (little colour),
# at belt height, and skinned to a thigh or the tail.
def fix_chains():
    m = mesh_obj.data
    mr, w, h = pixels("texture_0_metallic_roughness")
    col, _, _ = pixels("texture_0")
    uv = m.uv_layers.active.data
    groups = {g.index: g.name for g in mesh_obj.vertex_groups}
    pulled = {"Bone_016", "Bone_021", "Bone_015", "Bone_020", "Bone_009", "Bone_008"}
    verts = set()
    for p in m.polygons:
        c = mesh_obj.matrix_world @ p.center
        # (The back half only: the chains over the backs of the thighs. The
        # straps down the front of the hips keep Meshy's weights.)
        if not (0.62 < c.z < 0.9 and abs(c.x) < 0.45 and c.y > -0.12):
            continue
        uvs = [uv[li].uv for li in p.loop_indices]
        pts = uvs + [sum(uvs, Vector((0, 0))) / len(uvs)]
        met, sat = [], []
        for u in pts:
            x, y = min(w - 1, int(u[0] * w)), min(h - 1, int(u[1] * h))
            met.append(mr[y, x, 2])
            rgb = col[y, x, :3]
            sat.append((rgb.max() - rgb.min()) / max(rgb.max(), 1e-3))
        if np.mean(met) <= 0.4 or np.mean(sat) >= 0.35:
            continue
        bones = {groups[g.group] for vi in p.vertices for g in m.vertices[vi].groups if g.weight > 0.02}
        if bones & pulled:
            verts.update(p.vertices)
    hips = mesh_obj.vertex_groups["Bone_001"]
    back = mesh_obj.vertex_groups["Bone_003"]
    for vi in verts:
        for g in list(m.vertices[vi].groups):
            mesh_obj.vertex_groups[g.group].remove([vi])
        hips.add([vi], 0.7, 'REPLACE')
        back.add([vi], 0.3, 'REPLACE')
    print("CHAIN fix: %d vertices now follow the hips" % len(verts))


fix_chains()


# --- The shoulder fix ---------------------------------------------------------------
# The shoulders (and their armour) were skinned partly to the wing bones as
# well as the chest, collarbone and upper arm, so whenever a wing moved on
# its own it dragged the shoulder with it and the skin there stretched (up
# to 5x in the claw slash). Shoulder and arm vertices now leave the wings
# alone: their wing share goes to the collarbone.
def fix_shoulders():
    m = mesh_obj.data
    vg = mesh_obj.vertex_groups
    names = {g.index: g.name for g in vg}
    sides = {
        "L": (("Bone_033", "Bone_034", "Bone_032"), ("Bone_038", "Bone_037", "Bone_036", "Bone_035"), "Bone_034"),
        "R": (("Bone_028", "Bone_029", "Bone_027"), ("Bone_042", "Bone_041", "Bone_040", "Bone_039"), "Bone_029"),
    }
    moved = 0
    for v in m.vertices:
        w = {names[g.group]: g.weight for g in v.groups}
        for arm_bones, wing_bones, collar in sides.values():
            arm_w = sum(w.get(b, 0.0) for b in arm_bones)
            wing_w = sum(w.get(b, 0.0) for b in wing_bones)
            # (Only where the arm outweighs the wing well: the wing's own
            # skin near the shoulder must keep following the wing.)
            if arm_w >= 0.25 and 0.0 < wing_w < 0.5 * arm_w:
                for b in wing_bones:
                    if b in w:
                        vg[b].remove([v.index])
                vg[collar].add([v.index], w.get(collar, 0.0) + wing_w, 'REPLACE')
                moved += 1
            # ...and the wing's skin leaves the arm alone: its arm share goes
            # to the wing's root.
            elif wing_w >= 0.5 and 0.0 < arm_w:
                for b in arm_bones:
                    if b in w:
                        vg[b].remove([v.index])
                vg[wing_bones[0]].add([v.index], w.get(wing_bones[0], 0.0) + arm_w, 'REPLACE')
                moved += 1
    print("SHOULDER fix: %d vertices now follow the arm or the wing, not both" % moved)


fix_shoulders()


# --- Smoother shoulders -------------------------------------------------------------
# Next to each other, some shoulder points followed the upper arm fully and
# others the chest fully, so a big swing of the arm (a claw swipe) tore the
# skin between them. Each shoulder point's weights are averaged with its
# neighbours' a few times (by distance, across the mesh's separate pieces),
# so the skin blends from chest to arm and stretches evenly, far less.
def smooth_shoulders(radius=0.04, rounds=4, amount=0.6):
    from mathutils import kdtree
    m = mesh_obj.data
    vg = mesh_obj.vertex_groups
    names = {g.index: g.name for g in vg}
    shoulder = {"Bone_033", "Bone_034", "Bone_028", "Bone_029"}
    region = [v.index for v in m.vertices
              if (mesh_obj.matrix_world @ v.co).z > 0.85
              and sum(g.weight for g in v.groups if names[g.group] in shoulder) > 0.05]
    pos = [mesh_obj.matrix_world @ m.vertices[i].co for i in range(len(m.vertices))]
    tree = kdtree.KDTree(len(pos))
    for i, p in enumerate(pos):
        tree.insert(p, i)
    tree.balance()
    weights = [{names[g.group]: g.weight for g in v.groups} for v in m.vertices]
    near = {i: [j for (_, j, _) in tree.find_range(pos[i], radius)] for i in region}
    for _ in range(rounds):
        new = {}
        for i in region:
            avg = {}
            for j in near[i]:
                for b, w in weights[j].items():
                    avg[b] = avg.get(b, 0.0) + w / len(near[i])
            mix = {b: (1 - amount) * weights[i].get(b, 0.0) + amount * avg.get(b, 0.0)
                   for b in set(avg) | set(weights[i])}
            top = sorted(mix.items(), key=lambda kv: -kv[1])[:4]     # glTF: 4 per point
            total = sum(w for _, w in top) or 1.0
            new[i] = {b: w / total for b, w in top if w > 0.005}
        for i, w in new.items():
            weights[i] = w
    for i in region:
        for g in list(m.vertices[i].groups):
            vg[g.group].remove([i])
        for b, w in weights[i].items():
            vg[b].add([i], w, 'REPLACE')
    print("SMOOTH: %d shoulder vertices blended" % len(region))


smooth_shoulders()


# --- Arm webbing ---------------------------------------------------------------------
# A few triangles join the inner arm straight to the torso (the model was
# made with its arms near its sides): one corner followed the arm and
# another the body, so any swing of the arm tore them. (0.42 deleted them,
# which left holes at the shoulders and back.) Now their corners share
# blended weights, so they stretch a little instead of tearing.
def blend_webbing():
    names = {g.index: g.name for g in mesh_obj.vertex_groups}
    arms = [{"Bone_033", "Bone_032", "Bone_031", "Bone_030"}, {"Bone_028", "Bone_027", "Bone_026", "Bone_025"}]
    m = mesh_obj.data
    weights = [{names[g.group]: g.weight for g in v.groups} for v in m.vertices]
    def arm_w(i, bones):
        return sum(w for b, w in weights[i].items() if b in bones)
    webs = [p for p in m.polygons
            if any(max(arm_w(i, b) for i in p.vertices) - min(arm_w(i, b) for i in p.vertices) > 0.45 for b in arms)]
    sums = {}
    for p in webs:
        avg = {}
        for i in p.vertices:
            for b, w in weights[i].items():
                avg[b] = avg.get(b, 0.0) + w / len(p.vertices)
        for i in p.vertices:
            acc = sums.setdefault(i, [{}, 0])
            for b, w in avg.items():
                acc[0][b] = acc[0].get(b, 0.0) + w
            acc[1] += 1
    for i, (acc, n) in sums.items():
        # Half the point's own weights, half the faces' blend.
        mix = {b: 0.5 * weights[i].get(b, 0.0) + 0.5 * acc.get(b, 0.0) / n for b in set(acc) | set(weights[i])}
        set_weights(i, mix)
    print("WEBBING: %d triangles blended (%d points)" % (len(webs), len(sums)))


blend_webbing()


# --- Welding ------------------------------------------------------------------------
# The mesh is many separate pieces whose edges lie on top of each other.
# Touching points must have the same weights, or the pieces pull apart and
# open cracks (the 0.41 chain fix did that at the waist). Each group of
# touching points gets their average.
def weld():
    from collections import defaultdict
    m = mesh_obj.data
    names = {g.index: g.name for g in mesh_obj.vertex_groups}
    spots = defaultdict(list)
    for v in m.vertices:
        spots[tuple(round(c / 1e-4) for c in v.co)].append(v.index)
    welded = 0
    for group in spots.values():
        if len(group) < 2:
            continue
        ws = [{names[g.group]: g.weight for g in m.vertices[i].groups} for i in group]
        if all(w == ws[0] for w in ws[1:]):
            continue
        avg = {}
        for w in ws:
            for b, x in w.items():
                avg[b] = avg.get(b, 0.0) + x / len(ws)
        for i in group:
            set_weights(i, avg)
        welded += 1
    print("WELD: %d groups of touching points given the same weights" % welded)


weld()

# The textures: use the PNGs Godot extracted next to the .glb instead of
# packing 55 MB of them into the .blend.
for img in list(bpy.data.images):
    path = os.path.join(ASSETS, "NewerBalrog_%s.png" % img.name)
    if os.path.exists(path):
        ext = bpy.data.images.load(path)
        ext.colorspace_settings.name = img.colorspace_settings.name
        img.user_remap(ext)
        name = img.name
        bpy.data.images.remove(img)
        ext.name = name

PB = arm.pose.bones
if arm.animation_data:
    arm.animation_data.action = None
for pb in PB:
    pb.rotation_mode = 'QUATERNION'
    pb.matrix_basis.identity()
bpy.context.view_layer.update()
MW = arm.matrix_world
MWI = MW.inverted()


def upd():
    bpy.context.view_layer.update()


def hw(n):
    return MW @ PB[n].head


def rotate_world(n, q):
    """Turns a bone by q (world axes) about its own head."""
    pb = PB[n]
    m = pb.matrix.copy()
    h = m.translation.copy()
    pb.matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ m
    upd()


def aim(n, child, target, weight=1.0, max_angle=None):
    """Swings bone n (shortest turn) so bone `child`'s head moves to target,
    turning it at most `max_angle` (radians) from where it is (the bones
    this is used on are still in their rest pose then)."""
    h = hw(n)
    a, b = hw(child) - h, target - h
    if a.length < 1e-6 or b.length < 1e-6:
        return
    q = a.normalized().rotation_difference(b.normalized())
    if max_angle is not None and q.angle > max_angle:
        # Turn less, the same way (a clamp that recomputed its axis could
        # flip it, which flicked the right hand 83 degrees in one frame).
        weight *= max_angle / q.angle
    q = Quaternion().slerp(q, weight)
    rotate_world(n, q)


def qx(a): return Quaternion((1, 0, 0), a)
def qy(a): return Quaternion((0, 1, 0), a)
def qz(a): return Quaternion((0, 0, 1), a)
def rx(v, a): return qx(a) @ Vector(v)


def smooth(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


def keys(table, u):
    """Smoothly through (u, value) keys (flat at each key: heavy, no snap)."""
    for (u0, v0), (u1, v1) in zip(table, table[1:]):
        if u <= u1:
            return v0 + (v1 - v0) * smooth((u - u0) / (u1 - u0))
    return table[-1][1]


def wave(t, lag=0.0, k=1):
    """A sine over the cycle, k times a cycle, delayed by `lag` (cycles)."""
    return math.sin(2 * math.pi * k * (t - lag))


# --- The rest pose, measured ------------------------------------------------------
LEGS = {
    # side: (thigh, shin, cannon, pastern/hoof, hoof end), phase offset
    "R": (("Bone_016", "Bone_015", "Bone_014", "Bone_013", "Bone_012"), 0.0),
    "L": (("Bone_021", "Bone_020", "Bone_019", "Bone_018", "Bone_017"), 0.5),
}
ARMS = {
    # side: (collarbone, upper arm, forearm, hand, hand end)
    "R": ("Bone_029", "Bone_028", "Bone_027", "Bone_026", "Bone_025"),
    "L": ("Bone_034", "Bone_033", "Bone_032", "Bone_031", "Bone_030"),
}
WINGS = {"R": ("Bone_042", "Bone_041", "Bone_040", "Bone_039"),
         "L": ("Bone_038", "Bone_037", "Bone_036", "Bone_035")}
SPINE = ("Bone_003", "Bone_002", "Bone_011", "Bone_010")
TAIL = ("Bone_009", "Bone_008", "Bone_007")
FLAP = ("Bone_006", "Bone_005", "Bone_004")
REST = {}
for side, (b, _) in LEGS.items():
    hip, knee, hock, fet, tip = (hw(n).copy() for n in b)
    front = Vector((tip.x, -0.37, 0.0))      # the front edge of the hoof, on the ground
    REST[side] = dict(hip=hip, knee=knee, hock=hock, fet=fet, tip=tip, front=front)
REST_HAND = {s: hw(a[3]).copy() for s, a in ARMS.items()}
REST_HEAD = (MW @ PB["Bone_023"].matrix).to_quaternion()
worst_reach = [0.0]


def reset():
    for pb in PB:
        pb.matrix_basis.identity()
    upd()


def two_bone(upper, lower, end, target, pole, weight=1.0, max_reach=0.999, min_reach=0.0):
    """Puts the end bone's head at target, the middle joint bent toward pole.
    It reaches at most `max_reach` of the limb's length (a limb snapped
    fully straight stretches the skin round its joints)."""
    if weight <= 1e-4:
        return
    s = hw(upper)
    l1 = (hw(lower) - s).length
    l2 = (hw(end) - hw(lower)).length
    target = hw(end).lerp(target, weight)
    d = target - s
    worst_reach[0] = max(worst_reach[0], d.length / (l1 + l2))
    # (Not too close either: folding the middle joint far crushes the skin.)
    dist = max(min(d.length, (l1 + l2) * max_reach), (l1 + l2) * min_reach)
    dn = d.normalized()
    cos_a = max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))
    p = pole - dn * pole.dot(dn)
    if p.length < 1e-6:
        p = Vector((0, 0, -1)) - dn * dn.z
    p.normalize()
    mid = s + dn * (l1 * cos_a) + p * (l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a)))
    aim(upper, lower, mid)
    aim(lower, end, s + dn * dist)


def hinge_arm(upper, lower, end, target, pole, weight=1.0, max_reach=0.95, min_reach=0.85):
    """Like two_bone, for an arm, without flips: the upper arm is turned so
    both its direction and the plane its elbow bends in match the solved
    pose (the shortest turn could spin the arm round its own length, and put
    the elbow on the wrong side), then the forearm bends about the elbow's
    hinge only."""
    if weight <= 1e-4:
        return
    s, e, w = hw(upper), hw(lower), hw(end)
    l1, l2 = (e - s).length, (w - e).length
    d = target - s
    dist = max(min(d.length, (l1 + l2) * max_reach), (l1 + l2) * min_reach)
    dn = d.normalized()
    cos_a = max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))
    p = pole - dn * pole.dot(dn)
    p.normalize()
    mid = s + dn * (l1 * cos_a) + p * (l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a)))
    hand = s + dn * dist

    def frame(a, b):
        x = a.normalized()
        y = a.cross(b).normalized()
        return Matrix((x, y, x.cross(y))).transposed()

    turn = frame(mid - s, hand - mid) @ frame(e - s, w - e).inverted()
    # (Blended in by weight, so the arm eases from its hanging pose.)
    rotate_world(upper, Quaternion().slerp(turn.to_quaternion(), weight))
    aim(lower, end, hand, weight)


def place_leg(side, fet, tip, hock):
    r = REST[side]
    b = LEGS[side][0]
    pole = (r["knee"] - (r["hip"] + r["hock"]) * 0.5).normalized()
    two_bone(b[0], b[1], b[2], hock, pole)
    aim(b[2], b[3], fet)
    aim(b[3], b[4], tip)


def steady_head(strength, nod=0.0):
    """Holds the head toward where it looked at rest (cancels `strength` of
    the body's turning), then nods it by `nod`."""
    for n, share in (("Bone_024", 0.5), ("Bone_023", 1.0)):
        cur = (MW @ PB["Bone_023"].matrix).to_quaternion()
        fix = Quaternion().slerp(REST_HEAD @ cur.inverted(), strength * share)
        rotate_world(n, fix @ (qx(nod) if n == "Bone_023" else Quaternion()))


# --- Walks ----------------------------------------------------------------------------
WALK_ONE = dict(
    name="Walk", duty=0.62, sweep=0.38, sink=0.014,
    heel_from=0.62, heel=0.75,
    swing_y=[(0, 0.0), (0.15, 0.06), (0.75, 0.9), (1, 1.0)],
    swing_z=[(0, 0.0), (0.3, 0.11), (0.62, 0.09), (0.88, 0.025), (1, 0.0)],
    swing_pitch=[(0, 0.75), (0.35, 1.55), (0.7, 0.45), (0.9, 0.03), (1, 0.0)],
    swing_fold=[(0, 0.18), (0.35, 0.8), (0.72, 0.15), (1, 0.0)],
    hip_yaw=0.06, chest_turn=1.7, chest_lag=0.0, shoulder_roll=0.03,
)
# Walk two: a longer stride at the same speed (so each step takes longer),
# the hoof lifted later, lower and more slowly, folding less (the knee and
# heel no longer bend sharply at once, which made the legs look rubbery),
# and the shoulders turning against the hips with each step.
WALK_TWO = dict(
    name="WalkTwo", duty=0.62, sweep=0.48, sink=0.026,
    heel_from=0.58, heel=0.6,
    swing_y=[(0, 0.0), (0.25, 0.07), (0.82, 0.93), (1, 1.0)],
    swing_z=[(0, 0.0), (0.5, 0.085), (0.72, 0.075), (0.9, 0.025), (1, 0.0)],
    swing_pitch=[(0, 0.6), (0.45, 1.0), (0.76, 0.38), (0.93, 0.03), (1, 0.0)],
    swing_fold=[(0, 0.15), (0.45, 0.48), (0.76, 0.12), (1, 0.0)],
    hip_yaw=0.08, chest_turn=2.6, chest_lag=0.04, shoulder_roll=0.05,
)


def hoof(W, side, t):
    """Where the hoof's front edge is, its pitch (+ lifts the heel) and the
    cannon's fold (+ swings the hoof up behind), at cycle time t."""
    r = REST[side]
    p = (t - LEGS[side][1]) % 1.0
    duty, sweep = W["duty"], W["sweep"]
    back = r["front"].y + sweep * 0.5 + 0.02
    fwd = r["front"].y - sweep * 0.5 + 0.02
    if p < duty:
        s = p / duty
        y = fwd + (back - fwd) * s               # planted: the body passes over
        z = 0.0
        pitch = W["heel"] * smooth((s - W["heel_from"]) / (1 - W["heel_from"])) ** 1.3
        fold = keys([(0, 0.0), (0.3, -0.06), (0.7, 0.0), (1, W["swing_fold"][0][1])], s)
        out = 0.0
    else:
        q = (p - duty) / (1 - duty)
        y = back + (fwd - back) * keys(W["swing_y"], q)
        z = keys(W["swing_z"], q)
        pitch = keys(W["swing_pitch"], q)
        fold = keys(W["swing_fold"], q)
        out = 0.02 * math.sin(math.pi * q)       # swings a little wide
    sgn = -1 if side == "R" else 1
    front = Vector((r["front"].x + sgn * out, y, z))
    fet = front + rx(r["fet"] - r["front"], pitch)
    tip = front + rx(r["tip"] - r["front"], pitch)
    hock = fet + rx(r["hock"] - r["fet"], fold)
    return fet, tip, hock


def pose_walk(W, t):
    reset()
    # Pelvis. The weight drops onto each hoof just after it lands and the
    # body rises as it passes over; it sways over the standing leg (late, as
    # mass does), the free hip drops, and the hips turn with the stride.
    u = (2 * t) % 1.0
    drop = 0.5 + 0.5 * math.cos(2 * math.pi * (u - 0.2))
    root = PB["Bone_000"]
    m = root.matrix.copy()
    m.translation += MWI.to_3x3() @ Vector((
        -0.028 * wave(t, 0.08),
        0.007 * math.cos(2 * math.pi * (u - 0.05)),
        -W["sink"] - 0.022 * drop))
    root.matrix = m
    upd()
    yaw = W["hip_yaw"] * math.cos(2 * math.pi * t)
    roll = 0.045 * wave(t, 0.08)
    rotate_world("Bone_000", qz(yaw) @ qy(roll) @ qx(0.05 + 0.012 * drop))
    # Back: the shoulders turn against the hips (the shoulder over the
    # stepping leg comes back as it lands), the chest lags the sway.
    chest_yaw = -W["chest_turn"] * W["hip_yaw"] * math.cos(2 * math.pi * (t - W["chest_lag"]))
    for n, share in zip(SPINE, (0.2, 0.3, 0.3, 0.2)):
        rotate_world(n, qz(chest_yaw * share)
                     @ qy(-0.8 * roll * share - W["shoulder_roll"] * wave(t, 0.2) * share)
                     @ qx(0.02 * share * math.cos(2 * math.pi * (u - 0.32))))
    for side in LEGS:
        place_leg(side, *hoof(W, side, t))
    # Arms swing against the legs, late, heavy at the elbow.
    for side, sgn in (("R", 1), ("L", -1)):
        a = ARMS[side]
        rotate_world(a[1], qx(0.2 * sgn * math.cos(2 * math.pi * (t - 0.1))))
        rotate_world(a[2], qx(0.12 * sgn * math.cos(2 * math.pi * (t - 0.2)) - 0.04))
        rotate_world(a[3], qx(0.08 * sgn * math.cos(2 * math.pi * (t - 0.28))))
    # Wings: no flapping. Each footfall's jolt runs out along them: they
    # dip a little after the body drops and spring back, the tips last.
    for side, sgn in (("R", -1), ("L", 1)):
        for k, n in enumerate(WINGS[side]):
            droop = math.cos(2 * math.pi * (u - 0.28 - 0.05 * k))
            amount = (0.035, 0.035, 0.05, 0.06)[k]
            rotate_world(n, qy(sgn * amount * droop) @ qz(sgn * 0.012 * wave(t, 0.15 + 0.04 * k)))
    # Tail: follows the sway late, more at the tip; bounces with the steps.
    for k, n in enumerate(TAIL):
        rotate_world(n, qz((0.05, 0.08, 0.11)[k] * wave(t, 0.18 + 0.08 * k))
                     @ qx(0.03 * math.cos(2 * math.pi * (u - 0.3 - 0.07 * k))))
    # The front flap: pushed forward by each knee as it swings through.
    for k, n in enumerate(FLAP):
        knee = 0.5 + 0.5 * math.cos(2 * math.pi * (u - 0.31 - 0.06 * k))
        rotate_world(n, qx(-(0.05 + 0.09 * knee) * (1.0 if k == 0 else 0.6))
                     @ qy(0.04 * wave(t, 0.15 + 0.06 * k)))
    steady_head(0.75, 0.025 * math.cos(2 * math.pi * (u - 0.32)))


# --- Claw slash -------------------------------------------------------------------------
# Key poses. twist: + turns the torso to its left (right shoulder forward);
# lean: + forward; tip: + tips the top toward its left; drop: hips down (m).
# Each claw: hand target (None = hanging as at rest), elbow pole, claw
# direction (where the hand points), and how much of it shows.
_ = None
# (0.43: kept in front of the body and below the horns, the twist and the
# head's hold eased: the first version wrung the neck, swung the arm across
# the chest and locked it straight, which stretched the shoulders up to 5x.)
# (0.43: the wind-ups arc out, clear of the shoulders, and every elbow hint
# points down and out; two pointed up, which bent
# the elbow upward in the follow-throughs.)
SLASH = [
    # t    twist  lean   tip   drop   L hand                 L elbow          L claw              Lw   R hand                 R elbow           R claw              Rw
    (0.00,  0.00, 0.00,  0.00, 0.00,  _,                     (1, 0.2, -0.3),  _,                  0.0, _,                     (-1, 0.2, -0.3),  _,                  0.0),
    (0.25,  0.12, -0.02, -0.025, 0.005, (0.70, -0.04, 1.02),  (1, 0.25, -0.4), (0.3, 0.2, 0.9),    0.8, (-0.48, -0.25, 0.86), (-1, 0.2, -0.5),  (0.2, -0.8, -0.3),  0.3),
    (0.45,  0.24, -0.04, -0.05, 0.01, (0.60, 0.12, 1.45),    (1, 0.3, -0.5),  (0.3, 0.4, 0.85),   1.0, (-0.40, -0.32, 0.92), (-1, 0.2, -0.5),  (0.2, -0.8, -0.3),  0.5),
    (0.62,  0.27, -0.05, -0.06, 0.01, (0.54, 0.08, 1.40),    (1, 0.3, -0.5),  (0.3, 0.3, 0.9),    1.0, (-0.40, -0.33, 0.93), (-1, 0.2, -0.5),  (0.2, -0.8, -0.3),  0.5),
    (0.73,  0.08, 0.12,  -0.02, 0.03, (0.50, -0.44, 1.20),   (1, 0.1, -0.4),  (-0.2, -0.8, 0.3),  1.0, (-0.48, -0.12, 0.94), (-1, 0.3, -0.3),  _,                  0.5),
    (0.81, -0.20, 0.24,  0.03, 0.05,  (0.12, -0.64, 0.98),   (0.8, 0.2, -0.6), (-0.7, -0.6, -0.2), 1.0, (-0.55, 0.0, 1.05),   (-1, 0.3, -0.2),  (-0.2, 0.4, 0.6),   0.8),
    (0.96, -0.30, 0.26,  0.05, 0.05,  (-0.12, -0.58, 0.82),  (0.6, 0.4, -0.8), (-0.5, -0.3, -0.8), 1.0, (-0.54, 0.05, 1.30),  (-1, 0.2, -0.2),  (-0.3, 0.4, 0.85),  1.0),
    (1.14, -0.27, -0.02, 0.05, 0.01,  (0.40, -0.32, 0.92),   (1, 0.2, -0.5),  (-0.2, -0.8, -0.3), 0.5, (-0.54, 0.08, 1.40),  (-1, 0.3, -0.5),  (-0.3, 0.3, 0.9),   1.0),
    (1.24, -0.28, -0.03, 0.06, 0.01,  (0.40, -0.33, 0.93),   (1, 0.2, -0.5),  (-0.2, -0.8, -0.3), 0.5, (-0.55, 0.09, 1.41),  (-1, 0.3, -0.5),  (-0.3, 0.3, 0.9),   1.0),
    (1.35, -0.08, 0.12,  0.02, 0.03,  (0.48, -0.12, 0.94),   (1, 0.3, -0.3),  _,                  0.5, (-0.50, -0.44, 1.20), (-1, 0.1, -0.4),  (0.2, -0.8, 0.3),   1.0),
    (1.43,  0.20, 0.24, -0.03, 0.05,  (0.55, 0.0, 1.05),     (1, 0.3, -0.2),  _,                  0.4, (-0.12, -0.64, 0.98), (-0.8, 0.2, -0.6), (0.7, -0.6, -0.2),  1.0),
    (1.60,  0.30, 0.26, -0.05, 0.05,  (0.5, 0.0, 0.95),      (1, 0.3, -0.2),  _,                  0.3, (0.12, -0.58, 0.82),  (-0.6, 0.4, -0.8), (0.5, -0.3, -0.8),  1.0),
    (2.05,  0.10, 0.10, -0.02, 0.02,  _,                     (1, 0.2, -0.3),  _,                  0.0, (-0.25, -0.40, 0.84), (-0.8, 0.3, -0.4), (0.2, -0.3, -1.0),  0.5),
    (2.60,  0.00, 0.00,  0.00, 0.00,  _,                     (1, 0.2, -0.3),  _,                  0.0, _,                     (-1, 0.2, -0.3),  _,                  0.0),
]
SLASH_LEN = SLASH[-1][0]
SLASH_HITS = (0.81, 1.43)   # when each claw lands (seconds)


def catmull(p0, p1, p2, p3, u):
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def slash_at(t):
    i = min(max(k for k in range(len(SLASH) - 1) if SLASH[k][0] <= t), len(SLASH) - 2)
    a, b = SLASH[i], SLASH[i + 1]
    u = (t - a[0]) / (b[0] - a[0])
    # The swipe gathers speed out of the pause at the top, strikes at full
    # speed, and the follow-through slows heavily; everything else eases in
    # and out (heavy starts, a slow recovery).
    hits = [round(h, 2) for h in SLASH_HITS]
    nxt = SLASH[i + 2][0] if i + 2 < len(SLASH) else -1
    if round(b[0], 2) in hits:
        uu = u                              # the strike
    elif round(nxt, 2) in hits:
        uu = u * u                          # gathering speed
    elif round(a[0], 2) in hits:
        uu = 1 - (1 - u) * (1 - u)          # the follow-through
    else:
        uu = smooth(u)

    def lerp(col):
        return a[col] + (b[col] - a[col]) * uu

    def hand(col, side):
        pts = []
        for k in (i - 1, i, i + 1, i + 2):
            v = SLASH[max(0, min(len(SLASH) - 1, k))][col]
            pts.append(REST_HAND[side] if v is None else Vector(v))
        return catmull(*pts, uu)

    def direction(col):
        """Where the claw points, and how much (a key without a direction
        lets the hand ease back to its natural angle, rather than snap)."""
        ca, cb = a[col], b[col]
        if ca is None and cb is None:
            return None
        strength = (1.0 if ca is not None else 0.0) * (1 - uu) + (1.0 if cb is not None else 0.0) * uu
        ca, cb = Vector(ca if ca is not None else cb), Vector(cb if cb is not None else ca)
        return ca.normalized().lerp(cb.normalized(), uu), strength

    return dict(twist=lerp(1), lean=lerp(2), tip=lerp(3), drop=lerp(4),
                L=(hand(5, "L"), Vector(a[6]).lerp(Vector(b[6]), uu), direction(7), lerp(8)),
                R=(hand(9, "R"), Vector(a[10]).lerp(Vector(b[10]), uu), direction(11), lerp(12)))


def pose_slash(t):
    p = slash_at(t)
    late = slash_at(max(0.0, t - 0.12))     # where the torso was a moment ago
    later = slash_at(max(0.0, t - 0.25))
    reset()
    # Hips: drop and turn a little with the effort; the hooves stay put.
    root = PB["Bone_000"]
    m = root.matrix.copy()
    m.translation += MWI.to_3x3() @ Vector((0.0, -0.3 * p["drop"], -p["drop"]))
    root.matrix = m
    upd()
    rotate_world("Bone_000", qz(0.3 * p["twist"]) @ qx(0.25 * p["lean"]))
    for n, share in zip(SPINE, (0.25, 0.3, 0.25, 0.2)):
        rotate_world(n, qz(0.7 * p["twist"] * share) @ qx(0.75 * p["lean"] * share) @ qy(p["tip"] * share))
    for side in LEGS:
        r = REST[side]
        place_leg(side, r["fet"], r["tip"], r["hock"])
    # Claws.
    for side in ("L", "R"):
        target, pole, claw, w = p[side]
        a = ARMS[side]
        sgn = 1 if side == "L" else -1
        # The collarbone takes a share of each reach (the shoulder comes
        # forward and up with the arm), so the shoulder joint turns less.
        aim(a[0], a[1], hw(a[1]).lerp(target, 0.35), 0.35 * w, max_angle=0.35)
        # The elbow stays between 85% and 95% of the arm's length: never
        # locked straight, never folded tight (both tear the skin).
        # One steady elbow direction, out, back and down, for every pose:
        # never along the arm (an elbow hint pointing the way the arm
        # reaches leaves the elbow free to flip sides, which jerked the arm
        # round at frames 9 and 25), and never up. (The table's elbow
        # column is kept for reference but no longer used.)
        hinge_arm(a[1], a[2], a[3], target, Vector((0.5 * sgn, 0.7, -0.5)), w)
        if claw is not None and w > 1e-3:
            claw, strength = claw
            h = hw(a[3])
            reach = (hw(a[4]) - h).length
            aim(a[3], a[4], h + claw.normalized() * reach, w * strength, max_angle=0.7)
    # Wings trail the torso's turn and swing back past it; the tail
    # counterbalances, later still. No flapping.
    turning = p["twist"] - late["twist"]
    for side, sgn in (("R", -1), ("L", 1)):
        for k, n in enumerate(WINGS[side]):
            # (Barely at the root, which the shoulders sit against.)
            rotate_world(n, qz(-turning * (0.08, 0.3, 0.4, 0.5)[k]) @ qy(sgn * 0.6 * (p["drop"] - 0.02) * (0.3, 1.0, 1.4, 1.8)[k]))
    for k, n in enumerate(TAIL):
        rotate_world(n, qz(-later["twist"] * (0.25 + 0.12 * k)))
    for k, n in enumerate(FLAP):
        rotate_world(n, qx(-0.4 * p["drop"] * (1 + k)))
    steady_head(0.35, 0.1 * p["lean"])


# --- Bake -------------------------------------------------------------------------
arm.animation_data_create()


def bake(name, length, poser, cyclic):
    frames = int(round(length * FPS))
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for f in range(frames + 1):
        poser(f / frames if cyclic else f / FPS)
        for pb in PB:
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            pb.keyframe_insert("location", frame=f, group=pb.name)
    act.use_frame_range = True
    act.frame_start = 0
    act.frame_end = frames
    act.use_cyclic = cyclic
    return act, frames


for W in (WALK_ONE, WALK_TWO):
    cycle = W["sweep"] / (W["duty"] * SPEED)
    worst_reach[0] = 0.0
    act, frames = bake(W["name"], cycle, lambda t, W=W: pose_walk(W, t), True)
    print("%s: %d frames (%.2f s), worst leg reach %.3f" % (W["name"], frames, cycle, worst_reach[0]))
    # Check: a planted hoof moves back at exactly SPEED (so it stays still
    # when the clip plays at that speed).
    b = LEGS["R"][0]
    ys = []
    for f in (2, 8, 14):
        scene.frame_set(f)
        ys.append((MW @ PB[b[4]].head).y)
    print("  planted hoof: %.3f m/s (want %.3f)" % ((ys[-1] - ys[0]) / (12 / FPS), SPEED))
worst_reach[0] = 0.0
slash, slash_frames = bake("ClawSlash", SLASH_LEN, pose_slash, False)
for k, hit in enumerate(SLASH_HITS):
    scene.timeline_markers.new("%s claw lands" % ("Left" if k == 0 else "Right"), frame=int(round(hit * FPS)))
print("ClawSlash: %d frames, worst arm reach %.3f" % (slash_frames, worst_reach[0]))

walk_two = bpy.data.actions["WalkTwo"]
arm.animation_data.action = walk_two
scene.frame_start = 0
scene.frame_end = int(walk_two.frame_end) - 1     # (the last key repeats the first)
scene.frame_set(0)

# --- A stage, for looking at it in Blender ------------------------------------------
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
cam.data.lens = 40
scene.collection.objects.link(cam)
scene.camera = cam
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
look = Vector((0, -0.1, 0.8))


def place_camera(loc, target=look):
    cam.location = loc
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()


place_camera((3.6, -2.4, 1.3))
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.color_type = 'TEXTURE'
scene.render.resolution_x = 420
scene.render.resolution_y = 420
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, relative_remap=True)
print("SAVED", OUT_BLEND)

if RENDER_DIR:
    os.makedirs(RENDER_DIR, exist_ok=True)
    jobs = [("WalkTwo", "w2side", (-2.6, -0.2, 0.7), Vector((0, -0.15, 0.5)), 3),
            ("WalkTwo", "w2back", (0.4, 2.2, 0.8), Vector((0, 0.0, 0.5)), 6),
            ("ClawSlash", "slash", (0.6, -3.4, 1.3), Vector((0, -0.2, 0.95)), 3),
            ("ClawSlash", "slashtop", (0.0, -1.2, 3.4), Vector((0, -0.2, 0.9)), 3)]
    for action, tag, loc, target, step in jobs:
        arm.animation_data.action = bpy.data.actions[action]
        place_camera(loc, target)
        for f in range(0, int(bpy.data.actions[action].frame_end), step):
            scene.frame_set(f)
            scene.render.filepath = os.path.join(RENDER_DIR, "%s_%03d.png" % (tag, f))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = walk_two
    print("RENDERED")

# --- The game's copy: skeleton, the skinned mesh (no materials), the clips ------------
for o in list(bpy.data.objects):
    if o.type not in ('ARMATURE', 'MESH') or o.name == "Ground":
        bpy.data.objects.remove(o)
mesh_obj.data.materials.clear()
arm.animation_data.action = None
for pb in PB:
    pb.matrix_basis.identity()
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', export_animation_mode='ACTIONS',
                          export_materials='NONE', export_force_sampling=True)
print("EXPORTED", OUT_GLB)
