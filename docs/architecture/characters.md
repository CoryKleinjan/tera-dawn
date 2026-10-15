# Characters: creation, extras, balance and player actions

Part of the [architecture docs](../../ARCHITECTURE.md).

## Character creation and how heroes show

**Create** on character select opens the character creator (`TDCreator`): a name and the
starting outfit (`NewCharacter`). `Net.create_character` makes a level 1 character in the
starting job (`Character.START_JOB`) and saves it on this computer (`CharacterStore.create`),
then character select shows the list (name, level and job) with the new character picked.

- **Outfit** choices come from the starting job's `creator_gear` (one piece per kind). It is
  empty while the gear is being remade, so the creator offers no outfit for now.
- **Layered look**: the hero is drawn from painted layers, MapleStory style. `HeroLookDef`
  (`data/hero/look.tres`) holds his body, face and hair and which frames each animation shows
  (`"<anim>_<weapon kind>"` overrides it, like `attack_bow`; an animation with no frames, such as
  an attack for now, shows him standing). Each piece of gear's
  `EquipDef.worn` is its layer, cut from the same cells (`art/sheets/hero_*.json`, one frame per
  cell named like `idle1` or `walk2`), so layers line up frame by frame; `hides_hair` (helmets,
  hats) sets where it stacks. A weapon or off-hand is instead `EquipDef.held` (`HeldDef`,
  `data/hero/held/`): ONE painting pinned per frame (anchor point, spot, turn and layer), the
  MapleStory way. Pose him by hand in `scenes/dev/hero_pose_editor.tscn` (play it in Godot:
  pick the job ("No job" for the plain hero), pose and what he wears from the dropdowns, click
  any piece and drag it, wheel or Q/E to turn, Shift+wheel or [ ] to resize, PgUp/PgDn to move
  it up or down the stack, Save writes the files). Held pieces save to their pins; worn layers
  to `EquipDef.nudges` and his body, face, hair and fists to `HeroLookDef.nudges` (frame ->
  Vector4: shift, turn, places up the stack), and sizes to each one's `sizes` (frame -> share
  of its painted size), applied whole by `HeroBody.Layer`. A character has no picked appearance
  yet; older saves that carry one still load.
- **One body for every hero**: your hero (`TDPlayer`) and other players' (`TDAvatar`) each
  work out what they are doing (from your keys, or from the snapshot: an animation name such
  as "walk", "attack" or a skill's `animation`), and `HeroBody`
  (`scripts/components/hero_body.gd`) shows them the same way for both. It stacks one sprite per
  layer in a fixed order (`HeroBody.layers`) and brings along the companion (the pet).
  Other players' gear reaches you as item ids in their info (`SimPlayer.info`). The sizes the game needs for a
  hero (`TDPlayer.HEIGHT`, `WIDTH`, `CHEST`, `SimPlayer.HURTBOX_SIZE`) are constants.

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
  instead of the bag. The book's level adds to every main stat in `Character.recalc`.
- **Achievements** are **AchievementDef**s in `data/achievements/`, loaded by `Content`; each
  measures something about the Character (its `kind`, see `Achievements.measure`) against a
  `goal`. `Achievements.all()` lists them in `order` for the collection window and the server.
  The server checks them whenever a player's state changes (`TDServer.check_achievements`)
  and sends `ev_achievement`; the client shows it and calls `SteamService.unlock_achievement`
  with its `steam` id. Add one by adding a `.tres` (a new `id`, a `steam` name defined in
  Steamworks, the next `order`). Never change a shipped `id` or `steam` name: saves keep the
  id and Steamworks the name (`level_50` kept its name while the cap was 35; its goal is 50 again). A new kind of tally gets a name in `Counters` and is added with
  `Character.count(Counters.<NAME>)`.

### Balance

`Balance` builds a typical character for any job and level (points in the main stat, the best
gear they could wear) and works out how many hits of their main attack a monster takes and how
many kills a level needs. The smoke test keeps every job inside `Balance.BAND` against every
monster of its level; `tests/balance_report.tscn` prints the full table when tuning.

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
