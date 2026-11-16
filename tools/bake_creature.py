#!/usr/bin/env python3
"""Sculpts the creatures and writes them to assets/creature/.

A creature is described as a set of soft shapes (ellipsoids and tapered
capsules) that melt into each other. This script turns that description
into a dense, smooth mesh, paints it, and attaches it to a skeleton so the
game can animate it. Every creature uses the same bone names, so the game
animates them all with the same code (the raven and the balrog have wing
bones as well). To change one, edit build_shapes() (the tortoise,
creature.glb), build_squirrel(), build_raven() or build_balrog() below and run:

    pip install numpy scikit-image
    python3 tools/bake_creature.py tortoise
    python3 tools/bake_creature.py squirrel
    python3 tools/bake_creature.py raven
    python3 tools/bake_creature.py balrog

A second argument sets the cell size in metres (default 0.08; smaller is
finer and bigger).

Coordinates are metres: +Y up, +Z forward, origin on the ground between
the feet. Left limbs are at -X.
"""

import json
import struct
import sys
from pathlib import Path

import numpy as np
from skimage import measure

SPECIES = sys.argv[1] if len(sys.argv) > 1 else "tortoise"
if SPECIES not in ("tortoise", "squirrel", "raven", "balrog"):
    sys.exit("usage: bake_creature.py [tortoise|squirrel|raven|balrog] [cell size]")
OUT = Path(__file__).resolve().parent.parent / "assets" / "creature" / ("creature.glb" if SPECIES == "tortoise" else SPECIES + ".glb")
CELL = float(sys.argv[2]) if len(sys.argv) > 2 else 0.08

# --- Colours (r, g, b, scaliness, and optionally how much it glows) -----------
SKIN = (0.46, 0.48, 0.25, 1.0)
SKIN_DARK = (0.33, 0.36, 0.19, 1.0)
SHELL = (0.36, 0.23, 0.12, 0.9)
SHELL_RIM = (0.50, 0.36, 0.19, 0.3)
BELLY = (0.68, 0.52, 0.31, 0.75)
HORN = (0.88, 0.83, 0.66, 0.0)
# The squirrel has fur, not scales: the last number stays 0.
RUSSET = (0.8, 0.36, 0.13, 0.0)
CREAM = (0.97, 0.93, 0.84, 0.0)
TAIL = (0.62, 0.25, 0.1, 0.0)
TAIL_TIP = (0.95, 0.72, 0.45, 0.0)
PINK = (0.92, 0.5, 0.52, 0.0)
# The raven: blue-black feathers, grey scaly hands and legs.
FEATHER = (0.17, 0.2, 0.34, 0.0)
FEATHER_LIGHT = (0.28, 0.33, 0.54, 0.0)
FEATHER_DARK = (0.105, 0.12, 0.21, 0.0)
BIRD_SKIN = (0.5, 0.5, 0.53, 1.0)
BEAK = (0.36, 0.38, 0.46, 0.0)
CLAW = (0.1, 0.1, 0.12, 0.0)
# The balrog: dark cracked hide, iron and glowing purple armour.
HIDE = (0.2, 0.115, 0.1, 0.85)
HIDE_DARK = (0.125, 0.075, 0.07, 0.85)
HIDE_LIGHT = (0.29, 0.16, 0.12, 0.7)
LAVA = (1.0, 0.5, 0.1, 0.0, 1.0)
PURPLE = (0.62, 0.27, 0.95, 0.0, 1.0)
IRON = (0.24, 0.2, 0.22, 0.0)
RAM_HORN = (0.17, 0.14, 0.13, 0.0)
RAM_RIDGE = (0.31, 0.26, 0.22, 0.0)
BONE = (0.86, 0.8, 0.64, 0.0)
CLOTH = (0.2, 0.08, 0.3, 0.0)
MEMBRANE = (0.27, 0.11, 0.1, 0.0)
HOOF = (0.085, 0.065, 0.065, 0.0)

# --- Skeleton: name -> (parent, joint position) -------------------------------
BONES = {
    "pelvis": (None, (0.0, 3.9, 0.0)),
    "spine": ("pelvis", (0.0, 5.0, 0.1)),
    "chest": ("spine", (0.0, 6.6, 0.2)),
    "neck": ("chest", (0.0, 8.1, 0.6)),
    "head": ("neck", (0.0, 9.5, 1.0)),
    "jaw": ("head", (0.0, 9.25, 1.3)),
    "tail1": ("pelvis", (0.0, 3.6, -1.7)),
    "tail2": ("tail1", (0.0, 3.4, -2.2)),
    "tail3": ("tail2", (0.0, 3.2, -2.7)),
    "tail4": ("tail3", (0.0, 3.05, -3.1)),
}
for side, sx in (("l", -1.0), ("r", 1.0)):
    BONES[f"arm_upper_{side}"] = ("chest", (sx * 2.75, 7.2, 0.5))
    BONES[f"arm_lower_{side}"] = (f"arm_upper_{side}", (sx * 3.6, 5.5, 0.7))
    BONES[f"hand_{side}"] = (f"arm_lower_{side}", (sx * 4.0, 4.0, 1.1))
    BONES[f"thigh_{side}"] = ("pelvis", (sx * 1.45, 3.7, 0.1))
    BONES[f"shin_{side}"] = (f"thigh_{side}", (sx * 1.6, 2.1, 0.6))
    BONES[f"foot_{side}"] = (f"shin_{side}", (sx * 1.6, 0.7, 0.0))

# The squirrel: tall in the leg, thin in the arm, with a bushy tail that
# stands up behind its back.
SQUIRREL_BONES = {
    "pelvis": (None, (0.0, 4.4, 0.0)),
    "spine": ("pelvis", (0.0, 5.4, 0.1)),
    "chest": ("spine", (0.0, 6.8, 0.2)),
    "neck": ("chest", (0.0, 8.2, 0.5)),
    "head": ("neck", (0.0, 9.3, 0.8)),
    "jaw": ("head", (0.0, 9.05, 1.2)),
    "tail1": ("pelvis", (0.0, 4.5, -1.0)),
    "tail2": ("tail1", (0.0, 4.6, -2.2)),
    "tail3": ("tail2", (0.0, 6.2, -3.3)),
    "tail4": ("tail3", (0.0, 8.6, -3.4)),
}
for side, sx in (("l", -1.0), ("r", 1.0)):
    # The arms are sculpted held well out from the body. Shapes that touch
    # melt together, so an arm resting against a thigh would be glued to it.
    SQUIRREL_BONES[f"arm_upper_{side}"] = ("chest", (sx * 1.85, 7.7, 0.3))
    SQUIRREL_BONES[f"arm_lower_{side}"] = (f"arm_upper_{side}", (sx * 3.0, 6.7, 0.5))
    SQUIRREL_BONES[f"hand_{side}"] = (f"arm_lower_{side}", (sx * 4.0, 5.85, 0.75))
    SQUIRREL_BONES[f"thigh_{side}"] = ("pelvis", (sx * 1.05, 4.3, 0.05))
    SQUIRREL_BONES[f"shin_{side}"] = (f"thigh_{side}", (sx * 1.15, 2.4, 0.55))
    SQUIRREL_BONES[f"foot_{side}"] = (f"shin_{side}", (sx * 1.15, 0.7, 0.0))

