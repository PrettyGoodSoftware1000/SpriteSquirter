# Art plan: giants, villagers and animation

The owner's goals for the game's models and animation, and where the work
stands. Read this before any modelling, rigging or animation work, and keep
it up to date as steps are done.

## Words

- **Giants**: the player's creatures (tortoise, squirrel, raven) and the
  gooblins' balrog, together.
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
   and gooblins once the basic look is set.
3. **Animation for the giants**, a lot of it over time. It starts basic.
   Claude keeps animating, and the owner may animate by hand in Blender too,
   so the editable source of every animation stays in the repo.
   - Each giant must **move differently**, so it feels like its own animal.
   - They must **feel like giants**: heavy. Mass means slow starts and
     stops, weight shifting onto each foot before the next step, a pause at
     the top of a stomp, the ground shaking and dust at footfalls, follow-
     through after a strike (arms and tail keep swinging), slow turns.
4. **Trees**: their variety is good; no changes planned beyond the height
   variation added in 0.33 (up to 3 times as tall; 2 times since 0.56).
5. **Buildings** stay much as they are (built in code). Keep: the trees on
   buildings change colour with the colour palette, and rope bridges must
   keep working between treehouses.
   - (0.48, ArtShift) The owner's Meshy storehouse,
     `assets/buildings/StoreHouse.glb`, is the new asset **Store house**
     (kind `store_house`) with the Storehouse job in `Names.txt`; the old
     **Stacked houses** is kept but has no job (out of the build menu). It
     wears its own painted texture (no cel shading or outline), about 14 m
     tall. The village's free first storehouse is whichever asset has the
     Storehouse job (`BuildingCatalog.kind_for_role()`).
   - (0.58) StoreHouseAlt is in the build menu as its own asset, with the
     gameplay effect Showpiece: it costs nothing and does nothing.
   - (0.55) **StoreHouseAlt**, for the owner to review (not in the game then):
     `assets/buildings/StoreHouseAlt.glb`, made from StoreHouse.glb (left
     as it is) by `tools/storehouse_alt.py`. Meshy's 2048 px texture gave
     most of its room to the leaves, so each house wall had a few blurry
     pixels; the model is unwrapped again with the leaves made small, the
     old texture baked onto a 4096 px one, sharpened (wide unsharp mask,
     edge-keeping), with a little more colour. Its nearly flat panels
     (walls, floors, roofs, doors) are flattened onto planes, walls stood
     upright and floors levelled (at most 1.2 of its 120 units a point). The
     texture can only be as detailed as Meshy's painting was: a sharper
     result needs a higher resolution texture from Meshy. Before and after:
     `docs/storehouse_alt_preview.png`.

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
  the tortoise and squirrel `.glb` models from blobs; the old blob raven now
  goes to `raven_blob.glb`, unused), `tools/raven_rig.py` (the raven).
- The player's creatures are `assets/creature/{creature,squirrel,raven}.glb`,
  each with the same bone names: `pelvis`, `spine`, `chest`, `neck`, `head`,
  `jaw`, `thigh_l/r`, `shin_l/r`, `foot_l/r`, `arm_upper_l/r`, `tail1` ...
  (the raven has wing and finger bones too, and no jaw). The raven and the
  balrog are Meshy models now (below).
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

Since 0.54 the test environment also has the game's own giants (the
tortoise, the squirrel, the raven and the balrog, as `Creature` and
`Balrog` animate them in the game), for checking their animation: one on
its own, or two set to fight each other (`Creature.duel_foe`), on flat
ground (`Terrain.generate_flat()`, not drawn) with the game's effects and
fires. There is a size slider and a "Walk somewhere" button.

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
- All its animations are made by Claude with `tools/newer_balrog_anims.py`
  (Blender, run headless). Source: `assets/test/NewerBalrog.blend` (the
  model and its actions; its textures are the PNGs next to it, not packed
  in). The test environment plays `NewerBalrog_anims.glb` (the skeleton,
  the skinned mesh without materials, and the clips), dressed in the
  model's own material.
