# Items, gear and weapons

Part of the [architecture docs](../../ARCHITECTURE.md).

## Items, equipment and stats

Stats work like MapleStory. A character has base **STR / DEX / INT / LUK** (their job's
starting stats plus the Ability Points they spend, 5 per level), and everything they wear adds
a **StatBlock** on top. `Character.stats` is the total. From it, `CharacterStats` works out:

- **Damage range**: max = (primary × 4 + secondary) × Weapon Attack / 100 × `DAMAGE_SCALE`,
  min = max × the job's mastery. The job says which stat is primary (STR for warriors); a job
  with `uses_best_stat` (the Beginner) hits with whichever base stat is highest
  (`JobDef.damage_stats`).
- Accuracy (DEX, LUK) lets you hit monsters above your level, Avoidability (DEX, LUK) dodges
  their touches, Weapon Defense lowers the damage, Speed and Jump scale movement.
- Max HP and MP: the job's base plus growth per level plus gear.

`Combat` uses those numbers, so all balance lives in `character_stats.gd` and `combat.gd`.

Levels: `Character.xp_need` is the EXP curve (one formula, steeper from Lv 10, tuned with the
pace bot for about 2 hours to Lv 10 and 40 to the cap, quests included). `Character.MAX_LEVEL`
(35) is the cap: EXP stops there and the status bar and stats window say "Max level".

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

## How to add an item or piece of gear

1. Give it an icon in `assets/sprites/items/<id>.png`: a painted cell on an item sheet (a Gemini
   edit in `tools/art/gemini_pass.json`, cut by its `art/sheets/items_*.json` manifest). Gear's
   icon shows the same object the hero wears (shape, colours, details).
2. Create the `.tres` in `data/items/equips/`, `use/` or `etc/` as an **EquipDef**, **UseDef**
   or **ItemDef**. Fill in `id`, name, description, icon and `sell_price`; for gear, the slot,
   requirements and a **StatBlock** in `stats`. A top, bottom or shoes also needs a
   `worn_style`, the cut it's drawn in on the hero (tops: tunic, coat, robe, vest, plate,
   undershirt; bottoms: trousers, pants, breeches, shorts, greaves; shoes: shoes, boots,
   sandals, clogs, sabatons), tinted with its colour; `tests/unit/appearance_test.gd` checks
   the cut exists.
3. Make something drop it: a **DropEntry** on a monster's `drops` (item, chance from 0 to 1,
   amount range). Rare gear is usually 1 to 4%.

A **new kind of consumable** (something no `UseDef` field does yet) is a new field on
`UseDef` plus one small step in `ServerItems.on_use_item` (`scripts/server/services/items.gd`),
next to the ones for pet food, teleporting and restoring HP/MP.

Dawnshards go straight to the wallet when walked over; everything else waits on the ground
for the loot key, and stays there if its tab is full.

## How to add a weapon

- **A new weapon item** of an existing kind is just an item (above) with its `weapon_kind` and
  its icon on an `items_*` sheet: `python3 tools/art/paperdoll_layers.py` turns the icon into
  the picture he holds (`weapon_item_<id>`, a piece placed in his fist each frame), so it looks
  the same in his hand as in the bag. `held_size` grows or shrinks it against its kind.
- **A new shield or hat** works the same way: a shield needs its back drawn on
  `art/sheets/shield_backs.json` (its face is its icon), a hat its side and behind views on a
  `hats_items_*` sheet with its heads-erased `_only` twin (Gemini edits of `paperdoll_hats`).
  Without them it is drawn with its shape's tinted art.
- **A new top, bottom, pair of shoes or cape**: add a Gemini edit of the body sheet with
  the icon as reference (see the `wg_worn_*` entries in `tools/art/gemini_pass.json`), save the
  result as `art/source/worn/<item id>.png` and run the tool (`worn_item_<id>`). Until then it
  wears its `worn_style` cut in its colour. **New gloves** get a cuffless mitten painted from
  their icon on `art/sheets/glove_mittens.json` (one piece per hand, `glove_item_<id>_1/_2`).
- **A new weapon kind**: draw its greyscale template on the paperdoll weapons sheet (add its
  cell to `paperdoll_weapons.json` and `WEAPON_KINDS` in `tools/art/paperdoll/common.py`), say how it's
  held in `art/sheets/paperdoll_rig.json` "holds" ("like" another kind, or an angle per frame,
  "behind" for frames it goes behind him; add it to `AXIAL` if a long weapon drawn slanted
  should be straightened, `GRIPPED` if the fingers wrap it, `ON_BACK` if it's carried on the back), give it
  a row in `WeaponStyle.MOTIONS`, then run the tool and check `art/build/paperdoll_preview.png`
  (one row of frames per kind).
- **A new motion**: add the animation to the hero set in `art/sheets/paperdoll_body.json`
  (frames, fps, per-frame `durations`), point the kinds that use it at it in
  `WeaponStyle.MOTIONS`, list it in `WeaponStyle.ACTIONS`, and give it a `SpriteRig.FALLBACK`
  for sprites that don't have it.
