# Tera Dawn architecture

Tera Dawn is meant to grow into a much larger game, so content lives in data files and the
code is split into small pieces that each do one job. Adding a monster, a map or a skill
should never mean editing game code.

## The big picture

```
data/*.tres  ──►  Content (autoload)  ──►  World loads a MapDef  ──►  Stage builds it in 3D
 (what exists)     (finds it by id)          (spawns actors)            (terrain, backdrop, scenery)
```

- **Data** (`scripts/data/`, saved as `.tres` in `data/`) says *what* things are: a monster's
  stats and sprite, a map's platforms and spawns, a skill's reach and damage. Every class is a
  Godot `Resource`, so it can be edited in the Godot inspector.
- **Systems** (`scripts/systems/`) are the character's rules that aren't tied to the world:
  `Character` (level, EXP, stats, bag, gear, HP, MP), `Inventory`, `Equipment`, `ItemStack`
  (one slot's worth of an item, with its own rolled stats for gear) and `CharacterStats` (the
  MapleStory formulas). The server owns each player's `Character`; `Game.me` is your copy.
- **Components** (`scripts/components/`) are small reusable parts any actor can use: `Health`,
  `Hitbox` and `SpriteRig` (sprite, animation, shadow, light and aura).
- **Server** (`scripts/server/`) runs the game for everyone (see Multiplayer below).
- **Actors** (`scripts/actors/`) are what you see in the world: your hero, other players,
  monsters, NPCs and drops.
- **World** (`scripts/world/`) shows the map you're on: `world.gd` builds it and shows the
  server's events, `stage.gd` and its builders turn a map into the HD-2D diorama.
- **UI** (`scripts/ui/`) draws the HUD from the sliced UI sheet through `UiSkin`.
- **Art** comes from Cory's sheets in `art/source/`, cut by `tools/art/slice_sheets.py`
  (see `art/sheets/README.md`).

Game logic is 2D: positions are game pixels with y pointing down, and physics ticks 60 times a
second. Only the stage turns that into 3D (32 game pixels per 3D unit).

## Multiplayer: server and client

Tera Dawn is online, and there is always a server, even in single player. One codebase plays
three roles:

```
             requests (req_*)                    events (ev_*)
TDWorld  ───────────────────────►  TDServer  ─────────────────────►  TDWorld (every player
(your game)   through Net           MapInstance per map                on that map)
```

- **Server** (`scripts/server/`): `TDServer` holds every connected player as a `SimPlayer`
  (their `Character`, position and timers) and runs one `MapInstance` per visited map: its
  `SimMob`s, the `SimDrop`s on the ground and the players on it. It decides everything that
  matters: hits, damage, kills, EXP, levels, drops, who picks what up, HP and MP, potions,
  gear, portals, fainting. `CharacterStore` saves characters, one JSON file per name.
- **Client** (`scripts/world/`, `scripts/actors/`): `TDWorld` shows the map you're on. Your own
  hero (`TDPlayer`) moves and climbs on your machine so it feels instant, like MapleStory, and
  reports where it is 20 times a second; the server checks the report is possible and puts you
  back if not. Monsters (`TDMob`), other players (`TDAvatar`) and drops (`TDDrop`) are views
  that glide to where the server's snapshots say they are.
- **Net** (`scripts/autoload/net.gd`) is the whole protocol in one file. `req_*` methods go from
  a client to the server, `ev_*` methods from the server to clients. UI and actors call
  `Net.ask(&"req_…", [args])`; the server answers with events, and `Game.me` (your copy of
  your Character) is refreshed from them. Never change `Game.me` to make something happen.

The three ways to play all use the same rules: **Play** runs a server inside the game with an
offline peer (messages never touch the network), **Host** does the same on an ENet port so
others can join, and `-- --server` (see `scripts/boot.gd`) runs a server with no player.