# The raven: a tall bird on two legs with arms, and a great wing on each
# shoulder that folds out at the wrist (the wingtip bone).
RAVEN_BONES = {
    "pelvis": (None, (0.0, 4.6, 0.0)),
    "spine": ("pelvis", (0.0, 5.6, 0.1)),
    "chest": ("spine", (0.0, 7.0, 0.2)),
    "neck": ("chest", (0.0, 8.4, 0.5)),
    "head": ("neck", (0.0, 9.5, 0.8)),
    "jaw": ("head", (0.0, 9.3, 1.5)),
    "tail1": ("pelvis", (0.0, 4.4, -1.0)),
    "tail2": ("tail1", (0.0, 3.7, -1.6)),
    "tail3": ("tail2", (0.0, 2.9, -2.1)),
    "tail4": ("tail3", (0.0, 2.1, -2.5)),
}
RAVEN_WING_ROOT = (1.2, 8.3, -1.0)
RAVEN_WRIST = (2.4, 4.6)  # in the wing's own plane: outwards, up
RAVEN_SWEEP = np.radians(30.0)
for side, sx in (("l", -1.0), ("r", 1.0)):
    RAVEN_BONES[f"arm_upper_{side}"] = ("chest", (sx * 2.2, 7.9, 0.3))
    RAVEN_BONES[f"arm_lower_{side}"] = (f"arm_upper_{side}", (sx * 3.1, 6.2, 0.5))
    RAVEN_BONES[f"hand_{side}"] = (f"arm_lower_{side}", (sx * 3.5, 4.7, 0.9))
    RAVEN_BONES[f"thigh_{side}"] = ("pelvis", (sx * 1.1, 4.5, 0.05))
    RAVEN_BONES[f"shin_{side}"] = (f"thigh_{side}", (sx * 1.2, 2.5, 0.6))
    RAVEN_BONES[f"foot_{side}"] = (f"shin_{side}", (sx * 1.2, 0.75, 0.0))
    RAVEN_BONES[f"wing_{side}"] = ("chest", (sx * RAVEN_WING_ROOT[0], RAVEN_WING_ROOT[1], RAVEN_WING_ROOT[2]))
    RAVEN_BONES[f"wingtip_{side}"] = (f"wing_{side}", (
        sx * (RAVEN_WING_ROOT[0] + RAVEN_WRIST[0] * np.cos(RAVEN_SWEEP)), RAVEN_WING_ROOT[1] + RAVEN_WRIST[1],
        RAVEN_WING_ROOT[2] - RAVEN_WRIST[0] * np.sin(RAVEN_SWEEP)))

# The balrog: broad and heavy, with a long tail and a little wing on each
# shoulder blade.
BALROG_BONES = {
    "pelvis": (None, (0.0, 4.2, 0.0)),
    "spine": ("pelvis", (0.0, 5.4, 0.1)),
    "chest": ("spine", (0.0, 7.0, 0.3)),
    "neck": ("chest", (0.0, 8.6, 0.9)),
    "head": ("neck", (0.0, 9.5, 1.4)),
    "jaw": ("head", (0.0, 9.2, 1.9)),
    "tail1": ("pelvis", (0.0, 3.8, -1.6)),
    "tail2": ("tail1", (0.0, 2.9, -3.0)),
    "tail3": ("tail2", (0.0, 1.9, -4.3)),
    "tail4": ("tail3", (0.0, 1.2, -5.6)),
}
for side, sx in (("l", -1.0), ("r", 1.0)):
    BALROG_BONES[f"arm_upper_{side}"] = ("chest", (sx * 3.0, 7.9, 0.4))
    BALROG_BONES[f"arm_lower_{side}"] = (f"arm_upper_{side}", (sx * 4.1, 5.9, 0.6))
    BALROG_BONES[f"hand_{side}"] = (f"arm_lower_{side}", (sx * 4.5, 4.1, 1.1))
    BALROG_BONES[f"thigh_{side}"] = ("pelvis", (sx * 1.5, 4.0, 0.1))
    BALROG_BONES[f"shin_{side}"] = (f"thigh_{side}", (sx * 1.7, 2.2, 0.7))
    BALROG_BONES[f"foot_{side}"] = (f"shin_{side}", (sx * 1.7, 0.75, 0.0))
    BALROG_BONES[f"wing_{side}"] = ("chest", (sx * 1.3, 8.4, -1.5))
BONES = {"tortoise": BONES, "squirrel": SQUIRREL_BONES, "raven": RAVEN_BONES, "balrog": BALROG_BONES}[SPECIES]
BONE_NAMES = list(BONES)

shapes = []  # dicts: kind, params, bone, colour, blend
holes = []


def _colour(colour):
    return tuple(colour) + (0.0,) * (5 - len(colour))


def ellipsoid(centre, radii, bone, colour=SKIN, blend=0.5):
    shapes.append({"kind": "el", "c": np.array(centre, float), "r": np.array(radii, float),
                   "bone": bone, "colour": _colour(colour), "k": blend})


def cone(a, b, r1, r2, bone, colour=SKIN, blend=0.5):
    shapes.append({"kind": "rc", "a": np.array(a, float), "b": np.array(b, float), "r1": r1, "r2": r2,
                   "bone": bone, "colour": _colour(colour), "k": blend})


def blade(a, b, r1, r2, bone, colour, normal, flat=3.0, blend=0.1):
    """A cone squashed `flat` times thinner along `normal`: a feather, a
    strip of cloth or a piece of wing."""
    n = np.array(normal, float)
    shapes.append({"kind": "fc", "a": np.array(a, float), "b": np.array(b, float), "r1": r1, "r2": r2,
                   "n": n / np.linalg.norm(n), "flat": flat, "bone": bone, "colour": _colour(colour), "k": blend})


def hole(centre, radius, blend=0.12):
    holes.append({"c": np.array(centre, float), "r": radius, "k": blend})