- ✅ (0.39) **Walk** ("Walk one"): 1.8 s for two steps, in place, at 0.341 m/s at
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
  - In the test environment "Walk around" walks it round a wide circle
    and "Play walk in place" plays the walk on the spot (0.40); either way,
    like an elephant, takes about 4 s to reach full speed and as long to
    stop (`MASS_RESPONSE`), its upper body leaning into the change.
- ✅ (0.41) **Walk two** (`WalkTwo`): from the owner's notes on Walk one.
  A longer stride (0.48 m at model size, not 0.38) at the same speed, so
  2.27 s for two steps; the hoof lifts later, lower and more slowly and
  folds less (the knee and heel bent sharply at once looked rubbery); the
  shoulders turn against the hips with each step.
- ✅ (0.41) **Chain fix**: the chain belt round the waist (over the backs
  of the thighs) was skinned partly to the thighs and tail and stretched
  with each step. Its 1,134 vertices (found by the metal map, silver not
  gold, at belt height) now follow the hips (70%) and lower back (30%), so
  it moves as one piece. The fix is in `NewerBalrog_anims.glb` and the
  `.blend`, not in the original `NewerBalrog.glb`.
- ✅ (0.41) **Claw slash** (`ClawSlash`, 2.6 s): the left claw rises
  high and out with a pause at the top, swipes down and across as the
  torso twists into it (lands at 0.81 s); its follow-through winds up the
  right claw, which swipes back the other way (lands at 1.43 s); then a
  slow settle. Hooves stay planted, the hips drop with each blow, the
  wings trail the torso's turn and the tail counterbalances. Timeline
  markers in the `.blend` show where each claw lands. In the test
  environment it plays over the walk too (only the upper body then).

