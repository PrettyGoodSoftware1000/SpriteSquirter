"""Step 3 of the new raven: its walk and its flight (see raven_new_rig.py for
the rigs), keyed on every frame and exported for the game:

    blender -b --factory-startup --python tools/raven_new_anim.py -- [walk|fly|both] [render_dir]

    assets/creature/raven_walk.glb   the walking raven: "Walk", "AttackLeft",
                                     "AttackRight", "Throw", "StompRight",
                                     "StompLeft"
    assets/creature/raven_fly.glb    the flying raven and its "Fly" clip
    (and both .blend files, with the clip, for editing)

Both clips loop and stay in place (the game moves the raven). Everything
moves along smooth curves that loop round without a seam: each curve is a
closed Catmull-Rom spline through a few key values, or a sum of sines, so
speeds change gently and nothing snaps. Every hinge keeps inside its limits
(raven_new_rig.py HINGES): no elbow, knee or reverse knee ever opens past
straight.

Walk (WALK_SECONDS a cycle, two steps). A heavy giant's walk: each foot is on
the ground WALK_DUTY of the time and does not slide; it rolls off its toes
as it lifts, swings forward and sets down with no bump (its speed matches
the ground's). The leg is solved each frame: the thigh and shin reach the
reverse knee, which keeps the lower leg (tarsus) about as steep as the
thigh, like a bird's. The hips sink a little after each foot lands and rise
as the body passes over it, sway over the standing foot and turn with the
stride; the chest turns back against them, the arms swing a little against
the legs, the head stays steady, and the wings and tail follow a little late.

AttackLeft and AttackRight (ATTACK_SECONDS, on the walking model, after
the balrog's claw slash; the owner's timing, ATTACK_SPEEDUP times as fast,
and its mirror): the left claw rises up and out to the side (not as far back as the
balrog's), holds a moment, swipes down and across in front, strikes at
ATTACK_HIT, follows through and comes back to rest. The torso turns away on
the wind-up and whips round and leans into the swipe, the hips dropping a
little, so the whole body goes into it; the feet stay planted. The left
wing lifts up and back out of the arm's way; the right arm, the tail and the
other wing counter it. The wrist does not twist; the fingers open on the way
up and close on the strike. It starts and ends at rest, still.

Flight (FLY_SECONDS a beat): the eagle's flap. The downstroke (the first
FLY_DOWN of the beat) sweeps the wings, spread wide, down and a little
forward, the primaries fanned and their tips bent up under the load; the
upstroke folds the elbow and wrist and turns the hand so the feathers slip
through the air, the wing sweeping back, and opens it out again at the
top. The tips follow the shoulder a moment late. The body rises on each
downstroke and dips on the upstroke; the head holds level through it; the
tail fans a little and trims; the legs stay tucked.

At the end it checks how smoothly every bone turns (its speed's change
from frame to frame) and lists the frames worth a look (see
docs/raven_new_review.md).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "assets", "creature")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["both"]
WHICH = ARGS[0] if ARGS else "both"
RENDER_DIR = ARGS[1] if len(ARGS) > 1 else ""

FPS = 30
WALK_SECONDS = 2.0
# The raven's walking speed at the model's size (1.7 m tall): the game plays
# the clip faster or slower to match how fast it really goes. (0.62: a
# longer stride, 0.6 a second over the 2 s of two steps where it was 0.475;
# RavenGiant.CLIP_SPEED is the same.)
WALK_SPEED = 0.6
WALK_DUTY = 0.62
STEP_HEIGHT = 0.11
FLY_SECONDS = 1.2
FLY_DOWN = 0.52
# The claw attacks (on the walking model): the owner's, 50% faster; how
# long, and when the claw strikes.
ATTACK_SPEEDUP = 1.5
ATTACK_SECONDS = 1.8 / ATTACK_SPEEDUP
ATTACK_HIT = 0.84 / ATTACK_SPEEDUP
# The throw: when the goblins are in hand, and when they are let go.
THROW_SECONDS = 2.4
THROW_GRAB = 0.6
THROW_RELEASE = 1.62
# The stomp: how long, and when the foot lands.
STOMP_SECONDS = 1.15
STOMP_IMPACT = 0.8
# Casting a spell: the right arm out and the palm at the target, fingers
# spread; how long, and when the hand is up.
CAST_SECONDS = 1.6
CAST_UP = 0.45


def log(*a):
    print("ANIM", *a)


# --- Smooth curves ---------------------------------------------------------------

def loop_spline(keys):
    """A closed Catmull-Rom spline through (phase 0..1, value) keys: smooth,
    and it joins up at 1 with its start."""
    keys = sorted(keys)

    def f(phase):
        phase %= 1.0
        n = len(keys)
        ext = [(keys[i % n][0] + math.floor(i / n), keys[i % n][1]) for i in range(-2, n + 2)]
        for i in range(1, len(ext) - 2):
            t0, v0 = ext[i]
            t1, v1 = ext[i + 1]
            if t0 <= phase < t1 or (phase < ext[2][0] and i == 1 and phase < t1 and phase >= t0 - 1):
                pass
            if t0 <= phase < t1:
                tm, vm = ext[i - 1]
                tp, vp = ext[i + 2]
                h = t1 - t0
                s = (phase - t0) / h
                m0 = (v1 - vm) / (t1 - tm) * h
                m1 = (vp - v0) / (tp - t0) * h
                s2, s3 = s * s, s * s * s
                return (2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * m1
        return keys[0][1]
    return f


def short_turn(q):
    """The axis and angle of a turn, the short way round."""
    axis, ang = q.to_axis_angle()
    if ang > math.pi:
        ang -= 2 * math.pi
    return axis, ang


def track(keys):
    """A smooth curve through (time, value) keys (numbers or Vectors): each
    key's slope is set by its neighbours, and it is still at the first and
    last key, so it starts and ends at rest."""
    keys = sorted(keys, key=lambda k: k[0])
    n = len(keys)
    slopes = []
    for i in range(n):
        if i == 0 or i == n - 1:
            slopes.append(keys[i][1] * 0.0)
        else:
            slopes.append((keys[i + 1][1] - keys[i - 1][1]) / (keys[i + 1][0] - keys[i - 1][0]))

    def f(t):
        if t <= keys[0][0]:
            return keys[0][1] * 1.0
        if t >= keys[-1][0]:
            return keys[-1][1] * 1.0
        for i in range(n - 1):
            t0, v0 = keys[i]
            t1, v1 = keys[i + 1]
            if t0 <= t <= t1:
                h = t1 - t0
                s = (t - t0) / h
                s2, s3 = s * s, s * s * s
                return ((2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * h * slopes[i]
                        + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * h * slopes[i + 1])
        return keys[-1][1] * 1.0
    return f


def smooth_step(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


# --- Posing -------------------------------------------------------------------------

class Pose:
    """The rig's pose worked out here (as Blender would), so bones can be
    aimed at points: posed[name] = parent's posed @ (parent's rest)^-1 @
    rest @ loc @ rotation."""

    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
        self.hinge = {pb.name: (pb.get("hinge_rest_deg"), pb.get("hinge_close_deg")) for pb in arm.pose.bones
                      if pb.get("hinge_rest_deg") is not None}
        self.limit = {}
        for pb in arm.pose.bones:
            for c in pb.constraints:
                if c.type == "LIMIT_ROTATION":
                    self.limit[pb.name] = (c.min_x, c.max_x)
        self.reset()

    def reset(self):
        self.q = {n: Quaternion() for n in self.rest}
        self.loc = {n: Vector() for n in self.rest}
        self._cache = {}

    def base(self, name):
        """Where the bone would be with no turn of its own."""
        p = self.parent[name]
        if p is None:
            return self.rest[name] @ Matrix.Translation(self.loc[name])
        return self.world(p) @ (self.rest[p].inverted() @ self.rest[name]) @ Matrix.Translation(self.loc[name])

    def world(self, name):
        if name not in self._cache:
            self._cache[name] = self.base(name) @ self.q[name].to_matrix().to_4x4()
        return self._cache[name]

    def changed(self):
        self._cache = {}

    def head(self, name):
        return self.world(name).to_translation()

    def tail(self, name):
        b = self.arm.data.bones[name]
        return self.world(name) @ Vector((0, b.length, 0))

    def turn(self, name, axis, angle):
        """Turns the bone about a direction in the rig's space (on top of
        its turn so far)."""
        base = self.base(name).to_quaternion()
        w = Quaternion(axis.normalized(), angle)
        self.q[name] = (base.inverted() @ w @ base @ self.q[name]).normalized()
        self.changed()

    def aim(self, name, target, keep_axis=None, keep_dir=None):
        """Points the bone at `target` (its smallest turn); then, if asked,
        twists it about itself until its local `keep_axis` lies as near
        `keep_dir` as it can."""
        base = self.base(name)
        local = base.to_3x3().inverted() @ (target - base.to_translation())
        q = Vector((0, 1, 0)).rotation_difference(local.normalized())
        self.q[name] = q
        self.changed()
        if keep_axis is not None:
            m = self.world(name).to_3x3()
            y = (m @ Vector((0, 1, 0))).normalized()
            have = (m @ keep_axis).normalized()
            want = keep_dir - y * keep_dir.dot(y)
            if want.length > 1e-6:
                want.normalize()
                ang = math.atan2(y.dot(have.cross(want)), have.dot(want))
                self.q[name] = (q @ Quaternion(Vector((0, 1, 0)), ang)).normalized()
                self.changed()

    def bend(self, name, angle):
        """A hinge's turn about its X axis, kept inside its limits."""
        lo, hi = self.limit.get(name, (-math.pi, math.pi))
        a = min(max(angle, lo), hi)
        self.q[name] = Quaternion(Vector((1, 0, 0)), a)
        self.changed()
        return a

    def bend_toward(self, name, target):
        """The hinge turn (about its X) that brings its tail nearest `target`."""
        base = self.base(name)
        local = base.to_3x3().inverted() @ (target - base.to_translation())
        ang = math.atan2(local.z, local.y)
        return self.bend(name, ang)

    def write(self, frame):
        if not hasattr(self, "_last"):
            self._last = {}
        for name, pb in self.arm.pose.bones.items():
            q = self.q[name]
            # (A turn can be written two ways; keep to the side of the last
            # frame's, or the keys between would spin the long way round.)
            last = self._last.get(name)
            if last is not None and last.dot(q) < 0.0:
                q = -q
            self._last[name] = q.copy()
            if pb.rotation_mode == "QUATERNION":
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)
            else:
                pb.rotation_euler = self.q[name].to_euler(pb.rotation_mode)
                pb.keyframe_insert("rotation_euler", frame=frame, group=name)
            if name in ("pelvis",):
                pb.location = self.loc[name]
                pb.keyframe_insert("location", frame=frame, group=name)


