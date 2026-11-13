#!/usr/bin/env python3
"""Sculpts the creature and writes assets/creature/creature.glb.

The creature is described as a set of soft shapes (ellipsoids and tapered
capsules) that melt into each other. This script turns that description
into a dense, smooth mesh, paints it, and attaches it to a skeleton so the
game can animate it. To change the creature, edit build_shapes() below and
run:

    pip install numpy scikit-image
    python3 tools/bake_creature.py

Coordinates are metres: +Y up, +Z forward, origin on the ground between
the feet. Left limbs are at -X.
"""

import json
import struct
import sys
from pathlib import Path

import numpy as np
from skimage import measure

OUT = Path(__file__).resolve().parent.parent / "assets" / "creature" / "creature.glb"
CELL = float(sys.argv[1]) if len(sys.argv) > 1 else 0.08

# --- Colours (r, g, b, scaliness) ---------------------------------------------
SKIN = (0.46, 0.48, 0.25, 1.0)
SKIN_DARK = (0.33, 0.36, 0.19, 1.0)
SHELL = (0.36, 0.23, 0.12, 0.9)
SHELL_RIM = (0.50, 0.36, 0.19, 0.3)
BELLY = (0.68, 0.52, 0.31, 0.75)
HORN = (0.88, 0.83, 0.66, 0.0)

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
BONE_NAMES = list(BONES)

shapes = []  # dicts: kind, params, bone, colour, blend
holes = []


def ellipsoid(centre, radii, bone, colour=SKIN, blend=0.5):
    shapes.append({"kind": "el", "c": np.array(centre, float), "r": np.array(radii, float),
                   "bone": bone, "colour": colour, "k": blend})


def cone(a, b, r1, r2, bone, colour=SKIN, blend=0.5):
    shapes.append({"kind": "rc", "a": np.array(a, float), "b": np.array(b, float), "r1": r1, "r2": r2,
                   "bone": bone, "colour": colour, "k": blend})


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
    rgb, scaly = colours[:, :3], colours[:, 3:]
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
    return (colours * 255 + 0.5).astype(np.uint8), top.astype(np.uint8), q.astype(np.uint8)


# --- glTF writer ----------------------------------------------------------------

def write_glb(verts, normals, faces, colours, joints, weights):
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
        "TEXCOORD_1": add(np.column_stack((verts[:, 2], np.zeros(len(verts), np.float32))).astype(np.float32), FLOAT, "VEC2", 34962),
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
    build_shapes()
    verts, normals, faces = build_mesh()
    colours, joints, weights = paint_and_skin(verts, normals)
    write_glb(verts, normals, faces, colours, joints, weights)
    print(f"{OUT.name}: {len(verts)} vertices, {len(faces)} triangles, {len(BONE_NAMES)} bones, "
          f"{OUT.stat().st_size / 1e6:.1f} MB (cell {CELL} m)")


if __name__ == "__main__":
    main()
