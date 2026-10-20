# Items, gear and weapons

Part of the [architecture docs](../../ARCHITECTURE.md).

## Items, equipment and stats

There are no base stats and no levels (Hollow Knight style, Cory Oct 19). Everything a
character wears adds a **StatBlock**; `Character.stats` is the total. From it,
`CharacterStats` works out:

- **Damage range** (`damage_range`): max = the weapon's attack (the bigger of Weapon and Magic
  Attack, `main_attack`) × `DAMAGE_PER_ATTACK`, min = max × `MASTERY`. A piece's tier raises its
  own stats, so the weapon's tier sets damage.
- Hearts and Mana: `BASE_HEARTS` plus one per `HEART_SHARDS_PER_HEART` Heart Shards, and the
  Mana orb (`max_mp`); see [characters](characters.md).
- Speed and Jump scale movement. Attack Speed (%) shortens cooldowns and swings
  (`attack_ticks`); Melee and Ranged Damage (%) raise hits with and without a projectile
  (`damage_bonus`).

`Combat` uses those numbers, so all balance lives in `character_stats.gd` and `combat.gd`.

Old saves load without their level, EXP, essence and bought skill levels (`CharacterCodec`
skips them), and quickslots holding a removed skill or item come back empty.

There are four inventory tabs, and the class of the item decides which one it goes in:

| Class | Tab | What |
| --- | --- | --- |
| **EquipDef** | Equip | Gear: slot, the job lines that wear it, a hidden tuning tier (`required_level`), a `StatBlock` of bonuses, and `variance` (each dropped copy rolls every stat up or down by up to this much) |
| **UseDef** | Use | Scrolls and pet food: a teleport, `pet_food`, effect, cooldown (no potions) |
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

Gear tiers: `ItemStack.tier` (1 to `Content.top_gear_tier()`, saved as "tier"; saves from
before tiers load at 1) scales the piece's own stats by its **GearTierDef**'s `stat_scale`
(`ItemStack.own_stats`; runes don't scale). The tiers are `data/gear_tiers/tier_<n>.tres`
(`rank`, `display_name`, `stat_scale`, `fee`); `Content.gear_tier(rank)` finds one. The
enchant window's Upgrade button sends `Net.req_upgrade` to `ServerEnchanting.on_upgrade`, and
the rule is `Gear.upgrade`: one tier up for the next tier's `fee`, always working. A tier never
changes the look. Gear never drops (the content checks fail on a gear DropEntry in a monster,
region or chest); shops sell it, each line hidden until its `ShopEntry` unlock is done.

Zone runes drop from every monster on a region's maps (`RegionDef.drops`, rolled in
`MapInstance.kill_mob` after the monster's own `drops`); a boss's own rune is a line on its
`drops`. To add a rune, save a RuneDef in `data/items/runes/` and add a DropEntry for it to its
region or boss.

Equipment slots: Weapon, Armor, Earrings, Pendant and two Rings (`EquipDef.Slot` and
`Equipment.PLACES_FOR`; the enum keeps the numbers the data files hold). Adding a slot means
adding it to both and to `TDEquipmentWindow.LAYOUT`. The Armor piece is a whole outfit (hat to
shoes, cape and off-hand); there is no off-hand slot. A save from before keeps its weapon and
accessories and drops what was in the old Hat, Top, Bottom, Shoes, Gloves, Cape and Off-hand
places (`Equipment.load_dict`).

**Job sets** (`GearSetDef`, `data/gear_sets/`): one Armor piece and one weapon, painted onto the
hero together (see [characters](characters.md)), and the set's effect while both are worn
(`Gear.full_set`). The Vanguard's Battle Fury is its `kill_buff`: a buff `SkillDef` in no job
(`data/skills/sets/`) that `Gear.on_kill` (called from `MapInstance.kill_mob`) starts or raises
a level per kill up to its `max_level`, restarting its time; `Gear.equip`/`unequip` end it when a
piece comes off. Its stacks are the buff's level, so its stats (`attack_speed`) scale with
`stats_per_level`, and the client knows it like any buff. The item tooltip names the set and
lights its effect while it is worn.

## How to add an item or piece of gear

1. Give it an icon in `assets/sprites/items/<id>.png`: a painted cell on an item sheet (a Gemini
   edit in `tools/art/gemini_pass.json`, cut by its `art/sheets/items_*.json` manifest). A set
   piece's icon is painted fresh, showing what the hero wears (`items_vanguard.json`); older
   gear with no icon shows its name instead. A set piece also needs its outfits painted (see
   [characters](characters.md)).
2. Create the `.tres` in `data/items/equips/`, `use/`, `etc/` or `setup/` as an
   **EquipDef**, **UseDef** or **ItemDef**. Fill in `id`, name, description, icon and
   `sell_price`; for gear, the slot, its job lines and a **StatBlock** in `stats`.
3. Make it reachable: an item is a **DropEntry** on a monster's `drops` (item, chance from 0
   to 1, amount range); gear never drops, so a shop line sells it (`ShopEntry`, with its
   unlock).

A **new kind of consumable** (something no `UseDef` field does yet) is a new field on
`UseDef` plus one small step in `ServerItems.on_use_item` (`scripts/server/services/items.gd`),
next to the ones for pet food, teleporting and restoring HP/MP.

Dawnshards go straight to the wallet when walked over; everything else waits on the ground
for the loot key, and stays there if its tab is full.

## How to add a weapon

A weapon is an **EquipDef** in the Weapon slot with a `weapon_kind` (sword, dagger, bow, wand,
staff, knuckle...), which skills can ask for (`SkillDef.weapons`), and optionally a
`basic_attack` that replaces the plain attack while it is wielded. It shows in his hand only
where an outfit paints it (see characters.md).
