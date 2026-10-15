class_name EquipDef
extends ItemDef
## A piece of gear: where it's worn, what it takes to wear it and the stats it gives.
## Each one that drops rolls its own stats around `stats` (see `variance`).

## Kinds of gear. A slot kind can have several places on the body (two rings).
enum Slot { WEAPON, HAT, TOP, BOTTOM, SHOES, GLOVES, CAPE, EARRINGS, PENDANT, RING, SHIELD }
const SLOT_NAMES := ["Weapon", "Hat", "Top", "Bottom", "Shoes", "Gloves", "Cape", "Earrings", "Pendant", "Ring", "Off-hand"]

@export var slot: Slot = Slot.WEAPON
## What each off-hand kind is called in messages ("Learn Star Scatter: needs throwing stars").
const OFFHAND_NAMES := {&"shield": "a shield", &"star": "throwing stars", &"book": "a book",
	&"quiver": "a quiver", &"pistol": "a pistol"}

@export_group("Weapon")
## "sword", "dagger", "bow", "wand", "staff", "knuckle"... Skills can require one.
@export var weapon_kind: StringName
## Replaces the plain attack while wielded (a bow's shot). Null keeps the basic attack.
@export var basic_attack: SkillDef

@export_group("Off-hand slot")
## What a piece worn in the off-hand slot is: "shield", or a job's off-hand ("star" for a
## Thief's throwing stars, "book" for a Magician, "quiver" for an Archer, "pistol" for a
## Pirate). Skills can need one (SkillDef.offhand). Off-hands are gear, never used up.
@export var offhand_kind: StringName = &"shield"

@export_group("Worn look")
## Its painted layer on the hero (art/sheets/hero_<id>.json), frames named as in HeroLookDef.
## Frames it has no painting for show the hero without it. Null shows nothing.
@export var worn: SpriteFrames
## A hat or helmet that covers his hair, so the hair layer isn't drawn under it.
@export var hides_hair := false
## An off-hand held in front of his rear arm, under his top (a book), rather than slung behind
## him (a shield).
@export var worn_in_front := false
## A top whose long sleeves reach his wrists (a robe), so the fists painted with bare forearms
## (HeroLookDef.bare_arm_frames) aren't drawn over them.
@export var long_sleeves := false

@export_group("Requirements")
## Job lines that can wear it (JobDef.family); empty for anyone.
@export var jobs: Array[StringName] = []
@export var required_level := 0
@export var required_strength := 0
@export var required_dexterity := 0
@export var required_intelligence := 0
@export var required_luck := 0
@export var required_charisma := 0

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

## How an off-hand kind reads in a sentence: "throwing stars", "a pistol".
static func offhand_name(kind: StringName) -> String:
	return OFFHAND_NAMES.get(kind, "a " + String(kind))

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
			[&"intelligence", required_intelligence], [&"luck", required_luck], [&"charisma", required_charisma]]:
		if pair[1] > 0:
			out[pair[0]] = pair[1]
	return out
