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

## Milestone 0.5: Art style pass ✅
- Surreal cel-shaded look: banded light, ink outlines, nature palettes
- Floating island with rivers and waterfalls; weather moods
- The eight concept-art buildings, a goblin cave and camp
- High-poly skinned tortoise creature
- Dev menu (~) for terrain tools, weather, palettes and world generation

## Milestone 0.75: Village game ✅
- Main menu; map sizes (Small, Medium, Large)
- Map editor: sculpting, start locations, goblin caves, trees, rocks; save / load
- Pick a start location; villagers gather lumber, stone and food, earn magicko
- Build menu with rotatable outlines; villagers raise the buildings
- Births every few seconds while there is housing; children grow up in a minute
- Rain spell that puts out fires; spell bar; resource counter
- Day-night cycle; dev menu gameplay settings (day length, rates, birth timer)
- Headless smoke test (tools/smoke_test.tscn)

## Milestone 0.9: Night raids ✅
- Nights half as long as days; goblins raid the village at midnight
- Health, damage and attack speed for villagers and goblins; children don't fight
- Named buildings with jobs: Home, Storehouse (villagers carry resources), Town guard (soldiers)
- Wheat fields drawn on the ground from the build menu
- Stone in boulder fields; Roots spell
- The tortoise stomps, throws and eats goblins

## Milestone 0.95: Comic look and ogres ✅
- Halftone cel shading, darker coloured shadows, inked terrain, "Alpine" palette
- Detailed close-up models for villagers, soldiers and goblins (two levels of detail)
- Tortoise face: moving eyes, blinking, angry lids, an inked mouth that opens
- Flame tongues drawn by a shader; wheelbarrows; roofs no longer cut by walls
- Ogres join raids of 15 goblins; camps grow each night
- Blood Sacrifice spell; rain speeds up wheat

## Milestone 1: Feel and polish
- [ ] Sound: footsteps, explosions, crackling fire, villager screams
  (free CC0 packs from Kenney / freesound.org)
- [x] Slow automatic day-night cycle built on the weather moods
- [ ] Rain (beyond the spell), snow and wind as real weather effects
- [ ] Chimney smoke, flowers, fences, market stalls and other village props
- [ ] Creature: idle fidgets, roar, facial expressions
- [ ] Settings menu (resolution, shadows, grass, mouse sensitivity)

## Milestone 2: RTS foundations
- [ ] Selection system: click and box-select, selection circles
- [ ] Multiple units with a shared `Unit` base class (creature becomes one)
- [ ] Navigation: `NavigationRegion3D` baked from the terrain, rebaked when it is sculpted
- [x] Villager jobs and resources (wood from trees, stone from rocks)
- [x] Building types with a purpose (Home, Storehouse, Town guard)
- [ ] Jobs for the windmill, crystal tower and singing rocks
- [x] Save / load maps from the editor
- [ ] Save / load a game in progress (resources, buildings, villagers)

## Milestone 3: Tower defense / conflict
- [x] Goblin raids: every goblin leaves the cave at midnight and attacks the village
- [x] Raids that grow night by night; ogres
- [ ] More goblin types
- [ ] Health bars and player orders for soldiers
- [ ] Defensive buildings that shoot
- [x] Spell bar (fireball, rain, roots), magicko, cooldowns
- [ ] More spells
- [ ] Win / lose conditions

## Milestone 4: Scale and art
- [ ] MultiMesh / instancing for trees and villagers, LODs, object pooling
- [ ] Optional hand-made or AI-assisted models (Blender, TRELLIS, Hunyuan3D),
  exported as `.glb` (add Git LFS when binary assets arrive)
- [ ] More creature species (edit the shape list in `tools/bake_creature.py`)

## Process
- Work on short-lived branches, open a PR, merge when the game still runs.
- Keep each script small with one job, and put tunables at the top.
- GitHub Actions: export Windows/Linux/Web builds on every push
  (free for public repos). Optionally publish to itch.io with `butler`.
- Add `gdUnit4` tests for pure logic (terrain brushes, fire spread rules) once
  gameplay systems grow.
