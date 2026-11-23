# Art plan: giants, villagers and animation

The owner's goals for the game's models and animation, and where the work
stands. Read this before any modelling, rigging or animation work, and keep
it up to date as steps are done.

## Words

- **Giants**: the player's creatures (tortoise, squirrel, raven) and the
  goblins' balrog, together.
- **Mesh**: the surface of a model (points, edges, faces).
- **UVs**: where each point of a mesh takes its colour from on a flat
  texture image.
- **Rig / skeleton**: bones inside a mesh; moving a bone moves the part of
  the mesh weighted to it.
- **Humanoid rig**: the standard two-legs, two-arms, spine, neck and head
  skeleton (Mixamo's bone names: `mixamorig:Hips`, `Spine`, `LeftUpLeg`,
  `LeftArm` ...). Animations made for one humanoid rig can be moved onto any
  other ("retargeting"), and Mixamo has a free library of them. Meshy's
  automatic rigging makes this kind of rig.

## Goals (from the owner)

1. **Better models for all the giants**, made in Meshy by the owner (and
   with Claude through the Meshy MCP), brought into the game.
2. **Better villagers and enemies later**: cleaned up, less clipping. Meshy
   models, or a mix of the owner and Claude making variations of villagers
   and goblins once the basic look is set.
3. **Animation for the giants**, a lot of it over time. It starts basic.
   Claude keeps animating, and the owner may animate by hand in Blender too,
   so the editable source of every animation stays in the repo.
   - Each giant must **move differently**, so it feels like its own animal.
   - They must **feel like giants**: heavy. Mass means slow starts and
     stops, weight shifting onto each foot before the next step, a pause at
     the top of a stomp, the ground shaking and dust at footfalls, follow-
     through after a strike (arms and tail keep swinging), slow turns.
4. **Trees**: their variety is good; no changes planned beyond the height
   variation added in 0.33 (up to 3 times as tall).
5. **Buildings** stay much as they are (built in code). Keep: the trees on
   buildings change colour with the colour palette, and rope bridges must
   keep working between treehouses.

## How the work is done

- **Desktop sessions** (Claude Code on the owner's computer) for art and
  animation: Blender with the Blender MCP add-on, Godot 4.7 and Git are
  installed there. Claude can build, rig and animate in the owner's open
  Blender while the owner watches, and run the game on the real graphics
  card to look at the result.
- **Cloud sessions** are fine for gameplay code.
- `main` is the single source for both. The usual rules in `CLAUDE.md` hold
  (version +0.01 per update, push the branch and `main`, keep the owner's
  `balancing.txt`).
- **Keep the sources**: each giant's `.blend` file goes in the repo next to
  its exported `.glb`, so either of us can change it later. Set up Git LFS
  for `.blend`, `.glb` and big `.png` files before many are added.

## How the giants work now

- Code: `scripts/units/creature.gd` (body, walking, attacks, the face),
  `creature_mind.gd` (choices), `balrog.gd`, `tools/bake_creature.py` (makes
  the tortoise, squirrel and raven `.glb` models from blobs).
- The player's creatures are `assets/creature/{creature,squirrel,raven}.glb`,
  each with the same bone names: `pelvis`, `spine`, `chest`, `neck`, `head`,
  `jaw`, `thigh_l/r`, `shin_l/r`, `foot_l/r`, `arm_upper_l/r`, `tail1` ...
  (the raven has wing bones too). The balrog is the Meshy model now (below).
- **All their movement is done in code** (`_update_legs()`, `_update_body()`,
  foot placement on the ground), not with animation clips. The shader
  (`shaders/creature.gdshader`) colours them with vertex colours and a
  triplanar texture, cel lighting and an ink outline; it uses no UVs.
- A new model with its own texture and animation clips needs: a shader that
  shows its UV texture in the game's cel style (with burn, tint, hit flash
  and glow), playing its clips (AnimationPlayer / AnimationTree, matched to
  its speed), and the code's touches on top (head turning to targets,
  leaning, footstep effects and stomp damage timed to the steps).

## The new balrog (owner's Meshy model)

Files the owner made in Meshy (Nov 2026): `BalrogRigged.glb`, now
`assets/creature/balrog.glb` in the game (its texture is extracted on
import as `balrog_Image_0.png`), and `BalrogModel.glb`, the bare mesh (not
needed). The old blob balrog is gone from the game; `bake_creature.py
balrog` still makes it, as `balrog_blob.glb`.

- 12,765 triangles, 1.86 m tall, one 2048x2048 colour texture (UV mapped),
  exported at 1/100 scale (armature scale 0.01), from Blender 4.5.
- Humanoid rig, 24 Mixamo-named bones (Godot names them `mixamorig_Hips`
  ...), plus `headfront` at the front of the face; no fingers, jaw, tail or
  wing bones (its wings and tail are part of the mesh and do not move).
- Faces +Z. Its rest pose is a wide, crouched fighting stance, which the
  game uses as its standing pose.
- Animations in it: **Walking** (1.03 s loop) and **Running** (0.63 s loop).
  No idle, attack, hit or death yet.

Plan:
1. ✅ (0.36) In the game as the balrog, scaled 6 times (`MODEL_SCALE` in
   `balrog.gd`) to about 11 m full grown, like the old one.
2. ✅ (0.36) `shaders/giant.gdshader`: its texture with the game's cel
   lighting and ink outline; bright, strongly coloured texels (the lava
   cracks, mouth, purple armour and eyes) glow and flicker. Not yet: burn,
   tint or a hit flash (the other giants have none either).
3. ✅ (0.36) The Walking clip plays as fast as the balrog really walks
   (`CLIP_SPEED`: the clip's feet carry the 1.86 m model 1.43 m a second),
   blended into the rest stance as it stops, and its footfalls (fire, dust,
   shaking, trampling) come when the clip's feet come down (`FOOTFALLS`).
   Code adds breathing, a lean into the stride, head turning to what it
   watches and back to spit fire. Running is not used (it never runs).
4. Idle, stomp, punch, fireball spit, hit and death: from Mixamo (same
   skeleton), or animated in Blender by the owner or Claude. Until then
   they are code-made (0.36): a punch aims the arm at the foe, a stomp
   lifts the thigh high and slams it down, and dead it topples onto its
   face.
5. ✅ (0.36) No separate eyes or jaw any more. Its wings are in the mesh
   and cannot flap (no wing bones); ask the owner if they should.
6. ✅ (0.36) Looked at in the game, smoke test run, pushed.

## The other giants

The owner will make new Meshy models for the tortoise, squirrel and raven.
They are not humanoid (four legs, or wings for arms), so Meshy's automatic
humanoid rig will not fit them well and Mixamo's animations will not either;
they will need rigs made in Blender (by the owner, or Claude through the
Blender MCP) and their own animations. Each should move in its own way:

- **Tortoise**: slow, deliberate, legs planted wide, body rocking side to
  side, a long pause before each step, head out low.
- **Squirrel**: quick and twitchy between bursts of stillness; runs on all
  fours; tail always moving.
- **Raven**: hops and struts on the ground, head bobbing; heavy wingbeats to
  take off; glides.
- **Balrog**: a heavy two-legged stride, shoulders rolling, fists and tail
  swinging, the ground smoking where it treads.
