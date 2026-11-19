# Notes for Claude

## Version number

- The game's version is `config/version` in `project.godot`. It is shown
  in the corner of the main menu.
- Raise it by 0.01 with every update you make to the game (0.10, 0.11,
  0.12, ...), in the same commit as the update, and say the new number
  when you report back.
- The project owner downloads the game from `main`, so `main` always has
  the latest code: every finished update goes to `main` as well as the
  working branch, until the owner decides a separate branch is needed.

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
  the screen, the creature's other floating lines and the Bless / Condemn
  text) is in `Announcements.txt`. The owner writes it. New announcement
  text gets a line there (and a default in `scripts/core/texts.gd`), never
  a string in the code.
- What floats up when the creature does an action is its sentence from
  `Actions.csv` (the most specific that fits; `CreatureMind.did()`); the
  line in `Announcements.txt` is only used when the table has none.

## Creature actions

- `Actions.csv` is the owner's table of the creature's actions (they keep
  it in a Google Sheet and export it as CSV). Row 1 names each category;
  the actions go below it, most specific at the top, most general (no
  brackets) at the bottom. Each cell is the sentence players see, with
  its condition in square brackets at the end; `[enemy name]` and
  `[a or an]` are placeholders. The owner writes the sentences and the
  conditions. The game reads the conditions by key words
  (`ActionTable._parse_condition()`); a new kind of condition needs code
  there and in `CreatureMind.passes()`, never a sentence in the code.

## Design principles

- Creatures have personalities and are trainable, and both matter:
  personality traits (`<kind>_<trait>_personality` in `balancing.txt`,
  100% average) are born in and last for life, and Bless and Condemn
  train affinities on top. Two creatures with the same training still
  behave differently, and enough training can override a creature's
  nature. New creature behaviour should keep both levers.
- The creature is tactical only as far as the player trains it: nothing
  hard-wires a sensible reaction (for example, there is no built-in
  "run when badly hurt"); its affinities for the rows of `Actions.csv`
  and its personality decide.
- Weights and personalities are written as percentage multipliers in
  `balancing.txt`, so people can read them.

## Branches

- Never create a branch, or choose a name for one, without asking the
  project owner first and waiting for a yes. This applies locally and on
  GitHub, including pushing to a branch name that does not exist yet
  (that creates it).
- The project owner creates and names branches.
- Work on the branch you are given, and keep `main` up to date with it
  (a fast-forward push) after every finished update.
- The owner edits files such as `balancing.txt` straight on `main`.
  Fetch `main` and merge it into the branch before pushing, keep the
  owner's values, and make the smoke test read numbers from
  `balancing.txt` rather than expect particular ones.
