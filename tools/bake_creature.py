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
CELL = float(sys.argv[1]) if len(sys.argv) > 1 else 0.1

# --- Colours (r, g, b, scaliness) ---------------------------------------------
SKIN = (0.20, 0.36, 0.24, 1.0)
SKIN_DARK = (0.12, 0.23, 0.20, 1.0)
BELLY = (0.74, 0.62, 0.34, 0.55)
HORN = (0.86, 0.80, 0.64, 0.0)
SPIKE = (0.10, 0.36, 0.38, 0.25)
GUM = (0.45, 0.14, 0.12, 0.0)

# --- Skeleton: name -> (parent, joint position) -------------------------------
BONES = {
    "pelvis": (None, (0.0, 5.4, 0.0)),
    "spine": ("pelvis", (0.0, 6.6, 0.1)),
    "chest": ("spine", (0.0, 8.2, 0.35)),
    "neck": ("chest", (0.0, 10.0, 0.7)),
    "head": ("neck", (0.0, 10.9, 1.0)),
    "jaw": ("head", (0.0, 10.55, 1.25)),
    "tail1": ("pelvis", (0.0, 5.2, -1.3)),
    "tail2": ("tail1", (0.0, 4.6, -2.8)),
    "tail3": ("tail2", (0.0, 4.1, -4.2)),
    "tail4": ("tail3", (0.0, 3.8, -5.4)),
}
for side, sx in (("l", -1.0), ("r", 1.0)):
    BONES[f"arm_upper_{side}"] = ("chest", (sx * 2.3, 9.1, 0.4))
    BONES[f"arm_lower_{side}"] = (f"arm_upper_{side}", (sx * 3.4, 7.4, 0.5))
    BONES[f"hand_{side}"] = (f"arm_lower_{side}", (sx * 4.1, 5.8, 1.0))
    BONES[f"thigh_{side}"] = ("pelvis", (sx * 1.35, 5.2, 0.0))
    BONES[f"shin_{side}"] = (f"thigh_{side}", (sx * 1.5, 2.9, 0.7))
    BONES[f"foot_{side}"] = (f"shin_{side}", (sx * 1.5, 0.75, -0.1))
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
    # Torso
    ellipsoid((0, 5.3, -0.1), (2.0, 1.5, 1.7), "pelvis")
    ellipsoid((0, 6.7, 0.45), (2.25, 2.0, 2.0), "spine")
    ellipsoid((0, 6.9, 1.5), (1.55, 1.9, 1.0), "spine", BELLY)
    ellipsoid((0, 8.5, 0.3), (2.3, 1.7, 1.65), "chest")
    ellipsoid((0, 8.6, 1.35), (1.5, 1.2, 0.7), "chest", BELLY)
    ellipsoid((0, 9.4, -0.35), (1.9, 1.0, 1.3), "chest", SKIN_DARK)
    cone((0, 9.6, 0.4), (0, 10.6, 0.8), 1.2, 1.0, "neck")
    cone((0, 9.5, 1.1), (0, 10.3, 1.35), 0.7, 0.6, "neck", BELLY)

    # Head
    ellipsoid((0, 11.2, 1.0), (1.35, 1.2, 1.45), "head")
    ellipsoid((0, 11.72, 1.85), (1.15, 0.36, 0.55), "head", SKIN_DARK, 0.3)
    cone((0, 10.95, 1.6), (0, 10.82, 2.95), 0.95, 0.68, "head")
    ellipsoid((0, 11.0, 3.3), (0.52, 0.4, 0.36), "head", SKIN_DARK, 0.3)
    cone((0, 10.3, 1.25), (0, 10.22, 2.8), 0.72, 0.5, "jaw", BELLY, 0.25)
    # Crest and back spines
    for a, b, bone in [((0, 12.2, 0.6), (0, 13.0, 0.0), "head"), ((0, 11.9, -0.1), (0, 12.5, -0.8), "head"),
                       ((0, 10.7, -0.5), (0, 11.4, -1.4), "neck"), ((0, 9.7, -1.3), (0, 10.4, -2.3), "chest"),
                       ((0, 8.5, -1.5), (0, 8.9, -2.6), "chest"), ((0, 7.2, -1.6), (0, 7.4, -2.7), "spine"),
                       ((0, 6.0, -1.6), (0, 6.0, -2.6), "pelvis")]:
        cone(a, b, 0.42, 0.05, bone, SPIKE, 0.3)

    # Tail
    tail = [((0, 5.2, -1.3), 1.3), ((0, 4.6, -2.8), 1.02), ((0, 4.1, -4.2), 0.76), ((0, 3.8, -5.4), 0.52), ((0, 3.75, -6.5), 0.26)]
    for i in range(4):
        cone(tail[i][0], tail[i + 1][0], tail[i][1], tail[i + 1][1], f"tail{i + 1}")
        top = np.array(tail[i][0]) * 0.5 + np.array(tail[i + 1][0]) * 0.5 + np.array((0, tail[i + 1][1] * 0.8, 0))
        cone(top, top + np.array((0, 0.7 - i * 0.1, -0.5)), 0.3, 0.04, f"tail{i + 1}", SPIKE, 0.25)
    ellipsoid((0, 3.75, -6.85), (0.5, 0.42, 0.62), "tail4", SKIN_DARK, 0.3)
    for sx in (-1, 1):
        cone((sx * 0.3, 3.8, -6.9), (sx * 0.95, 4.0, -7.2), 0.2, 0.03, "tail4", HORN, 0.15)

    for side, sx in (("l", -1.0), ("r", 1.0)):
        # Face details
        ellipsoid((sx * 0.92, 10.85, 1.3), (0.55, 0.6, 0.72), "head")
        ellipsoid((sx * 1.42, 11.35, 0.45), (0.22, 0.62, 0.5), "head", SKIN_DARK, 0.25)
        cone((sx * 0.85, 12.0, 0.6), (sx * 1.55, 12.95, 0.3), 0.44, 0.32, "head", HORN, 0.2)
        cone((sx * 1.55, 12.95, 0.3), (sx * 1.8, 13.85, 0.75), 0.32, 0.15, "head", HORN, 0.1)
        cone((sx * 1.8, 13.85, 0.75), (sx * 1.6, 14.35, 1.3), 0.15, 0.03, "head", HORN, 0.08)
        cone((sx * 0.46, 10.55, 2.95), (sx * 0.46, 9.95, 3.02), 0.14, 0.02, "head", HORN, 0.1)
        for k in range(3):
            z = 2.45 - k * 0.42
            cone((sx * (0.6 + k * 0.05), 10.5, z), (sx * (0.62 + k * 0.05), 10.15, z), 0.1, 0.02, "head", HORN, 0.08)
        hole((sx * 0.66, 11.32, 2.08), 0.36)
        hole((sx * 0.22, 11.08, 3.62), 0.1, 0.05)

        # Arms (held out a little so the skin separates cleanly from the body)
        ellipsoid((sx * 2.3, 9.1, 0.4), (0.98, 0.92, 0.92), f"arm_upper_{side}")
        cone((sx * 2.3, 9.1, 0.4), (sx * 3.4, 7.4, 0.5), 0.8, 0.6, f"arm_upper_{side}", SKIN, 0.4)
        cone((sx * 3.4, 7.4, 0.5), (sx * 4.1, 5.8, 1.0), 0.68, 0.48, f"arm_lower_{side}", SKIN, 0.3)
        ellipsoid((sx * 3.72, 6.9, 0.5), (0.3, 0.5, 0.3), f"arm_lower_{side}", SPIKE, 0.25)
        ellipsoid((sx * 4.25, 5.35, 1.15), (0.56, 0.58, 0.6), f"hand_{side}", SKIN, 0.3)
        for k, dx in enumerate((-0.38, 0.0, 0.38)):
            base = np.array((sx * 4.25 + dx, 5.1, 1.4))
            mid = base + np.array((dx * 0.25, -0.55, 0.3))
            cone(base, mid, 0.22, 0.16, f"hand_{side}", SKIN, 0.2)
            cone(mid, mid + np.array((dx * 0.1, -0.5, 0.22)), 0.14, 0.02, f"hand_{side}", HORN, 0.06)

        # Legs
        cone((sx * 1.35, 5.2, 0.0), (sx * 1.5, 2.9, 0.7), 1.28, 0.85, f"thigh_{side}", SKIN, 0.5)
        ellipsoid((sx * 1.5, 2.9, 1.05), (0.55, 0.6, 0.45), f"shin_{side}", SKIN_DARK, 0.3)
        cone((sx * 1.5, 2.9, 0.7), (sx * 1.5, 0.95, -0.1), 0.86, 0.6, f"shin_{side}", SKIN, 0.35)
        ellipsoid((sx * 1.5, 2.0, -0.2), (0.68, 0.9, 0.7), f"shin_{side}", SKIN, 0.4)
        ellipsoid((sx * 1.5, 0.55, 0.6), (0.9, 0.55, 1.35), f"foot_{side}", SKIN, 0.3)
        ellipsoid((sx * 1.5, 0.5, -0.4), (0.62, 0.5, 0.56), f"foot_{side}", SKIN, 0.3)
        for dx in (-0.55, 0.0, 0.55):
            base = np.array((sx * 1.5 + dx, 0.42, 1.55))
            mid = base + np.array((dx * 0.35, -0.08, 0.7))
            cone(base, mid, 0.36, 0.27, f"foot_{side}", SKIN, 0.2)
            cone(mid, mid + np.array((dx * 0.1, -0.1, 0.55)), 0.22, 0.03, f"foot_{side}", HORN, 0.06)


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
    return 0.05 * n + 0.025 * n2


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
    lo = np.array((-5.3, -0.4, -7.9))
    hi = np.array((5.3, 14.9, 4.3))
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
    shade = 1.0 - 0.3 * np.clip(-normals[:, 2], 0, 1) * scaly[:, 0] - 0.2 * np.clip(-normals[:, 1], 0, 1)
    mottle = 1.0 + 0.12 * np.sin(verts[:, 0] * 2.3 + verts[:, 1] * 1.1) * np.sin(verts[:, 1] * 2.9 + verts[:, 2] * 1.7)
    rgb = np.clip(rgb * shade[:, None] * mottle[:, None], 0, 1)
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
