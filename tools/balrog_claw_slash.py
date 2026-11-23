"""Builds a heavy claw-slash for the Meshy balrog and saves a .blend.

Run: blender -b --factory-startup --python tools/balrog_claw_slash.py -- [out.blend] [render_dir]
(out.blend defaults to assets/creature/balrog_claw_slash.blend)

Key poses are written in world space (Blender: +Z up, the balrog faces -Y,
its right side is -X). Each frame is solved here (spine twist, two-bone arm
and leg IK with the feet pinned to the ground) and keyed, so the clip plays
without constraints in Blender and exports to glTF as plain bone keys.
"""
import bpy, sys, math, os
from mathutils import Vector, Matrix, Quaternion

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "creature", "balrog_claw_slash.blend")
RENDER_DIR = ARGS[1] if len(ARGS) > 1 else None
GLB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "creature", "balrog.glb")
FPS = 24
CX = -0.05  # the model's centre line (x)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0  # (no .blend1 backups)
bpy.ops.import_scene.gltf(filepath=GLB)
scene = bpy.context.scene
scene.render.fps = FPS
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.name = "Balrog"
for o in list(bpy.data.objects):
    if o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o)
arm.animation_data.action = None
PB = arm.pose.bones
for pb in PB:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

S = arm.matrix_world.to_scale()[0]  # 0.01: armature space is centimetres


def B(n):
    return PB["mixamorig:" + n] if "mixamorig:" + n in PB else PB[n]


def head_w(n):
    """World position of a bone's head in the current pose."""
    return arm.matrix_world @ B(n).head


REST = {pb.name: pb.matrix.copy() for pb in PB}
REST_FOOT = {s: head_w(s + "Foot").copy() for s in ("Left", "Right")}
REST_KNEE = {s: head_w(s + "Leg").copy() for s in ("Left", "Right")}
REST_ELBOW = {s: head_w(s + "ForeArm").copy() for s in ("Left", "Right")}
REST_HAND = {s: head_w(s + "Hand").copy() for s in ("Left", "Right")}
REST_HIPS = head_w("Hips").copy()


def upd():
    bpy.context.view_layer.update()


def rotate_world(n, q):
    """Turns a bone by quaternion q (world axes) about its own head."""
    pb = B(n)
    m = pb.matrix.copy()
    h = m.translation.copy()
    r = q.to_matrix().to_4x4()
    pb.matrix = Matrix.Translation(h) @ r @ Matrix.Translation(-h) @ m
    upd()


def aim(n, child_head_w, target_w, weight=1.0):
    """Swings bone n (shortest turn) so its child's head moves toward target."""
    pb = B(n)
    h = head_w(n)
    a = (child_head_w - h)
    b = (target_w - h)
    if a.length < 1e-6 or b.length < 1e-6:
        return
    q = a.normalized().rotation_difference(b.normalized())
    q = Quaternion().slerp(q, weight)
    rotate_world(n, q)


def two_bone(upper, lower, end, target, pole, weight=1.0):
    """Places the end bone's head at target, the middle joint bent toward pole."""
    if weight <= 1e-4:
        return
    s = head_w(upper)
    l1 = (head_w(lower) - s).length
    l2 = (head_w(end) - head_w(lower)).length
    rest_target = head_w(end).copy()
    target = rest_target.lerp(target, weight)
    d = target - s
    dist = min(d.length, (l1 + l2) * 0.995)
    dn = d.normalized()
    # Elbow/knee: law of cosines, bent toward the pole direction.
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    cos_a = max(-1.0, min(1.0, cos_a))
    p = (pole - dn * pole.dot(dn))
    if p.length < 1e-6:
        p = Vector((0, 0, -1)) - dn * dn.z
    p.normalize()
    mid = s + dn * (l1 * cos_a) + p * (l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a)))
    aim(upper, head_w(lower), mid)
    aim(lower, head_w(end), s + dn * dist)


