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

## Milestone 0.9: Bigger worlds, water and jobs ✅
- Medium and Large islands 1.5x and 2x wider; half the forest, same density on every size
- Water as its own layer: it flows into lowered ground and pours off the edge
- Editor: land, sand, grass and water brushes; growing the map square
- Rock skirt along the island's edge; stone craters
- Jobs row: warriors (Town guard) and wizards (Singing rocks) with training times
- Food upkeep and starvation; goblin caves spawn faster every night
- Resource icons; UI scales with the window

## Milestone 0.95: Comic look and ogres ✅
- Halftone cel shading, darker coloured shadows, inked terrain, "Alpine" palette
- Detailed close-up models for villagers, soldiers and goblins (two levels of detail)
- Tortoise face: moving eyes, blinking, angry lids, an inked mouth that opens
- Flame tongues drawn by a shader; wheelbarrows; roofs no longer cut by walls
- Ogres join raids of 15 goblins
- Blood Sacrifice spell; rain speeds up wheat

## Milestone 0.97: Creatures and research ✅
- A second creature: the nervous tiger (30% faster, half the tortoise's health)
- Creatures start at 15% size and grow for 30 minutes; they eat, can be hurt and knocked out
- Blacksmith: wheelbarrows, and research (sharper swords, bows, pitchforks, picks, axes)
- Archers, two per Town guard, once bows are researched

## Version 0.10: A creature with a mind ✅
- The creature explores near where it was left, defends the village, learns spells and harvesting by watching
- Bless and Curse spells shape what it likes to do; floating text says what it did
- balancing.txt for health, damage, knowledge and cooldowns
- Free first Storehouse; gatherer counts the player can set; Esc pauses; version number on the menu

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
- [x] Singing rocks train wizards
- [ ] Jobs for the windmill and crystal tower
- [x] Jobs panel: player-set warriors and wizards; food upkeep and hunger
- [x] Save / load maps from the editor
- [ ] Save / load a game in progress (resources, buildings, villagers)

## Milestone 3: Tower defense / conflict
- [x] Goblin raids: every goblin leaves the cave at midnight and attacks the village
- [x] Raids that grow night by night (caves spawn faster every night); ogres
- [ ] More goblin types
- [ ] Health bars and player orders for warriors and wizards
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
- The project owner creates and names branches; ask before making a new one
  (see CLAUDE.md). Merge into `main` when the game still runs.
- Keep each script small with one job, and put tunables at the top.
- GitHub Actions: export Windows/Linux/Web builds on every push
  (free for public repos). Optionally publish to itch.io with `butler`.
- Add `gdUnit4` tests for pure logic (terrain brushes, fire spread rules) once
  gameplay systems grow.
