"""Builds the newer balrog's walk (a heavy, hoofed two-legged stride).

Run from the project folder:
    blender -b --factory-startup --python tools/newer_balrog_walk.py [-- render_dir]

Writes:
    assets/test/NewerBalrog.blend     the model with its "Walk" action, to
                                      look at and edit (its textures are the
                                      PNGs next to it, not packed in)
    assets/test/NewerBalrog_walk.glb  the skeleton and the clip, for Godot

The walk is made in place (the game moves the body): one cycle is
CYCLE seconds, and the body would travel SPEED metres a second (at the
model's own size, 1.7 m tall). Each frame is solved here and keyed, so it
plays in Blender and Godot without constraints.

Blender space: +Z up, the balrog faces -Y, its right side is -X.

The legs are a horse's hind legs: hip, thigh (Bone_016 / 021), shin
(015 / 020), a long cannon bone with the heel (hock) high up (014 / 019),
and the pastern and hoof (013 / 018). A step: the hoof lands flat and
takes the weight (the body sinks onto it), stays planted while the body
passes over, the heel rolls up over the front of the hoof, the hoof
curls up under and swings forward, flattens out and lands again.
"""
import bpy, sys, math, os
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets", "test"))
GLB = os.path.join(ASSETS, "NewerBalrog.glb")
OUT_BLEND = os.path.join(ASSETS, "NewerBalrog.blend")
OUT_GLB = os.path.join(ASSETS, "NewerBalrog_walk.glb")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER_DIR = ARGS[0] if ARGS else None

FPS = 30
CYCLE = 1.8          # seconds for two steps: slow and heavy
DUTY = 0.62          # share of the cycle each hoof is on the ground
SWEEP = 0.38         # metres a planted hoof travels under the body
SPEED = SWEEP / (DUTY * CYCLE)   # 0.34 m/s at model size (2.2 m/s at 6.5x)

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


def aim(n, child, target):
    """Swings bone n (shortest turn) so bone `child`'s head moves to target."""
    h = hw(n)
    a, b = hw(child) - h, target - h
    if a.length < 1e-6 or b.length < 1e-6:
        return
    rotate_world(n, a.normalized().rotation_difference(b.normalized()))


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
REST = {}
for side, (b, _) in LEGS.items():
    hip, knee, hock, fet, tip = (hw(n).copy() for n in b)
    front = Vector((tip.x, -0.37, 0.0))      # the front edge of the hoof, on the ground
    REST[side] = dict(hip=hip, knee=knee, hock=hock, fet=fet, tip=tip, front=front,
                      l1=(knee - hip).length, l2=(hock - knee).length)
REST_HEAD = {n: (MW @ PB[n].matrix).to_quaternion() for n in ("Bone_023",)}
worst_reach = [0.0]


def two_bone(upper, lower, end, target, pole):
    s = hw(upper)
    l1 = (hw(lower) - s).length
    l2 = (hw(end) - hw(lower)).length
    d = target - s
    ratio = d.length / (l1 + l2)
    worst_reach[0] = max(worst_reach[0], ratio)
    dist = min(d.length, (l1 + l2) * 0.999)
    dn = d.normalized()
    cos_a = max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))
    p = pole - dn * pole.dot(dn)
    p.normalize()
    mid = s + dn * (l1 * cos_a) + p * (l1 * math.sqrt(max(0.0, 1 - cos_a * cos_a)))
    aim(upper, lower, mid)
    aim(lower, end, s + dn * dist)