- ✅ (0.42) **Slash clean-up** (the owner: the left claw slash stretched
  the mesh), done live in the owner's Blender, measured by comparing every
  edge's length with its rest length (past 2x counts as torn):
  - Motion: arms never lock straight or fold tight (the hand stays at 85
    to 95% of the arm's length), wrists bend at most 40 degrees, the
    collarbone takes a share of each reach, the claw stays in front of the
    body and below the horns, a smaller torso twist and a looser hold on
    the head (it wrung the neck), the wing roots barely turn.
  - Skin: shoulder and arm points follow the arm or the wing, not both;
    shoulder weights smoothed so the skin blends from chest to arm; 99
    triangles that joined the inner arm to the torso (Meshy made it with
    its arms at its sides) removed, hidden in the armpits; the chain fix
    kept to the back (the front straps tore against the thighs).
  - Result: torn edges down by half at both shoulders and by about three
    quarters at the hips in the slash, and by half at the hips in Walk
    two. Some stretch is left where the upper arm swings ~90 degrees at the
    shoulder: linear skinning (what Godot uses) cannot hold that fully; a
    shoulder helper bone or corrective shapes would be the next step.
- ✅ (0.43) **Slash fixes** from the owner's notes on 0.42:
  - The elbows bent upward in the follow-throughs (frames ~29 and ~49):
    the arms are now solved as hinges, the upper arm placed by both its
    direction and the plane its elbow bends in, with one steady elbow
    direction (out, back and down) that never lines up with the arm.
  - A sudden twist from frame 8 to 9: the left wind-up's path passed right
    by its own shoulder, where a small move of the hand swings the arm a
    long way. Both wind-ups now arc out, clear of the shoulders, the arm
    eases in from its hanging pose, the wrist limit no longer flips, and
    a key without a claw direction eases the hand back instead of
    snapping. Above 15 degrees a frame is now only the swipes themselves.
  - Holes at the shoulders and back: 0.42's deleted armpit triangles are
    back (their weights are blended instead), and a weld step gives
    touching points the same weights, so the mesh's separate pieces never
    pull apart (0.42 had 172 cracks at the waist from the chain fix; now
    none in any frame).
- ✅ (0.44) **Slash fixes** from the owner's notes on 0.43:
  - The arm went inside the chest (frames ~25 and ~49): the swipes end
    further forward and cross the body less, elbows point out and down
    (away from the body), and the arm solver keeps elbow, forearm and
    wrist at least 0.36 m from the spine line (the chest reaches ~0.30),
    pushing the hand out if needed.
  - Extra fingers (13-26, 43): the hands are locked to the forearms (no
    wrist bend or twist, in the slash and the walks); bending the wrist
    left finger points behind.
  - Chest-to-armpit stretch at the wind-ups (18, 35): the claws rise to
    about chin height, out to the side rather than back, and the
    collarbone carries half of each reach (down ~25% at those frames).
- ✅ (0.45) **Horn chains clipped**: the owner asked for the chains that
  hang from the horns to go (they deformed badly: Meshy skinned them, with
  the shoulder armour and the lower horns, to the upper arms). 146 polygons
  of the two hanging strands are removed (`remove_horn_chains()`); the
  links wrapped round the horns, the chains on the shoulder armour, and the
  top two polygons on each side (horn, the owner checked) stay.
- ✅ (0.46) **Horn chain stubs and the left horn's hole**: the short stubs
  left hanging just under each horn tip go too (37 polygons,
  `remove_horn_stubs()`; the owner checked which, and the top two on each
  side, a spike on the armour and two polygons by the horn stay). The hole
  this left under the left horn is patched (`patch_left_horn()`: the
  mesh's pieces are joined near the tip and the closed holes filled, 3
  polygons, with the horn's texture).

- ✅ (0.47) **In the game** (ArtShift only): the gooblins' balrog is now the
  newer model. `balrog.gd` loads `NewerBalrog_anims.glb` (the re-skinned
  mesh and clips) dressed in `NewerBalrog.glb`'s own PBR material (no cel
  shading, no ink outline), scaled 6.5 times (11 m full grown), walks with
  WalkTwo (`CLIP_SPEED` 0.341, hooves landing at 0.01 and 0.51 of the
  cycle), and strikes with ClawSlash, each claw a blow as it lands (0.81
  and 1.43 s). Bones are mapped to Meshy's rig (`HIPS` Bone_000 ...). The
  stomp, fireball rear and death fall are still code-made on top. Smoke
  test passes.

## The new raven (owner's Meshy model, 0.51)

`assets/creature/RavenMeshyRig.glb`, the owner's Meshy model and rig (Nov
2026), kept as it came (Godot skips importing it). `tools/raven_rig.py`
(Blender, run headless) rigs it for the game and writes:

- `assets/creature/raven.blend`: the rig to look at, edit and animate, at
  the model's size (1.7 m tall, faces -Y), bones lying along the limbs,
  each finger bone's X axis the one it curls about.
- `assets/creature/raven.glb`: what the game loads, 8 times as big (13.6 m,
  like the old raven), every bone pointing up with no roll (what the game's
  procedural animation expects), with the model's texture (extracted on
  import as `raven_Image_0.png`, lossless).

The model: 15,858 triangles, one 2048 x 2048 colour texture, purple
glowing eyes painted on, a closed beak, wings spread at rest, three clawed
fingers and a thumb on each hand, bird legs (thigh, drumstick, long bone
above the toes, three toes forward and one back).

- ✅ (0.51) **Finger bones**: Meshy gave each hand one bone for all three
  fingers and a thumb bone hung from the upper arm. Each hand now has
  `thumb`, `index`, `middle` and `ring` (front to back), three bones each
  (`index1_l` at the knuckle, `index2_l`, `index3_l` the claw). They are
  found from the mesh: each claw tip is followed back along the finger to
  where it joins the palm, the bones run down its middle, and its skin is
  weighted along them with soft joints (the ring finger's hooked claw ends
  in two points; both are its). Curling every joint by 0.6 radians closes
  the hand into a fist with 3 stretched points out of 800.
- ✅ (0.51) **Symmetry**: Meshy's rig was lopsided. The -X wing had one
  chain of bones where the +X has two, so its long feathers were bound to
  the shoulder, the arm and the fingers. The +X side is mirrored onto the
  -X side, bones and skin weights both (the mesh is symmetric to about a
  millimetre, 3 cm at worst).
