# Skills

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a skill

1. Create `data/skills/<id>.tres` as a **SkillDef**: its `kind` (attack, buff or passive),
   the `job` whose skill book it's in, `max_level` and an optional `requires` skill. Costs and
   numbers that grow with the skill's level have a `_per_level` partner (`mp_cost_per_level`,
   `damage_per_level`, `stats_per_level`, `duration_per_level`, `regen_hp_per_level`).
   - Attacks: cooldown, how long the player is busy (`action_ticks`), the hit area (`reach`,
     `height`), `max_targets`, `hits` and the damage multiplier.
   - Buffs: `stats` added while it lasts, and `duration` in seconds. Also: `party` (it reaches
     party members within `SkillDef.PARTY_REACH`, at the caster's level), `heal` (a share of
     Max HP; a heal with no duration adds no buff), `mp_guard` (a share of damage taken comes
     out of MP), `steady` (no knockback), `hide` (monsters can't see or touch you; attacking
     ends it), and HP/MP recovery.
   - Passives: `stats` always added, and/or extra HP/MP recovery. Attack Speed, Melee Damage
     and Ranged Damage are stats too.
   - Any skill can have its own `recharge` in seconds on top of the shared cooldown (tracked
     per skill in `SimPlayer.recharge` and `TDPlayer`).
   - Attacks can also `slow` what they hit, `splash` (hit the nearest monster in the area and
     everything within `splash` of it), push harder (`knockback`), or not aim (`aims`).
   - The hero animation to play and the effects to show (`effect` on the player,
     `hit_effect` on each target).
2. Effects are **EffectDef**s in `data/effects/`: a flipbook of frames from
   `assets/sprites/effects/`, its speed and size, an optional light and particle burst.
   Effects the game fires on its own rather than through a skill or item (celebrate, monster
   poof, level up, critical) are named as constants on `EffectDef`; code uses those, never
   the id as a string.
3. Give it an icon: a painted badge on a skill icon sheet (a Gemini edit in `tools/art/gemini_pass.json`,
   matching `skill_icons_test`), cut by an `art/sheets/skill_icons_<sheet>.json` manifest into
   `assets/sprites/skills/<skill id>.png`.

It then appears in its job's tab of the skill window (K). Players spend Skill Points on it
(`SkillBook.learn`, checked by `ServerJobs.on_learn_skill`), and a newly learned attack or
buff goes on the first free quickslot. A job taken late still pays the Skill Points of every
level since it opened (`Character.advance`), and unspent points never go above the levels
left on the job line's skills (`SkillBook.room`), so a new skill raises that limit by itself.
Saves settle up when the server loads them (`SkillBook.settle`, from
`CharacterStore.load_file`). Quickslots (`Character.quickslots`, eight keys in
`Game.QUICKSLOT_ACTIONS`) hold skills or items and are saved with the character. The
server checks the skill is known and pays its MP (`TDServer.on_skill`), then works out what
it hits (`MapInstance.use_skill`) or starts the buff (`SkillBook.add_buff`, counted down
in `SimPlayer.step`). Passives and buffs feed into the character's stats in `recalc`.

Ranged and magic skills:
- A `projectile` (a **ProjectileDef** in `data/projectiles/`: texture, speed, spin, light) makes
  the skill a shot. The server still decides the hit at once; clients fly one projectile per
  hit (`TDProjectile`) and pop the damage number when it lands, holding the monster's death
  until then.
- A weapon (`EquipDef`) names its `weapon_kind` (sword, dagger, bow, wand, staff, knuckle, star, gun)
  and an optional `basic_attack` skill that replaces the plain swing (a bow's Shoot). Ranged
  weapons need no ammo.
- `weapons` limits a skill to weapon kinds and `offhand` to what's worn in the off-hand slot
  (a Thief's stars, a Pirate's pistol); `magic` uses Magic Attack (INT included) through
  `CharacterStats.magic_range` instead of the weapon.

Movement skills (`kind` Movement) carry a **MoveDef** (`move`): its style (Charge, air jump,
Blink, backstep, roll), distance, ticks, whether it works on the ground and once per jump in
the air, whether nothing can hit you meanwhile, how many monsters it shoves aside and its trail
colour. The hero moves on his own machine (`TDPlayer._start_move`); the server pays the MP,
puts a Blink where it lands (`MoveDef.blink_to`, the same sum on both sides), shoves monsters
and keeps a roller from being hit (`ServerMoves`, `SimPlayer.dodge_t`). Everyone sees the
code-drawn trail or Blink bolt (`TDMoveFx`) until painted effects replace it.

Aiming and melee weight:
- Attacks with `aims` on (the default) turn with the held direction: Up aims up, Down in the
  air aims down (`Hitbox.Aim`, chosen in `TDPlayer._held_aim`, kept to real aims by
  `SkillDef.aim_for`). The aim travels in `req_skill` and `ev_skill`; the server checks
  `Hitbox.aimed_area` and every client turns the swing effect (`TDEffect`) and any shot that way.
- A skill without a projectile is melee (`SkillDef.is_ranged`): it knocks monsters back
  `MapInstance.MELEE_KNOCKBACK` times harder, holds a longer hit-stop and kicks the camera
  (`TDWorldFx`), and pushes you back (`TDPlayer.recoil`). A downward melee blow that meets a
  monster on your screen bounces you at once (`TDPlayer.POGO_SPEED`); the server still decides
  the damage.

Damage is worked out in `scripts/world/combat.gd`, so balance changes stay in one place.
