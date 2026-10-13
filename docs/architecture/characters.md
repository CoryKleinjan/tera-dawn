# Characters: looks, extras, balance and player actions

Part of the [architecture docs](../../ARCHITECTURE.md).

## Character creation and looks

**Create** on character select opens the character creator (`TDCreator`): a name and the
look and outfit (`NewCharacter`). `Net.create_character` makes a level 1 character in the
starting job (`Character.START_JOB`) and saves it on this computer (`CharacterStore.create`),
then character select shows the list with the new character picked.

- **Appearance** (on the Character) is a skin tone, face, eye colour, hairstyle and hair
  colour, each the id of a `LookDef` in `data/looks/`. Add an option by adding a file;
  `creator` and `order` decide whether and where the creator lists it.
- **Outfit** choices come from the starting job's `creator_gear` (one piece per kind). It is
  empty while the gear is being redrawn, so the creator offers no outfit for now.
- **Looks** travel in each player's info (`ev_player_info`, sent when it changes; `Character.look()`: appearance and the worn
  gear that shows), so everyone sees everyone's hair and gear.
- **Drawing** is done by `Paperdoll`, which works out the layers from a look;
  `PaperdollSprite` shows it in the world (on `SpriteRig`). Menus (the creator, character
  select, the equipment window) draw him the same way: `PaperdollView` stands the world's own
  rig (`HeroBody.make_rig`) in a little 3D stage of its own, lit and colour graded like the map
  showing now (`TDStage.light_portrait`, `shaders/grade.gdshaderinc`), so he looks exactly as he
  does in game. There is no separate menu drawing to keep in step.
- **The old hero's layers** (in game until the new paperdoll hero, being rebuilt from
  `art/reference/hero.png`, is approved and replaces them): a bare body strip (`hero.png`)
  with layers that play frame for frame with it: hair (front and back), faces and irises, and
  worn cuts (`assets/animations/paperdoll/`). `tools/art/paperdoll_layers.py` builds them, with
  the body's region map (`hero_regions.png`) and rig (`hero_rig.json`: head, face, neck, hand
  and off-hand per frame, and how each weapon kind is held). The skin tone recolours the body;
  hair, irises and greyscale gear cuts are tinted (`shaders/gear_tint.gdshaderinc` keeps the
  painted shading). Under a hat his own hair layer is cut where the hat's
  `haircut_<hat>_<style>.png` strip says (`Piece.hair_cuts`). In the 3D stage his layers are
  lit like everyone else, sampled from mipmaps and blended at their edges
  (`shaders/paperdoll_stage.gdshaderinc`), drawn in order with their own render priorities
  (`TDStage.PRIORITY_*`). Gear that keeps its shape (weapon, off-hand, hat) is a
  `Paperdoll.Piece`: one picture per view that the game places, turns and sizes on every frame
  (`assets/sprites/characters/pieces/<name>.json`, written by `tools/art/paperdoll/pieces.py`).
  A weapon is always in his front fist with his fingers drawn over its grip (`fist_<kind>.png`,
  `shaders/paperdoll_piece.gdshaderinc`) and on his back while he climbs; every kind copies the
  staff's holds ("holds" in `art/sheets/paperdoll_rig.json`) with its own grip point. Clothes,
  shoes and capes bend with his body, so they stay strips (`EquipDef.worn_style`,
  `EquipDef.worn_frames`). The strip is cut at the painted sheet's full resolution:
  `Paperdoll.ART_SCALE` strip pixels make one hero pixel.
- **Animation**: each weapon fights its own way (`WeaponStyle`): a skill's motion ("attack",
  "slash") becomes the weapon's own animation (a bow shoots, a star is thrown, knuckles punch, a
  staff smashes), and other names play as they are, except "cast" (`WeaponStyle.SPELL`):
  buffs and spells make no motion, the hero flashes the skill's colour (`SkillDef.flash`,
  `SpriteRig.pulse`). Frames have their own durations (a held wind-up), and `TDPlayer` adds a
  ready stance after fighting, a turn, the top of a jump, a landing crouch only after a real
  drop and a walk that keeps step with his speed and picks up 15% pace after about 0.4 s
  (`SpriteRig.STEP_CYCLES`; the run frames never play). Every walk frame is drawn mid-stride, so on the passing
  steps (`Paperdoll.PASSING_STEPS`) the shaders slide his lower legs in toward each other,
  his body and every strip layer alike (`shaders/paperdoll_stride.gdshaderinc`). Standing, he breathes (the rig's body rises and settles
  slightly from his feet, so every layer moves with it: `SpriteRig.breathes`, `BREATH_*`) and blinks
  now and then, sometimes twice (the "blink" animation, `SpriteRig.BLINK_EVERY`), in menus too.
  NPCs hold still (`SpriteRig.hold_still`). Held weapons point forward on every resting and
  moving frame (`tests/unit/hero_pose_test.gd`). Poses not drawn yet fall back to the nearest
  one (`SpriteRig.FALLBACK`). `WeaponTrail` draws the streak a
  swung blade leaves and the flash of a shot.
- **One body for every hero**: your hero (`TDPlayer`) and other players' (`TDAvatar`) each
  work out their pose (from your keys, or from the snapshot), and `HeroBody`
  (`scripts/components/hero_body.gd`) draws it the same way for both: the rig with its light
  (`HeroBody.FRAMES`, `SCALE`, `LIGHT`), the chair lift, the walk keeping step
  (`stride_speed`), the blink after a hit, a skill's weapon motion or spell flash
  (`use_skill`), and the companion. A change to how heroes are drawn goes there.

### Chairs, pets, the Monster Book and achievements

- **Chairs** (`ChairDef`) and **pets** (`PetDef`) live in the Setup tab and are used with
  `req_setup`. The server keeps the chair you sit on in `SimPlayer.chair` (moving clears it)
  and adds its regen; the pet that's out is `Character.pet`, with `pet_full` dropping every
  `hunger_ticks` and `MapInstance._pet_step` picking up drops within `loot_reach`. Both go out
  in the player's info, and `TDCompanion` (owned by each `HeroBody`) draws them next to you and other players.
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
  id and Steamworks the name (that's why `level_50` keeps its name from when the cap was 50,
  though its goal is 35). A new kind of tally gets a name in `Counters` and is added with
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