Shared pieces both sides use: `MapLayout` (a map's platforms, ropes, portals), `DropFlight`
(how a drop flies and lands, run identically everywhere), `Combat` and `CharacterStats`.
Monster index `i` is the same monster on both sides because both build them from
`MapDef.roster()`: the map's spawns in order, each monster that splits followed by the
monsters it splits into (those sleep, dead, until their parent is defeated).

### Players together

`TDSocial` (`scripts/server/social.gd`, owned by the server) runs everything players do with
each other: chat and its slash commands, invitations (`ev_invite` / `req_invite_answer`),
buddies (kept on the Character), parties (server memory only; `party_shares` hands out kill
EXP), trades (offers are held by the server until both press Trade, then swapped, or handed
back on cancel), guilds (saved in `guilds.data` next to the character saves), fame, and player
shops on maps with `MapDef.market`. Each player gets a summary of their buddies, party and
guild through `ev_social` whenever it changes (`Game.social`); the community window, the
player menu, the party HP list and the trade and shop windows (`scripts/ui/social/`) read it.

### Chairs, pets, the Monster Book and achievements

- **Chairs** (`ChairDef`) and **pets** (`PetDef`) live in the Setup tab and are used with
  `req_setup`. The server keeps the chair you sit on in `SimPlayer.chair` (moving clears it)
  and adds its regen; the pet that's out is `Character.pet`, with `pet_full` dropping every
  `hunger_ticks` and `MapInstance._pet_step` picking up drops within `loot_reach`. Both go out
  in the player snapshot, and `TDCompanion` draws them next to you and other players.
- **The Monster Book** (`MonsterBook`, on the Character) counts kills and cards per monster.
  `Content` makes a `CardDef` for every monster at startup (`card_<id>`, no files); monsters
  drop it at `CardDef.CHANCE` until your page is full, and picking it up files it in the book
  instead of the bag. The book's level adds to every main stat in `Character.recalc`.
- **Achievements** (`Achievements.LIST`) each measure something about the Character and a
  goal. The server checks them whenever a player's state changes (`TDServer.check_achievements`)
  and sends `ev_achievement`; the client shows it and calls `SteamService.unlock_achievement`
  with its `steam` id. Add one by adding a line; a new kind of tally goes through
  `Character.count`.

### Balance

`Balance` builds a typical character for any job and level (points in the main stat, the best
gear they could wear) and works out how many hits of their main attack a monster takes and how
many kills a level needs. The smoke test keeps every job inside `Balance.BAND` against every
monster of its level; `tests/balance_report.tscn` prints the full table when tuning.

### How to add something the player does

1. Add a `req_<thing>` to `Net` that calls `server.on_<thing>(_sender(), …)`.
2. Write `TDServer.on_<thing>`: check it's allowed, change the `Character` or map, and mark
   `dirty_character` / `dirty_vitals` so the player gets their new state.
3. If other players should see it, broadcast an `ev_<thing>` from the `MapInstance` and show
   it in `TDWorld`.
4. Call `Net.ask(&"req_<thing>", […])` from the UI or `TDPlayer`.

## Folders

```
data/                 Content, one .tres per thing
  monsters/ npcs/ items/ skills/ effects/ jobs/   Looked up by id through Content
  items/equips/ items/use/ items/etc/ items/setup/   Subfolders are scanned too
  maps/ biomes/ climb_styles/               Maps and how they look
scripts/
  autoload/           Content (data index), Game (your character copy, settings, input),
                      Net (connections and the protocol), SteamService
  server/             TDServer, MapInstance, SimPlayer, SimMob, SimDrop, CharacterStore
  data/               Resource classes for everything in data/
  systems/            Character, Inventory, Equipment, ItemStack, CharacterStats, MonsterBook,
                      Achievements, Balance
  components/         Health, Hitbox, SpriteRig
  actors/             Player (you), Avatar (other players), Companion (chairs, pets), Mob, Npc, Drop views
  world/              World (what you see), Stage + Terrain/Backdrop/Scenery builders, MapLayout,
                      Platform, DropFlight, Combat
  fx/                 Flipbook effects and floating text
  ui/                 HUD, status bar, overlay, UiSkin, Palette
  ui/windows/         Draggable windows (inventory, equipment, character) and the item tooltip
assets/
  sprites/            Cut sprites, one folder per kind (generated, don't hand-edit)
  animations/         SpriteFrames for animated actors (generated)
art/
  source/             Cory's raw sheets
  sheets/             One manifest per sheet: how to cut it
  reference/          Style reference (the hero)
store/                Steam capsules and key art
tools/art/            Slicer, store-art cropper, fx texture and item placeholder generators, contact-sheet preview
tests/                Headless smoke test (with a second game joining), bot client, screenshot scene
```

## Draw order

The world is a 3D diorama, so what covers what depends on depth (3D z, bigger is nearer the
camera). The layers are constants at the top of `scripts/world/stage.gd`, back to front:

| Layer | Depth | What |
| --- | --- | --- |
| Backdrop | far behind | Sky, mountains, distant trees (`BackdropLayerDef.depth`) |
| Land | up to `LAND_FRONT` | Ground, platforms and their front skins, decoration, props, lanterns, signs, portals |
| `Z_CLIMBABLE` | 0.2 | Ropes, vines and ladders |
| `Z_NPC` | 0.3 | NPCs |
| `Z_MONSTER` | 0.38 to 0.52 | Monsters, each at a slightly different depth so overlapping ones don't flicker |
| `Z_DROP` | 0.56 | Dawnshards and other drops |
| `Z_OTHER_PLAYER` | 0.6 | Other players |
| `Z_PLAYER` | 0.64 | Your hero |
| `Z_EFFECT` | 0.8 | Skill and hit effects |

Everything you can touch stands in front of all the land, so a platform, bush or prop never
hides a character, NPC, rope or ladder. Decoration and prop depths in data are clamped with
`TDStage.land_depth()`, so a `DecorDef` or `PropPlacement` can't be set in front of the
actors by mistake. Something new that the player interacts with should use one of the `Z_`
layers (or add one here) rather than a raw number.

## How to add a monster

1. Get its sprite. A single image goes in `assets/sprites/monsters/<id>.png`; an animated
   one comes from a sheet with a `sets` block that writes `assets/animations/<id>.tres` with
   the animations `idle`, `move`, `attack`, `hurt` and `die` (any missing one falls back to
   `idle`; single images get a little procedural bob and squash instead).
2. Create `data/monsters/<id>.tres` as a **MonsterDef** (in the editor: right-click
   `data/monsters/` → New Resource → MonsterDef). Fill in `id`, name, level, HP, attack, EXP,
   speed, hitbox `size`, and either `texture` or `sprite_frames`. Use `sprite_scale` if the art
   is too big or small next to the hero.
3. Add drops: each `DropEntry` is an item, a chance and an amount range.
4. Optional: `flying` with `hover_height`, `boss`, a `light_color` or `aura_color` for
   glowing monsters, a `tint` (one sprite can stand in for several monsters), and
   `respawn_ticks`.
5. Optional behavior (`SimMob` runs it): `jumps` hops now and then; `stationary` never walks;
   `shot` (a ProjectileDef) with `shot_range` and `shot_cooldown` shoots whoever hit it, or
   anyone in range when `aggressive`. A shot flies to where the player stood (`ev_mob_shot`)
   and only hurts them if they're still there when it lands. `splits_into` with `split_count`
   bursts into smaller monsters when defeated.
6. Put it on a map: add a **SpawnDef** to the map's `spawns` with the monster, a platform index
   and a count.

`Content` finds every `.tres` in `data/monsters/` on its own; there's no list to update.

## How to add a map

1. Create `data/maps/<id>.tres` as a **MapDef**. Give it an `id`, a display name, a size and
   a `biome` (`data/biomes/meadow.tres` or `ember.tres`, or a new BiomeDef).
2. Lay it out: `platforms` (one-way, numbered from 1; the floor is 0), `climbables` (x, top,
   bottom and a climb style: rope, vine, ladder or rope ladder) and `portals`.
3. Fill it: `spawns`, `npcs` (an **NpcPlacement** with an NpcDef and an x) and hand-placed
   `props` on top of the biome's random decoration.
4. Connect it: add a **PortalDef** on an existing map whose `target_map` is the new id, and a
   portal back.
5. Place it in the world: its `region` (a **RegionDef** in `data/regions/`), `world_pos` on
   the world map (1000 x 600 units), `level_text`, and either `town = true` or the
   `return_map` where fainting and Return Scrolls send you.

An NpcDef with `storage = true` keeps the player's storage (`Character.storage`, an
Inventory saved with the character; `TDServer.on_store` / `on_retrieve`, `TDStorageWindow`).
The same NpcDef can stand in several maps (Brin is in every town).

