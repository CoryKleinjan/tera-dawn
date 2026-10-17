# Tears

A tear is a small hidden zone of its own (3-4 maps and a guardian) past a secret room in a
mainland zone. Only a boss move from another zone reaches that room. Finishing what waits
inside turns the zone it opens from: darker light and fog, and more dangerous versions of its
monsters.

## How it works
- `TearDef` (`scripts/data/tear_def.gd`, saved in `data/tears/`) names its zone (`region`),
  the story quest that unseals it (`seal_quest`, `story_a_closer_look` by default), the quest
  that finishes it (`finish_quest`), the zone's `dark_look` and its `dangerous` versions.
- `TearState` (`scripts/systems/tear_state.gd`) holds every rule: `open`, `finished`, `dark`
  (a field, never a town, in a zone whose tear is finished), `kind` (the monster that spawns
  in place of another), `strength` (`STRENGTH`, 1.5x HP, attack and essence) and `look`.
- What a character has finished comes from their quests done, so saves need nothing new.
- `MapInstance` asks `TearState` which kind spawns and how strong when it is made, following
  the host's character (peer 1) so everyone on a shared map sees the same thing. A map is made
  fresh each time someone arrives on an empty one, so a turn shows from the next visit.
  `full_state()` sends `dark`; `TDWorld.load_map` builds the same kinds and `TDStage` shows
  `TearState.look`.

## Adding a tear
1. Make its maps (their own region, so they never turn), its quests and its guardian.
2. Save a `TearDef` in `data/tears/`: `region`, `finish_quest` (the last quest), and a
   `dark_look` (a `BiomeVariantDef`) that sets only the keys in `TearState.LIGHT_AND_FOG`.
   Art is never recoloured in code, so no sky, grade or backdrop colours.
3. Each dangerous version is its own `MonsterDef` with its own painted sheets. List it in
   `dangerous` under the id of the monster it replaces (one that lives in that zone).
4. `tests/content/content_tears_test.gd` checks all of this.
