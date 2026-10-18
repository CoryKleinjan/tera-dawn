# Characters: creation, extras, balance and player actions

Part of the [architecture docs](../../ARCHITECTURE.md).

## Character creation and how heroes show

**Create** on character select opens the character creator (`TDCreator`): a name, the hero's
look and the starting outfit (`NewCharacter`). `Net.create_character` makes a new character in the
starting job (`Character.START_JOB`) and saves it on this computer (`CharacterStore.create`),
then character select shows the list (name and job) with the new character picked.

- **Looks** are `HeroLookDef`s (`data/hero/looks/`, loaded by `Content` into `Content.looks`):
  each is one painted hero, every frame painted whole (`art/sheets/hero_look_<id>_<move>.json`,
  one sheet per move; the walk sheet's manifest writes the look's `SpriteFrames`). The creator
  shows the picked look standing; `Character.look` keeps its id, and a save from before the
  looks (or an id the game doesn't know) gets the first (`HeroLookDef.of`).
- **Outfit** choices come from the starting job's `creator_gear` (one piece per kind). It is
  empty for now (no starting outfits are painted yet), so the creator offers none.
- **One body for every hero**: your hero (`TDPlayer`) and other players' (`TDAvatar`) each
  work out what they are doing (from your keys, or from the snapshot: an animation name such
  as "walk", "dash" or a skill's `animation`), and `HeroBody`
  (`scripts/components/hero_body.gd`) shows them the same way for both: one sprite playing the
  look's animation of that name (`HeroBody.resolve`: a few poses such as "ready" stand, and every
  skill's motion plays "attack", the Surge's punch, until the job sets paint their own), and the
  companion (the pet). Shots leave from his punching fist (`HeroLookDef.fist`,
  `HeroBody.muzzle`). Other players' looks and worn set pieces reach you in their info
  (`SimPlayer.info`, `Gear.shown`). The sizes the game needs for a hero (`TDPlayer.HEIGHT`, `WIDTH`,
  `CHEST`, `SimPlayer.HURTBOX_SIZE`) are constants.
- **Outfits** are `HeroOutfitDef`s (`data/hero/outfits/`, `Content.outfits`): a look painted
  wearing a set's pieces, one per pair (armor and weapon, armor with an empty fist, plain clothes
  with the weapon), every frame painted whole like the look itself (`art/sheets/hero_outfit_<look>_<set>_<move>.json`,
  sources in `art/source/hero/outfits/`). `HeroLookDef.frames_for(armor, weapon)` picks the
  painting of that pair, else the armor's, else the weapon's, else plain clothes, and
  `HeroBody.draw` plays it. A frame whose art crosses its cell line gets a manifest of its own
  over a wider `region` (the sword-only dash's second frame). Adding a set means painting its
  three outfits for every look, cutting them and adding a `HeroOutfitDef` for each.
- **Adding a look**: paint its sheets (one per move, the cells the other looks' manifests name),
  copy a look's manifests with its id, cut them, and add its `HeroLookDef` with its `order` and
  `fist` (where the punching fist is on the last "attack" frame).

### Sitting, pets, the Monster Book and achievements

- **Sitting** is on the ground (there are no chairs): the Sit key asks `req_sit`, the server
  keeps it in `SimPlayer.sitting` and doubles the base regen while it's on. Moving
  (`SimPlayer.report_move`) or a monster hit (`MapInstance.hurt_player`) clears it; others see
  the "sit" animation in the snapshot.
- **Pets** (`PetDef`) live in the Setup tab and are brought out with `req_setup`. The pet
  that's out is `Character.pet`, with `pet_full` dropping every `hunger_ticks` and
  `MapInstance._pet_step` picking up drops within `loot_reach`. It goes out in the player's
  info, and `TDCompanion` (owned by each `HeroBody`) draws it next to you and other players.
- **The Monster Book** (`MonsterBook`, on the Character) counts kills and cards per monster.
  `Content` makes a `CardDef` for every monster at startup (`card_<id>`, no files); monsters
  drop it at `CardDef.CHANCE` until your page is full, and picking it up files it in the book
  instead of the bag. The book's rank adds to power (`Character.power`).
- **Relic moves** (`RelicDef.Move`: Dash, Double Jump, Slam, Surge) come from boss relics.
  Picking one up (`MapInstance._learn_relic`) adds its id to `Character.relics` for good,
  never to the bag; `Character.has_move` says what's unlocked. `TDPlayer` does the moves on
  your own machine like any other step (`_relic_moves`, `_air_jump`, the "dash" key); the
  server only breaks what a Slam lands on (`req_slam`). A move shows its own painted animation
  ("dash", "surge_charge", "surge", "slam", "double_jump", then "slam_land" or "surge_end" for a
  few ticks, `TDPlayer._pose`) and plays its relic's painted `effect` round him (a code-drawn
  `trail` while it has none). A relic drop is its owner's alone and never expires (`SimDrop`).
- **Achievements** are **AchievementDef**s in `data/achievements/`, loaded by `Content`; each
  measures something about the Character (its `kind`, see `Achievements.measure`) against a
  `goal`. `Achievements.all()` lists them in `order` for the collection window and the server.
  The server checks them whenever a player's state changes (`TDServer.check_achievements`)
  and sends `ev_achievement`; the client shows it and calls `SteamService.unlock_achievement`
  with its `steam` id. Add one by adding a `.tres` (a new `id`, a `steam` name defined in
  Steamworks, the next `order`). Never change a shipped `id` or `steam` name: saves keep the
  id and Steamworks the name (`level_50`, `well_liked` and `dealmaker` kept their names when they became solo goals). A new kind of tally gets a name in `Counters` and is added with
  `Character.count(Counters.<NAME>)`.

### Balance

`Balance` builds a typical character for any job and tier of progress (that level, the best
gear made for that tier) and works out how many hits of their main
attack a monster takes and how many kills pay for a tier. The smoke test keeps every job inside
`Balance.BAND` against every monster of its tier; `tests/balance_report.tscn` prints the full table when tuning.

### How to add something the player does

1. Add a `req_<thing>` to `Net`, in the group of the server part it belongs to, that calls
   `server.<part>.on_<thing>(_sender(), …)` (`server.items`, `npc_shop`, `storage`, `travel`,
   `quests`, `jobs`; moving and fighting stay on `TDServer` itself, `server.social` for
   players together). A new area gets its own `ServerPart` in `scripts/server/services/`,
   made in `TDServer._init`.
2. Write `on_<thing>` in that part: check it's allowed, change the `Character` or map, and mark
   `dirty_character` / `dirty_vitals` so the player gets their new state. `tell` sends the
   player a line in their chat log and `change` runs a Character change that returns a problem.
3. If other players should see it, broadcast an `ev_<thing>` from the `MapInstance` and show
   it in `TDWorld`.
4. Call `Net.ask(&"req_<thing>", […])` from the UI or `TDPlayer`.