def open_rig(model):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "raven_%s.blend" % model))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if arm.animation_data and arm.animation_data.action:
        bpy.data.actions.remove(arm.animation_data.action)
    arm.animation_data_create()
    return arm


MADE = ("Walk", "Fly", "Attack", "AttackLeft", "AttackRight", "Throw", "StompRight", "StompLeft")


def new_action(arm, name, frames):
    # (A clip made before, and its numbered copies, gives way to the new one.)
    for old in [a for a in bpy.data.actions if a.name.split(".")[0] in MADE and a.name.split(".")[0] == name]:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start = 1
    sc.frame_end = frames
    return act


def finish_action(act, frames):
    """Loops it in Blender too (the keys already join up)."""
    try:
        fcurves = act.fcurves
    except AttributeError:
        fcurves = [fc for layer in act.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    act.use_frame_range = True
    act.frame_start = 1
    act.frame_end = frames
    act.use_cyclic = True


# --- The walk -------------------------------------------------------------------------

def walk():
    arm = open_rig("walk")
    pose = Pose(arm)
    frames = int(round(WALK_SECONDS * FPS))
    act = new_action(arm, "Walk", frames + 1)
    stride = WALK_SPEED * WALK_SECONDS
    stance_travel = stride * WALK_DUTY
    fwd = Vector((0, -1, 0))
    up = Vector((0, 0, 1))
    side_x = Vector((1, 0, 0))
    rest_ankle = {s: pose.head("tarsus" + s).copy() for s in ("_r", "_l")}
    rest_ankle = {s: pose.tail("tarsus" + s).copy() for s in ("_r", "_l")}
    rest_ball = {s: pose.tail("foot" + s).copy() for s in ("_r", "_l")}
    foot_len = (rest_ball["_r"] - rest_ankle["_r"]).length
    rest_hip = {s: pose.head("thigh" + s).copy() for s in ("_r", "_l")}
    L1 = arm.data.bones["thigh_r"].length
    L2 = arm.data.bones["shin_r"].length
    L3 = arm.data.bones["tarsus_r"].length
    # The tarsus keeps its rest angle to the thigh (seen from the side).
    def side_angle(v):
        return math.atan2(v.z, -v.y)
    thigh_rest = side_angle(pose.tail("thigh_r") - pose.head("thigh_r"))
    tarsus_rest = side_angle(pose.tail("tarsus_r") - pose.head("tarsus_r"))
    tarsus_offset = tarsus_rest - thigh_rest
    # The foot's heel lift as it rolls off its toes (degrees), through the stride.
    # The knee's hinge (the shin's X axis) as the thigh carries it, and which
    # way round it lies across the leg at rest.
    shin_x_in_thigh = {}
    hinge_side = {}
    for s in ("_r", "_l"):
        rel = (pose.rest["thigh" + s].inverted() @ pose.rest["shin" + s]).to_3x3()
        shin_x_in_thigh[s] = (rel @ Vector((1, 0, 0))).normalized()
        k, h, a = pose.tail("thigh" + s), pose.tail("shin" + s), pose.head("thigh" + s)
        n0 = (k - a).cross(h - k).normalized()
        sx = (pose.world("shin" + s).to_3x3() @ Vector((1, 0, 0))).normalized()
        hinge_side[s] = 1.0 if sx.dot(n0) >= 0 else -1.0
    heel = loop_spline([(0.0, 0.0), (0.55, 0.0), (0.66, 8.0), (0.74, 22.0), (0.82, 14.0), (0.92, 0.0), (0.96, -4.0)])
    toe_curl = loop_spline([(0.0, 0.0), (0.5, 0.0), (0.7, 10.0), (0.8, 22.0), (0.9, 8.0), (0.97, -6.0)])

    def foot_path(phase):
        """The ankle's place (forward, up) relative to where it stands at rest."""
        p = phase % 1.0
        if p < WALK_DUTY:
            x = stance_travel / 2 - stance_travel * (p / WALK_DUTY)
            lift = 0.0
        else:
            s = (p - WALK_DUTY) / (1.0 - WALK_DUTY)
            ts = (1.0 - WALK_DUTY) * WALK_SECONDS
            m = -WALK_SPEED * ts
            p0, p1 = -stance_travel / 2, stance_travel / 2
            s2, s3 = s * s, s * s * s
            x = (2 * s3 - 3 * s2 + 1) * p0 + (s3 - 2 * s2 + s) * m + (-2 * s3 + 3 * s2) * p1 + (s3 - s2) * m
            lift = STEP_HEIGHT * math.sin(math.pi * s ** 0.85) ** 2
        return x, lift

    def solve_leg(s, ankle, pitch_deg, curl):
        hip = pose.head("thigh" + s)
        lateral = side_x if s == "_r" else -side_x
        # Thigh and tarsus kept about parallel: find the hock by turns.
        t_dir = (pose.tail("tarsus" + s) - pose.head("tarsus" + s)).normalized()
        for _ in range(8):
            hock = ankle - t_dir * L3
            d = hock - hip
            dist = min(d.length, (L1 + L2) * 0.985)
            dn = d.normalized()
            # The knee points forward: law of cosines in the plane of the leg.
            cos_a = (L1 * L1 + dist * dist - L2 * L2) / (2 * L1 * dist)
            a = math.acos(max(-1.0, min(1.0, cos_a)))
            bend_dir = (fwd - dn * fwd.dot(dn)).normalized()
            knee = hip + (dn * math.cos(a) + bend_dir * math.sin(a)) * L1
            thigh_dir = (knee - hip).normalized()
            ang = side_angle(thigh_dir) + tarsus_offset
            t_new = Vector((0.0, -math.cos(ang), math.sin(ang)))
            t_new.x = t_dir.x
            t_dir = t_new.normalized()
        hock = ankle - t_dir * L3
        plane_n = (knee - hip).cross(hock - knee).normalized()
        # The thigh points at the knee, twisted so the knee's hinge (the
        # shin's X axis) lies across the leg, the same way round as at rest.
        pose.aim("thigh" + s, knee, keep_axis=shin_x_in_thigh[s], keep_dir=plane_n * hinge_side[s])
        pose.bend_toward("shin" + s, hock)
        pose.bend_toward("tarsus" + s, ankle)
        # The foot: flat on the ground but for its roll.
        # (A positive pitch lifts the heel: the toes point down.)
        ball_dir = fwd * math.cos(math.radians(pitch_deg)) - up * math.sin(math.radians(pitch_deg))
        ball = ankle + ball_dir.normalized() * foot_len
        pose.bend_toward("foot" + s, ball)
        for toe in ("toe_in", "toe_mid", "toe_out"):
            for k in (1, 2, 3):
                pose.bend("%s%d%s" % (toe, k, s), math.radians(curl * (0.4 + 0.3 * k)))
        for k in (1, 2):
            pose.bend("toe_back%d%s" % (k, s), math.radians(curl * 0.5))

    bob = loop_spline([(0.0, 0.0), (0.09, -0.016), (0.31, 0.012), (0.5, 0.0), (0.59, -0.016), (0.81, 0.012)])
    for f in range(frames + 1):
        phase = f / frames
        pose.reset()
        # Hips: sink after each footfall, rise over the standing foot, sway
        # over it, and turn with the stride.
        sway = 0.028 * math.cos(2 * math.pi * (phase - 0.31))
        lift = bob(phase)
        pelvis_rest = pose.rest["pelvis"].to_3x3()
        offset = Vector((sway, 0.0, lift))
        pose.loc["pelvis"] = pelvis_rest.inverted() @ offset
        pose.changed()
        yaw = math.radians(-5.0) * math.cos(2 * math.pi * phase)
        roll = math.radians(2.2) * math.sin(2 * math.pi * (phase - 0.31))
        pitch = math.radians(1.2) * math.sin(4 * math.pi * (phase - 0.05))
        pose.turn("pelvis", up, yaw)
        pose.turn("pelvis", fwd, roll)
        pose.turn("pelvis", side_x, pitch)
        # The chest turns back against the hips, a moment late.
        pose.turn("spine", up, -0.35 * yaw)
        pose.turn("chest", up, -0.45 * math.radians(-5.0) * math.cos(2 * math.pi * (phase - 0.04)))
        pose.turn("chest", fwd, -0.6 * roll)
        pose.turn("chest_upper", side_x, -0.5 * pitch)
        # Legs.
        for s, offset_phase in (("_r", 0.0), ("_l", 0.5)):
            p = (phase + offset_phase) % 1.0
            x, h = foot_path(p)
            pitch_deg = heel(p)
            heel_up = foot_len * math.sin(math.radians(max(pitch_deg, 0.0)))
            ankle = rest_ankle[s] + fwd * x + up * (h + heel_up)
            # (The pelvis moved: the ankle is where it is on the ground, so it
            # is measured from the ground, not from the hips.)
            solve_leg(s, ankle, pitch_deg, toe_curl(p))
        # Arms swing a little against the legs.
        for s, sign in (("_r", 1.0), ("_l", -1.0)):
            swing = math.radians(7.0) * math.cos(2 * math.pi * (phase - 0.5 - 0.04)) * sign
            pose.turn("arm_upper" + s, side_x, -swing)
            pose.bend("arm_lower" + s, math.radians(4.0 + 3.0 * max(0.0, math.cos(2 * math.pi * (phase - 0.55)) * sign)))
            for name in ("thumb", "index", "middle", "ring"):
                for k in (1, 2, 3):
                    pose.bend("%s%d%s" % (name, k, s), math.radians(2.0 * math.sin(2 * math.pi * (phase - 0.15)) * sign))
        # Head: holds still while the body moves under it, with a soft nod.
        chest_q = pose.world("chest_upper").to_quaternion() @ pose.rest["chest_upper"].to_quaternion().inverted()
        axis, ang = short_turn(chest_q.inverted())
        pose.turn("neck1", axis, ang * 0.45)
        pose.turn("neck2", axis, ang * 0.35)
        pose.turn("head", axis, ang * 0.2)
        pose.turn("head", side_x, math.radians(1.5) * math.sin(4 * math.pi * (phase - 0.12)))
        # Tail: follows the hips' turn, late.
        pose.turn("tail1", up, -0.8 * math.radians(-5.0) * math.cos(2 * math.pi * (phase - 0.1)))
        pose.turn("tail2", up, -0.5 * math.radians(-5.0) * math.cos(2 * math.pi * (phase - 0.16)))
        pose.turn("tail1", side_x, math.radians(1.5) * math.sin(4 * math.pi * (phase - 0.18)))
        # Wings: dip a little at each footfall and spring back (a damped
        # bounce, summed over the steps so it loops), the long feathers last.
        def bounce(ph, lag=0.0):
            total = 0.0
            for k in range(-3, 1):
                for start in (0.0, 0.5):
                    t = ((ph - lag - start) % 1.0 + k) * WALK_SECONDS
                    if t >= 0:
                        total += math.exp(-3.2 * t) * math.sin(2 * math.pi * 2.4 * t)
            return total
        for s, sign in (("_r", 1.0), ("_l", -1.0)):
            dip = math.radians(2.6) * bounce(phase)
            pose.turn("wing_upper" + s, fwd, -dip * sign)
            for k in range(1, 6):
                pose.turn("prim%d%sb" % (k, s), fwd, -math.radians(2.0) * bounce(phase, 0.03) * sign)
        pose.write(f + 1)
    finish_action(act, frames + 1)
    act.use_fake_user = True
    walk.legs = (pose, solve_leg, rest_ankle)
    return arm, act, frames


# --- The attack -----------------------------------------------------------------------------

def mirror_v(v, m):
    """`v` for the side `m` (1: as written, the raven's left; -1: its right)."""
    return Vector((v.x * m, v.y, v.z))


class Body:
    """What the attack, the throw and the stomp share: the hips, spine and
    head; the legs planted (or one stepping); an arm reaching for a point;
    the wings and tail following. Every hinge stays inside its limits."""

    def __init__(self, arm):
        self.arm = arm
        self.pose, self.solve_leg, self.rest_ankle = walk.legs
        p = self.pose
        p.reset()
        self.wrist0 = {s: p.tail("arm_lower" + s).copy() for s in ("_r", "_l")}
        self.L1 = arm.data.bones["arm_upper_l"].length
        self.L2 = arm.data.bones["arm_lower_l"].length
        self.fore_x = {}
        self.arm_side = {}
        for s in ("_r", "_l"):
            rel = (p.rest["arm_upper" + s].inverted() @ p.rest["arm_lower" + s]).to_3x3()
            self.fore_x[s] = (rel @ Vector((1, 0, 0))).normalized()
            s0, e0, w0 = p.head("arm_upper" + s), p.tail("arm_upper" + s), p.tail("arm_lower" + s)
            n0 = (e0 - s0).cross(w0 - e0).normalized()
            fx0 = (p.world("arm_lower" + s).to_3x3() @ Vector((1, 0, 0))).normalized()
            self.arm_side[s] = 1.0 if fx0.dot(n0) >= 0 else -1.0
        self.reach_worst = 0.0

    def torso(self, twist, lean, tip, drop, sway=0.0):
        """Hips down `drop` (and over `sway` sideways), turned `twist` (+:
        the left shoulder forward), leaning `lean` (+: forward) and tipped
        `tip` (+: the top to its right); the spine takes most of it."""
        p = self.pose
        p.loc["pelvis"] = p.rest["pelvis"].to_3x3().inverted() @ Vector((sway, 0.3 * drop, -drop))
        p.changed()
        p.turn("pelvis", UP, 0.3 * twist)
        p.turn("pelvis", SIDE, 0.2 * lean)
        for name, share in (("spine", 0.25), ("chest", 0.3), ("chest_upper", 0.25)):
            p.turn(name, UP, 0.7 * twist * share / 0.8)
            p.turn(name, SIDE, 0.8 * lean * share / 0.8)
            p.turn(name, FWD, -tip * share / 0.8)

    def legs(self, step=None):
        """Both feet where they stand, or `step` = (side, ankle, pitch, curl)
        for one lifted."""
        for s in ("_r", "_l"):
            if step is not None and step[0] == s:
                self.solve_leg(s, step[1], step[2], step[3])
            else:
                self.solve_leg(s, self.rest_ankle[s], 0.0, 0.0)

    def reach(self, s, target, pole, lift=0.0):
        """The arm on side `s` reaches for `target` (its wrist), the elbow
        towards `pole`, the collarbone lifted `lift`; never straight, never
        folded tight; the hand stays in line with the forearm."""
        p = self.pose
        clav = (p.tail("clavicle" + s) - p.head("clavicle" + s)).normalized()
        p.turn("clavicle" + s, clav.cross(UP), -lift)
        shoulder = p.head("arm_upper" + s)
        L1, L2 = self.L1, self.L2
        d = target - shoulder
        self.reach_worst = max(self.reach_worst, d.length / (L1 + L2))
        dist = min(max(d.length, 0.45 * (L1 + L2)), 0.94 * (L1 + L2))
        dn = d.normalized()
        cos_a = (L1 * L1 + dist * dist - L2 * L2) / (2 * L1 * dist)
        a = math.acos(max(-1.0, min(1.0, cos_a)))
        pole = pole.normalized()
        bend_dir = (pole - dn * pole.dot(dn)).normalized()
        elbow = shoulder + (dn * math.cos(a) + bend_dir * math.sin(a)) * L1
        hand_at = shoulder + dn * dist
        plane_n = (elbow - shoulder).cross(hand_at - elbow).normalized()
        p.aim("arm_upper" + s, elbow, keep_axis=self.fore_x[s], keep_dir=plane_n * self.arm_side[s])
        p.bend_toward("arm_lower" + s, hand_at)

    def grip(self, s, degrees):
        for name in ("thumb", "index", "middle", "ring"):
            for k in (1, 2, 3):
                self.pose.bend("%s%d%s" % (name, k, s), math.radians(degrees * (0.6 + 0.2 * k)))

    def wing(self, s, lift, back):
        """Lifts the wing on side `s` up (`lift`) and back (`back`), radians."""
        m = 1.0 if s == "_l" else -1.0
        self.pose.turn("wing_root" + s, FWD, -0.4 * lift * m)
        self.pose.turn("wing_upper" + s, FWD, -0.6 * lift * m)
        self.pose.turn("wing_upper" + s, UP, -back * m)

    def head_steady(self, nod=0.0):
        p = self.pose
        chest_q = p.world("chest_upper").to_quaternion() @ p.rest["chest_upper"].to_quaternion().inverted()
        axis, ang = short_turn(chest_q.inverted())
        p.turn("neck1", axis, ang * 0.35)
        p.turn("neck2", axis, ang * 0.3)
        p.turn("head", axis, ang * 0.2)
        p.turn("head", SIDE, nod)

    def tail(self, twist_late):
        self.pose.turn("tail1", UP, -0.5 * twist_late)
        self.pose.turn("tail2", UP, -0.3 * twist_late)


UP = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))
SIDE = Vector((1, 0, 0))


