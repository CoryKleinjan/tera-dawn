class_name EquipDef
extends ItemDef
## A piece of gear: where it's worn, what it takes to wear it and the stats it gives.
## Each one that drops rolls its own stats around `stats` (see `variance`).

## Kinds of gear. A slot kind can have several places on the body (two rings).
enum Slot { WEAPON, HAT, TOP, BOTTOM, SHOES, GLOVES, CAPE, EARRINGS, PENDANT, RING, SHIELD }
const SLOT_NAMES := ["Weapon", "Hat", "Top", "Bottom", "Shoes", "Gloves", "Cape", "Earrings", "Pendant", "Ring", "Shield"]
## Slots whose pieces can have a worn_style cut, and the name its layers start with.
const WORN_STYLE_PLACES := {Slot.TOP: "top", Slot.BOTTOM: "bottom", Slot.SHOES: "shoes"}

@export var slot: Slot = Slot.WEAPON

@export_group("Weapon")
## "sword", "bow", "wand", "star", "knuckle", "gun"... Skills can require one.
@export var weapon_kind: StringName
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

@export_group("Look")
## Layered art of this piece worn, frame for frame like the hero's SpriteFrames. Until it
## exists, the piece is shown on the hero with stand-ins (see Paperdoll).
@export var worn_frames: SpriteFrames
## For a top, bottom or shoes without worn_frames: the cut it's worn as, greyscale art tinted
## with its look colour: res://assets/animations/paperdoll/<place>_<style>.tres (worn_style_path),
## e.g. "tunic", "coat", "robe", "vest"; "trousers", "breeches"; "shoes", "boots", "sandals",
## "clogs". Empty: it only recolours the part of the body it covers.
@export var worn_style: StringName
## The shape of a hat or shield's art. Hats: "cap", "helm", "hood", "bandana", "wizard",
## "tricorn" (Paperdoll.hat_piece; empty: a cap). Shields: "kite", or empty for a round one
## (Paperdoll.SHIELDS).
@export var look_shape: StringName
## The colour it's shown in. Fully transparent takes the main colour of its icon.
@export var look_color := Color(0, 0, 0, 0)
## For a weapon with its own held picture (Paperdoll.weapon_piece): how big it's drawn in his
## hand against others of its kind (a claymore 1.3). Read by tools/art/paperdoll_layers.py, so
## run it after changing this.
@export var held_size := 1.0

## Icon colours worked out so far: item id -> Color.
static var _icon_colors := {}

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

## Where its worn_style layer is (empty without one): top_tunic.tres for a top in "tunic".
func worn_style_path() -> String:
	var place: String = WORN_STYLE_PLACES.get(slot, "")
	if worn_style == &"" or place == "":
		return ""
	return "res://assets/animations/paperdoll/%s_%s.tres" % [place, worn_style]

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
