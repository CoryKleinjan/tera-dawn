# Tears and the world's decline

Part of the [architecture docs](../../ARCHITECTURE.md).

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
  (`STRENGTH_PER_STEP`, +50% HP and attack a step) and `look`.
- What a character has finished comes from their quests done, so saves need nothing new.
- The way in is a `SceneSpot` with `tear` set, on a secret ledge (`PlatformDef.secret`) of
  the zone: it is shut and its glow hidden until `TearState.open`, then it sends the player to
  `then_map`, a map inside. The tear's own zone (`inside`) is not a `RegionDef`: it is off the
  world map, with no town and no routes (`TearState.inside_tear`; `WorldRoutes` gives its maps
  no region, and the border-field and "every boss" counts leave them out).
- `MapInstance` asks `TearState` which kind spawns and how strong when it is made, following
  the host's character (peer 1) so everyone on a shared map sees the same thing. A map is made
  fresh each time someone arrives on an empty one, so a new step shows from the next visit.
  `full_state()` sends `decline`; `TDWorld.load_map` builds the same kinds and `TDStage` shows
  `TearState.look`.

## Adding a tear
1. Make its maps (`MapDef.region` is the tear's `inside`), its quests and its guardian. A
   one-way portal leads back out; its arena follows the boss arena rules.
2. Save a `TearDef` in `data/tears/` with `region`, `inside` and `finish_quest` (the last quest).
3. Add its way in: a secret ledge on a map of `region` that only its `way_in` move reaches,
   and a `SceneSpot` on it with `tear`, `then_map`, `then_x` and `glow`.

## The Greenbough tear (the pilot)
- Way in: a Dash-only ledge on Oak Crown (x 1515-1655, y 185, out past P10's left end), the
  only change to that map. `TearDef.way_in` names the move; `content_tears_test` checks that
  only it reaches the ledge. Out: a one-way portal from the Stilled Grove back to
  Oak Crown's floor.
- Maps (region `greenbough_tear`): Stilled Grove (Shardling, Pale Moth), Ivory Hollow
  (Hollow Stag, Shardling, a chest), Silent Stair (Pale Moth, Hollow Stag; a cracked wall at the
  top opens a shortcut to the Stilled Grove) and Warden's Ring (the Petrified Warden alone).
  The fields are silent until the tear has music; the arena plays Greenbough's boss track.
- Quests: Old Fenwick's `tear_greenbough_1..3` (the last is `finish_quest`); their text
  waits on Cory.

## Adding a decline step
1. Save a `DeclineDef` in `data/declines/` with its `step`. Its `look` (a `BiomeVariantDef`)
   sets only the keys in `TearState.LIGHT_AND_FOG`: art is never recoloured in code, so the
   dreary scenery is painted as its own art.
2. Each dangerous version is its own `MonsterDef` with its own painted sheets, listed in
   `dangerous` under the id it replaces (for a later step, the earlier step's version).
3. `tests/content/content_tears_test.gd` checks all of this.