def hoof(side, t):
    """Where the hoof's front edge is, its pitch (+ lifts the heel) and the
    cannon's fold (+ swings the hoof up behind), at cycle time t."""
    r = REST[side]
    p = (t - LEGS[side][1]) % 1.0
    back = r["front"].y + SWEEP * 0.5 + 0.02
    fwd = r["front"].y - SWEEP * 0.5 + 0.02
    if p < DUTY:
        s = p / DUTY
        y = fwd + (back - fwd) * s               # planted: the body passes over
        z = 0.0
        pitch = 0.75 * smooth((s - 0.62) / 0.38) ** 1.3   # heel rolls up late
        fold = keys([(0, 0.0), (0.3, -0.06), (0.7, 0.0), (1, 0.18)], s)
        out = 0.0
    else:
        q = (p - DUTY) / (1 - DUTY)
        # Out of the ground fast, then a long, slow reach and a heavy landing.
        y = back + (fwd - back) * keys([(0, 0.0), (0.15, 0.06), (0.75, 0.9), (1, 1.0)], q)
        z = keys([(0, 0.0), (0.3, 0.11), (0.62, 0.09), (0.88, 0.025), (1, 0.0)], q)
        pitch = keys([(0, 0.75), (0.35, 1.55), (0.7, 0.45), (0.9, 0.03), (1, 0.0)], q)
        fold = keys([(0, 0.18), (0.35, 0.8), (0.72, 0.15), (1, 0.0)], q)
        out = 0.02 * math.sin(math.pi * q)       # swings a little wide
    sgn = -1 if side == "R" else 1
    front = Vector((r["front"].x + sgn * out, y, z))
    fet = front + rx(r["fet"] - r["front"], pitch)
    tip = front + rx(r["tip"] - r["front"], pitch)
    hock = fet + rx(r["hock"] - r["fet"], fold)
    return fet, tip, hock


def pose(t):
    for pb in PB:
        pb.matrix_basis.identity()
    upd()
    # Pelvis. The weight drops onto each hoof just after it lands and the
    # body rises as it passes over; it sways over the standing leg (late, as
    # mass does), the free hip drops, and the hips turn with the stride.
    u = (2 * t) % 1.0
    drop = 0.5 + 0.5 * math.cos(2 * math.pi * (u - 0.2))
    root = PB["Bone_000"]
    m = root.matrix.copy()
    m.translation += MWI.to_3x3() @ Vector((
        -0.028 * wave(t, 0.08),                     # sway over the standing leg
        0.007 * math.cos(2 * math.pi * (u - 0.05)),  # held back as each hoof lands
        -0.014 - 0.022 * drop))                     # sink into each step
    root.matrix = m
    upd()
    yaw = 0.06 * math.cos(2 * math.pi * t)
    roll = 0.045 * wave(t, 0.08)
    rotate_world("Bone_000", qz(yaw) @ qy(roll) @ qx(0.05 + 0.012 * drop))

    # Back: the shoulders roll against the hips, the chest lags the sway.
    for n, share in (("Bone_003", 0.2), ("Bone_002", 0.3), ("Bone_011", 0.3), ("Bone_010", 0.2)):
        rotate_world(n, qz(-1.7 * yaw * share) @ qy(-0.8 * roll * share - 0.03 * wave(t, 0.2) * share)
                     @ qx(0.02 * share * math.cos(2 * math.pi * (u - 0.32))))

    # Legs.
    for side, (b, _) in LEGS.items():
        r = REST[side]
        fet, tip, hock = hoof(side, t)
        pole = (r["knee"] - (r["hip"] + r["hock"]) * 0.5).normalized()
        two_bone(b[0], b[1], b[2], hock, pole)
        aim(b[2], b[3], fet)
        aim(b[3], b[4], tip)

    # Arms swing against the legs, late, heavy at the elbow.
    for side, (clav, upper, fore, hand), sgn in (("R", ("Bone_029", "Bone_028", "Bone_027", "Bone_026"), 1),
                                                   ("L", ("Bone_034", "Bone_033", "Bone_032", "Bone_031"), -1)):
        swing = sgn * math.cos(2 * math.pi * (t - 0.1))
        rotate_world(upper, qx(0.2 * swing))
        rotate_world(fore, qx(0.12 * sgn * math.cos(2 * math.pi * (t - 0.2)) - 0.04))
        rotate_world(hand, qx(0.08 * sgn * math.cos(2 * math.pi * (t - 0.28))))

    # Wings: no flapping. Each footfall's jolt runs out along them: they
    # dip a little after the body drops and spring back, the tips last.
    for chain, sgn in ((("Bone_042", "Bone_041", "Bone_040", "Bone_039"), -1),
                       (("Bone_038", "Bone_037", "Bone_036", "Bone_035"), 1)):
        for k, n in enumerate(chain):
            droop = math.cos(2 * math.pi * (u - 0.28 - 0.05 * k))
            amount = (0.035, 0.035, 0.05, 0.06)[k]
            # (+Y turn lowers the left wing's tip, -Y the right's.)
            rotate_world(n, qy(sgn * amount * droop) @ qz(sgn * 0.012 * wave(t, 0.15 + 0.04 * k)))

    # Tail: follows the sway late, more at the tip; bounces with the steps.
    for k, n in enumerate(("Bone_009", "Bone_008", "Bone_007")):
        rotate_world(n, qz((0.05, 0.08, 0.11)[k] * wave(t, 0.18 + 0.08 * k))
                     @ qx(0.03 * math.cos(2 * math.pi * (u - 0.3 - 0.07 * k))))

    # The front flap: pushed forward by each knee as it swings through.
    for k, n in enumerate(("Bone_006", "Bone_005", "Bone_004")):
        knee = 0.5 + 0.5 * math.cos(2 * math.pi * (u - 0.31 - 0.06 * k))
        rotate_world(n, qx(-(0.05 + 0.09 * knee) * (1.0 if k == 0 else 0.6))
                     @ qy(0.04 * wave(t, 0.15 + 0.06 * k)))

    # Head: held steady on the target (cancels most of the body's turn and
    # roll), with a small heavy nod after each footfall.
    cur = (MW @ PB["Bone_023"].matrix).to_quaternion()
    fix = Quaternion().slerp(REST_HEAD["Bone_023"] @ cur.inverted(), 0.75)
    half = Quaternion().slerp(fix, 0.5)
    rotate_world("Bone_024", half)
    cur = (MW @ PB["Bone_023"].matrix).to_quaternion()
    fix = Quaternion().slerp(REST_HEAD["Bone_023"] @ cur.inverted(), 0.75)
    rotate_world("Bone_023", fix @ qx(0.025 * math.cos(2 * math.pi * (u - 0.32))))


