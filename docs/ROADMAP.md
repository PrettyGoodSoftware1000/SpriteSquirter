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

## Version 0.11: Treehouses, bones and goblin builders ✅
- Homes are treehouses; the player hangs rope bridges between them and villagers walk over
- Bones from the dead; Necromancer tower; necromancers raise skeleton warriors and archers
- Building costs in balancing.txt; building time in proportion to the cost
- Goblins put up their own buildings near the caves every 5 minutes

## Version 0.12: Names, builders, slopes and a bat ✅
- Names.txt: asset names (Stacked houses, Moon tower, Skull tower...) paired with gameplay names
- Builders; at most 5 villagers per building; Workers are the unassigned villagers
- Three more treehouses; bridge tool lights up the treehouses it can join
- The tiger becomes a squirrel; a giant bat carries villagers off during raids
- Chain lightning (double damage to the wet); solid 3D flames; controls under Esc
- Slopes slow walkers, cliffs stop them, and villagers and goblins find routes round both
- Map editor: expand-island, cut-cliff and goblin-path brushes

## Version 0.13: A raven and a balrog ✅
- A third creature, the raven: flies long journeys and over climbs, flees when badly hurt
- The balrog, the goblins' giant: guards its cave while it grows, then joins the raids; casts fireball from half size
- Giants fight each other with their fists; glowing parts on creature models

## Version 0.14: Stamina, shells and jointed villagers ✅
- Villagers of every kind rebuilt: elbows and knees that bend, hands, boots, faces, aprons, beards, armour
- Creature health, stamina and magicko bars; stats level up with use; the creature's spells cost its own magicko
- The squirrel runs on all fours; the tortoise hides in its shell; both, and flying, can be blessed and cursed
- Ogres come from goblin war huts and giant bats from watchtowers; goblin build speed in the dev menu
- The balrog: slimmer, horns rooted in the skull, an open jaw of teeth, smoke, sparks and burning footprints

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
