# Notes for Claude

## Version number

- The game's version is `config/version` in `project.godot`. It is shown
  in the corner of the main menu.
- Raise it by 0.01 with every update you make to the game (0.10, 0.11,
  0.12, ...), in the same commit as the update, and say the new number
  when you report back.
- The project owner downloads the game from `main`, so finished updates
  go to `main` when they ask for that.

## Asset names

- Every building has an asset name (its model) and a gameplay name (what
  it does). `Names.txt` pairs them, and the owner edits the gameplay names
  there.
- Asset names never change unless the owner says so: Treehouse, Lookout
  treehouse, Twin treehouse, Great treehouse, Stacked houses, Moon tower,
  Blacksmith, Mushroom cottage, Singing rocks, Skull tower, Windmill,
  Crystal tower, Tall house. A new building gets a new asset name and a
  line in `Names.txt`.

## Announcements

- Every line of text the game announces (the messages in the middle of
  the screen, the creature's floating lines, the Bless / Curse text and
  the sentence for each creature action) is in `Announcements.txt`. The
  owner writes it. New announcement text gets a line there (and a default
  in `scripts/core/texts.gd`), never a string in the code.

## Creature actions

- `Actions.csv` is the owner's table of the creature's actions: row 1
  names each category, the actions go below it, most general first. A
  new action gets a cell there and a sentence in `Announcements.txt`
  (`action_<id>`), never a string in the code.

## Branches

- Never create a branch, or choose a name for one, without asking the
  project owner first and waiting for a yes. This applies locally and on
  GitHub, including pushing to a branch name that does not exist yet
  (that creates it).
- The project owner creates and names branches.
- Work on the branch you are given. `main` holds the merged game.
