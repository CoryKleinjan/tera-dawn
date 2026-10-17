# Tears and the world's decline

A tear is a small hidden zone of its own (3-4 maps and a guardian) past a secret room in a
mainland zone. Only a boss move from another zone reaches that room. Finishing what waits
inside takes the whole world a step into its decline: the first finished tear turns every map
but the tears' own, and each one after takes it further.

## How it works
- `TearDef` (`scripts/data/tear_def.gd`, saved in `data/tears/`) names the zone its way in is
  in (`region`), its own maps' zone (`inside`, which never declines), the story quest that
  unseals it (`seal_quest`, `story_a_closer_look` by default) and the quest that finishes it
  (`finish_quest`).
- `DeclineDef` (`scripts/data/decline_def.gd`, saved in `data/declines/`) is one step: its
  light and fog (`look`) and the dangerous versions that take monsters' places (`dangerous`).
  Every step up to the character's applies, in order.
- `TearState` (`scripts/systems/tear_state.gd`) holds every rule: `open`, `finished`,
  `decline` (tears finished), `decline_of` (0 inside a tear), `kind`, `strength`
  (`STRENGTH_PER_STEP`, +50% HP, attack and essence a step) and `look`.
- What a character has finished comes from their quests done, so saves need nothing new.
- `MapInstance` asks `TearState` which kind spawns and how strong when it is made, following
  the host's character (peer 1) so everyone on a shared map sees the same thing. A map is made
  fresh each time someone arrives on an empty one, so a new step shows from the next visit.
  `full_state()` sends `decline`; `TDWorld.load_map` builds the same kinds and `TDStage` shows
  `TearState.look`.

## Adding a tear
1. Make its maps (their own region, named in `inside`), its quests and its guardian.
2. Save a `TearDef` in `data/tears/` with `region`, `inside` and `finish_quest` (the last quest).

## Adding a decline step
1. Save a `DeclineDef` in `data/declines/` with its `step`. Its `look` (a `BiomeVariantDef`)
   sets only the keys in `TearState.LIGHT_AND_FOG`: art is never recoloured in code, so the
   dreary scenery is painted as its own art.
2. Each dangerous version is its own `MonsterDef` with its own painted sheets, listed in
   `dangerous` under the id it replaces (for a later step, the earlier step's version).
3. `tests/content/content_tears_test.gd` checks all of this.
