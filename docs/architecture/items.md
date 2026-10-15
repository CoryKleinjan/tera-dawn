# Items, gear and weapons

Part of the [architecture docs](../../ARCHITECTURE.md).

## Items, equipment and stats

Stats work like MapleStory. A character has base **STR / DEX / INT / LUK / CHA** (their job's
starting stats plus the Ability Points they spend, 5 per level), and everything they wear adds
a **StatBlock** on top. `Character.stats` is the total. From it, `CharacterStats` works out:

- **Damage range**: max = main stat × `MAIN_STAT_WEIGHT` × Weapon Attack / 100 × `DAMAGE_SCALE`,
  min = max × the job's mastery. The job's `primary_stat` is its one main stat (STR for
  warriors, CHA for pirates); no other stat adds to damage. A job with `uses_best_stat` (the
  Beginner) hits with whichever base stat is highest (`JobDef.damage_stat`).
- What each stat also gives: STR Max HP, INT Max MP (and Magic Attack), DEX Accuracy (hitting
  monsters above your level), LUK Avoidability (dodging their touches), CHA a shop discount
  (`shop_discount`, capped at `MAX_DISCOUNT`, used by `ShopEntry.cost_for`) and more
  Dawnshards picked up (`shard_bonus`). Weapon Defense lowers the damage, Speed and Jump scale
  movement.
- Max HP and MP: the job's base plus growth per level plus gear, plus STR and INT.
- Attack Speed (%) shortens cooldowns and swings (`attack_ticks`); Melee and Ranged Damage (%)
  raise hits with and without a projectile (`damage_bonus`).
- When these rules change, `CharacterCodec.STAT_RULES` goes up and older saves get every
  Ability Point back once (`AbilityPoints.refund_all`).

`Combat` uses those numbers, so all balance lives in `character_stats.gd` and `combat.gd`.

Levels: `Character.xp_need` is the EXP curve (one formula, steeper from Lv 10, tuned with the
pace bot, then halved for twice the speed: roughly half an hour to Lv 10 and 15-25 to the cap,
quests included). `Character.MAX_LEVEL`
(100) is the cap: EXP stops there and the status bar and stats window say "Max level".

There are four inventory tabs, and the class of the item decides which one it goes in:

| Class | Tab | What |
| --- | --- | --- |
| **EquipDef** | Equip | Gear: slot, required level and stats, a `StatBlock` of bonuses, and `variance` (each dropped copy rolls every stat up or down by up to this much) |
| **UseDef** | Use | Potions: HP / MP restored (flat and percent), effect, cooldown |
| **ScrollDef** | Use | Upgrade scrolls: the gear `slots` they work on, a success `chance` and the `stats` they add. Each use spends one of the gear's `upgrade_slots` (`ItemStack.slots_used`; `upgrades` counts the ones that worked) |
| **ItemDef** | Etc | Monster parts and anything else; stacks up to `max_stack` |
| **ChairDef** | Setup | Chairs: extra `regen_hp` / `regen_mp` while sitting |
| **PetDef** | Setup | Pets: `loot_reach`, `loot_every`, `hunger_ticks` and their `chatter` |
| **CardDef** | (book) | Monster Book cards, made by `Content` for every monster |

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
2. Create the `.tres` in `data/items/equips/`, `use/`, `etc/`, `scrolls/` or `setup/` as an
   **EquipDef**, **UseDef** or **ItemDef**. Fill in `id`, name, description, icon and
   `sell_price`; for gear, the slot, requirements and a **StatBlock** in `stats`.
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
`basic_attack` that replaces the plain attack while it is wielded. It has no art for now: how
weapons look and are held comes back with the hero's new look.