def bake(arm, name, seconds, pose_at):
    """Keys `pose_at(t)` on every frame of a new clip `name`, `seconds` long."""
    frames = int(round(seconds * FPS))
    act = new_action(arm, name, frames + 1)
    act.use_fake_user = True
    walk.legs[0]._last = {}
    for f in range(frames + 1):
        walk.legs[0].reset()
        pose_at(f / FPS)
        walk.legs[0].write(f + 1)
    act.use_frame_range = True
    act.frame_start = 1
    act.frame_end = frames + 1
    act.use_cyclic = False
    return act, frames


def attack(arm, s):
    """The claw attack with the arm on side `s` (AttackLeft, AttackRight):
    the owner's (raven_walk_slow.blend: the one made at 0.60, 1.8 s) played
    ATTACK_SPEEDUP times as fast, and its mirror for the right claw."""
    body = Body(arm)
    m = 1.0 if s == "_l" else -1.0
    other = "_r" if s == "_l" else "_l"
    k = 1.0 / ATTACK_SPEEDUP
    hit = ATTACK_HIT

    def T(t):
        return t * k
    wrist0 = body.wrist0[s]
    wrist = track([
        (0.0, wrist0),
        (T(0.32), mirror_v(Vector((-0.64, -0.32, 1.20)), m)),
        (T(0.52), mirror_v(Vector((-0.67, -0.29, 1.28)), m)),
        (T(0.68), mirror_v(Vector((-0.54, -0.55, 1.20)), m)),
        (hit, mirror_v(Vector((-0.20, -0.78, 0.96)), m)),
        (T(1.02), mirror_v(Vector((0.00, -0.70, 0.82)), m)),
        (T(1.30), mirror_v(Vector((-0.22, -0.62, 0.78)), m)),
        (ATTACK_SECONDS, wrist0),
    ])
    twist = track([(0.0, 0.0), (T(0.32), -0.12), (T(0.52), -0.16), (T(0.68), -0.06), (hit, 0.17), (T(1.02), 0.23), (T(1.30), 0.09), (ATTACK_SECONDS, 0.0)])
    lean = track([(0.0, 0.0), (T(0.32), -0.03), (T(0.52), -0.04), (hit, 0.14), (T(1.02), 0.17), (T(1.30), 0.06), (ATTACK_SECONDS, 0.0)])
    tip = track([(0.0, 0.0), (T(0.52), 0.03), (hit, 0.07), (T(1.02), 0.08), (T(1.30), 0.03), (ATTACK_SECONDS, 0.0)])
    drop = track([(0.0, 0.0), (T(0.52), 0.006), (hit, 0.03), (T(1.02), 0.035), (T(1.30), 0.014), (ATTACK_SECONDS, 0.0)])
    lift = track([(0.0, 0.0), (T(0.32), 0.14), (T(0.52), 0.17), (hit, 0.02), (T(1.02), -0.03), (T(1.30), 0.0), (ATTACK_SECONDS, 0.0)])
    grip = track([(0.0, 0.0), (T(0.45), -12.0), (T(0.64), -10.0), (hit, 14.0), (T(1.05), 26.0), (T(1.40), 8.0), (ATTACK_SECONDS, 0.0)])
    pole = mirror_v(Vector((-1.0, 0.25, -0.35)), m)

    def pose_at(t):
        tw = twist(t)
        body.torso(m * tw, lean(t), m * tip(t), drop(t))
        body.legs()
        target = wrist(t)
        body.reach(s, target, pole, lift(t))
        body.grip(s, grip(t))
        body.pose.turn("arm_upper" + other, SIDE, 0.3 * tw)
        raised = smooth_step((target.z - wrist0.z) / 0.45)
        body.wing(s, 0.6 * raised, 0.35 * raised)
        late = twist(max(0.0, t - T(0.12)))
        body.pose.turn("wing_upper" + other, UP, -0.35 * m * (tw - late))
        body.tail(m * twist(max(0.0, t - T(0.22))))
        body.head_steady(0.4 * lean(t))
    act, frames = bake(arm, "Attack" + ("Left" if s == "_l" else "Right"), ATTACK_SECONDS, pose_at)
    log("attack%s: frames %d, farthest reach %.2f of the arm" % (s, frames + 1, body.reach_worst))
    return act, frames


