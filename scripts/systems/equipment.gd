class_name Equipment
extends RefCounted
## What the character is wearing: one ItemStack per place on the body.

signal changed

## Places on the body, in the order the equipment window lays them out.
const PLACES: Array[StringName] = [
	&"armor", &"weapon", &"earrings", &"pendant", &"ring_1", &"ring_2",
]
## Which places each kind of gear can go in.
const PLACES_FOR := {
	EquipDef.Slot.WEAPON: [&"weapon"],
	EquipDef.Slot.ARMOR: [&"armor"],
	EquipDef.Slot.EARRINGS: [&"earrings"],
	EquipDef.Slot.PENDANT: [&"pendant"],
	EquipDef.Slot.RING: [&"ring_1", &"ring_2"],
}
const PLACE_NAMES := {
	&"armor": "Armor", &"weapon": "Weapon", &"earrings": "Earrings", &"pendant": "Pendant",
	&"ring_1": "Ring", &"ring_2": "Ring",
}

## place -> ItemStack
var worn := {}

func clear() -> void:
	worn.clear()
	changed.emit()

func at(place: StringName) -> ItemStack:
	return worn.get(place)

## Where a piece of gear goes: the first free place of its kind, else the first place.
func place_for(e: EquipDef) -> StringName:
	var places: Array = PLACES_FOR[e.slot]
	for p in places:
		if not worn.has(p):
			return p
	return places[0]

static func fits(e: EquipDef, place: StringName) -> bool:
	return place in PLACES_FOR[e.slot]

## Wears a stack in a place and returns whatever was there (or null).
func put(place: StringName, stack: ItemStack) -> ItemStack:
	var old: ItemStack = worn.get(place)
	worn[place] = stack
	changed.emit()
	return old

func take(place: StringName) -> ItemStack:
	var old: ItemStack = worn.get(place)
	worn.erase(place)
	changed.emit()
	return old

## Everything the worn gear adds up to.
func bonus() -> StatBlock:
	var out := StatBlock.new()
	for s in worn.values():
		out.add(s.total())
	return out

## What's worn as place -> EquipDef.
func defs() -> Dictionary:
	var out := {}
	for p in worn:
		out[p] = worn[p].equip_def()
	return out

func to_dict() -> Dictionary:
	var out := {}
	for p in worn:
		out[String(p)] = worn[p].to_dict()
	return out

## Loads what to_dict() wrote. Gear in places that are gone (the old hat, top, bottom, shoes,
## gloves, cape and off-hand) or that the game no longer has is dropped.
func load_dict(data: Dictionary) -> void:
	worn.clear()
	for key in data:
		var place := StringName(key)
		var d: Variant = data[key]
		if not place in PLACES or not d is Dictionary:
			continue
		var s := ItemStack.from_dict(d)
		if s and s.item is EquipDef and fits(s.item, place):
			worn[place] = s
	changed.emit()
