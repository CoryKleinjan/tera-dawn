# Skills

Part of the [architecture docs](../../ARCHITECTURE.md).

Job skills, the skill window and buying skill levels are gone (Cory Oct 19). The skills left
are the weapons' own attacks: the plain swing (`Character.BASIC_ATTACK`) and a weapon's
`basic_attack` (a bow's shot). The machinery below stays for the found spells to come.

## How to add a skill

1. Create `data/skills/<id>.tres` as a **SkillDef**: its `kind` (attack, buff or passive)
   and an optional `requires` skill.
   - Attacks: cooldown, how long the player is busy (`action_ticks`), the hit area (`reach`,
     `height`), `max_targets`, `hits` and the damage multiplier.
   - Buffs: `stats` added while it lasts, and `duration` in seconds. Also: `party` (it reaches
     party members within `SkillDef.PARTY_REACH`), `heal` (a share of
     Max HP; a heal with no duration adds no buff), `mp_guard` (a share of damage taken comes
     out of MP), `steady` (no knockback), `hide` (monsters can't see or touch you; attacking
     ends it), and HP/MP recovery.
   - Passives: `stats` always added, and/or extra HP/MP recovery. Attack Speed, Melee Damage
     and Ranged Damage are stats too.
   - Any skill can have its own `recharge` in seconds on top of the shared cooldown (tracked
     per skill in `SimPlayer.recharge` and `TDPlayer`).
   - Attacks can also `slow` what they hit, `splash` (hit the nearest monster in the area and
     everything within `splash` of it), push harder (`knockback`), or not aim (`aims`).
   - The motion the player makes (`animation`; "cast" makes none) and the effects to show
     (`effect` on the player, `hit_effect` on each target, and for a buff its `aura`).
2. Effects are **EffectDef**s in `data/effects/`: a flipbook of frames from
   `assets/sprites/effects/`, its speed and size, an optional light and particle burst.
   Painted 8-frame effects (`art/sheets/skillfx_<name>.json`, cut with `"glow": true` into
   `assets/sprites/effects/skills/`, played at 14 fps; the boss moves' are the ones left) fade
   themselves out, so their defs set `fade_out` false. A buff's aura loops round each player it
   landed on for as long as the buff lasts (`Net.ev_aura`, `TDWorldFx.add_aura`; casting again
   replaces it). A painting whose light runs off its frame's edge (the Slam
   impact) sets `edge_fade`: the game fades each frame's edges in as it plays (`TDEffect.faded`)
   and the picture itself stays as painted.
   Effects the game fires on its own rather than through a skill or item (celebrate, monster
   poof, critical) are named as constants on `EffectDef`; code uses those, never
   the id as a string.
3. Give it an icon: a painted badge on a skill icon sheet (a Gemini edit in `tools/art/gemini_pass.json`,
   matching `skill_icons_test`), cut by an `art/sheets/skill_icons_<sheet>.json` manifest into
   `assets/sprites/skills/<skill id>.png`.

A skill is known when it's `innate` or listed in `SkillBook.learned`. Quickslots (`Character.quickslots`, eight keys in
`Game.QUICKSLOT_ACTIONS`) hold skills or items and are saved with the character. The
server checks the skill is known and pays its MP (`TDServer.on_skill`), then works out what
it hits (`MapInstance.use_skill`) or starts the buff (`SkillBook.add_buff`, counted down
in `SimPlayer.step`). Passives and buffs feed into the character's stats in `recalc`.

Ranged and magic skills:
- A `projectile` (a **ProjectileDef** in `data/projectiles/`: texture, or painted `frames` it
  loops in flight, speed, spin, light) makes
  the skill a shot. The server still decides the hit at once; clients fly one projectile per
  hit (`TDProjectile`) and show the hit when it lands, holding the monster's death
  until then.
- A weapon (`EquipDef`) names its `weapon_kind` (sword, dagger, bow, wand, staff, knuckle, star, gun)
  and an optional `basic_attack` skill that replaces the plain swing (a bow's Shoot). Ranged
  weapons need no ammo.
- `weapons` limits a skill to weapon kinds and `offhand` to what's worn in the off-hand slot
  (a Thief's stars, a Pirate's pistol). Damage always comes from the weapon
  (`CharacterStats.damage_range`).

Jobs have no movement skills: the hero's moves come from boss relics (`RelicDef`, see
`characters.md`).

Aiming and melee weight:
- Attacks with `aims` on (the default) turn with the held direction: Up aims up, Down in the
  air aims down (`Hitbox.Aim`, chosen in `TDPlayer._held_aim`, kept to real aims by
  `SkillDef.aim_for`). The aim travels in `req_skill` and `ev_skill`; the server checks
  `Hitbox.aimed_area` and every client turns the swing effect (`TDEffect`) and any shot that way.
- A skill without a projectile is melee (`SkillDef.is_ranged`): it knocks monsters back
  `MapInstance.MELEE_KNOCKBACK` times harder, holds a longer hit-stop (on the monster and on you,
  `TDPlayer.hit_stop`) and kicks the camera (`TDWorldFx`), and pushes you back (`TDPlayer.recoil`). A downward melee blow that meets a
  monster on your screen bounces you at once (`TDPlayer.POGO_SPEED`); the server still decides
  the damage.

Area and hold rules (all in `MapInstance.use_skill`):
- `around` hits both sides of the player (a spin, a wall along the platform).
- `root` stops a monster moving (`SimMob.root`), shown to clients as a tint
  (`SnapshotFlags.MOB_ROOTED`).

Monster control (no skill uses it now; all in `MapInstance.use_skill` and `SimMob`):
- `launch` throws what it hits up (`SimMob.launch`, `tossed`); `slam` first yanks airborne
  monsters within reach down and grounds fliers (`SimMob.slam_down`, `downed_t`,
  `SnapshotFlags.MOB_DOWNED`), then hits only grounded ones; `stun` holds a monster out of
  action and in the air (`SimMob.stun`, `hang_t`, `SnapshotFlags.MOB_STUNNED`, stars drawn by
  `TDMob`); `pin` makes a root hold it in the air too; `pull` drags it in front of the player.
- `ambush` blinks the player into the biggest group ahead first (`SkillDef.ambush_spot`,
  worked out alike by `TDPlayer` and `MapInstance._ambush`; the server sends `ev_place`). Its
  `move` only gives the blink bolt its colour.
- A thrown or stunned monster (`SimMob.held`) can't move, attack or hurt by touch. Bosses
  (`SimMob.controllable`) take the damage but are never thrown, dragged or stunned.

Damage is worked out in `scripts/world/combat.gd`, so balance changes stay in one place.
