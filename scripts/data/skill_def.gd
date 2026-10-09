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
## Ticks the player is rooted in the attack pose.
@export var action_ticks := 16

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
## Spends one of the weapon's ammo per hit.
@export var uses_ammo := false
## Weapon kinds it needs (EquipDef.weapon_kind); empty for any.
@export var weapons: Array[StringName] = []

@export_group("Buffs and passives")
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
## Player animation to play (see assets/animations/hero.tres).
@export var animation := &"attack"
## Played in front of the player, flipped with their facing.
@export var effect: EffectDef
## Played on each monster hit.
@export var hit_effect: EffectDef

func mp_at(level: int) -> int:
	return mp_cost + roundi(mp_cost_per_level * maxi(0, level - 1))

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
	var s := stats_at(level)
	for f in s.nonzero():
		out.append("%s %s" % [StatBlock.LABELS[f], StatBlock.format(f, s.value(f))])
	if regen_hp_at(level) > 0:
		out.append("HP recovery +%d" % regen_hp_at(level))
	if regen_mp_at(level) > 0:
		out.append("MP recovery +%d" % regen_mp_at(level))
	if kind == Kind.BUFF:
		out.append("Lasts %d seconds" % roundi(duration_ticks(level) / 60.0))
	return out