def throw(arm):
    """Throw (THROW_SECONDS), with the right hand: crouches and reaches down
    to scoop goblins up (in hand at THROW_GRAB), straightens and lifts them,
    winds up over its shoulder (the right wing lifts back out of the way)
    and hurls them forward (let go at THROW_RELEASE), following through
    and coming back to rest. The left arm balances it."""
    body = Body(arm)
    s, other = "_r", "_l"
    w0 = body.wrist0[s]
    g, r = THROW_GRAB, THROW_RELEASE
    wrist = track([
        (0.0, w0),
        (g, Vector((0.30, -0.78, 0.30))),
        (g + 0.42, Vector((0.46, -0.48, 0.98))),
        (r - 0.24, Vector((0.56, -0.06, 1.42))),
        (r, Vector((0.24, -0.76, 1.24))),
        (r + 0.24, Vector((0.02, -0.74, 0.84))),
        (r + 0.5, Vector((0.32, -0.60, 0.78))),
        (THROW_SECONDS, w0),
    ])
    twist = track([(0.0, 0.0), (g, -0.06), (g + 0.42, 0.04), (r - 0.24, 0.20), (r, -0.16), (r + 0.24, -0.24), (r + 0.5, -0.08), (THROW_SECONDS, 0.0)])
    lean = track([(0.0, 0.0), (g, 0.42), (g + 0.42, 0.10), (r - 0.24, -0.08), (r, 0.16), (r + 0.24, 0.20), (r + 0.5, 0.06), (THROW_SECONDS, 0.0)])
    drop = track([(0.0, 0.0), (g, 0.12), (g + 0.42, 0.02), (r - 0.24, 0.0), (r, 0.03), (r + 0.24, 0.035), (THROW_SECONDS, 0.0)])
    tip = track([(0.0, 0.0), (g, 0.05), (r - 0.24, -0.05), (r, 0.06), (THROW_SECONDS, 0.0)])
    lift = track([(0.0, 0.0), (g, -0.05), (r - 0.24, 0.18), (r, 0.04), (THROW_SECONDS, 0.0)])
    grip = track([(0.0, 0.0), (g - 0.3, -12.0), (g + 0.08, 30.0), (r - 0.12, 30.0), (r + 0.14, -10.0), (r + 0.6, 0.0), (THROW_SECONDS, 0.0)])
    # The wing on the throwing side: up and back while the hand is behind the shoulder.
    wing_up = track([(0.0, 0.0), (g + 0.3, 0.0), (r - 0.36, 1.0), (r - 0.12, 1.0), (r + 0.34, 0.0), (THROW_SECONDS, 0.0)])
    # The left hand reaches down a little for balance, then swings back.
    other_w = track([(0.0, body.wrist0[other]), (g, Vector((-0.40, -0.62, 0.50))), (g + 0.42, body.wrist0[other]),
                     (r, Vector((-0.50, -0.20, 0.82))), (r + 0.5, body.wrist0[other]), (THROW_SECONDS, body.wrist0[other])])

    def pose_at(t):
        tw = twist(t)
        body.torso(tw, lean(t), tip(t), drop(t))
        body.legs()
        target = wrist(t)
        body.reach(s, target, Vector((1.0, 0.35, -0.4)), lift(t))
        body.grip(s, grip(t))
        body.reach(other, other_w(t), Vector((-1.0, 0.25, -0.35)))
        # The wing on the throwing side goes up and back while the hand is behind the shoulder.
        behind = wing_up(t)
        body.wing(s, 0.9 * behind, 0.45 * behind)
        body.wing(other, 0.0, 0.25 * (tw - twist(max(0.0, t - 0.12))))
        body.tail(twist(max(0.0, t - 0.22)))
        body.head_steady(0.3 * lean(t))
    act, frames = bake(arm, "Throw", THROW_SECONDS, pose_at)
    log("throw: frames %d, farthest reach %.2f of the arm" % (frames + 1, body.reach_worst))
    return act, frames