# --- Bake -------------------------------------------------------------------------
frames = int(round(CYCLE * FPS))
act = bpy.data.actions.new("Walk")
act.use_fake_user = True
arm.animation_data_create()
arm.animation_data.action = act
lowest_swing = 1.0
for f in range(frames + 1):
    t = (f / frames) % 1.0
    pose(t)
    for pb in PB:
        pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
        pb.keyframe_insert("location", frame=f, group=pb.name)
act.use_frame_range = True
act.frame_start = 0
act.frame_end = frames
act.use_cyclic = True
for fc in act.fcurves if hasattr(act, "fcurves") else []:
    for kp in fc.keyframe_points:
        kp.interpolation = 'LINEAR'
print("WALK frames %d, speed %.3f m/s (model size), worst leg reach %.3f" % (frames, SPEED, worst_reach[0]))

# Check: a planted hoof must not slide (it moves back at exactly SPEED).
for side, (b, off) in LEGS.items():
    pts = []
    for f in (2, 8, 14):
        t = (off + f / frames)
        scene.frame_set(f + int(off * frames))
        pts.append(((MW @ PB[b[4]].head).y, f / FPS))
    v = (pts[-1][0] - pts[0][0]) / (pts[-1][1] - pts[0][1])
    print("PLANTED %s hoof moves back at %.3f m/s (want %.3f)" % (side, v, SPEED))

scene.frame_start = 0
scene.frame_end = frames - 1          # (the last key repeats the first)
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
target = Vector((0, -0.1, 0.8))


def place_camera(loc):
    cam.location = loc
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()


place_camera((3.6, -2.4, 1.3))
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.color_type = 'TEXTURE'
scene.render.resolution_x = 400
scene.render.resolution_y = 400
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, relative_remap=True)
print("SAVED", OUT_BLEND)

if RENDER_DIR:
    os.makedirs(RENDER_DIR, exist_ok=True)
    for vname, loc in (("side", (4.2, -0.1, 0.9)), ("front", (0.6, -4.0, 1.1)), ("three", (3.0, -2.8, 1.4))):
        place_camera(loc)
        for f in range(0, frames, 2):
            scene.frame_set(f)
            scene.render.filepath = os.path.join(RENDER_DIR, "%s_%02d.png" % (vname, f))
            bpy.ops.render.render(write_still=True)
    print("RENDERED")

# --- The game's copy: skeleton, a bare mesh to skin, the clip ---------------------------
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