def set_world_rot(n, rot3):
    """Gives a bone a world-space orientation, keeping its head where it is."""
    pb = B(n)
    m = pb.matrix.copy()
    new = rot3.to_4x4()
    new.translation = m.translation
    # matrix is in armature space; armature has only uniform scale.
    sc = m.to_scale()
    pb.matrix = new @ Matrix.Diagonal(sc).to_4x4()
    upd()


def zq(a):
    return Quaternion((0, 0, 1), a)


def euler_q(twist, lean, tip):
    """twist: about +Z (+ turns its right shoulder forward); lean: + forward;
    tip: + tips the top toward its left (+X)."""
    return zq(twist) @ Quaternion((1, 0, 0), lean) @ Quaternion((0, 1, 0), tip)


# --- Key poses ---------------------------------------------------------------
# t in seconds. hand = slashing (right) hand target, elbow = pole direction,
# claw = direction the hand bone points (its claws), off = other hand target.
# twist/lean/tip are for the whole spine; hips_* move the pelvis (feet stay put).
R = None  # rest
KEYS = [
    # t     twist  lean   tip   hipsT  hipsXYZ               hand                      elbow             claw               w   off                    offElbow          ow
    (0.00,  0.00,  0.00,  0.00, 0.00, (0, 0, 0),           R,                         (-1, 0.3, -0.3),   R,                0.0, R,                     (1, 0.3, -0.3),  0.0),
    (0.18, -0.20, -0.06,  0.04, -0.06, (0.0, 0.015, -0.02), (-0.68, 0.36, 1.20),       (-1, 0.4, -0.5),   (-0.3, 0.6, 0.6), 1.0, (0.30, -0.30, 0.95),   (1, 0.2, -0.6),  1.0),
    (0.36, -0.42, -0.12,  0.10, -0.12, (0.0, 0.035, -0.03), (-0.62, 0.36, 1.62),       (-1, 0.5, -0.1),   (-0.1, 0.6, 1.0), 1.0, (0.32, -0.40, 1.05),   (1, 0.1, -0.6),  1.0),
    (0.46, -0.46, -0.13,  0.11, -0.13, (0.0, 0.040, -0.035),(-0.60, 0.38, 1.66),       (-1, 0.5, 0.0),    (-0.1, 0.5, 1.0), 1.0, (0.32, -0.41, 1.05),   (1, 0.1, -0.6),  1.0),
    (0.54, -0.05,  0.12,  0.04, 0.02,  (0.0, -0.02, -0.06), (-0.52, -0.30, 1.42),      (-1, 0.0, 0.4),    (0.0, -0.8, 0.5), 1.0, (0.45, 0.05, 1.00),    (1, 0.3, -0.4),  1.0),
    (0.60,  0.42,  0.30, -0.06, 0.16,  (0.0, -0.07, -0.10), (-0.05, -0.62, 1.05),      (-0.6, 0.0, 0.8),  (0.5, -0.8, -0.3),1.0, (0.62, 0.32, 0.92),    (1, 0.4, -0.2),  1.0),
    (0.70,  0.62,  0.40, -0.10, 0.24,  (0.02, -0.08, -0.12),(0.32, -0.38, 0.68),       (-0.3, 0.3, 1.0),  (0.5, -0.1, -1.0),1.0, (0.66, 0.42, 0.95),    (1, 0.4, 0.0),   1.0),
    (0.80,  0.66,  0.42, -0.11, 0.26,  (0.02, -0.08, -0.12),(0.38, -0.22, 0.60),       (-0.2, 0.4, 1.0),  (0.4, 0.1, -1.0), 1.0, (0.64, 0.40, 0.92),    (1, 0.4, 0.0),   1.0),
    (1.00,  0.28,  0.18, -0.04, 0.10,  (0.01, -0.03, -0.05),(0.10, -0.10, 0.78),       (-0.6, 0.3, 0.3),  (0.2, 0.0, -1.0), 0.8, (0.55, 0.0, 0.88),     (1, 0.3, -0.3),  0.6),
    (1.25,  0.00,  0.00,  0.00, 0.00,  (0, 0, 0),           R,                         (-1, 0.3, -0.3),   R,                0.0, R,                     (1, 0.3, -0.3),  0.0),
]
LENGTH = KEYS[-1][0]
IMPACT = 0.60


