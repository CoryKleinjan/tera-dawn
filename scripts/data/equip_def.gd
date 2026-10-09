class_name EquipDef
extends ItemDef
## A piece of gear: where it's worn, what it takes to wear it and the stats it gives.
## Each one that drops rolls its own stats around `stats` (see `variance`).

## Kinds of gear. A slot kind can have several places on the body (two rings).
enum Slot { WEAPON, HAT, TOP, BOTTOM, SHOES, GLOVES, CAPE, EARRINGS, PENDANT, RING, SHIELD }
const SLOT_NAMES := ["Weapon", "Hat", "Top", "Bottom", "Shoes", "Gloves", "Cape", "Earrings", "Pendant", "Ring", "Shield"]

@export var slot: Slot = Slot.WEAPON

@export_group("Weapon")
## "sword", "bow", "wand", "claw", "knuckle", "gun"... Skills can require one.
@export var weapon_kind: StringName
## The ammo kind it fires (AmmoDef.kind), empty for melee weapons.
@export var ammo: StringName
## Replaces the plain attack while wielded (a bow's shot). Null keeps the basic attack.
@export var basic_attack: SkillDef

@export_group("Requirements")
## Job lines that can wear it (JobDef.family); empty for anyone.
@export var jobs: Array[StringName] = []
@export var required_level := 0
@export var required_strength := 0
@export var required_dexterity := 0
@export var required_intelligence := 0
@export var required_luck := 0

@export_group("Stats")
@export var stats: StatBlock
## Each nonzero stat on a dropped copy moves up or down by up to this much.
@export var variance := 1
## Upgrade slots for scrolls (not used yet).
@export var upgrade_slots := 7

func tab() -> Tab:
	return Tab.EQUIP

func stack_size() -> int:
	return 1

## "Warriors and Pirates" for a list of job lines.
static func families_text(families: Array[StringName]) -> String:
	var names := []
	for f in families:
		names.append(String(f).capitalize() + "s")
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]

func slot_name() -> String:
	return SLOT_NAMES[slot]

## What it takes to wear this, as {stat: amount}, with "level" for the level.
func requirements() -> Dictionary:
	var out := {}
	if required_level > 0:
		out[&"level"] = required_level
	for pair in [[&"strength", required_strength], [&"dexterity", required_dexterity],
			[&"intelligence", required_intelligence], [&"luck", required_luck]]:
		if pair[1] > 0:
			out[pair[0]] = pair[1]
	return out