def stomp(arm, s):
    """Stomp (StompRight, StompLeft; STOMP_SECONDS): the weight goes onto the
    other foot, the knee comes up high, and the foot slams down a little
    ahead (lands at STOMP_IMPACT) and the body settles. The arms come out
    for balance, the wings lift and drop with it."""
    body = Body(arm)
    m = -1.0 if s == "_r" else 1.0  # (+ for the left foot, as the attack's sides)
    ankle0 = body.rest_ankle[s]
    hit = STOMP_IMPACT
    ankle = track([
        (0.0, ankle0),
        (0.22, ankle0 + Vector((0.0, -0.04, 0.12))),
        (0.50, ankle0 + Vector((m * 0.02, -0.16, 0.36))),
        (0.62, ankle0 + Vector((m * 0.02, -0.18, 0.38))),
        (hit, ankle0 + Vector((0.0, -0.10, 0.0))),
        (STOMP_SECONDS, ankle0 + Vector((0.0, -0.10, 0.0))),
    ])
    pitch = track([(0.0, 0.0), (0.22, 18.0), (0.55, 10.0), (hit - 0.05, -6.0), (hit, 0.0), (STOMP_SECONDS, 0.0)])
    curl = track([(0.0, 0.0), (0.3, 14.0), (0.6, 6.0), (hit, 0.0), (STOMP_SECONDS, 0.0)])
    # Weight over the standing foot, a lean back as the knee rises, and down into the stamp.
    sway = track([(0.0, 0.0), (0.25, 0.05), (0.6, 0.06), (hit, 0.02), (STOMP_SECONDS, 0.0)])
    lean = track([(0.0, 0.0), (0.5, -0.07), (0.62, -0.06), (hit, 0.12), (hit + 0.12, 0.13), (STOMP_SECONDS, 0.0)])
    drop = track([(0.0, 0.0), (0.5, -0.01), (hit, 0.035), (hit + 0.12, 0.04), (STOMP_SECONDS, 0.0)])
    arms = track([(0.0, 0.0), (0.5, 1.0), (0.62, 1.0), (hit, 0.6), (STOMP_SECONDS, 0.0)])
    wings = track([(0.0, 0.0), (0.5, 0.35), (0.62, 0.38), (hit, -0.08), (hit + 0.15, 0.06), (STOMP_SECONDS, 0.0)])

    def pose_at(t):
        # (Sway towards the standing foot: away from the stamping one.)
        body.torso(0.0, lean(t), 0.0, drop(t), sway=m * sway(t))
        body.legs(step=(s, ankle(t), pitch(t), curl(t)))
        for side, sgn in (("_r", 1.0), ("_l", -1.0)):
            out = arms(t)
            body.reach(side, body.wrist0[side].lerp(Vector((sgn * 0.62, -0.42, 0.98)), out), Vector((sgn, 0.25, -0.35)))
            body.wing(side, wings(t), 0.0)
        body.head_steady(0.2 * lean(t))
    act, frames = bake(arm, "Stomp" + ("Right" if s == "_r" else "Left"), STOMP_SECONDS, pose_at)
    return act, frames