def catmull(p0, p1, p2, p3, u):
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def ease(u):
    return u * u * (3 - 2 * u)


def sample(t, side):
    """Interpolated pose at time t. side +1 = right claw, -1 = mirrored (left)."""
    i = max(k for k in range(len(KEYS) - 1) if KEYS[k][0] <= t)
    i = min(i, len(KEYS) - 2)
    a, b = KEYS[i], KEYS[i + 1]
    u = (t - a[0]) / (b[0] - a[0])
    # The swing itself (into and out of the impact) is fast and nearly linear;
    # everything else eases in and out, so it starts and stops heavily.
    uu = u if a[0] >= 0.45 and b[0] <= 0.70 else ease(u)

    def rest_hand(s):
        return REST_HAND[s]

    slash = "Right" if side > 0 else "Left"
    other = "Left" if side > 0 else "Right"

    def mirror(v):
        v = Vector(v)
        return Vector((2 * CX - v.x, v.y, v.z)) if side < 0 else v

    def mdir(v):
        v = Vector(v)
        return Vector((-v.x, v.y, v.z)) if side < 0 else v

    def pts(col, restname):
        out = []
        for k in (i - 1, i, i + 1, i + 2):
            k = max(0, min(len(KEYS) - 1, k))
            v = KEYS[k][col]
            out.append(rest_hand(restname) if v is None else mirror(v))
        return out

    def lerp(col):
        return a[col] + (b[col] - a[col]) * uu

    def vlerp(col):
        return mdir(a[col]).lerp(mdir(b[col]), uu)

    hand = catmull(*pts(6, slash), uu)
    off = catmull(*pts(10, other), uu)

    def claw():
        ca, cb = a[8], b[8]
        if ca is None and cb is None:
            return None, 0.0
        ca = mdir(ca if ca is not None else cb)
        cb = mdir(cb if cb is not None else ca)
        return ca.normalized().lerp(cb.normalized(), uu), lerp(9)

    hx, hy, hz = vlerp(5)
    return dict(
        twist=side * lerp(1), lean=lerp(2), tip=side * lerp(3), hips_t=side * lerp(4),
        hips=Vector((hx, hy, hz)),
        hand=hand, elbow=vlerp(7), claw=claw(), w=lerp(9),
        off=off, off_elbow=vlerp(11), ow=lerp(12), slash=slash, other=other,
    )


def pose(p):
    for pb in PB:
        pb.matrix_basis.identity()
    upd()
    # Pelvis: shift and turn; the legs are re-solved below to pin the feet.
    hips = B("Hips")
    m = hips.matrix.copy()
    m.translation += p["hips"] / S
    hips.matrix = m
    upd()
    rotate_world("Hips", zq(p["hips_t"]) @ Quaternion((1, 0, 0), p["lean"] * 0.25))
    # Spine: the turn, lean and tip shared out up the back.
    for n, share in (("Spine", 0.25), ("Spine1", 0.35), ("Spine2", 0.40)):
        rotate_world(n, euler_q((p["twist"] - p["hips_t"]) * share, p["lean"] * 0.75 * share, p["tip"] * share))
    # Shoulders roll with the swing (the slashing one comes forward and up).
    sl = 1 if p["slash"] == "Right" else -1
    rotate_world(p["slash"] + "Shoulder", zq(-sl * 0.0) @ Quaternion((0, 1, 0), 0.0))
    # Head: keeps its eyes on the foe (counters most of the turn and lean).
    for n, share in (("Neck", 0.4), ("Head", 0.6)):
        rotate_world(n, euler_q(-p["twist"] * 0.75 * share, -p["lean"] * 0.6 * share, -p["tip"] * 0.7 * share))
    # Legs: feet stay where they stood; knees keep bending the way they did.
    for s in ("Left", "Right"):
        foot_rot = (arm.matrix_world.to_3x3() @ REST["mixamorig:%sFoot" % s].to_3x3()).normalized()
        knee_dir = (REST_KNEE[s] - (REST_FOOT[s] + head_w(s + "UpLeg")) * 0.5)
        two_bone(s + "UpLeg", s + "Leg", s + "Foot", REST_FOOT[s], knee_dir + Vector((0, -0.3, 0)))
        set_world_rot(s + "Foot", REST["mixamorig:%sFoot" % s].to_3x3().normalized())
    # Arms.
    two_bone(p["slash"] + "Arm", p["slash"] + "ForeArm", p["slash"] + "Hand", p["hand"], p["elbow"], p["w"])
    claw, cw = p["claw"]
    if claw is not None and cw > 1e-3:
        h = head_w(p["slash"] + "Hand")
        hb = B(p["slash"] + "Hand")
        tip = arm.matrix_world @ hb.tail
        aim(p["slash"] + "Hand", tip, h + claw.normalized() * (tip - h).length, cw)
    two_bone(p["other"] + "Arm", p["other"] + "ForeArm", p["other"] + "Hand", p["off"], p["off_elbow"], p["ow"])


