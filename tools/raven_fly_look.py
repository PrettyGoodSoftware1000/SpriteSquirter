"""Gives the flying raven (assets/creature/raven_fly.blend) the walking
raven's sheen, without touching its texture colours.

    blender -b --factory-startup --python tools/raven_fly_look.py

Meshy made the two models' metal/roughness maps differently: the walker's is
rough (0.78 on average) and half metallic (0.48), which gives its feathers
their soft bluish sheen; the flier's is glossier (0.54) and hardly metallic
(0.03). In the flier's material, its roughness and metallic are each mapped
onto the walker's (the same average and spread), by nodes between the map
and the shader; the images themselves stay as they are.
"""
import bpy
import numpy as np

WALK = "C:/Gray/SpriteSquirter/assets/creature/raven_walk.blend"
FLY = "C:/Gray/SpriteSquirter/assets/creature/raven_fly.blend"


def stats(path):
    """Mean and spread of the green (roughness) and blue (metallic) channels
    of the model's metal/roughness map."""
    bpy.ops.wm.open_mainfile(filepath=path)
    mat = next(m for m in bpy.data.materials if m.users and m.node_tree)
    sep = next(n for n in mat.node_tree.nodes if n.type == "SEPARATE_COLOR")
    img = sep.inputs["Color"].links[0].from_node.image
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    return {"rough": (px[:, 1].mean(), px[:, 1].std()), "metal": (px[:, 2].mean(), px[:, 2].std())}


walk = stats(WALK)
fly = stats(FLY)
print("LOOK walk", walk, "fly", fly)
mat = next(m for m in bpy.data.materials if m.users and m.node_tree)
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
sep = next(n for n in nt.nodes if n.type == "SEPARATE_COLOR")
for old in [n for n in nt.nodes if n.name.startswith("Look ")]:
    nt.nodes.remove(old)
for channel, socket, key in (("Green", "Roughness", "rough"), ("Blue", "Metallic", "metal")):
    (wm, ws), (fm, fs) = walk[key], fly[key]
    scale = ws / max(fs, 1e-4)
    node = nt.nodes.new("ShaderNodeMath")
    node.name = node.label = "Look " + socket
    node.operation = "MULTIPLY_ADD"
    node.use_clamp = True
    node.inputs[1].default_value = scale
    node.inputs[2].default_value = wm - fm * scale
    node.location = (sep.location.x + 200, sep.location.y - (0 if key == "rough" else 160))
    nt.links.new(sep.outputs[channel], node.inputs[0])
    nt.links.new(node.outputs[0], bsdf.inputs[socket])
    print("LOOK %s: x %.3f + %.3f" % (socket, scale, wm - fm * scale))
bpy.ops.wm.save_as_mainfile(filepath=FLY)
import os
if os.path.exists(FLY + "1"):
    os.remove(FLY + "1")
print("LOOK saved", FLY)