def cast(arm):
    """Cast (CAST_SECONDS): the right arm comes up and out ahead at shoulder
    height (up by CAST_UP), the hand bends back so the palm faces ahead and
    the fingers spread (as far as the knuckles allow); a moment's hold, and
    back to rest. In the game the arm is turned on top to point at the
    spell's target."""
    body = Body(arm)
    p = body.pose
    s = "_r"
    w0 = body.wrist0[s]
    p.reset()
    shoulder = p.head("arm_upper" + s)
    out = shoulder + Vector((0.1, -0.96 * (body.L1 + body.L2), -0.12))
    up = CAST_UP
    reach = track([(0.0, 0.0), (up, 1.0), (up + 0.4, 1.0), (CAST_SECONDS, 0.0)])
    torso = track([(0.0, 0.0), (up, 1.0), (up + 0.45, 1.0), (CAST_SECONDS, 0.0)])

    def pose_at(t):
        k = reach(t)
        body.torso(0.08 * torso(t), 0.04 * torso(t), 0.0, 0.0)
        body.legs()
        body.reach(s, w0.lerp(out, k), Vector((1.0, 0.6, -0.2)), 0.0)
        body.grip(s, -45.0 * k)
        # The palm down, then the hand bent back: the palm faces ahead.
        fore = (p.tail("arm_lower" + s) - p.head("arm_lower" + s)).normalized()
        palm = _palm(p, s)
        flat = (palm - fore * palm.dot(fore)).normalized()
        down = (-UP - fore * (-UP).dot(fore)).normalized()
        roll = math.atan2(flat.cross(down).dot(fore), flat.dot(down))
        p.turn("hand" + s, fore, roll * k)
        p.turn("hand" + s, fore.cross(UP), math.radians(65.0) * k)
        # The fingers spread from the middle one (the knuckles allow a little).
        middle = (p.tail("middle1" + s) - p.head("middle1" + s)).normalized()
        palm = _palm(p, s)
        for name in ("thumb", "index", "ring"):
            d = (p.tail(name + "1" + s) - p.head(name + "1" + s)).normalized()
            away = p.head(name + "1" + s) - p.head("middle1" + s)
            away = (away - palm * away.dot(palm)).normalized()
            p.turn(name + "1" + s, d.cross(away), math.radians(6.0 if name != "thumb" else 5.0) * k)
        body.wing(s, 0.5 * k, 0.25 * k)
        body.head_steady()
    act, frames = bake(arm, "Cast", CAST_SECONDS, pose_at)
    p.reset()
    pose_at(up)
    tip = p.tail("middle3" + s)
    log("cast: frames %d, fingertips %.2f above the wrist, palm facing %s, wrist %.2f of the way out (%.2f ahead of the shoulder, %.2f below)" % (frames + 1,
        tip.z - p.tail("arm_lower" + s).z, tuple(round(c, 2) for c in _palm(p, s)),
        (p.tail("arm_lower" + s) - shoulder).length / (body.L1 + body.L2), shoulder.y - p.tail("arm_lower" + s).y, shoulder.z - p.tail("arm_lower" + s).z))
    return act, frames


