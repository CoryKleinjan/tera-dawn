class_name StatBlock
extends Resource
## A bundle of MapleStory-style stats: the four base stats plus everything gear can add.
## Used for a character's base stats, an equip's bonuses and the rolled stats of one item.

## Every stat, in the order windows and tooltips list them.
const FIELDS: Array[StringName] = [
	&"strength", &"dexterity", &"intelligence", &"luck", &"max_hp", &"max_mp",
	&"attack", &"magic_attack", &"defense", &"magic_defense", &"accuracy", &"avoid",
	&"speed", &"jump",
]
## Short names for tooltips and the stats window.
const LABELS := {
	&"strength": "STR", &"dexterity": "DEX", &"intelligence": "INT", &"luck": "LUK",
	&"max_hp": "MaxHP", &"max_mp": "MaxMP", &"attack": "Weapon Attack",
	&"magic_attack": "Magic Attack", &"defense": "Weapon Defense",
	&"magic_defense": "Magic Defense", &"accuracy": "Accuracy", &"avoid": "Avoidability",
	&"speed": "Speed", &"jump": "Jump",
}
## The four stats Ability Points go into.
const BASE: Array[StringName] = [&"strength", &"dexterity", &"intelligence", &"luck"]

@export var strength := 0
@export var dexterity := 0
@export var intelligence := 0
@export var luck := 0
@export var max_hp := 0
@export var max_mp := 0
## Weapon attack: the main multiplier on physical damage.
@export var attack := 0
@export var magic_attack := 0
## Weapon defense: lowers damage taken from monster touches.
@export var defense := 0
@export var magic_defense := 0
@export var accuracy := 0
@export var avoid := 0
## Movement speed bonus in percent.
@export var speed := 0
## Jump height bonus in percent.
@export var jump := 0

## A bonus as players read it: "+3", "-2", "+5%" for Speed and Jump.
static func format(stat: StringName, amount: int) -> String:
	return "%+d%s" % [amount, "%" if stat in [&"speed", &"jump"] else ""]

func value(stat: StringName) -> int:
	return int(get(stat))

## Adds `other` into this block.
func add(other: StatBlock) -> void:
	if other == null:
		return
	for f in FIELDS:
		set(f, value(f) + other.value(f))

func plus(other: StatBlock) -> StatBlock:
	var out := copy()
	out.add(other)
	return out

func copy() -> StatBlock:
	var out := StatBlock.new()
	for f in FIELDS:
		out.set(f, value(f))
	return out

## The stats that aren't zero, in display order.
func nonzero() -> Array[StringName]:
	var out: Array[StringName] = []
	for f in FIELDS:
		if value(f) != 0:
			out.append(f)
	return out

## A copy where each nonzero stat moves up or down by up to `spread` (never below 0),
## like MapleStory's random equip stats.
func rolled(spread: int) -> StatBlock:
	var out := copy()
	if spread <= 0:
		return out
	for f in nonzero():
		out.set(f, maxi(0, value(f) + randi_range(-spread, spread)))
	return out

## Only the nonzero stats, for the save file.
func to_dict() -> Dictionary:
	var d := {}
	for f in nonzero():
		d[String(f)] = value(f)
	return d

static func from_dict(d: Dictionary) -> StatBlock:
	var out := StatBlock.new()
	for f in FIELDS:
		out.set(f, int(d.get(String(f), 0)))
	return out
