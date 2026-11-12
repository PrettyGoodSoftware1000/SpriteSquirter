# SpriteSquirter

A 3D sandbox experiment built with [Godot 4](https://godotengine.org). A giant
two-legged creature stomps around a procedurally generated island full of
funky villages and tiny villagers, and casts **fireball** to blow things up
and start fires. The long-term plan is to grow it into an RTS / tower-defense
game (see [docs/ROADMAP.md](docs/ROADMAP.md)).

Everything you see is generated in code from primitive shapes, so no 3D
modelling tools are needed to run or change it.

## Running it

1. Download **Godot 4.7** (standard build, not .NET) from
   <https://godotengine.org/download>. It is free and needs no install, so just unzip and run it.
2. In the Godot Project Manager click **Import**, choose this folder's
   `project.godot`, then **Import & Edit**.
3. Press **F5** (or the ▶ button) to play.

The first import takes a few seconds while Godot builds its cache in `.godot/`.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Pan camera (hold Shift for faster) |
| Q / E | Rotate camera |
| Mouse wheel | Zoom |
| Middle mouse drag | Rotate and tilt camera |
| Space | Jump the camera to the creature |
| Right click | Walk the creature to that spot |
| F | Cast fireball at the cursor (any tool) |
| 1–7 | Tools: Command, Fireball, Raise, Lower, Flatten, Smooth, Build |
| [ / ] | Brush size for terrain tools |
| R | New random design while in Build mode |
| Esc | Back to Command tool |
| N | Generate a brand-new world |

## What's in the demo

- **Procedural terrain:** a noise-based island with hills, lakes and flat
  village sites. You can sculpt it live (raise, lower, flatten, smooth), and
  fireballs leave craters and scorch marks.
- **Funky buildings:** five generated styles (twisted stacks, mushroom
  houses, crooked towers, domes, bubble towers), each with random colours,
  roofs, windows and doors. You can place more by hand with the Build tool.
  Each new house brings two villagers.
- **Tiny villagers:** they wander around their village, panic when the
  creature or fire comes near, catch fire, get flung by explosions and get
  squashed flat by footsteps.
- **The creature:** procedural walking with two-bone IK legs, planted
  feet, body bob and sway, and swinging arms and tail. Its footsteps shake the
  camera and crush whatever they land on.
- **Fireball:** an arcing projectile that explodes and digs a crater. It
  breaks buildings and trees into physics debris (Jolt), and sets fires that
  spread across grass, char buildings and eventually collapse them.

## Project layout

```
project.godot              Engine settings (Jolt physics, autoload "Game")
scenes/main.tscn           The only scene; everything else is built in code
scripts/
  main.gd                  World setup, input, tools, building placement
  core/game.gd             Autoload: global access to terrain, effects, camera...
  world/terrain.gd         Heightmap, chunked mesh, collision, sculpt brushes, raycast
  world/building_factory.gd  Procedural buildings and trees from primitive meshes
  world/destructible.gd    Shared burn / damage / shatter behaviour
  world/world_populator.gd Places villages, villagers and trees
  world/fire_system.gd     Spreading ground fires
  units/creature.gd        The giant: locomotion, procedural animation, IK
  units/villager.gd        Villager state machine
  spells/fireball.gd       Projectile
  spells/explosion.gd      Blast gameplay: damage, craters, flinging, fires
  fx/effects.gd            Particles, flashes, dust, debris bodies
  fx/fire_emitter.gd       A single flickering fire
  camera/rts_camera.gd     RTS-style orbit camera
  ui/hud.gd                Toolbar, hints, stats
```

### Conventions

- GDScript with static types everywhere (`var x := ...`, typed arguments).
- One `class_name` per script. Shared systems are reached through the `Game`
  autoload instead of node paths.
- Units are metres. Local +Z is "forward" for the creature and buildings.
- Tunable numbers are `const` or `@export` at the top of each script.

## Tech notes

- **Engine:** Godot 4.7, Forward+ renderer, Jolt physics.
- **Performance budget:** around 300 trees, 30–50 buildings and ~100
  villagers as individual nodes. That is fine for a demo. MultiMesh and
  pooling are on the roadmap for RTS-scale unit counts.
- Debris pieces fade out after about 10 s, and the number of fires and fire
  lights is capped so the wildfire can't run away with the frame rate.
