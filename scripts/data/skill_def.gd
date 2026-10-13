class_name SkillDef
extends Resource
## A skill: an attack, a buff the player casts on themselves, or a passive that is always on.
## The basic attack is a skill too (`innate`, known by everyone without Skill Points).
##
## Skills belong to a job (`job`) and are learned with Skill Points in the skill window (K),
## up to `max_level`. Numbers that grow with the skill's level have a `_per_level` partner,
## added once for every level above 1 (see the `*_at` functions).
##
## Add a skill by saving a SkillDef in data/skills/: it shows up in its job's tab of the
## skill window, and players put it on a quickslot to use it.

enum Kind { ATTACK, BUFF, PASSIVE }
const KIND_NAMES := ["Attack", "Buff", "Passive"]
## The flash of a skill that goes off as a spell without a colour of its own (an attack with
## a wand's or staff's spell motion, like Dawn Slash in a Magician's hands): soft dawn gold.
const DEFAULT_FLASH := Color(1.0, 0.9, 0.65)
## How far a party buff reaches from the caster, in game pixels (about a screen).
const PARTY_REACH := 640.0

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var kind := Kind.ATTACK

@export_group("Learning")
## The job whose skill book it's in (empty for innate skills).
@export var job: StringName
## Everyone knows it at level 1 from the start; it takes no Skill Points.
@export var innate := false
@export var max_level := 20
## Another skill that must reach `requires_level` before this one can be learned.
@export var requires: StringName
@export var requires_level := 1

@export_group("Cost")
@export var mp_cost := 0
@export var mp_cost_per_level := 0.0
## Ticks before any attack can be used again.
@export var cooldown := 24
## Ticks the player spends in the attack pose (he can still move meanwhile).
@export var action_ticks := 16
## Seconds before this skill can be used again, on top of the shared cooldown (0: none).
## Attack Speed doesn't shorten it.
@export var recharge := 0.0
@export var recharge_per_level := 0.0

@export_group("Attack")
## How far in front of the player it reaches, and how tall the hit area is.
@export var reach := 78.0
@export var height := 100.0
@export var max_targets := 1
## Damage lines per target (each rolls its own damage and critical).
@export var hits := 1
@export var damage_multiplier := 1.0
@export var damage_per_level := 0.0
## Uses Magic Attack and INT instead of the weapon (spells).
@export var magic := false
## Shown flying to each target. Null for melee.
@export var projectile: ProjectileDef
## Weapon kinds it needs (EquipDef.weapon_kind); empty for any.
@export var weapons: Array[StringName] = []
## What it needs in the off-hand slot (EquipDef.offhand_kind: "star", "book", "quiver",
## "pistol"); empty for anything or nothing.
@export var offhand: Array[StringName] = []
## How hard it knocks monsters back, against a normal hit.
@export var knockback := 1.0
## Above 0, the blast lands on the nearest monster in reach and also hits every monster within
## this many pixels of it (up to max_targets).
@export var splash := 0.0
## Seconds each monster it hits is slowed (SimMob.SLOW).
@export var slow := 0.0
@export var slow_per_level := 0.0
## Holding up aims it upward, and down (in the air) aims it downward (Hitbox.Aim). Off for an
## attack that only ever works ahead of the player.
@export var aims := true

@export_group("Buffs and passives")
## A buff that also reaches every party member on the map within PARTY_REACH.
@export var party := false
## Heals this share of Max HP as it goes off (a buff with no duration is just the heal).
@export var heal := 0.0
@export var heal_per_level := 0.0
## While the buff lasts, this share of the damage taken comes out of MP instead of HP.
@export var mp_guard := 0.0
@export var mp_guard_per_level := 0.0
## While the buff lasts, monster hits don't knock the player back.
@export var steady := false
## While the buff lasts, monsters can't see or hit the player; attacking ends it.
@export var hide := false
## What it adds to the character's stats while a buff lasts, or always for a passive.
@export var stats: StatBlock
@export var stats_per_level: StatBlock
## How long a buff lasts, in seconds.
@export var duration := 0.0
@export var duration_per_level := 0.0
## Extra HP and MP restored every few seconds (passives).
@export var regen_hp := 0
@export var regen_hp_per_level := 0
@export var regen_mp := 0
@export var regen_mp_per_level := 0

@export_group("Look")
## The motion the player makes: "attack" (the weapon's own basic blow) or "slash" (its big
## one) are worked out from the weapon worn (WeaponStyle); any other name is a hero animation
## played as it is (assets/animations/hero.tres). "cast" (buffs, and a wand's or staff's
## spells) makes no motion at all: the player flashes `flash` instead (WeaponStyle.SPELL).
@export var animation := &"attack"
## The colour the player flashes when a buff or spell goes off, each skill its own.
## Transparent: DEFAULT_FLASH (see flash_color).
@export var flash := Color(0, 0, 0, 0)
## Played in front of the player, flipped with their facing.
@export var effect: EffectDef
## Played on each monster hit.
@export var hit_effect: EffectDef
## Played as it goes off (Sound.play id). Empty: its projectile's sound, or a swing for an
## attack and a cast for a spell (see cast_sound).
@export var sound: StringName

