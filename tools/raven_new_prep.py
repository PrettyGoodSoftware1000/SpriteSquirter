"""Step 1 of the new raven: makes the owner's two Meshy models (art_sources/
raven/, too big for git) ready to rig, and saves them as
art_sources/raven/prep_walk.blend and prep_fly.blend.

    blender -b --factory-startup --python tools/raven_new_prep.py

  Raven3Spit.glb        the raven on the ground: body, and both wings apart
  RavenFlyingSplit.glb  the raven flying: body, wings, and the tail fan apart

For each:
  - Each part is cut down to a game's number of triangles (TARGET), after
    welding the points Meshy splits along its UV seams.
  - Scaled: the walking raven stands HEIGHT tall. Meshy fits each model to
    its own box, so the flying one is scaled to match by its body's surface
    area (the same creature, whatever its pose).
  - The textures are brought down to TEX px.
  - Its parts are named body, wings and tail.
The flying raven is pitched forward to fly level in tools/raven_new_rig.py.
Blender space: +Z up, the raven faces -Y.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "art_sources", "raven")
HEIGHT = 1.7
TEX = 2048
# Triangles each part is cut down to.
TARGET = {
    "walk": {"body": 70000, "wings": 60000},
    "fly": {"body": 60000, "wings": 60000, "tail": 9000},
}
# Which part is which, by its size order in Meshy's file (biggest first).
PARTS = {"walk": ["wings", "body"], "fly": ["wings", "body", "tail"]}


def area(obj):
    return sum(p.area for p in obj.data.polygons)


def load(tag, path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = sorted([o for o in bpy.context.scene.objects if o.type == "MESH"],
                    key=lambda o: -len(o.data.polygons))
    named = {}
    for name, obj in zip(PARTS[tag], meshes):
        obj.name = name
        obj.data.name = name
        named[name] = obj
    return named


def weld_and_cut(obj, target):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bm.to_mesh(obj.data)
    bm.free()
    faces = len(obj.data.polygons)
    mod = obj.modifiers.new("cut", "DECIMATE")
    mod.ratio = min(1.0, target / max(faces, 1))
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Smooth shading: the corners are shared (a smaller file) and the
    # feathers are not faceted.
    for p in obj.data.polygons:
        p.use_smooth = True
    print("  %s: %d -> %d faces" % (obj.name, faces, len(obj.data.polygons)))


def clean_jpeg(path):
    """Takes out the extra blocks Blender writes into a colour JPEG (a colour
    profile, a "NeoGeo" tag, notes): Godot's JPEG reader turns it down."""
    data = open(path, "rb").read()
    out = bytearray(data[:2])
    i = 2
    while i < len(data) - 4 and data[i] == 0xFF:
        marker = data[i + 1]
        length = int.from_bytes(data[i + 2:i + 4], "big")
        if marker == 0xDA:
            out += data[i:]
            break
        if not (0xE1 <= marker <= 0xEF or marker == 0xFE):
            out += data[i:i + 2 + length]
        i += 2 + length
    open(path, "wb").write(bytes(out))


def shrink_textures(tag):
    """Each texture TEX px, kept as a good JPEG (the colour, the normals and
    the metal/roughness map alike), so the files stay small."""
    for img in bpy.data.images:
        if img.size[0] > TEX:
            img.scale(TEX, TEX)
        path = os.path.join(SRC, "tex_%s_%s.jpg" % (tag, img.name))
        sc = bpy.context.scene
        sc.render.image_settings.file_format = "JPEG"
        sc.render.image_settings.quality = 93
        img.save_render(path, scene=sc)
        clean_jpeg(path)
        # The JPEG takes the old image's place (and only it is kept).
        new = bpy.data.images.load(path)
        new.colorspace_settings.name = img.colorspace_settings.name
        new.pack()
        for mat in bpy.data.materials:
            if mat.node_tree:
                for n in mat.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image == img:
                        n.image = new
        name = img.name
        bpy.data.images.remove(img)
        new.name = name


def main():
    scales = {}
    body_area = {}
    for tag, file in [("walk", "Raven3Spit.glb"), ("fly", "RavenFlyingSplit.glb")]:
        parts = load(tag, os.path.join(SRC, file))
        if tag == "walk":
            top = max((parts["body"].matrix_world @ v.co).z for v in parts["body"].data.vertices)
            scales[tag] = HEIGHT / top
        else:
            scales[tag] = scales["walk"] * math.sqrt(body_area["walk"] / area(parts["body"]))
        body_area[tag] = area(parts["body"]) * scales[tag] ** 2 if tag == "fly" else area(parts["body"])
        print(tag, "scale", scales[tag])
        for name, obj in parts.items():
            obj.data.transform(Matrix.Scale(scales[tag], 4))
            weld_and_cut(obj, TARGET[tag][name])
        mat = parts["body"].data.materials[0]
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                used = [l.to_socket.name + "@" + l.to_node.type for l in n.outputs["Color"].links]
                print("  image", n.image.name, n.image.size[:], "->", used)
        for img in list(bpy.data.images):
            img.use_fake_user = False
        shrink_textures(tag)
        out = os.path.join(SRC, "prep_%s.blend" % tag)
        bpy.ops.wm.save_as_mainfile(filepath=out)
        print("saved", out)


main()
