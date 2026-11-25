"""Builds assets/buildings/StoreHouseAlt.glb: a cleaned-up copy of the owner's
Meshy storehouse (StoreHouse.glb, which is left as it is).

  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b --factory-startup \
      --python tools/storehouse_alt.py [-- render_dir]

What it does:
  1. A sharper texture. Meshy's 2048 px texture gives most of its room to the
     leaves, so the house walls get a few blurry pixels each. The model is
     unwrapped again (Smart UV Project) with the leaves' pieces shrunk to a
     third, so the houses get far more of a 4096 px texture, and the old
     texture is baked onto it.
  2. Cleaner paint. The baked texture loses its finest speckle (a small,
     edge-keeping guided filter), is sharpened twice (unsharp mask: wide for
     the soft edges Meshy painted, then fine) and gets a little more colour
     and contrast.
  3. Straighter lines. The nearly flat panels (walls, floors, roofs, doors)
     are found, and each is flattened onto a plane; walls within
     WALL_SNAP_DEG of upright are stood exactly upright, and floors within
     FLOOR_SNAP_DEG of level are levelled. Every vertex moves at most
     MAX_MOVE (in the model's own units, 120 tall), so the tree, roots and
     leaves keep their shapes.
With a render_dir it also writes before-and-after pictures there.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ROOT = "C:/Gray/SpriteSquirter/"
SOURCE = ROOT + "assets/buildings/StoreHouse.glb"
OUT = ROOT + "assets/buildings/StoreHouseAlt.glb"
TEX_SIZE = 4096
LEAF_SHRINK = 0.33
SMOOTH_RADIUS = 2
SMOOTH_EPS = 0.0008
SHARPEN_WIDE = (6, 1.4)
SHARPEN_FINE = (2, 0.0)
SATURATION = 1.1
CONTRAST = 1.05
PANEL_ANGLE_DEG = 11.0
PANEL_MIN_AREA = 6.0
WALL_SNAP_DEG = 12.0
FLOOR_SNAP_DEG = 10.0
MAX_MOVE = 1.2

render_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else ""


def load_source():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    src = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = src
    src.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    src.name = "StoreHouse_src"
    return src


def source_pixels(src):
    img = src.data.materials[0].node_tree.nodes["Image Texture"].image if "Image Texture" in src.data.materials[0].node_tree.nodes else None
    if img is None:
        for n in src.data.materials[0].node_tree.nodes:
            if n.type == "TEX_IMAGE":
                img = n.image
    w, h = img.size
    return img, np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)


# --- 1. A new unwrap with the leaves made small, and the bake -----------------------

def leaf_faces(obj, px):
    """Faces whose colour (sampled from the old texture) is leaf green."""
    h, w = px.shape[:2]
    uv = obj.data.uv_layers[0].data
    out = set()
    for poly in obj.data.polygons:
        cu = sum((uv[i].uv for i in poly.loop_indices), Vector((0, 0))) / poly.loop_total
        x = min(w - 1, max(0, int(cu.x * w)))
        y = min(h - 1, max(0, int(cu.y * h)))
        r, g, b = px[y, x, :3]
        if g > r * 1.35 and g > b * 1.35 and g > 0.12:
            out.add(poly.index)
    return out


def unwrap(target, leaves):
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    new_uv = target.data.uv_layers.new(name="Clean")
    target.data.uv_layers.active = new_uv
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Islands: faces joined by edges whose UVs match on both sides.
    bm = bmesh.new()
    bm.from_mesh(target.data)
    bm.faces.ensure_lookup_table()
    layer = bm.loops.layers.uv["Clean"]
    parent = list(range(len(bm.faces)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f1, f2 = e.link_faces
        uv1 = {l.vert.index: l[layer].uv.copy() for l in f1.loops if l.vert in e.verts}
        uv2 = {l.vert.index: l[layer].uv.copy() for l in f2.loops if l.vert in e.verts}
        if all((uv1[k] - uv2[k]).length < 1e-5 for k in uv1):
            parent[find(f1.index)] = find(f2.index)
    islands = {}
    for f in bm.faces:
        islands.setdefault(find(f.index), []).append(f)
    # An island that is mostly leaf is shrunk about its middle.
    for faces in islands.values():
        leafy = sum(1 for f in faces if f.index in leaves)
        if leafy * 2 < len(faces):
            continue
        uvs = [l[layer] for f in faces for l in f.loops]
        mid = sum((u.uv for u in uvs), Vector((0, 0))) / len(uvs)
        for u in uvs:
            u.uv = mid + (u.uv - mid) * LEAF_SHRINK
    bm.to_mesh(target.data)
    bm.free()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(src, target, src_img):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16  # (smooth edges: one sample gives stair steps)
    # The old texture shines as it is (emission), so the bake copies it.
    mat = src.data.materials[0]
    nt = mat.node_tree
    tex = [n for n in nt.nodes if n.type == "TEX_IMAGE"][0]
    emit = nt.nodes.new("ShaderNodeEmission")
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    baked = bpy.data.images.new("StoreHouseAlt_tex", TEX_SIZE, TEX_SIZE, alpha=False)
    tmat = bpy.data.materials.new("StoreHouseAlt")
    tmat.use_nodes = True
    tnt = tmat.node_tree
    ttex = tnt.nodes.new("ShaderNodeTexImage")
    ttex.image = baked
    tnt.nodes.active = ttex
    target.data.materials.clear()
    target.data.materials.append(tmat)
    bpy.ops.object.select_all(action="DESELECT")
    src.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.05
    scene.render.bake.max_ray_distance = 0.2
    scene.render.bake.margin = 24
    bpy.ops.object.bake(type="EMIT")
    return baked, tmat, ttex


# --- 2. Cleaner paint ----------------------------------------------------------------

def blur(a, radius):
    """A box blur, three times over (about a Gaussian), on an HxWxC array."""
    out = a
    for _ in range(3):
        for axis in (0, 1):
            c = np.cumsum(np.pad(out, [(radius + 1, radius) if i == axis else (0, 0) for i in range(out.ndim)], mode="edge"), axis=axis)
            hi = np.take(c, range(2 * radius + 1, c.shape[axis]), axis=axis)
            lo = np.take(c, range(0, c.shape[axis] - 2 * radius - 1), axis=axis)
            out = (hi - lo) / (2 * radius + 1)
    return out


def clean_paint(img):
    """Takes out the finest of Meshy's speckle while keeping the edges (a
    small guided filter), then sharpens it twice (wide, for the soft edges
    the old texture has, then fine) and lifts the colour a little."""
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[..., :3]
    guide = rgb.mean(-1, keepdims=True)
    r = SMOOTH_RADIUS
    mean_i = blur(guide, r)
    var_i = blur(guide * guide, r) - mean_i * mean_i
    mean_p = blur(rgb, r)
    cov = blur(guide * rgb, r) - mean_i * mean_p
    a = cov / (var_i + SMOOTH_EPS)
    b = mean_p - a * mean_i
    smooth = blur(a, r) * guide + blur(b, r)
    # Sharpened twice: wide, for the soft edges the old texture had, and fine.
    sharp = smooth + SHARPEN_WIDE[1] * (smooth - blur(smooth, SHARPEN_WIDE[0]))
    sharp = sharp + SHARPEN_FINE[1] * (sharp - blur(sharp, SHARPEN_FINE[0]))
    grey = sharp.mean(-1, keepdims=True)
    lifted = grey + (sharp - grey) * SATURATION
    px[..., :3] = np.clip((lifted - 0.5) * CONTRAST + 0.5, 0.0, 1.0)
    px[..., 3] = 1.0
    img.pixels[:] = px.reshape(-1)


# --- 3. Straighter lines ----------------------------------------------------------

def straighten(obj):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    limit = math.cos(math.radians(PANEL_ANGLE_DEG))
    region = [-1] * len(bm.faces)
    panels = []
    order = sorted(bm.faces, key=lambda f: -f.calc_area())
    for seed in order:
        if region[seed.index] >= 0:
            continue
        rid = len(panels)
        faces = [seed]
        region[seed.index] = rid
        normal = seed.normal * seed.calc_area()
        stack = [seed]
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if region[g.index] >= 0:
                        continue
                    n = normal.normalized()
                    if g.normal.dot(n) < limit or g.normal.dot(f.normal) < limit:
                        continue
                    region[g.index] = rid
                    faces.append(g)
                    normal += g.normal * g.calc_area()
                    stack.append(g)
        area = sum(f.calc_area() for f in faces)
        panels.append({"faces": faces, "area": area, "normal": normal.normalized()})
    planes = {}
    for rid, p in enumerate(panels):
        if p["area"] < PANEL_MIN_AREA or len(p["faces"]) < 3:
            continue
        n = p["normal"].copy()
        tilt = math.degrees(math.asin(max(-1.0, min(1.0, n.z))))
        if abs(tilt) < WALL_SNAP_DEG:
            n.z = 0.0
            n.normalize()
        elif abs(tilt) > 90.0 - FLOOR_SNAP_DEG:
            n = Vector((0.0, 0.0, 1.0 if n.z > 0 else -1.0))
        total = sum(f.calc_area() for f in p["faces"])
        d = sum(n.dot(f.calc_center_median()) * f.calc_area() for f in p["faces"]) / total
        planes[rid] = (n, d)
    vert_planes = {}
    for rid, (n, d) in planes.items():
        for f in panels[rid]["faces"]:
            for v in f.verts:
                vert_planes.setdefault(v.index, set()).add(rid)
    start = {i: bm.verts[i].co.copy() for i in vert_planes}
    for _ in range(12):
        for i, rids in vert_planes.items():
            v = bm.verts[i]
            p = v.co.copy()
            for rid in rids:
                n, d = planes[rid]
                p -= n * (n.dot(p) - d)
            move = p - start[i]
            if move.length > MAX_MOVE:
                move = move.normalized() * MAX_MOVE
            v.co = start[i] + move
    bm.to_mesh(me)
    bm.free()
    me.update()
    return len(planes), len(vert_planes)


def render(obj, name):
    if not render_dir:
        return
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 1000
    hidden = [o for o in scene.objects if o.type == "MESH" and o != obj]
    for o in hidden:
        o.hide_render = True
    obj.hide_render = False
    cam = scene.camera
    if cam is None:
        cd = bpy.data.cameras.new("cam")
        cam = bpy.data.objects.new("cam", cd)
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 130
    for view, az, el in [("three", 40, 22), ("close", 40, 15)]:
        a, e = math.radians(az), math.radians(el)
        c = Vector((0, 0, 60 if view == "three" else 25))
        cam.data.ortho_scale = 130 if view == "three" else 55
        cam.location = c + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * 300
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(render_dir, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    for o in hidden:
        o.hide_render = False


def main():
    src = load_source()
    src_img, src_px = source_pixels(src)
    render(src, "before")
    target = src.copy()
    target.data = src.data.copy()
    target.name = "StoreHouseAlt"
    bpy.context.scene.collection.objects.link(target)
    leaves = leaf_faces(target, src_px)
    print("leaf faces", len(leaves), "of", len(target.data.polygons))
    unwrap(target, leaves)
    baked, tmat, ttex = bake(src, target, src_img)
    if os.environ.get("NO_CLEAN") != "1":
        clean_paint(baked)
    # Only the new unwrap is kept.
    old = target.data.uv_layers[0]
    if old.name != "Clean":
        target.data.uv_layers.remove(old)
    count, moved = straighten(target)
    print("panels straightened", count, "vertices on them", moved)
    bsdf = tmat.node_tree.nodes.get("Principled BSDF")
    tmat.node_tree.links.new(ttex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    baked.filepath_raw = ROOT + "assets/buildings/StoreHouseAlt_texture.png"
    baked.file_format = "PNG"
    baked.save()
    baked.pack()
    bpy.data.objects.remove(src, do_unlink=True)
    render(target, "after")
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB", export_image_format="AUTO")
    os.remove(ROOT + "assets/buildings/StoreHouseAlt_texture.png")
    print("wrote", OUT)


main()
