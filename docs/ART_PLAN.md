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
   they are code-made (0.36): a stomp
   lifts the thigh high and slams it down, and dead it topples onto its
   face.
   - ✅ (0.37) Claw slash, made in Blender by Claude (Nov 2026), in place
     of the punch: `assets/creature/balrog_claw_slash.blend` is the source
     (actions `ClawSlash_R` and its mirror `ClawSlash_L`, 30 frames at 24
     fps = 1.25 s; the claw lands at frame 14, about the game's
     `STRIKE_LANDS` of 0.6 s, and a timeline marker shows it), and
     `balrog_claw_slash.glb` is what the game plays (`balrog.gd`, one claw
     and then the other). A wind-up with the claw raised above the head
     and a pause at the top, a fast diagonal slash across the body, a heavy
     follow-through and a slow recovery; the feet stay planted. Rebuild
     both with `tools/balrog_claw_slash.py` (its key poses are a table at
     the top). Preview: `docs/balrog_claw_slash_preview.gif`.
5. ✅ (0.36) No separate eyes or jaw any more. Its wings are in the mesh
   and cannot flap (no wing bones); ask the owner if they should.
6. ✅ (0.36) Looked at in the game, smoke test run, pushed.

## The newer balrog (ArtShift branch, 0.38)

`assets/test/NewerBalrog.glb`, the owner's newer Meshy model (Nov 2026),
shown on its own by the **Test environment** button on the title menu
(`scripts/game/test_environment.gd`): its own PBR materials with no cel
shading or outline, under studio lights (key with shadows, fill, rim) and
a soft sky, tone mapped (ACES), with the game's camera. It is not in the
game yet.

- 9,832 triangles, 1.7 m tall, faces +Z. One material with three 4096 x
  4096 maps: colour, normal, and metal/roughness. They import lossless
  (no VRAM compression) so it looks as it does on Meshy. No emission map:
  the lava cracks are painted into the colour map, and nothing in the file
  makes them glow.
- No lights or cameras in the file: Meshy's look comes from its viewer's
  lighting, which the test environment imitates.
- A new skeleton, 43 bones (`SmartRigArmature`, named `Bone_000` to
  `Bone_042`, not Mixamo names): a 5-bone spine to the neck, a 3-bone
  head and neck chain, arms of 5 (shoulder to hand), legs of 5 (hip to
  toe), **wings of 4 bones each**, a **3-bone tail**, and a 3-bone flap
  hanging at the front. "Show skeleton" draws it.
- ✅ (0.39) **Walk**, made by Claude with `tools/newer_balrog_walk.py`
  (Blender, run headless). Source: `assets/test/NewerBalrog.blend` (the
  model and its `Walk` action; its textures are the PNGs next to it, not
  packed in). The test environment plays `NewerBalrog_walk.glb` (the
  skeleton and the clip). 1.8 s for two steps, in place, at 0.341 m/s at
  model size (2.2 m/s at the test environment's 6.5x, near the game
  balrog's 2.3), so the clip plays as fast as it walks and planted hooves
  do not slide.
  - Horse-like hind legs: the hoof lands flat and takes the weight, stays
    planted, the heel rolls up over the front of the hoof, the hoof curls
    toe-down and swings forward, flattens, and lands again (62% of the
    cycle on the ground: a heavy walk).
  - Mass: the body sinks just after each hoof lands, sways late over the
    standing leg, the free hip drops, hips and shoulders turn against each
    other, arms and tail swing late, the head stays steady with a small
    nod. The wings do not flap: each footfall's jolt makes them dip a
    little and spring back, the tips last.
  - In the test environment ("Walk") it walks round a wide circle and,
    like an elephant, takes about 4 s to reach full speed and as long to
    stop (`MASS_RESPONSE`), its upper body leaning into the change.

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