def bake(name, side):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    frames = int(round(LENGTH * FPS))
    for f in range(frames + 1):
        pose(sample(f / FPS, side))
        for pb in PB:
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            pb.keyframe_insert("location", frame=f, group=pb.name)
    # Impact marker, for timing damage/shake in the game.
    m = scene.timeline_markers.new("%s impact" % name, frame=int(round(IMPACT * FPS)))
    return act, frames


act_r, frames = bake("ClawSlash_R", 1)
act_l, _ = bake("ClawSlash_L", -1)
arm.animation_data.action = act_r
scene.frame_start = 0
scene.frame_end = frames
scene.frame_set(0)

# --- A stage to look at it on ---------------------------------------------------
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
gm = bpy.data.materials.new("Ground")
gm.diffuse_color = (0.25, 0.22, 0.2, 1)
ground.data.materials.append(gm)
cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 40
cam = bpy.data.objects.new("Camera", cam_data)
scene.collection.objects.link(cam)
cam.location = (2.6, -3.6, 1.6)
tgt = Vector((0.0, 0.0, 0.95))
cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = cam
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.color_type = 'TEXTURE'
scene.display.shading.light = 'STUDIO'
scene.render.resolution_x = 480
scene.render.resolution_y = 480

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT, "frames", frames)

if RENDER_DIR:
    os.makedirs(RENDER_DIR, exist_ok=True)
    views = {"front": ((2.6, -3.6, 1.6)), "side": ((-4.2, -0.4, 1.4)), "top": ((0.3, -1.2, 4.5))}
    for vname, loc in views.items():
        cam.location = loc
        cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
        for f in range(0, frames + 1):
            scene.frame_set(f)
            scene.render.filepath = os.path.join(RENDER_DIR, "%s_%02d.png" % (vname, f))
            bpy.ops.render.render(write_still=True)
    print("RENDERED")

# --- The game's copy: the skeleton, a bare mesh to skin, and the two clips. ---
# (The .blend above stays the editable source; the game reads this .glb.)
GAME_GLB = os.path.join(os.path.dirname(os.path.abspath(OUT)), "balrog_claw_slash.glb")
for o in list(bpy.data.objects):
    if o.type not in ('ARMATURE', 'MESH') or o.name == "Ground":
        bpy.data.objects.remove(o)
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.materials.clear()
for a in list(bpy.data.actions):
    if not a.name.startswith("ClawSlash"):
        bpy.data.actions.remove(a)
arm.animation_data.action = None
for pb in PB:
    pb.matrix_basis.identity()
bpy.ops.export_scene.gltf(filepath=GAME_GLB, export_format='GLB', export_animation_mode='ACTIONS',
                          export_materials='NONE', export_force_sampling=True, export_frame_range=False)
print("EXPORTED", GAME_GLB)
