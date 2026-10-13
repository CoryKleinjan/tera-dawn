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

@export_group("Look")
## How it looks on the hero is its own art (Paperdoll: layers/worn_item_<id>.png, or a weapon
## or shield's piece), made by tools/art/hero_build.py. A hat's shape: which of the hat/hair
## templates it is painted on, "helm", "tricorn", "bandana", "hood" or "wizard"; the hair under
## it is that shape's.
@export var look_shape: StringName
## The colour it's shown in (a weapon's streak). Fully transparent takes the main colour of
## its icon.
@export var look_color := Color(0, 0, 0, 0)

## Icon colours worked out so far: item id -> Color.
static var _icon_colors := {}

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

## The colour it's shown in while worn: `look_color`, else its icon's main colour.
func worn_color() -> Color:
	if look_color.a > 0.0:
		return look_color
	if not _icon_colors.has(id):
		_icon_colors[id] = main_color(icon)
	return _icon_colors[id]

## The typical colour of a picture's mid-tones (not its outline or shine).
static func main_color(tex: Texture2D) -> Color:
	var img := tex.get_image() if tex else null
	if img == null:
		return Color(0.7, 0.7, 0.7)
	if img.is_compressed():
		img.decompress()
	var sum := Vector3.ZERO
	var weight := 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or c.v < 0.22 or c.v > 0.97:
				continue
			var w := 0.25 + c.s # colourful pixels say more about it than grey ones
			sum += Vector3(c.r, c.g, c.b) * w
			weight += w
	if weight == 0.0:
		return Color(0.7, 0.7, 0.7)
	sum /= weight
	return Color(sum.x, sum.y, sum.z)

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