Travel NPCs (ships, wagons) list **TravelRoute**s in `NpcDef.travel` (destination, arrival x,
fare, "Ship"/"Wagon"); their dialogue offers "Travel" and `TDServer.on_travel` moves the
player. A **UseDef** with `teleport` set to a map id, or to `town`, is a return scroll.

The smoke test checks that every portal points at a real map and every spawn at a real
platform, so a typo fails the test instead of the game.

A **BiomeDef** is the look shared by many maps: sky and light colours, ground and platform
textures, parallax backdrop layers (`BackdropLayerDef`: a tiled strip or scattered pieces at a
depth), random decoration (`DecorDef`), lantern, signpost and portal art. A new region of the
world is usually a new biome plus a few maps that use it.

## How to add a skill

1. Create `data/skills/<id>.tres` as a **SkillDef**: its `kind` (attack, buff or passive),
   the `job` whose skill book it's in, `max_level` and an optional `requires` skill. Costs and
   numbers that grow with the skill's level have a `_per_level` partner (`mp_cost_per_level`,
   `damage_per_level`, `stats_per_level`, `duration_per_level`, `regen_hp_per_level`).
   - Attacks: cooldown, how long the player is busy (`action_ticks`), the hit area (`reach`,
     `height`), `max_targets`, `hits` and the damage multiplier.
   - Buffs: `stats` added while it lasts, and `duration` in seconds.
   - Passives: `stats` always added, and/or extra HP/MP recovery.
   - The hero animation to play and the effects to show (`effect` on the player,
     `hit_effect` on each target).