def _palm(p, s):
    """The way the palm of hand `s` faces: where the fingertips go as they curl."""
    names = ["%s%d%s" % (f, k, s) for f in ("index", "middle", "ring") for k in (1, 2, 3)]
    saved = {n: p.q[n].copy() for n in names}
    before = p.tail("middle3" + s).copy()
    for n in names:
        p.q[n] = p.q[n] @ Quaternion(Vector((1, 0, 0)), math.radians(15.0))
    p.changed()
    after = p.tail("middle3" + s).copy()
    for n in names:
        p.q[n] = saved[n]
    p.changed()
    hand = (p.tail("hand" + s) - p.head("hand" + s)).normalized()
    v = after - before
    return (v - hand * v.dot(hand)).normalized()


# --- The flight ---------------------------------------------------------------------------

def fly():
    arm = open_rig("fly")
    pose = Pose(arm)
    frames = int(round(FLY_SECONDS * FPS))
    act = new_action(arm, "Fly", frames + 1)
    fwd = Vector((0, -1, 0))
    up = Vector((0, 0, 1))
    side_x = Vector((1, 0, 0))
    d = FLY_DOWN
    # Wing elevation at the shoulder (degrees up from the rest spread).
    elev = loop_spline([(0.0, 40.0), (0.1, 33.0), (0.25, 8.0), (0.4, -20.0), (d, -28.0), (0.62, -22.0),
                        (0.76, 0.0), (0.88, 26.0)])
    sweep = loop_spline([(0.0, -2.0), (0.25, 6.0), (d, 2.0), (0.75, -8.0)])
    # Elbow and wrist: open on the way down, folding on the way up.
    elbow = loop_spline([(0.0, 6.0), (0.12, -10.0), (0.45, -12.0), (0.6, 2.0), (0.77, 24.0), (0.9, 16.0)])
    wrist = loop_spline([(0.0, 8.0), (0.12, -6.0), (0.45, -8.0), (0.6, 12.0), (0.79, 42.0), (0.92, 26.0)])
    # The hand turns (degrees) so the feathers slip up through the air.
    twist = loop_spline([(0.0, 4.0), (0.25, -6.0), (d, -2.0), (0.72, 18.0), (0.9, 10.0)])
    # Primaries fanned on the way down, closed on the way up.
    spread = loop_spline([(0.0, 0.3), (0.2, 1.0), (0.45, 1.0), (0.62, 0.0), (0.8, -0.6), (0.95, -0.1)])
    body_z = loop_spline([(0.0, -0.02), (0.3, 0.03), (d, 0.055), (0.72, 0.01), (0.9, -0.03)])
    body_pitch = loop_spline([(0.0, 1.0), (0.3, -1.5), (0.6, -0.5), (0.85, 2.0)])
    rest_tail_q = None
    for f in range(frames + 1):
        phase = f / frames
        pose.reset()
        pelvis_rest = pose.rest["pelvis"].to_3x3()
        pose.loc["pelvis"] = pelvis_rest.inverted() @ Vector((0.0, 0.0, body_z(phase)))
        pose.changed()
        pose.turn("pelvis", side_x, math.radians(body_pitch(phase)))
        # Load on the wing: how fast it beats down (for the feathers' bend).
        rate = (elev(phase + 0.01) - elev(phase - 0.01)) / 0.02 / 300.0
        for s, sign in (("_r", 1.0), ("_l", -1.0)):
            e = math.radians(elev(phase))
            # (A turn about "forward" by +e lifts the +X wing.)
            pose.turn("wing_root" + s, fwd, 0.12 * e * sign)
            pose.turn("wing_upper" + s, fwd, 0.88 * e * sign)
            pose.turn("wing_upper" + s, up, -math.radians(sweep(phase)) * sign)
            pose.bend("wing_fore" + s, math.radians(elbow(phase)) + pose.limit_rest("wing_fore" + s))
            # The hand follows the shoulder a little late (a wave down the wing).
            lag = math.radians(elev(phase - 0.05) - elev(phase)) * 0.22
            pose.bend("wing_hand" + s, math.radians(wrist(phase)) + pose.limit_rest("wing_hand" + s))
            pose.turn("wing_hand" + s, fwd, lag * sign)
            hand_axis = (pose.tail("wing_hand" + s) - pose.head("wing_hand" + s)).normalized()
            pose.turn("wing_hand" + s, hand_axis, math.radians(twist(phase)) * sign)
            normal = (pose.world("wing_hand" + s).to_3x3() @ Vector((0, 0, 1))).normalized()
            for k in range(1, 6):
                # Fan: each primary turns about the wing's normal, outer ones most.
                fan = math.radians(3.0 * (3 - k)) * spread(phase)
                pose.turn("prim%d%sa" % (k, s), normal, fan * sign)
                # Tips bend up under the downstroke, trail on the way up.
                bend_axis = (pose.tail("prim%d%sb" % (k, s)) - pose.head("prim%d%sb" % (k, s))).normalized().cross(normal)
                pose.turn("prim%d%sb" % (k, s), bend_axis, math.radians(max(-6.0, min(12.0, -rate * 9.0 * (0.6 + 0.1 * (5 - k))))))
            for k in range(1, 5):
                bend_axis = (pose.tail("sec%d%sb" % (k, s)) - pose.head("sec%d%sb" % (k, s))).normalized().cross(normal)
                pose.turn("sec%d%sb" % (k, s), bend_axis, math.radians(max(-4.0, min(7.0, -rate * 5.0))))
        # Head holds level: undo the body's pitch along the neck.
        body_q = pose.world("chest_upper").to_quaternion() @ pose.rest["chest_upper"].to_quaternion().inverted()
        axis, ang = short_turn(body_q.inverted())
        pose.turn("neck1", axis, ang * 0.4)
        pose.turn("neck2", axis, ang * 0.35)
        pose.turn("head", axis, ang * 0.25)
        # Tail: trims against the body's pitch and fans a little on the downstroke.
        pose.turn("tail1", side_x, -math.radians(body_pitch(phase - 0.05)) * 0.8)
        for name, k in (("tail_fan_l2", -2), ("tail_fan_l1", -1), ("tail_fan_r1", 1), ("tail_fan_r2", 2)):
            pose.turn(name + "a", up, math.radians(2.0 * k) * spread(phase - 0.08))
        # Legs tucked, swaying a touch with the beat.
        for s, sign in (("_r", 1.0), ("_l", -1.0)):
            pose.turn("thigh" + s, side_x, math.radians(2.0) * math.sin(2 * math.pi * (phase - 0.2)))
            pose.turn("arm_upper" + s, side_x, math.radians(1.5) * math.sin(2 * math.pi * (phase - 0.3)))
        pose.write(f + 1)
    finish_action(act, frames + 1)
    return arm, act, frames


