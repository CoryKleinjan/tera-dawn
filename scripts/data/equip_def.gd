class_name EquipDef
extends ItemDef
## A piece of gear: where it's worn, what it takes to wear it and the stats it gives.
## Each one that drops rolls its own stats around `stats` (see `variance`).

## Kinds of gear. A slot kind can have several places on the body (two rings).
enum Slot { WEAPON, HAT, TOP, BOTTOM, SHOES, GLOVES, CAPE, EARRINGS, PENDANT, RING, SHIELD }
const SLOT_NAMES := ["Weapon", "Hat", "Top", "Bottom", "Shoes", "Gloves", "Cape", "Earrings", "Pendant", "Ring", "Shield"]

@export var slot: Slot = Slot.WEAPON

@export_group("Requirements")
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