def build_shapes():
    # Shell on the back, with a paler rim, and the body tucked inside it.
    ellipsoid((0, 5.9, -1.0), (3.35, 3.4, 2.3), "spine", SHELL, 0.3)
    ellipsoid((0, 5.9, -0.3), (3.6, 3.6, 0.75), "spine", SHELL_RIM, 0.3)
    ellipsoid((0, 4.3, 0.2), (2.3, 1.5, 1.7), "pelvis")
    ellipsoid((0, 5.6, 0.5), (2.6, 2.6, 1.8), "spine")
    ellipsoid((0, 5.5, 1.7), (2.15, 2.5, 0.85), "spine", BELLY, 0.3)
    ellipsoid((0, 7.0, 0.5), (2.5, 1.6, 1.6), "chest")

    # Neck and head
    cone((0, 7.5, 0.6), (0, 9.1, 1.0), 1.15, 0.92, "neck")
    ellipsoid((0, 8.3, 1.45), (0.7, 0.9, 0.5), "neck", SKIN_DARK, 0.4)
    ellipsoid((0, 9.9, 1.2), (1.5, 1.12, 1.5), "head")
    ellipsoid((0, 9.62, 2.25), (1.08, 0.72, 0.85), "head", SKIN, 0.4)
    ellipsoid((0, 9.12, 1.95), (0.98, 0.42, 0.95), "jaw", SKIN_DARK, 0.25)
    # Tail
    cone((0, 3.7, -1.5), (0, 3.05, -3.2), 0.62, 0.14, "tail2", SKIN, 0.4)

    for side, sx in (("l", -1.0), ("r", 1.0)):
        # Heavy brows that slope down and out, eye sockets, nostrils.
        ellipsoid((sx * 0.8, 10.5, 1.95), (0.62, 0.22, 0.5), "head", SKIN_DARK, 0.25)
        hole((sx * 0.74, 10.0, 2.3), 0.37)
        hole((sx * 0.2, 9.75, 3.08), 0.07, 0.04)

        # Arms hang at the sides
        ellipsoid((sx * 2.75, 7.2, 0.5), (0.95, 0.95, 0.95), f"arm_upper_{side}")
        cone((sx * 2.75, 7.2, 0.5), (sx * 3.6, 5.5, 0.7), 0.85, 0.72, f"arm_upper_{side}", SKIN, 0.4)
        cone((sx * 3.6, 5.5, 0.7), (sx * 4.0, 4.0, 1.1), 0.74, 0.6, f"arm_lower_{side}", SKIN, 0.3)
        ellipsoid((sx * 4.05, 3.65, 1.2), (0.62, 0.55, 0.66), f"hand_{side}", SKIN_DARK, 0.3)
        for dx in (-0.36, 0.0, 0.36):
            base = np.array((sx * 4.05 + dx, 3.3, 1.5))
            cone(base, base + np.array((dx * 0.2, -0.55, 0.3)), 0.19, 0.03, f"hand_{side}", HORN, 0.08)

        # Short, thick legs
        cone((sx * 1.45, 3.7, 0.1), (sx * 1.6, 2.1, 0.6), 1.38, 1.08, f"thigh_{side}", SKIN, 0.5)
        cone((sx * 1.6, 2.1, 0.6), (sx * 1.6, 0.9, 0.0), 1.08, 0.95, f"shin_{side}", SKIN, 0.35)
        ellipsoid((sx * 1.6, 0.55, 0.45), (1.08, 0.58, 1.25), f"foot_{side}", SKIN_DARK, 0.3)
        for dx in (-0.6, 0.0, 0.6):
            base = np.array((sx * 1.6 + dx, 0.42, 1.45))
            cone(base, base + np.array((dx * 0.15, -0.12, 0.6)), 0.3, 0.05, f"foot_{side}", HORN, 0.08)

    # A down-turned mouth carved into the snout.
    for k in range(11):
        x = -0.85 + 1.7 * k / 10.0
        hole((x, 9.42 - 0.3 * (x / 0.85) ** 2, 3.02 - 0.45 * (x / 0.85) ** 2), 0.075, 0.05)


def build_squirrel():
    """A lanky squirrel on its hind legs: big head, staring eyes, thin arms
    held to its chest and a great bushy tail standing up behind it."""
    # A long, narrow, slightly hunched trunk with a pale front.
    ellipsoid((0, 5.0, -0.1), (1.35, 1.35, 1.15), "pelvis", RUSSET)
    ellipsoid((0, 6.1, 0.05), (1.25, 1.3, 1.05), "spine", RUSSET)
    ellipsoid((0, 7.3, 0.3), (1.6, 1.25, 1.2), "chest", RUSSET)
    ellipsoid((0, 6.2, 0.8), (0.85, 1.9, 0.5), "spine", CREAM, 0.3)
    cone((0, 8.0, 0.45), (0, 9.0, 0.75), 0.75, 0.7, "neck", RUSSET)

    # A head too big for the body: round skull, pale muzzle, fat cheeks
    # and a pair of buck teeth.
    ellipsoid((0, 9.9, 0.9), (1.6, 1.3, 1.35), "head", RUSSET)
    ellipsoid((0, 9.5, 2.0), (0.85, 0.55, 0.6), "head", CREAM, 0.3)
    ellipsoid((0, 9.05, 1.7), (0.62, 0.3, 0.6), "jaw", CREAM, 0.25)
    ellipsoid((0, 9.76, 2.6), (0.2, 0.14, 0.12), "head", PINK, 0.06)
    for sx in (-1.0, 1.0):
        ellipsoid((sx * 0.13, 9.22, 2.42), (0.12, 0.22, 0.07), "head", HORN, 0.04)

    # The tail: thin where it leaves the body, then a fat brush that
    # stands up behind the back and curls forward at the top. It is kept
    # clear of the back so the two do not melt together.
    cone((0, 4.5, -1.0), (0, 4.6, -2.2), 0.5, 0.75, "tail1", RUSSET, 0.3)
    cone((0, 4.6, -2.2), (0, 6.2, -3.3), 0.8, 1.2, "tail2", TAIL, 0.3)
    cone((0, 6.2, -3.3), (0, 8.6, -3.4), 1.2, 1.35, "tail3", TAIL, 0.3)
    cone((0, 8.6, -3.4), (0, 10.4, -2.7), 1.35, 1.15, "tail4", TAIL, 0.3)
    ellipsoid((0, 11.0, -2.0), (1.0, 0.9, 1.0), "tail4", TAIL_TIP, 0.35)

    for side, sx in (("l", -1.0), ("r", 1.0)):
        ellipsoid((sx * 1.35, 9.55, 0.9), (0.66, 0.7, 0.6), "head", CREAM, 0.3)
        # Tall ears with a tuft of dark hair on each.
        ellipsoid((sx * 1.05, 11.15, 0.6), (0.42, 0.7, 0.22), "head", RUSSET, 0.2)
        ellipsoid((sx * 1.05, 11.1, 0.8), (0.24, 0.42, 0.1), "head", PINK, 0.08)
        cone((sx * 1.05, 11.7, 0.6), (sx * 1.15, 12.5, 0.5), 0.2, 0.03, "head", TAIL, 0.1)
        hole((sx * 0.66, 10.15, 2.05), 0.44)

        # Thin arms ending in pale paws.
        ellipsoid((sx * 1.85, 7.7, 0.3), (0.6, 0.6, 0.6), f"arm_upper_{side}", RUSSET)
        cone((sx * 1.85, 7.7, 0.3), (sx * 3.0, 6.7, 0.5), 0.5, 0.42, f"arm_upper_{side}", RUSSET, 0.3)
        cone((sx * 3.0, 6.7, 0.5), (sx * 4.0, 5.85, 0.75), 0.42, 0.36, f"arm_lower_{side}", RUSSET, 0.25)
        ellipsoid((sx * 4.2, 5.65, 0.85), (0.5, 0.45, 0.55), f"hand_{side}", CREAM, 0.2)
        for dz in (-0.28, 0.0, 0.28):
            base = np.array((sx * 4.5, 5.4, 0.95 + dz))
            cone(base, base + np.array((sx * 0.3, -0.3, dz * 0.2)), 0.14, 0.02, f"hand_{side}", HORN, 0.06)

        # Long legs on big soft paws.
        cone((sx * 1.05, 4.3, 0.05), (sx * 1.15, 2.4, 0.55), 0.95, 0.62, f"thigh_{side}", RUSSET, 0.45)
        cone((sx * 1.15, 2.4, 0.55), (sx * 1.15, 0.9, 0.0), 0.6, 0.45, f"shin_{side}", RUSSET, 0.3)
        ellipsoid((sx * 1.15, 0.45, 0.45), (0.78, 0.45, 1.1), f"foot_{side}", CREAM, 0.25)
        for dx in (-0.42, 0.0, 0.42):
            base = np.array((sx * 1.15 + dx, 0.36, 1.35))
            cone(base, base + np.array((dx * 0.15, -0.1, 0.42)), 0.2, 0.04, f"foot_{side}", HORN, 0.06)