def _limit_rest(self, name):
    """0: hinge turns are from the rest pose (whose own bend is in the limits)."""
    return 0.0


Pose.limit_rest = _limit_rest


# --- Checks, pictures and export -------------------------------------------------------

def smoothness(arm, frames, loop=True):
    """How smoothly every bone turns: the largest change in its turning speed
    from one frame to the next (degrees a frame, per frame), and where. (A
    loop's last frame is its first again.)"""
    worst = []
    sc = bpy.context.scene
    mats = []
    for f in range(1, frames + 2):
        sc.frame_set(f)
        mats.append({pb.name: pb.matrix.to_quaternion() for pb in arm.pose.bones})
    count = len(mats) - 1 if loop else len(mats)
    for name in mats[0]:
        speeds = []
        steps = count if loop else count - 1
        for f in range(steps):
            turn = math.degrees(mats[f][name].rotation_difference(mats[(f + 1) % count][name]).angle)
            speeds.append(min(turn, 360.0 - turn))
        changes = [abs(speeds[(f + 1) % len(speeds)] - speeds[f]) for f in range(len(speeds) if loop else len(speeds) - 1)]
        f = max(range(len(changes)), key=lambda i: changes[i])
        worst.append((changes[f], max(speeds), name, f + 1))
    worst.sort(reverse=True)
    return worst


def export(arm, act, model):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "raven_%s.blend" % model))
    backup = os.path.join(OUT, "raven_%s.blend1" % model)
    if os.path.exists(backup):
        os.remove(backup)
    for obj in bpy.data.objects:
        obj.select_set(obj == arm or obj.parent == arm)
    out = os.path.join(OUT, "raven_%s.glb" % model)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_force_sampling=True, export_frame_range=True, export_def_bones=False,
                              export_animation_mode="ACTIONS", export_image_format="JPEG", export_jpeg_quality=93,
                              export_apply=False)
    log("exported", out)


def render_frames(arm, model, frames, picks, name=None):
    if not RENDER_DIR:
        return
    os.makedirs(RENDER_DIR, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 700
    sc.render.image_settings.file_format = "PNG"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.42, 0.42, 0.45)
    cd = bpy.data.cameras.new("c")
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cd.type = "ORTHO"
    c = Vector((0, -0.1, 0.85)) if model == "walk" else Vector((0, -0.1, 1.0))
    cd.ortho_scale = 2.3 if model == "walk" else 5.0
    views = [("side", Vector((1, 0, 0.08))), ("front", Vector((0.25, -1, 0.2)))]
    for f in picks:
        sc.frame_set(f)
        for vname, d in views:
            cam.location = c + d.normalized() * 20
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(RENDER_DIR, "%s_f%02d_%s.png" % (name or model, f, vname))
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    report = {}
    path = os.path.join(OUT, "raven_anim_check.json")
    if os.path.exists(path):
        with open(path) as f:
            report = json.load(f)
    if WHICH in ("walk", "both"):
        arm, act, frames = walk()
        worst = smoothness(arm, frames)
        report["walk"] = worst[:12]
        log("walk: frames", frames + 1)
        for w in worst[:12]:
            log("  walk smooth: %-14s max change %.2f deg/frame/frame at frame %d (top speed %.2f deg/frame)" % (w[2], w[0], w[3], w[1]))
        render_frames(arm, "walk", frames, [1, 8, 16, 23, 31, 38, 46, 53])
        last = act
        for maker, args in ((attack, ("_l",)), (attack, ("_r",)), (throw, ()), (stomp, ("_r",)), (stomp, ("_l",)), (cast, ())):
            last, n = maker(arm, *args)
            worst = smoothness(arm, n, loop=False)
            report[last.name] = worst[:6]
            render_frames(arm, "walk", n, [1 + round(i * n / 7) for i in range(8)], last.name)
            for w in worst[:3]:
                log("  %s smooth: %-14s max change %.2f deg/frame/frame at frame %d (top speed %.2f deg/frame)" % (last.name, w[2], w[0], w[3], w[1]))
        for old in [a for a in bpy.data.actions if a.name.split(".")[0] == "Attack"]:
            bpy.data.actions.remove(old)
        log("clips:", ", ".join(sorted(a.name for a in bpy.data.actions)))
        export(arm, last, "walk")
    if WHICH in ("fly", "both"):
        arm, act, frames = fly()
        worst = smoothness(arm, frames)
        report["fly"] = worst[:12]
        log("fly: frames", frames + 1)
        for w in worst[:12]:
            log("  fly smooth: %-14s max change %.2f deg/frame/frame at frame %d (top speed %.2f deg/frame)" % (w[2], w[0], w[3], w[1]))
        render_frames(arm, "fly", frames, [1, 5, 9, 13, 17, 21, 25, 29, 33])
        export(arm, act, "fly")
    with open(os.path.join(OUT, "raven_anim_check.json"), "w") as f:
        json.dump(report, f, indent=1)


main()
