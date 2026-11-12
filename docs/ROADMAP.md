# Roadmap

The current build is a **playable tech demo**. The goal is to grow it into an
RTS or tower-defense game step by step, keeping something runnable at every
stage.

## Milestone 0: Tech demo ✅
- Procedural, sculptable terrain with village sites
- Generated funky buildings and trees, hand placement
- Tiny wandering villagers
- Giant procedural-walking creature
- Fireball: explosions, craters, debris, spreading fire
- RTS camera and tool HUD

## Milestone 1: Feel and polish
- [ ] Sound: footsteps, explosions, crackling fire, villager screams
  (free CC0 packs from Kenney / freesound.org)
- [ ] Water shader with waves and foam; better sky / day-night cycle
- [ ] Terrain texture splatting (grass / dirt / rock textures from Poly Haven)
- [ ] Creature: head looks at the target, casting animation, idle fidgets
- [ ] Settings menu (resolution, shadows, mouse sensitivity)

## Milestone 2: RTS foundations
- [ ] Selection system: click and box-select, selection circles
- [ ] Multiple units with a shared `Unit` base class (creature becomes one)
- [ ] Navigation: `NavigationRegion3D` baked from the terrain, rebaked when it is sculpted
- [ ] Villager jobs and resources (wood from trees, stone from rocks)
- [ ] Building types with a purpose (houses, towers, storage)
- [ ] Save / load the world (seed + edits + placed buildings)

## Milestone 3: Tower defense / conflict
- [ ] Enemy waves that path toward villages
- [ ] Defensive buildings that shoot
- [ ] Spell bar (fireball + more), mana, cooldowns
- [ ] Win / lose conditions

## Milestone 4: Scale and art
- [ ] MultiMesh / instancing for trees and villagers, LODs, object pooling
- [ ] Optional hand-made or AI-assisted models (Blender, TRELLIS, Hunyuan3D),
  exported as `.glb` (add Git LFS when binary assets arrive)
- [ ] Rigged creature with Godot's IK modifiers instead of primitive limbs

## Process
- Work on short-lived branches, open a PR, merge when the game still runs.
- Keep each script small with one job, and put tunables at the top.
- GitHub Actions: export Windows/Linux/Web builds on every push
  (free for public repos). Optionally publish to itch.io with `butler`.
- Add `gdUnit4` tests for pure logic (terrain brushes, fire spread rules) once
  gameplay systems grow.