def tuft(base, direction, length, radius, bone, colour, blend=0.12):
    """A short pointed lock of feathers or hair."""
    d = np.array(direction, float)
    base = np.array(base, float)
    cone(base, base + d / np.linalg.norm(d) * length, radius, 0.05, bone, colour, blend)


def build_raven():
    """A raven that stands like a man: shaggy blue-black feathers, a heavy
    beak, grey clawed hands and feet, a fan of tail feathers and a pair of
    great wings held half open behind its shoulders."""
    # A deep-chested trunk.
    ellipsoid((0, 5.0, -0.1), (1.45, 1.4, 1.25), "pelvis", FEATHER)
    ellipsoid((0, 6.2, 0.05), (1.4, 1.4, 1.2), "spine", FEATHER)
    ellipsoid((0, 7.5, 0.35), (1.85, 1.4, 1.45), "chest", FEATHER)
    cone((0, 8.2, 0.5), (0, 9.2, 0.8), 1.0, 0.9, "neck", FEATHER)
    # Shaggy feathers down the breast and round the neck.
    for row, (y, z, n) in enumerate(((8.1, 1.5, 4), (7.3, 1.75, 5), (6.4, 1.3, 4), (5.5, 1.1, 3))):
        for i in range(n):
            x = (i - (n - 1) / 2.0) * 0.72
            tuft((x, y, z - 0.12 * abs(x)), (x * 0.25, -1.0, 0.28), 1.25, 0.42, "chest" if row < 2 else "spine",
                 FEATHER_LIGHT if (i + row) % 2 else FEATHER, 0.14)
    for i in range(9):
        a = i / 9.0 * 2.0 * np.pi + 0.35
        tuft((np.sin(a) * 0.95, 8.9, 0.6 + np.cos(a) * 0.9), (np.sin(a) * 0.55, -1.0, np.cos(a) * 0.55), 1.2, 0.4, "neck",
             FEATHER_LIGHT if i % 2 else FEATHER_DARK, 0.14)

    # Head: a round skull, heavy brows and a long hooked beak. The lower
    # half of the beak hangs from the jaw bone, a little open.
    ellipsoid((0, 10.0, 0.9), (1.25, 1.15, 1.35), "head", FEATHER)
    ellipsoid((0, 10.2, 1.7), (0.7, 0.6, 0.6), "head", FEATHER_DARK, 0.3)
    cone((0, 9.9, 1.9), (0, 9.5, 3.5), 0.56, 0.12, "head", BEAK, 0.12)
    cone((0, 9.5, 3.5), (0, 9.12, 3.72), 0.12, 0.03, "head", BEAK, 0.06)
    cone((0, 9.12, 1.7), (0, 8.86, 3.05), 0.3, 0.06, "jaw", BEAK, 0.05)
    ellipsoid((0, 9.25, 1.45), (0.62, 0.42, 0.55), "jaw", FEATHER_DARK, 0.2)
    for i in range(5):
        x = (i - 2) * 0.42
        tuft((x, 10.75 - 0.12 * abs(x), 0.1), (x * 0.3, 0.25, -1.0), 0.95, 0.34, "head", FEATHER_LIGHT if i % 2 else FEATHER, 0.14)

    # Tail: a fan of long feathers hanging down behind the legs.
    ellipsoid((0, 4.3, -1.1), (0.95, 0.65, 0.6), "tail1", FEATHER, 0.3)
    for i in range(5):
        x = (i - 2) * 0.8
        blade((x * 0.35, 4.2, -1.2), (x, 1.25 + 0.3 * abs(i - 2), -2.95 + 0.1 * abs(i - 2)), 0.5, 0.36, "tail2",
              FEATHER_LIGHT if i % 2 else FEATHER, (0.0, 0.5, -0.85), 3.0)

    for side, sx in (("l", -1.0), ("r", 1.0)):
        ellipsoid((sx * 0.6, 10.5, 1.75), (0.52, 0.2, 0.5), "head", FEATHER_DARK, 0.2)
        hole((sx * 0.63, 10.12, 1.98), 0.34)

        # Feathered arms that end in grey, scaly hands with hooked claws.
        ellipsoid((sx * 2.2, 7.9, 0.3), (0.85, 0.85, 0.85), f"arm_upper_{side}", FEATHER)
        cone((sx * 2.2, 7.9, 0.3), (sx * 3.1, 6.2, 0.5), 0.72, 0.58, f"arm_upper_{side}", FEATHER, 0.35)
        cone((sx * 3.1, 6.2, 0.5), (sx * 3.42, 5.1, 0.8), 0.58, 0.46, f"arm_lower_{side}", FEATHER, 0.3)
        for i in range(3):
            tuft((sx * 3.25, 6.3 - 0.45 * i, 0.2), (sx * 0.5, -0.6, -1.0), 0.95, 0.34, f"arm_lower_{side}",
                 FEATHER_LIGHT if i % 2 else FEATHER_DARK)
        cone((sx * 3.42, 5.1, 0.8), (sx * 3.5, 4.65, 0.9), 0.36, 0.32, f"arm_lower_{side}", BIRD_SKIN, 0.15)
        ellipsoid((sx * 3.55, 4.3, 1.0), (0.42, 0.5, 0.45), f"hand_{side}", BIRD_SKIN, 0.2)
        for dz in (-0.3, 0.0, 0.3):
            base = np.array((sx * 3.6 + sx * 0.1 * (1 - abs(dz) * 3), 4.0, 1.1 + dz))
            mid = base + np.array((sx * 0.05, -0.75, 0.3))
            cone(base, mid, 0.17, 0.11, f"hand_{side}", BIRD_SKIN, 0.08)
            cone(mid, mid + np.array((-sx * 0.12, -0.5, 0.12)), 0.11, 0.02, f"hand_{side}", CLAW, 0.05)
        thumb = np.array((sx * 3.3, 4.3, 1.4))
        cone(thumb, thumb + np.array((-sx * 0.25, -0.45, 0.35)), 0.15, 0.1, f"hand_{side}", BIRD_SKIN, 0.08)
        cone(thumb + np.array((-sx * 0.25, -0.45, 0.35)), thumb + np.array((-sx * 0.4, -0.85, 0.4)), 0.1, 0.02, f"hand_{side}", CLAW, 0.05)

        # Thick feathered thighs with a ragged hem, thin scaly shins and
        # long toes.
        cone((sx * 1.1, 4.5, 0.05), (sx * 1.2, 2.9, 0.5), 1.08, 0.78, f"thigh_{side}", FEATHER, 0.45)
        for i in range(7):
            a = i / 7.0 * 2.0 * np.pi
            tuft((sx * 1.2 + np.sin(a) * 0.55, 2.75, 0.5 + np.cos(a) * 0.55), (np.sin(a) * 0.3, -1.0, np.cos(a) * 0.3), 0.85, 0.36,
                 f"thigh_{side}", FEATHER_LIGHT if i % 2 else FEATHER_DARK)
        cone((sx * 1.2, 2.5, 0.6), (sx * 1.2, 0.9, 0.0), 0.36, 0.32, f"shin_{side}", BIRD_SKIN, 0.2)
        ellipsoid((sx * 1.2, 0.42, 0.15), (0.5, 0.4, 0.55), f"foot_{side}", BIRD_SKIN, 0.2)
        for dx in (-0.55, 0.0, 0.55):
            base = np.array((sx * 1.2 + dx * 0.5, 0.36, 0.5))
            tip = np.array((sx * 1.2 + dx * 1.5, 0.24, 1.75 - 0.25 * abs(dx)))
            cone(base, tip, 0.24, 0.15, f"foot_{side}", BIRD_SKIN, 0.1)
            cone(tip, tip + np.array((dx * 0.2, -0.16, 0.5)), 0.14, 0.02, f"foot_{side}", CLAW, 0.05)
        cone((sx * 1.2, 0.36, -0.2), (sx * 1.2, 0.24, -0.85), 0.2, 0.12, f"foot_{side}", BIRD_SKIN, 0.1)
        cone((sx * 1.2, 0.24, -0.85), (sx * 1.2, 0.1, -1.2), 0.12, 0.02, f"foot_{side}", CLAW, 0.05)

        # The wing lies in one flat plane that leans back from the
        # shoulder. Points on it are (how far out, how far up).
        root = np.array((sx * RAVEN_WING_ROOT[0], RAVEN_WING_ROOT[1], RAVEN_WING_ROOT[2]))
        out = np.array((sx * np.cos(RAVEN_SWEEP), 0.0, -np.sin(RAVEN_SWEEP)))
        normal = np.array((sx * np.sin(RAVEN_SWEEP), 0.0, np.cos(RAVEN_SWEEP)))

        def on_wing(u, v):
            return root + out * u + np.array((0.0, v, 0.0))

        def quill(base, degrees, length, r1, r2, bone, colour, flat):
            a = np.radians(degrees)
            blade(on_wing(*base), on_wing(base[0] + np.cos(a) * length, base[1] + np.sin(a) * length), r1, r2, bone, colour, normal, flat)

        wrist = np.array(RAVEN_WRIST)
        cone(root, on_wing(*wrist), 0.55, 0.4, f"wing_{side}", FEATHER_LIGHT, 0.25)
        # Long feathers hang from the arm of the wing...
        for i in range(9):
            t = 0.3 + 0.7 * i / 8.0
            quill(wrist * t, -93.0 + 7.0 * t, 5.6 + 4.2 * t, 0.62, 0.34, f"wing_{side}", FEATHER if i % 2 else FEATHER_DARK, 3.2)
        # ...with a row of short ones over their roots...
        for i in range(6):
            t = 0.25 + 0.75 * i / 5.0
            quill(wrist * t, -92.0 + 8.0 * t, 2.5 + 1.4 * t, 0.62, 0.42, f"wing_{side}", FEATHER_LIGHT, 2.0)
        # ...and the longest fan out from the wrist.
        for i in range(8):
            t = i / 7.0
            quill(wrist, -84.0 + 46.0 * t, 10.2 - 6.0 * t * t, 0.6, 0.3, f"wingtip_{side}", FEATHER_DARK if i % 2 else FEATHER, 3.2)
        for i in range(5):
            t = i / 4.0
            quill(wrist, -84.0 + 46.0 * t, 3.6 - 1.2 * t, 0.6, 0.4, f"wingtip_{side}", FEATHER_LIGHT, 2.0)