- ✅ (0.51) **Wings**: a `wing_l/r` bone (no skin of its own) at the
  shoulder carries the wing's bones (0.51: Meshy's two chains; 0.52: the
  fan below), so the wings beat without swinging the arms,
  which hang from the same joint. The thighs hang from the pelvis (Meshy
  hung them from the middle of the spine).
- ✅ (0.51) **In the game**: the raven wears its own texture (no cel
  shading or outline, like the balrog), with no drawn face or jaw. The
  game's code animates it like the others: legs by IK (its "foot" is the
  long bone above the toes, so its ankle is that bone's joint, 2.3 m up),
  arms hanging as modelled, wings opening out and beating in flight (see
  0.52 below). The
  fingers clench round what it holds or carries, spread when it strikes
  or stomps or is alert, and otherwise flex a little.
- ✅ (0.52) **Wings that open**: the owner wanted the wings spread wide
  to fly and flapping up and down. Meshy's outer chain ran down the
  wing's outer edge, so the wing could only swing as one stiff piece. Each
  wing is now a fan of ten bones built like a bird's: `wing_arm1` and
  `wing_arm2` along the leading edge from the shoulder to the wrist,
  primaries `wing_prim1a/b`, `wing_prim2a/b`, `wing_prim3a/b` fanning from
  the wrist (two bones each, so their tips trail a wingbeat), secondaries
  `wing_sec1` and `wing_sec2` hanging from the arm; Meshy's inner chain
  (`wing_inner1..3`, down the back of the arm) stays. The skin Meshy's
  outer chain held is shared among the new bones by distance, so the
  feathers between two bones fan out between them. In flight the game
  opens the fan (`wing_spread` in creature.gd: the arm rises level, the
  primaries spread from the wrist) and beats the wing up and down from
  the shoulder, the primaries' tips bending after each beat.
- ✅ (0.52) The arms swing a third as much as the other creatures' when it
  walks (`arm_swing`).
- ✅ (0.53) A stride a quarter longer than the others' (`stride`), the
  swinging foot reaching forwards toes first (`step_tilt`; the others tip
  their toes down, which on the raven's long foot pointed its toes back),
  and the wings bounce with its steps: each footfall makes them dip, and
  they spring back past where they were and settle, the primaries most.
- (0.55, deleted in 0.57) A "raven alt" with twice as thick hands and feet
  was made for the owner to compare, and dropped for the new models below.
- Not yet: the toes are Meshy's (one bone chain for the three front toes);
  a jaw for the beak; the raven's own walk, hop and wingbeat clips (see
  below).

## The newest raven: two models, rigged and animated (0.57, for review)

The owner's two new Meshy ravens (Nov 2026): `Raven3Spit.glb`, the raven on
the ground, and `RavenFlyingSplit.glb`, the raven flying, each with its
wings (and the flier's tail fan) as separate parts. The raven is to change
from one model to the other as it takes off and lands. The originals (about
90 MB each, 1.6 to 1.9 million faces) are kept out of git in
`art_sources/raven/`; three scripts make everything from them:

1. `tools/raven_new_prep.py`: each part cut down to a game's size (about
   130,000 triangles a model, smooth shaded), scaled so the walking raven
   stands 1.7 m (the flier matched to it by its body's surface area, as
   Meshy fits each model to its own box: its wings span 4.6 m), the
   textures (colour, normals, metal/roughness) 2048 px JPEGs.