func mp_at(level: int) -> int:
	return mp_cost + roundi(mp_cost_per_level * maxi(0, level - 1))

## Recharge length in physics ticks (60 a second).
func recharge_ticks(level: int) -> int:
	return roundi(maxf(0.0, recharge + recharge_per_level * maxi(0, level - 1)) * 60.0)

func slow_ticks(level: int) -> int:
	return roundi(maxf(0.0, slow + slow_per_level * maxi(0, level - 1)) * 60.0)

func heal_at(level: int) -> float:
	return heal + heal_per_level * maxi(0, level - 1) if level > 0 else 0.0

func mp_guard_at(level: int) -> float:
	return clampf(mp_guard + mp_guard_per_level * maxi(0, level - 1), 0.0, 1.0) if level > 0 else 0.0

func damage_at(level: int) -> float:
	return damage_multiplier + damage_per_level * maxi(0, level - 1)

## Buff length in physics ticks (60 a second).
func duration_ticks(level: int) -> int:
	return roundi((duration + duration_per_level * maxi(0, level - 1)) * 60.0)

func stats_at(level: int) -> StatBlock:
	var out := stats.copy() if stats else StatBlock.new()
	if stats_per_level:
		for f in stats_per_level.nonzero():
			out.set(f, out.value(f) + stats_per_level.value(f) * maxi(0, level - 1))
	return out

func regen_hp_at(level: int) -> int:
	return regen_hp + regen_hp_per_level * maxi(0, level - 1) if level > 0 else 0

func regen_mp_at(level: int) -> int:
	return regen_mp + regen_mp_per_level * maxi(0, level - 1) if level > 0 else 0

## Shot from a distance (it has a projectile), rather than a melee blow. Melee blows hit
## harder on screen: longer hit-stop, recoil and knockback (see TDWorldFx, MapInstance).
func is_ranged() -> bool:
	return projectile != null

## The aim it actually takes when used aimed `aim`: only aiming attacks turn.
func aim_for(aim: Hitbox.Aim) -> Hitbox.Aim:
	return aim if kind == Kind.ATTACK and aims else Hitbox.Aim.AHEAD

## A player can press it (attacks and buffs; passives are always on).
func is_active() -> bool:
	return kind != Kind.PASSIVE

## What it does at `level`, one line each, for the skill window ("Damage: 160%").
func describe_level(level: int) -> PackedStringArray:
	var out := PackedStringArray()
	if level <= 0:
		return out
	if is_active() and mp_at(level) > 0:
		out.append("MP cost: %d" % mp_at(level))
	if kind == Kind.ATTACK:
		var line := "%s: %d%%" % ["Magic" if magic else "Damage", roundi(damage_at(level) * 100)]
		if hits > 1:
			line += " x%d hits" % hits
		if max_targets > 1:
			line += ", up to %d monsters" % max_targets
		out.append(line)
		if slow_ticks(level) > 0:
			out.append("Slows them for %s seconds" % _seconds(slow_ticks(level)))
	if heal_at(level) > 0.0:
		out.append("Heals %d%% of Max HP" % roundi(heal_at(level) * 100))
	var s := stats_at(level)
	for f in s.nonzero():
		out.append("%s %s" % [StatBlock.LABELS[f], StatBlock.format(f, s.value(f))])
	if regen_hp_at(level) > 0:
		out.append("HP recovery +%d" % regen_hp_at(level))
	if regen_mp_at(level) > 0:
		out.append("MP recovery +%d" % regen_mp_at(level))
	if mp_guard_at(level) > 0.0:
		out.append("%d%% of damage taken comes out of MP" % roundi(mp_guard_at(level) * 100))
	if steady:
		out.append("No knockback")
	if hide:
		out.append("Monsters can't see you; attacking ends it")
	if kind == Kind.BUFF and duration_ticks(level) > 0:
		out.append("Lasts %d seconds" % roundi(duration_ticks(level) / 60.0))
	if party:
		out.append("Also reaches party members nearby")
	if recharge_ticks(level) > 0:
		out.append("Recharges in %s seconds" % _seconds(recharge_ticks(level)))
	return out

## "1.5" or "20" seconds from ticks.
static func _seconds(ticks: int) -> String:
	var sec := ticks / 60.0
	return str(roundi(sec)) if is_equal_approx(sec, roundf(sec)) else "%.1f" % sec

## The colour the player flashes when this goes off as a buff or spell.
func flash_color() -> Color:
	return flash if flash.a > 0.0 else DEFAULT_FLASH

## The sounds an attack makes when it has none of its own.
const SWING_SOUND := &"swing"
const CAST_SOUND := &"cast"

## The sound it makes as it goes off: its own, its projectile's, or a swing (a cast for
## magic); buffs and passives sound only through their effect.
func cast_sound() -> StringName:
	if sound != &"":
		return sound
	if projectile and projectile.sound != &"":
		return projectile.sound
	if kind != Kind.ATTACK:
		return &""
	return CAST_SOUND if magic else SWING_SOUND