def build_balrog():
    """A horned demon as broad as it is tall: cracked dark hide, a glowing
    scar on its chest, iron and purple armour, hooves, a heavy tail and two
    little wings that will never lift it."""
    # Trunk: a barrel chest over a narrower waist, hunched at the shoulders.
    ellipsoid((0, 4.5, 0.0), (2.1, 1.5, 1.6), "pelvis", HIDE)
    ellipsoid((0, 5.7, 0.3), (2.1, 1.7, 1.6), "spine", HIDE)
    ellipsoid((0, 7.3, 0.5), (3.0, 1.9, 2.0), "chest", HIDE)
    ellipsoid((0, 8.4, -0.4), (2.2, 1.0, 1.4), "chest", HIDE_DARK)
    ellipsoid((0, 5.9, 1.6), (1.3, 1.3, 0.5), "spine", HIDE_LIGHT, 0.3)
    # A glowing scar across the breastbone.
    for a, reach in ((0.7, 1.4), (2.3, 0.8), (3.6, 1.2), (5.3, 0.7), (4.6, 1.0)):
        d = np.array((np.cos(a), np.sin(a), 0.0))
        cone((0.1, 7.5, 2.6), np.array((0.1, 7.5, 2.48)) + d * reach, 0.16, 0.03, "chest", LAVA, 0.05)
    # Bony plates down the spine.
    for i in range(6):
        y = 5.0 + 0.75 * i
        z = -1.55 - 0.45 * np.sin((y - 4.6) / 4.6 * np.pi)
        cone((0, y, z + 0.3), (0, y + 0.25, z - 0.55), 0.3, 0.04, "spine" if i < 3 else "chest", BONE, 0.08)

    # Head: low between the shoulders, a heavy muzzle and a jaw full of fangs.
    cone((0, 8.2, 0.8), (0, 9.3, 1.3), 1.25, 1.05, "neck", HIDE)
    ellipsoid((0, 9.95, 1.5), (1.25, 1.15, 1.35), "head", HIDE)
    ellipsoid((0, 9.6, 2.5), (0.98, 0.68, 0.8), "head", HIDE, 0.35)
    ellipsoid((0, 9.0, 2.2), (0.92, 0.42, 0.98), "jaw", HIDE_DARK, 0.25)
    for x in (-0.62, -0.25, 0.25, 0.62):
        cone((x, 9.3, 3.12 - 0.3 * abs(x)), (x, 8.82, 3.2 - 0.3 * abs(x)), 0.13, 0.02, "head", BONE, 0.04)
    for sx in (-1.0, 1.0):
        cone((sx * 0.5, 9.15, 2.98), (sx * 0.52, 9.75, 3.12), 0.15, 0.02, "jaw", BONE, 0.04)

    # Tail: thick, dragging on the ground, with a blade at the tip.
    joints = [(0, 3.9, -1.3), (0, 2.9, -3.0), (0, 1.9, -4.3), (0, 1.2, -5.6), (0, 1.05, -6.2)]
    radii = [1.0, 0.8, 0.6, 0.42, 0.3]
    for i in range(4):
        cone(joints[i], joints[i + 1], radii[i], radii[i + 1], f"tail{i + 1}", HIDE, 0.35)
        mid = (np.array(joints[i]) + np.array(joints[i + 1])) * 0.5
        cone(mid + np.array((0, radii[i] * 0.7, 0)), mid + np.array((0, radii[i] + 0.55, -0.35)), 0.24, 0.03, f"tail{i + 1}", BONE, 0.06)
    blade((0, 1.05, -6.1), (0, 1.5, -7.5), 0.7, 0.05, "tail4", RAM_HORN, (0.0, 1.0, 0.3), 3.0, 0.12)

    # A belt with a skull for a buckle, and rags of purple cloth.
    ellipsoid((0, 4.95, 0.1), (2.3, 0.42, 1.85), "pelvis", IRON, 0.12)
    ellipsoid((0, 4.95, 1.95), (0.5, 0.56, 0.32), "pelvis", BONE, 0.08)
    for x, drop in ((-0.75, 2.5), (0.0, 3.1), (0.75, 2.3)):
        blade((x, 4.7, 1.85), (x * 1.25, 4.7 - drop, 2.1), 0.5, 0.26, "pelvis", CLOTH, (0.0, 0.1, 1.0), 3.0)
    for x, drop in ((-0.6, 2.2), (0.6, 2.6)):
        blade((x, 4.7, -1.6), (x * 1.3, 4.7 - drop, -1.9), 0.5, 0.26, "pelvis", CLOTH, (0.0, -0.1, 1.0), 3.0)

    for side, sx in (("l", -1.0), ("r", 1.0)):
        # Brows, eye sockets, and purple fire streaming back from the eyes.
        ellipsoid((sx * 0.7, 10.45, 2.3), (0.66, 0.25, 0.5), "head", HIDE_DARK, 0.25)
        hole((sx * 0.68, 10.05, 2.6), 0.34)
        cone((sx * 1.0, 10.25, 2.35), (sx * 1.75, 11.0, 1.7), 0.2, 0.03, "head", PURPLE, 0.05)

        # Ram's horns: out from the temples, back, down and round to the front.
        centre = np.array((sx * 1.15, 10.3, 0.2))
        last = None
        for i in range(13):
            t = i / 12.0
            a = 0.95 + t * 4.6
            reach = 1.55 - 0.45 * t
            p = centre + np.array((sx * (0.25 + 2.3 * t ** 1.3), np.sin(a) * reach, np.cos(a) * reach))
            if last is not None:
                cone(last, p, 0.66 * (1.0 - t) + 0.14, 0.66 * (1.0 - t) + 0.07, "head", RAM_RIDGE if i % 2 else RAM_HORN, 0.1)
            last = p

        # Arms like tree trunks. A spiked plate on each shoulder and a
        # glowing band on each forearm.
        ellipsoid((sx * 3.0, 7.9, 0.4), (1.3, 1.25, 1.3), f"arm_upper_{side}", HIDE)
        cone((sx * 3.0, 7.9, 0.4), (sx * 4.1, 5.9, 0.6), 1.08, 0.88, f"arm_upper_{side}", HIDE, 0.4)
        cone((sx * 4.1, 5.9, 0.6), (sx * 4.5, 4.1, 1.1), 0.92, 0.78, f"arm_lower_{side}", HIDE, 0.3)
        ellipsoid((sx * 4.6, 3.55, 1.25), (0.82, 0.76, 0.82), f"hand_{side}", HIDE_DARK, 0.3)
        for dz in (-0.42, 0.0, 0.42):
            base = np.array((sx * 4.65, 3.05, 1.45 + dz))
            cone(base, base + np.array((-sx * 0.1, -0.7, 0.25)), 0.2, 0.03, f"hand_{side}", BONE, 0.06)
        ellipsoid((sx * 3.25, 8.85, 0.4), (1.5, 0.75, 1.45), f"arm_upper_{side}", IRON, 0.15)
        ellipsoid((sx * 3.45, 9.2, 1.0), (0.7, 0.3, 0.55), f"arm_upper_{side}", PURPLE, 0.06)
        for dz, tall in ((0.5, 1.5), (-0.6, 1.2)):
            cone((sx * 3.7, 9.2, dz), (sx * 4.5, 9.2 + tall, dz - 0.15), 0.3, 0.03, f"arm_upper_{side}", BONE, 0.06)
        elbow = np.array((sx * 4.1, 5.9, 0.6))
        wrist = np.array((sx * 4.5, 4.1, 1.1))
        cone(elbow + (wrist - elbow) * 0.2, elbow + (wrist - elbow) * 0.85, 1.08, 0.98, f"arm_lower_{side}", IRON, 0.08)
        cone(elbow + (wrist - elbow) * 0.47, elbow + (wrist - elbow) * 0.6, 1.1, 1.06, f"arm_lower_{side}", PURPLE, 0.04)
        for f in (0.3, 0.75):
            p = elbow + (wrist - elbow) * f
            cone(p + np.array((sx * 0.8, 0, -0.3)), p + np.array((sx * 1.7, 0.35, -0.9)), 0.26, 0.03, f"arm_lower_{side}", BONE, 0.06)

        # Legs: huge thighs, and shins that end in cloven hooves.
        cone((sx * 1.5, 4.0, 0.1), (sx * 1.7, 2.2, 0.7), 1.42, 1.02, f"thigh_{side}", HIDE, 0.5)
        cone((sx * 1.7, 2.2, 0.7), (sx * 1.7, 1.0, 0.05), 0.98, 0.74, f"shin_{side}", HIDE, 0.35)
        ellipsoid((sx * 1.7, 0.5, 0.25), (0.86, 0.56, 0.9), f"foot_{side}", HOOF, 0.2)
        for dx in (-0.36, 0.36):
            ellipsoid((sx * 1.7 + dx, 0.4, 1.0), (0.36, 0.42, 0.6), f"foot_{side}", HOOF, 0.1)

        # The wings: three thin fingers with skin stretched between them.
        root = np.array((sx * 1.3, 8.4, -1.5))
        knuckle = np.array((sx * 2.5, 10.3, -2.6))
        tips = [np.array((sx * 4.6, 11.2, -3.3)), np.array((sx * 4.7, 9.5, -3.6)), np.array((sx * 3.5, 8.0, -3.4))]
        normal = np.cross(tips[0] - knuckle, tips[2] - knuckle)
        cone(root, knuckle, 0.34, 0.24, f"wing_{side}", HIDE_DARK, 0.2)
        cone(knuckle, knuckle + np.array((sx * 0.1, 0.75, 0.1)), 0.2, 0.03, f"wing_{side}", BONE, 0.06)
        for tip in tips:
            cone(knuckle, tip, 0.22, 0.07, f"wing_{side}", HIDE_DARK, 0.1)
        for a, b in ((0, 1), (1, 2)):
            for f in (0.2, 0.5, 0.8):
                edge = tips[a] + (tips[b] - tips[a]) * f
                blade(knuckle, knuckle + (edge - knuckle) * 0.86, 0.3, 0.42, f"wing_{side}", MEMBRANE, normal, 4.0, 0.1)


