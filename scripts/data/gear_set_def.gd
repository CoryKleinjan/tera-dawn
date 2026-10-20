class_name GearSetDef
extends Resource
## A job's set (data/gear_sets/): one Armor piece and one weapon, painted onto the hero
## together (HeroOutfitDef), and the set's own effect while both are worn (Gear.full_set).
## Each job has its own sets, and each set its own effect.

@export var id: StringName
@export var display_name := ""
@export var armor: EquipDef
@export var weapon: EquipDef

@export_group("Effect")
## A buff each kill starts while both pieces are worn, one level (stack) higher each time up
## to its max_level, its time starting again with every kill (the Vanguard's Battle Fury).
## It ends when a piece comes off. Never learned: it has no job.
@export var kill_buff: SkillDef

## Whether `e` is one of its two pieces.
func has_piece(e: EquipDef) -> bool:
	return e != null and (e == armor or e == weapon)

## The set whose effect `skill` is (its kill_buff), or null: a set's buff is in no skill book.
static func with_buff(skill: SkillDef) -> GearSetDef:
	for s: GearSetDef in Content.gear_sets.values():
		if s.kill_buff == skill:
			return s
	return null

## The set `e` belongs to, or null.
static func of(e: EquipDef) -> GearSetDef:
	for s: GearSetDef in Content.gear_sets.values():
		if s.has_piece(e):
			return s
	return null