2. Effects are **EffectDef**s in `data/effects/`: a flipbook of frames from
   `assets/sprites/effects/`, its speed and size, an optional light and particle burst.
3. Give it an icon (until there's art, add it to `tools/art/make_skill_placeholders.py`).

It then appears in its job's tab of the skill window (K). Players spend Skill Points on it
(`Character.learn`, checked by `TDServer.on_learn_skill`), and a newly learned attack or
buff goes on the first free quickslot. Quickslots (`Character.quickslots`, eight keys in
`Game.QUICKSLOT_ACTIONS`) hold skills or items and are saved with the character. The
server checks the skill is known and pays its MP (`TDServer.on_skill`), then works out what
it hits (`MapInstance.use_skill`) or starts the buff (`Character.add_buff`, counted down
in `SimPlayer.step`). Passives and buffs feed into the character's stats in `recalc`.

Ranged and magic skills:
- A `projectile` (a **ProjectileDef** in `data/projectiles/`: texture, speed, spin, light) makes
  the skill a shot. The server still decides the hit at once; clients fly one projectile per
  hit (`TDProjectile`) and pop the damage number when it lands, holding the monster's death
  until then.
- `uses_ammo` spends one of the weapon's ammo per hit. A weapon (`EquipDef`) names its
  `weapon_kind` (bow, claw, gun, wand, sword, knuckle), the `ammo` kind it fires, and an
  optional `basic_attack` skill that replaces the plain swing (a bow's Shoot). Ammo is an
  **AmmoDef** (Use tab) whose `attack` adds to Weapon Attack while fired.
- `weapons` limits a skill to weapon kinds; `magic` uses Magic Attack (INT included) through
  `CharacterStats.magic_range` instead of the weapon.

Damage is worked out in `scripts/world/combat.gd`, so balance changes stay in one place.

## Items, equipment and stats

Stats work like MapleStory. A character has base **STR / DEX / INT / LUK** (their job's
starting stats plus the Ability Points they spend, 5 per level), and everything they wear adds
a **StatBlock** on top. `Character.stats` is the total. From it, `CharacterStats` works out:

- **Damage range**: max = (primary × 4 + secondary) × Weapon Attack / 100 × `DAMAGE_SCALE`,
  min = max × the job's mastery. The job says which stat is primary (STR for warriors).
- Accuracy (DEX, LUK) lets you hit monsters above your level, Avoidability (DEX, LUK) dodges
  their touches, Weapon Defense lowers the damage, Speed and Jump scale movement.
- Max HP and MP: the job's base plus growth per level plus gear.

`Combat` uses those numbers, so all balance lives in `character_stats.gd` and `combat.gd`.

There are four inventory tabs, and the class of the item decides which one it goes in:

| Class | Tab | What |
| --- | --- | --- |
| **EquipDef** | Equip | Gear: slot, required level and stats, a `StatBlock` of bonuses, and `variance` (each dropped copy rolls every stat up or down by up to this much) |
| **UseDef** | Use | Potions: HP / MP restored (flat and percent), effect, cooldown |
| **AmmoDef** | Use | Arrows, stars and bullets fired by ranged weapons |
| **ScrollDef** | Use | Upgrade scrolls: the gear `slots` they work on, a success `chance` and the `stats` they add. Each use spends one of the gear's `upgrade_slots` (`ItemStack.slots_used`; `upgrades` counts the ones that worked) |
| **ItemDef** | Etc | Monster parts and anything else; stacks up to `max_stack` |
| **ChairDef** | Setup | Chairs: extra `regen_hp` / `regen_mp` while sitting |
| **PetDef** | Setup | Pets: `loot_reach`, `loot_every`, `hunger_ticks` and their `chatter` |
| **CardDef** | (book) | Monster Book cards, made by `Content` for every monster |

Equipment slots: Weapon, Hat, Top, Bottom, Shoes, Gloves, Cape, Earrings, Pendant, two Rings
and Shield (`EquipDef.Slot` and `Equipment.PLACES_FOR`). Adding a slot means adding it to both.

## How to add an item or piece of gear

1. Give it an icon in `assets/sprites/items/<id>.png`. Until there's real art, add it to
   `ICONS` in `tools/art/make_item_placeholders.py` (or `tools/art/item_icons.json`) and run
   the script.
2. Create the `.tres` in `data/items/equips/`, `use/` or `etc/` as an **EquipDef**, **UseDef**
   or **ItemDef**. Fill in `id`, name, description, icon and `sell_price`; for gear, the slot,
   requirements and a **StatBlock** in `stats`.
3. Make something drop it: a **DropEntry** on a monster's `drops` (item, chance from 0 to 1,
   amount range). Rare gear is usually 1 to 4%.

Dawnshards go straight to the wallet when walked over; everything else waits on the ground
for the loot key, and stays there if its tab is full.

## How to add a job

Create `data/jobs/<id>.tres` as a **JobDef**: primary and secondary stat, mastery, HP and MP
growth, Ability Points per level, its `family` (the job line gear names in `EquipDef.jobs`),
and a `tint` the hero is drawn in until the job has its own art.

Everyone starts as `Character.START_JOB` (the Beginner, which lists starting stats, gear and
items). A job that others reach sets `advances_from`, `advance_level`, `advance_requirements`
(base STR/DEX/INT/LUK) and `advance_gifts`. To let an NPC hand it out, add its id to that
NPC's `instructs`: their dialogue then offers "Choose a job", and the server
(`TDServer.on_advance` → `Character.advance`) checks the requirements again before changing it.

## How to add a window

Extend `TDWindow` (`scripts/ui/windows/window.gd`): draw in `_draw_body`, handle clicks in
`_click`, show tooltips from `_hovered`. Register it in `TDHud._build_windows` under an input
action, add the action to `TDHud.WINDOW_ACTIONS` and bind a key in `Game._setup_input`.

## How to add an NPC

Create `data/npcs/<id>.tres` as an **NpcDef** (name, title, sprite, a `greeting`, and the
`lines` they say when you pick Chat), then place it on a map with an **NpcPlacement**.
Pressing Up next to them opens `TDDialogueWindow`, which lists what they offer. To make NPCs
offer something new, add an option in `TDDialogueWindow._options()`.

## How to add a quest

Create `data/quests/<id>.tres` as a **QuestDef**: a title, the `giver` NPC id (and a
`turn_in` NPC if someone else takes it back), who can take it (`min_level`, `jobs`, quests it
`requires`), what the NPC says when offering it, while it's in progress and when it's handed
in, its **QuestObjective**s, and its rewards (EXP, Dawnshards, items). Objectives are:

- **KILL** `count` of a `monster`;
- **COLLECT** `count` of an `item` (taken when handed in). Give it a `drop_from` monster and a
  `drop_chance` to make a quest item that only drops for players on the quest (set
  `quest_item` on the ItemDef so it can't be sold or dropped);
- **VISIT** a `map`.

NPCs offer their quests on their own: a "!" over their head when one is available, "?" when
one is ready to hand in. `QuestLog` (in `Character`) holds progress and the rules; the
server's `on_quest_accept` / `on_quest_complete` apply them.

## How to add a shop

Create `data/shops/<id>.tres` as a **ShopDef**: a name and a list of **ShopEntry**s (an item
and its price; 0 means four times what a shop pays for it). Set it as an NpcDef's `shop` and
they offer "Open shop". Every shop also buys anything for the item's `sell_price`. The server
checks the player is standing by that NPC before buying or selling (`TDServer.on_buy`).

## How to add art

Drop the sheet in `art/source/`, write a manifest in `art/sheets/`, and run
`python3 tools/art/slice_sheets.py <name>`. `art/sheets/README.md` explains the manifest. The
cut sprites land in `assets/sprites/`, ready to be referenced from data.

## Conventions

- Ids are `StringName`s in snake_case and match the file name (`data/monsters/ember_boar.tres`
  has `id = &"ember_boar"`).
- Data classes end in `Def`; placements on a map (`SpawnDef`, `NpcPlacement`, `PropPlacement`)
  point at a Def.
- Code never names a specific monster, map or item; it reads what it needs from the Def.
- Generated files (`assets/sprites/`, `assets/animations/`) are rebuilt by the tools, so fix
  art in the sheet or manifest rather than in the output.
