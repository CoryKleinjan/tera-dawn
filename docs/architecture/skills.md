# Skills

Part of the [architecture docs](../../ARCHITECTURE.md).

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
(`SkillBook.learn`, checked by `ServerJobs.on_learn_skill`), and a newly learned attack or
buff goes on the first free quickslot. Quickslots (`Character.quickslots`, eight keys in
`Game.QUICKSLOT_ACTIONS`) hold skills or items and are saved with the character. The
server checks the skill is known and pays its MP (`TDServer.on_skill`), then works out what
it hits (`MapInstance.use_skill`) or starts the buff (`SkillBook.add_buff`, counted down
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
