# Art style

**Surreal and cel shaded.** A comic-book look: light falls in flat bands,
everything has a black ink outline, colours are bold, and the world is
strange: an island floating in the sky, buildings shaped like moons,
mushrooms and singing boulders, and a gloomy tortoise the size of a house.

## Rules of thumb

- **Cel shading:** two or three flat tones per surface with hard edges
  between them, and crisp shadows. No soft gradients, no shiny highlights.
- **Ink:** a black outline round every object, plus ink lines inside the
  textures (between bricks, planks, shingles, scales and rock cracks).
- **Dimension:** the sun is never overhead. It always comes in from the
  side (under about 35 degrees up), so every shape shows a lit side, a
  shaded side and a cast shadow.
- **Shapes:** fat, wonky and rounded. Towers lean, roofs sag, hats curl.
- **Buildings:** modelled on the concept drawings: treehouse Homes with
  rope bridges, crystal tower, moon tower, mushroom house, singing rocks,
  store-in-a-tree, winged windmill, the Necromancer tower with its giant
  horned skull, gooblin hut. Their colours are fixed and saturated.
- **Gooblin buildings:** crooked dark planks under roofs of coloured rags
  (red, purple, blue, orange, green), held down by crossed bones with a
  horned skull over the door, and sharpened stakes round the bottom.
- **Fire:** tongues of flame are solid teardrop shapes with hard colour
  bands (`shaders/flame.gdshader`), not sprites, so a fire looks right
  from above.
- **The giant bat:** dark fur, torn purple-grey wings, armour and bone
  spikes strapped to its back, a pig's snout and fangs.
- **The raven** (the owner's Meshy model): stands like a man. Glossy
  blue-black feathers, a heavy beak, glowing purple eyes, grey scaly
  three-fingered hands and bird's feet with dark claws, a fan of tail
  feathers and two great wings spread wide.
- **The balrog:** as broad as it is tall. Dark cracked hide with glowing
  lines between the scales, ridged ram's horns, glowing purple eyes that
  trail fire, a glowing scar on the chest, iron armour with purple
  panels, purple rags, cloven hooves, a bladed tail and two little wings.
- **The undead:** necromancers wear black with glowing purple runes;
  skeletons are bone-white with inked eye sockets and ribs.
- **Nature follows a palette:** grass, trees, rocks, dirt and water take
  their colours from the current palette (Meadow, Candy, Autumn, Alien,
  Frost, Ember), which can be switched while playing from the dev menu.
- **Things that glow really glow:** fire, crystals, runes, the moon and
  lit windows are the only things that bloom.

## How the look is built

| Piece | Where | Notes |
|---|---|---|
| Cel shading | `shaders/toon.gdshaderinc` | One light function shared by every lit shader: sunlight on or off, halftone dots where they meet. Shadow colour and darkness come from `ambient_color` / `ambient_energy` in `Atmosphere.MOODS`. |
| Terrain inking | `shaders/terrain.gdshader` | Flat patches of colour, hatched pen strokes, an ink line where grass meets rock, dirt or sand. |
| Characters | `scripts/units/villager.gd` (`_villager_near`, `_goblin_near`, `_leg_parts`, `_arm_parts`, `_head`, ...) | Two sets of meshes per look: simple far away, detailed within the dev menu's villager detail distance. Legs and arms are each two meshes, hinged at the knee and the elbow. Small black shapes (`INK`) draw brows, mouths and seams. |
| Tortoise face | `scripts/units/creature.gd` (`_update_face`, `_draw_mouth`) | Pupils, lids and the mouth line are separate pieces moved by code. |
| Fire | `shaders/particle.gdshader` | Each particle is a flame tongue drawn by the shader, in hard bands of colour. |
| Outlines | `shaders/outline.gdshader` | Second material pass: back faces pushed outwards, drawn black. |
| Surfaces | `shaders/surface.gdshader`, `Art.surface()` / `Art.paint()` | Triplanar textures reduced to flat tones plus ink lines. Buildings are coloured per shape with `MeshBuilder.color`. |
| Palettes | `Art.PALETTES`, `Art.set_palette()` | Add a dictionary to get a new button in the dev menu. |
| Weather | `Atmosphere.MOODS` | Sun angle and colour, sky, haze. Add a dictionary for a new mood. |
| Shapes | `scripts/core/mesh_builder.gd` | Lathes, bevelled boxes, tubes, blobs, curved sheets. |
| Buildings | `scripts/world/building_factory.gd` | One function per building design. |
| Island | `scripts/world/terrain.gd` | Outline, underside, rivers and waterfalls. |
| Creatures | `tools/bake_creature.py` → `assets/creature/creature.glb` (tortoise), `squirrel.glb` | Sculpted from blended soft shapes, auto-painted and auto-skinned. |
| Raven, balrog | The owner's Meshy models: `assets/creature/raven.glb` (rigged by `tools/raven_rig.py`), `balrog.glb` and `assets/test/NewerBalrog*.glb` | Their own painted textures; see `docs/ART_PLAN.md`. |
| Textures | `tools/bake/patterns.gdshader` → `assets/textures/` | Procedural patterns baked to PNG. |

## Swapping in hand-made or AI-made art later

A Blender or AI-generated model can replace any generated mesh: export it
as `.glb`, load it instead of the factory output, and give it a material
from `Art` so it picks up the cel shading and outline. The creature only
needs the same bone names as the generated skeleton.
