# Items, gear and weapons

Part of the [architecture docs](../../ARCHITECTURE.md).

## Items, equipment and stats

There are no base stats: a character's level and job set what gear doesn't. Everything they
wear (and their passive and buff skills) adds a **StatBlock**; `Character.stats` is the total.
From the level, job and stats, `CharacterStats` works out:

- **Power** (`power`): the job's `base_power` plus `POWER_PER_LEVEL` every level past the first;
  `Character.power` adds the Monster Book's rank (`MonsterBook.power_bonus`).
- **Damage range**: max = power × `MAIN_STAT_WEIGHT` × Weapon Attack / 100 × `DAMAGE_SCALE`,
  min = max × the job's mastery. Spells use Magic Attack plus power (`magic_attack`).
- Avoidability (dodging monster touches): gear's, `BASE_AVOID`, and the job's `avoid_growth` a
  level. Weapon Defense lowers the damage, Speed and Jump scale movement.
- Max HP and MP: the job's base plus its `hp_growth`/`mp_growth` times the level, plus gear.
- Attack Speed (%) shortens cooldowns and swings (`attack_ticks`); Melee and Ranged Damage (%)
  raise hits with and without a projectile (`damage_bonus`).

`Combat` uses those numbers, so all balance lives in `character_stats.gd` and `combat.gd`.

Levels (`Character.level`, `xp`, up to `MAX_LEVEL`) come from EXP: `TDServer.give_xp` adds a
kill's essence (`SimMob.essence`) or a quest's `reward_essence` as EXP, `Character.gain_xp`
levels up on `CharacterStats.xp_need` and refills HP and MP, and `ev_level_up` plays the
`level_up` effect and jingle (`TDWorldFx.show_level_up`). Fainting loses 10% of the EXP toward
the next level (`Combat.faint_penalty`).

Dawn Essence (`Character.essence`): monsters (`MonsterDef.essence`, flown to the killer by
`TDWorldFx.fly_essence`) and quests (`QuestDef.reward_essence`) give it, and it buys skill
levels (`SkillBook.learn`, `CharacterStats.skill_price`: each skill level bought makes the
next dearer). Saves that still carry base stats get the essence of every stat point bought
back (`CharacterCodec.old_points_bought`); saves from before essence keep their level and EXP
and turn unspent points into essence (`CharacterCodec._essence_from_points`); saves from the
days without levels get a level per `CharacterCodec.OLD_POINTS_PER_LEVEL` stat points.

There are four inventory tabs, and the class of the item decides which one it goes in:

| Class | Tab | What |
| --- | --- | --- |
| **EquipDef** | Equip | Gear: slot, the job lines that wear it, a hidden tuning tier (`required_level`), a `StatBlock` of bonuses, and `variance` (each dropped copy rolls every stat up or down by up to this much) |
| **UseDef** | Use | Potions: HP / MP restored (flat and percent), effect, cooldown |
| **ItemDef** | Etc | Monster parts and anything else; stacks up to `max_stack` |
| **PetDef** | Setup | Pets: `loot_reach`, `loot_every`, `hunger_ticks` and their `chatter` |
| **CardDef** | (book) | Monster Book cards, made by `Content` for every monster |
| **RelicDef** | (moves) | A boss's relic: picking it up unlocks its `move` for good (`Character.relics`) |
| **RuneDef** | Etc | An enchant rune: a `StatBlock` of bonuses, the enchanter's `fee`, `boss` for a boss's own |

## Runes and enchanting

Every piece of gear has `ItemStack.RUNE_SLOTS` (3) rune slots: `ItemStack.runes` holds the
RuneDef in each, null where it's empty, and saves them by id ("runes"; saves from before runes
load with three empty slots). `ItemStack.total()` is the piece's own stats plus its runes', and
that is what worn gear adds (`Equipment.bonus`). An enchanter (`NpcDef.enchants`) opens
`TDEnchantWindow`; `Net.req_enchant` goes to `ServerEnchanting.on_enchant`, which checks the
player stands by them, and the rule is `Gear.enchant`: a rune from the Etc tab into a slot of a
piece in the Equip tab for the rune's `fee`, always working, replacing what was there.

Zone runes drop from every monster on a region's maps (`RegionDef.drops`, rolled in
`MapInstance.kill_mob` after the monster's own `drops`); a boss's own rune is a line on its
`drops`. To add a rune, save a RuneDef in `data/items/runes/` and add a DropEntry for it to its
region or boss.

Equipment slots: Weapon, Hat, Top, Bottom, Shoes, Gloves, Cape, Earrings, Pendant, two Rings
and Shield (`EquipDef.Slot` and `Equipment.PLACES_FOR`). Adding a slot means adding it to both.
The Shield slot is called Off-hand in the game (its place key stays `shield`): it holds a shield or a job's off-hand: `EquipDef.offhand_kind` says what a piece is
(shield, star, book, quiver, pistol; `Gear.offhand`), and skills can ask for one
(`SkillDef.offhand`).

## How to add an item or piece of gear

1. Give it an icon in `assets/sprites/items/<id>.png`: a painted cell on an item sheet (a Gemini
   edit in `tools/art/gemini_pass.json`, cut by its `art/sheets/items_*.json` manifest). Gear
   has no icon yet; an item slot shows the item's name instead, and a drop shows only its glow.
   Gear the hero wears also sets `worn` (its layer, see [characters](characters.md)).
2. Create the `.tres` in `data/items/equips/`, `use/`, `etc/` or `setup/` as an
   **EquipDef**, **UseDef** or **ItemDef**. Fill in `id`, name, description, icon and
   `sell_price`; for gear, the slot, its job lines and a **StatBlock** in `stats`.
3. Make something drop it: a **DropEntry** on a monster's `drops` (item, chance from 0 to 1,
   amount range). Rare gear is usually 1 to 4%.

A **new kind of consumable** (something no `UseDef` field does yet) is a new field on
`UseDef` plus one small step in `ServerItems.on_use_item` (`scripts/server/services/items.gd`),
next to the ones for pet food, teleporting and restoring HP/MP.

Dawnshards go straight to the wallet when walked over; everything else waits on the ground
for the loot key, and stays there if its tab is full.

## How to add a weapon

A weapon is an **EquipDef** in the Weapon slot with a `weapon_kind` (sword, dagger, bow, wand,
staff, knuckle...), which skills can ask for (`SkillDef.weapons`), and optionally a
`basic_attack` that replaces the plain attack while it is wielded. How it looks and is held is
its hero painting (`data/hero/held/`, see characters.md); it has no icon yet.
