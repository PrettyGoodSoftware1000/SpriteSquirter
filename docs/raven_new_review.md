# New raven: animation review (0.57, in the game since 0.61)

The owner's two new Meshy ravens, rigged and animated. Since 0.61 they are
the game's raven (`RavenGiant`). The test environment shows their clips
("Raven's clips": Walk, Stand, Take off, Land, Claw L, Claw R, Throw,
Stomp L, Stomp R). See `docs/ART_PLAN.md` for how they were made.

- `assets/creature/raven_walk.glb` (and `.blend`): the raven on the ground,
  its **Walk** clip: 61 frames at 30 fps (2 s, two steps; frame 61 is frame 1
  again).
- `assets/creature/raven_fly.glb` (and `.blend`): the raven flying, its
  **Fly** clip: 37 frames at 30 fps (1.2 s, one wingbeat; frame 37 is frame 1).

In Blender, open the `.blend` and play the action; every joint's limits are
on its bone (Limit Rotation), and both clips loop.

## Pictures

Each sheet is eight frames, left to right and top to bottom.

- `raven_review/walk_side.png`, `walk_front.png`: frames 1, 8, 16, 23, 31,
  38, 46, 53.
- `raven_review/fly_front.png`, `fly_side.png`: frames 1, 5, 9, 13, 17, 21,
  25, 29.
- `raven_review/in_godot.png`: in the game's engine (the test environment):
  walking, then flying.

## The walk, frame by frame

| Frames | What happens |
|---|---|
| 1 | Right foot planted under the body, left foot rolling off its toes behind |
| 1-6 | Weight onto the right foot: the hips sink a little |
| 8 | Left foot lifts and swings forward; the hips rise over the right foot |
| 16 | Left foot passing the right; the right heel starts to rise |
| 23 | Left foot reaching ahead, toes curled; right foot rolling off its toes |
| 31 | Left foot down (the same as frame 1, the other side) |
| 31-61 | The same on the other side |

## Frames worth a check

These are where the motion changes fastest or where something I could not
judge well from pictures alone happens.

1. **Walk 26-31 and 56-61: the toes as the foot lands.** The toe tips turn
   fastest here (they uncurl and flatten on the ground): the clip's biggest
   frame-to-frame change (6 degrees a frame per frame). Check they settle
   onto the ground and do not flick.
2. **Walk 16-24 and 46-54: the hands passing the knees.** The arms swing
   only a little, but the hands hang near the knees; check they do not
   brush through each other.
3. **Walk 1-8 and 31-38: the hips.** They sink after each foot lands and
   sway over it. Check it reads as weight, not as bouncing.
4. **Fly 33-37 (into frame 1): the wing opening at the top.** The fastest
   change in the flight (under 3 degrees a frame per frame, in the
   primaries) as the folded wing spreads before the downstroke.
5. **Fly 9-17: the primaries under load.** On the downstroke their tips
   should bend up (the air pushing them); check they bend that way and not
   down.
6. **Fly 21-29: the upstroke fold.** The elbow and wrist fold and the hand
   turns so the feathers slip through the air; check the turn goes the right
   way (the leading edge up) and the fold looks like a real wing's.
7. **Fly, all frames: the head.** It is meant to stay level while the body
   rises and dips; check it does not nod.

## The attacks (0.60; 50% faster and mirrored in 0.61)

`raven_walk.glb` / `.blend` have **AttackLeft** and **AttackRight**: the
owner's attack (made at 0.60 as "Attack", 1.8 s, and kept in
`raven_walk_slow.blend`) played 50% faster, 37 frames at 30 fps (1.2 s), and
its mirror for the right claw. The table below is the 0.60 timing: divide
the frames by 1.5 (the strike is at frame 18 now). Video (the 0.60 speed):
`raven_review/raven_attack.mp4`. The fastest change is now in the fingers
(about 11 degrees a frame per frame as the claw opens at the top).

| Frames | What happens |
|---|---|
| 1-10 | The left arm rises up and out (slightly ahead of the shoulder, not back); the left wing lifts up and back out of its way; the torso turns away |
| 10-16 | A moment's hold at the top, the fingers open |
| 16-26 | The swipe: down and across the chest, gathering speed; the torso whips round and leans into it, the hips drop; it strikes at frame 26 |
| 26-31 | Follow-through, the claw closing |
| 31-55 | Back to rest, slowing to a stop |

Worth a check: frames 16-26 (the swipe: fast enough, or too fast?), frames
1-16 (does the wing clear the raised arm?), and frame 26 (the strike). The
wrist does not twist; the arm never straightens past 90% of its length.

## Throw and stomps (0.61)

- **Throw** (73 frames, 2.4 s; the right hand): it crouches and reaches down
  (goblins in hand at 0.6 s, frame 19), straightens and lifts them, winds up
  over its right shoulder while the right wing lifts up and back out of the
  way (frames 30-46), hurls them (let go at 1.62 s, frame 49), follows
  through and comes back to rest. The left hand reaches down for balance.
  Worth a check: frames 40-52 (the wind-up and release; the fingers open
  fastest there, about 9 degrees a frame per frame).
- **StompRight** / **StompLeft** (35 frames, 1.15 s): the hips sway over the
  standing foot, the stamping knee comes up high with the toes curled, and
  the foot slams down a little ahead at 0.8 s (frame 25); the arms come out
  for balance and the wings lift, then drop with the stamp.
  Worth a check: frames 16-25 (the knee at its highest, and the drop).

In the game the throw is timed to the game's grab (goblins picked up at
0.7 s, let go at 1.95 s); to eat them it lifts them the same way and holds
them up. The stomp's foot lands when the game's stomp does.

## Joint limits

Every hinge closes only one way and never opens past straight: the elbows,
the knees (bending forward, like a man's), the reverse knees between knee and
ankle (bending the other way), the ankles, the wing elbows and wrists, every
finger and every toe joint. The limits are in the `.blend` files (each
hinge's Limit Rotation, and `hinge_rest_deg` / `hinge_close_deg` on the bone)
and in `raven_walk_hinges.json` / `raven_fly_hinges.json`; the clips are made
inside them.