# --- Distance functions -------------------------------------------------------

def dist_ellipsoid(p, c, r):
    q = p - c
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def dist_round_cone(p, a, b, r1, r2):
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    x2 = np.sum((pa * l2 - np.outer(y, ba)) ** 2, axis=1)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d_end = np.sqrt(x2 + z2) * il2 - r2
    d_start = np.sqrt(x2 + y2) * il2 - r1
    d_side = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > k, d_end, np.where(np.sign(y) * a2 * y2 < k, d_start, d_side))


def shape_distance(p, s):
    if s["kind"] == "el":
        return dist_ellipsoid(p, s["c"], s["r"])
    if s["kind"] == "fc":
        # Stretch space along the normal, so the cone comes out thin.
        n, k = s["n"], s["flat"] - 1.0
        q = p + np.outer((p - s["a"]) @ n, n) * k
        b = s["b"] + n * ((s["b"] - s["a"]) @ n) * k
        return dist_round_cone(q, s["a"], b, s["r1"], s["r2"])
    return dist_round_cone(p, s["a"], s["b"], s["r1"], s["r2"])


def smooth_min(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def lumps(p):
    """Low, wide bumps so the hide is not perfectly smooth."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    n = np.sin(1.7 * x + 1.3 * y) * np.sin(2.1 * y + 0.7 * z) * np.sin(1.9 * z + 1.1 * x)
    n2 = np.sin(4.3 * x - 2.1 * z) * np.sin(3.7 * y + 1.9 * x) * np.sin(4.1 * z + 2.3 * y)
    return 0.02 * n + 0.01 * n2


def field(p, per_shape=False):
    d = None
    all_d = []
    for s in shapes:
        di = shape_distance(p, s)
        if per_shape:
            all_d.append(di)
        d = di if d is None else smooth_min(d, di, s["k"])
    for h in holes:
        dh = np.linalg.norm(p - h["c"], axis=1) - h["r"]
        d = -smooth_min(-d, dh, h["k"])
    d = d + lumps(p)
    return (d, np.stack(all_d, axis=1)) if per_shape else d


# --- Meshing --------------------------------------------------------------------

def build_mesh():
    lo = np.array((-5.2, -0.4, -4.0))
    hi = np.array((5.2, 11.8, 3.8))
    if SPECIES in ("raven", "balrog"):
        # A box round all the shapes.
        lows, highs = [], []
        for s in shapes:
            if s["kind"] == "el":
                lows.append(s["c"] - s["r"])
                highs.append(s["c"] + s["r"])
            else:
                r = max(s["r1"], s["r2"])
                lows.append(np.minimum(s["a"], s["b"]) - r)
                highs.append(np.maximum(s["a"], s["b"]) + r)
        lo = np.min(lows, axis=0) - 0.4
        hi = np.max(highs, axis=0) + 0.4
    dims = np.ceil((hi - lo) / CELL).astype(int) + 1
    axes = [lo[i] + np.arange(dims[i]) * CELL for i in range(3)]
    volume = np.empty(dims, dtype=np.float32)
    yz = np.stack(np.meshgrid(axes[1], axes[2], indexing="ij"), axis=-1).reshape(-1, 2)
    for ix, x in enumerate(axes[0]):
        pts = np.column_stack((np.full(len(yz), x), yz))
        volume[ix] = field(pts).reshape(dims[1], dims[2])
    verts, faces, _, _ = measure.marching_cubes(volume, level=0.0, spacing=(CELL, CELL, CELL))
    verts = verts + lo

    # Smooth normals from the distance field itself.
    e = CELL * 0.5
    grad = np.stack([field(verts + off) - field(verts - off) for off in (np.array((e, 0, 0)), np.array((0, e, 0)), np.array((0, 0, e)))], axis=1)
    normals = grad / np.maximum(np.linalg.norm(grad, axis=1, keepdims=True), 1e-9)

    # glTF wants counter-clockwise triangles when seen from outside.
    a, b, c = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    facing = np.einsum("ij,ij->i", np.cross(b - a, c - a), normals[faces[:, 0]])
    if facing.mean() < 0:
        faces = faces[:, ::-1]
    return verts.astype(np.float32), normals.astype(np.float32), np.ascontiguousarray(faces).astype(np.uint32)


def paint_and_skin(verts, normals):
    _, per = field(verts, per_shape=True)
    nearest = per.min(axis=1, keepdims=True)

    # Colour: blend the colours of the shapes that meet at each vertex.
    wc = np.exp(-(per - nearest) / 0.1)
    wc /= wc.sum(axis=1, keepdims=True)
    colours = wc @ np.array([s["colour"] for s in shapes])
    rgb, scaly = colours[:, :3], colours[:, 3:4]
    # Glowing parts keep a hard edge: light does not smear into the hide.
    wg = np.exp(-(per - nearest) / 0.025)
    wg /= wg.sum(axis=1, keepdims=True)
    glow = wg @ np.array([s["colour"][4] for s in shapes])
    # Darker along the back and under the body, lighter where the sun hits.
    # Cel shading wants flat colour, so only the underside is darkened a little.
    shade = 1.0 - 0.15 * np.clip(-normals[:, 1], 0, 1)
    rgb = np.clip(rgb * shade[:, None], 0, 1)
    colours = np.concatenate((rgb, scaly), axis=1)

    # Skin weights: each shape belongs to a bone; shapes that blend share.
    wb = np.exp(-(per - nearest) / 0.3)
    bone_index = np.array([BONE_NAMES.index(s["bone"]) for s in shapes])
    weights = np.zeros((len(verts), len(BONE_NAMES)))
    for j in range(len(BONE_NAMES)):
        mask = bone_index == j
        if mask.any():
            weights[:, j] = wb[:, mask].sum(axis=1)
    top = np.argsort(-weights, axis=1)[:, :4]
    top_w = np.take_along_axis(weights, top, axis=1)
    top_w /= top_w.sum(axis=1, keepdims=True)
    # Quantise to bytes that still add up to exactly 255.
    q = np.floor(top_w * 255).astype(np.int32)
    q[:, 0] += 255 - q.sum(axis=1)
    top = np.where(q > 0, top, 0)
    return (colours * 255 + 0.5).astype(np.uint8), top.astype(np.uint8), q.astype(np.uint8), glow.astype(np.float32)


# --- glTF writer ----------------------------------------------------------------

def write_glb(verts, normals, faces, colours, joints, weights, glow):
    blob = bytearray()
    views, accessors = [], []

    def add(data, comp, kind, target=None, normalized=False, minmax=False):
        while len(blob) % 4:
            blob.append(0)
        raw = np.ascontiguousarray(data).tobytes()
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)}
        if target:
            view["target"] = target
        blob.extend(raw)
        views.append(view)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(data), "type": kind}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(v) for v in data.min(axis=0)]
            acc["max"] = [float(v) for v in data.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    FLOAT, UBYTE, UINT = 5126, 5121, 5125
    attrs = {
        "POSITION": add(verts, FLOAT, "VEC3", 34962, minmax=True),
        "NORMAL": add(normals, FLOAT, "VEC3", 34962),
        "COLOR_0": add(colours, UBYTE, "VEC4", 34962, normalized=True),
        # The rest pose, so the hide shader can pin its scales to the skin.
        "TEXCOORD_0": add(verts[:, :2].copy(), FLOAT, "VEC2", 34962),
        # (The second number is how much the spot glows.)
        "TEXCOORD_1": add(np.column_stack((verts[:, 2], glow)).astype(np.float32), FLOAT, "VEC2", 34962),
        "JOINTS_0": add(joints, UBYTE, "VEC4", 34962),
        "WEIGHTS_0": add(weights, UBYTE, "VEC4", 34962, normalized=True),
    }
    indices = add(faces.reshape(-1), UINT, "SCALAR", 34963)

    world = {name: np.array(pos, np.float32) for name, (_, pos) in BONES.items()}
    ibm = np.zeros((len(BONE_NAMES), 16), np.float32)
    nodes = []
    for i, name in enumerate(BONE_NAMES):
        parent = BONES[name][0]
        local = world[name] - (world[parent] if parent else 0.0)
        nodes.append({"name": name, "translation": [float(v) for v in local],
                      "children": [BONE_NAMES.index(n) for n in BONE_NAMES if BONES[n][0] == name]})
        if not nodes[-1]["children"]:
            del nodes[-1]["children"]
        m = np.eye(4, dtype=np.float32)
        m[3, :3] = -world[name]  # column-major: translation lives in the last column
        ibm[i] = m.reshape(-1)
    ibm_acc = add(ibm, FLOAT, "MAT4")

    mesh_node = len(nodes)
    nodes.append({"name": "CreatureMesh", "mesh": 0, "skin": 0})
    nodes.append({"name": "Creature", "children": [0, mesh_node]})
    gltf = {
        "asset": {"version": "2.0", "generator": "SpriteSquirter tools/bake_creature.py"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": [{"name": "Creature", "primitives": [{"attributes": attrs, "indices": indices, "material": 0}]}],
        "materials": [{"name": "Hide", "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.7}}],
        "skins": [{"joints": list(range(len(BONE_NAMES))), "inverseBindMatrices": ibm_acc, "skeleton": 0}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob += b"\0" * (-len(blob) % 4)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(text) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(text), b"JSON") + text)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob))


def main():
    {"tortoise": build_shapes, "squirrel": build_squirrel, "raven": build_raven, "balrog": build_balrog}[SPECIES]()
    verts, normals, faces = build_mesh()
    colours, joints, weights, glow = paint_and_skin(verts, normals)
    write_glb(verts, normals, faces, colours, joints, weights, glow)
    print(f"{OUT.name}: {len(verts)} vertices, {len(faces)} triangles, {len(BONE_NAMES)} bones, "
          f"{OUT.stat().st_size / 1e6:.1f} MB (cell {CELL} m)")


if __name__ == "__main__":
    main()