2. `tools/raven_new_rig.py`: one skeleton (134 bones, the same names on
   both), fitted to each pose. The flier is pitched forward 83 degrees to
   fly level, its head lifted to look ahead, and that is its rest pose.
   - Body: root, pelvis, spine, chest, chest_upper, neck1, neck2, head.
   - Legs: thigh, shin (the knee bends forward), tarsus (the reverse knee
     between it and the ankle bends back), foot, and four toes (three ahead,
     one behind, read off grid pictures of each foot).
   - Arms: clavicle, arm_upper, arm_lower, hand, and four fingers of three
     bones (found from the claw tips round the skin).
   - Tail: tail1, tail2 and five fanned tail feathers of two bones.
   - Wings, as a real wing: wing_root (the shoulder blade), wing_upper
     (humerus), wing_fore (forearm), wing_hand, just inside the leading
     edge; five primaries on the hand, four secondaries on the forearm, two
     tertials by the body, each two bones so it bends, fanned to the wing's
     outline.
   - Every hinge (elbows, knees, reverse knees, ankles, wing elbows and
     wrists, fingers, toes) bends about its bone's X, closes one way only and
     never opens past straight (a Limit Rotation constraint; HINGES).
   - Skin: on the body by distance round the skin (so a hand hanging by a
     thigh keeps off it), smoothed so joints bend softly; the wings and tail
     fan by distance to their feather bones, the wing's root holding to the
     body.
3. `tools/raven_new_anim.py`: the clips, keyed on every frame from smooth
   looping curves, inside the joint limits, checked for smoothness (the
   largest change in any bone's turning speed from one frame to the next).
   - **Walk** (2 s, two steps): feet planted without sliding (the leg solved
     each frame, the tarsus kept about as steep as the thigh), rolling off
     the toes and setting down softly; the hips sink after each footfall,
     sway and turn; the chest counters, the arms swing a little, the head
     holds still, the wings bounce and the tail follows late.
   - **Fly** (1.2 s a beat): the eagle's flap: spread wings sweeping down and
     forward, primaries fanned and bent up under the load; the elbow and
     wrist folding on the upstroke, the hand turning to let the air through;
     the tips a moment behind the shoulder; the body rising on each
     downstroke, the head level, the tail trimming, the legs tucked.

- (0.59) Fixed: a hinge whose bend in the model is the other way round from
  the way it closes (the flier's curled toes, the toe bases, a few finger
  joints) was forced to bend as far again; now every hinge's limits always
  allow the model's own pose, so the toes keep the model's flight position.

- (0.60) The flier's sheen matches the walker's (`tools/raven_fly_look.py`:
  its roughness and metallic mapped onto the walker's, in its material; the
  colours as they were). In `raven_fly.blend` only (not yet in the game's
  `raven_fly.glb`); rebuilding the flier undoes it, so run that script again
  after `raven_new_anim.py` makes the flier.
- (0.60) An **Attack** clip on the walking raven: the left claw, after the
  balrog's slash (see the review notes).
- ✅ (0.61) The owner's attack (from `raven_walk_slow.blend`, the same as
  0.60's) played 50% faster (1.2 s): **AttackLeft**, and its mirror
  **AttackRight**. New clips on the walking raven: **Throw** (crouch, scoop
  with the right hand, wind up over the shoulder with the wing lifted out
  of the way, hurl, follow through) and **StompRight** / **StompLeft** (the
  weight onto the other foot, the knee up, the foot slammed down a little
  ahead), all inside the rig's joint limits.
- ✅ (0.62) A longer stride on the walking raven (0.6 m a second of the
  clip at the model's size, was 0.475), and a **Cast** clip: the right arm
  out ahead, the hand bent back so the palm faces ahead, the fingers open
  and spread as far as the knuckles allow; in the game the arm is turned
  on top of it to point at where the spell goes.
- ✅ (0.61) **In the game**: the raven is the two-model one (`RavenGiant`):
  the walking model on the ground, its Walk clip played as fast as it
  walks; the flying model in the air with its Fly clip; its strikes,
  throws (and eating, which lifts the gooblins the same way) and stomps
  played by their clips, timed to the game's moments. The old `raven.glb`
  is no longer used.

Review notes, with the frames worth a check: `docs/raven_new_review.md`
(pictures in `docs/raven_review/`). The test environment shows them
("Raven's clips"), and the Raven giant is the game's. Not yet: the flier's
sheen in the game (`raven_fly.glb` still has its own; the 0.60 look is in
the `.blend` only); clips for taking off and landing (it swaps models at
once, in a puff of dust).

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
