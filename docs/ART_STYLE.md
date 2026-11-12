# Art style

**Stylised realism.** Not low-poly and not photoreal: rounded shapes with
plenty of polygons, readable painterly textures, and strong, colourful
lighting. Reference: modern stylised fantasy survival games. Creature scale
follows the classic "god game" idea: a giant that towers over houses, with
villagers no taller than its toes.

## Rules of thumb

- **Shapes:** bevelled edges, lathed curves, slight wonkiness. Nothing is
  perfectly straight: floors twist, towers lean, roofs sag.
- **Textures:** every surface has visible material detail (stone courses,
  wood grain, shingles, scales) plus a normal map, but colours stay clean
  and saturated. No photo textures.
- **Base palette:** taken from a sunlit green meadow. Grass runs from deep
  green roots to yellow-green tips; leaves from dark green to lime; bark
  is grey-brown; timber is dark brown; stone is warm grey with moss.
  Accent colours (roofs, plaster, mushroom caps, cloth) are saturated but
  earthy. All of it lives at the top of `scripts/core/art.gd`.
- **Lighting moves the palette.** The base colours stay fixed; the mood
  (sun colour, ambient light, fog) pushes the whole frame toward orange at
  golden hour, blue in the dawn mist, or firelit at night. Moods are plain
  data in `scripts/world/atmosphere.gd`, so adding one is a copy-and-edit.
- **Effects glow.** Fire, embers and magic are brighter than white so they
  bloom; smoke and dust are soft and take on the mood's light.

## How the look is built

| Piece | Where | Notes |
|---|---|---|
| Textures | `tools/bake/patterns.gdshader` → `assets/textures/` | Procedural patterns baked to PNG. Each surface has a detail map (brightness, per-element random tint, height) and a normal map. |
| Surfaces | `shaders/surface.gdshader`, `Art.surface()` | Triplanar, so meshes need no UVs. Two tint colours per material, optional moss, burn/char effect. |
| Shapes | `scripts/core/mesh_builder.gd` | Lathes, bevelled boxes, tubes, blobs, curved sheets, leaf cards. |
| Terrain | `shaders/terrain.gdshader` | Blends grass, dirt, sand, rock and snow by height, slope and painted masks. |
| Grass | `shaders/grass.gdshader`, `scripts/world/grass.gd` | Instanced blades placed by the shader from the height texture. |
| Trees | `scripts/world/flora_factory.gd`, `shaders/foliage.gdshader` | Tube trunks plus clumps of leaf cards shaded as soft volumes. |
| Creature | `tools/bake_creature.py` → `assets/creature/creature.glb` | Sculpted from blended soft shapes, auto-painted and auto-skinned. Opens in Blender like any glTF file. |
| Lighting | `scripts/world/atmosphere.gd`, `shaders/sky.gdshader` | Sun, sky, volumetric fog, colour grading, moods. |

## Swapping in hand-made or AI-made art later

Nothing here blocks real assets. A Blender or AI-generated model can
replace any generated mesh: export it as `.glb`, load it instead of the
factory output, and keep using `Art` materials or its own. The creature
only needs the same bone names as the generated skeleton.
