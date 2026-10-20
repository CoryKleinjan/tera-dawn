class_name Gear
extends CharacterPart
## The rules for a character's gear (Character.gear): who can wear what, putting gear on
## and taking it off between the bag's Equip tab and what's worn (Character.equipment), and
## setting runes in gear and raising its tier at an enchanter.

## The weapon worn, or null.
func weapon() -> EquipDef:
	var w := character.equipment.at(&"weapon")
	return w.equip_def() if w else null

## The armor worn, or null.
func armor() -> EquipDef:
	var a := character.equipment.at(&"armor")
	return a.equip_def() if a else null

## The set whose armor and weapon are both worn, or null.
func full_set() -> GearSetDef:
	var s := GearSetDef.of(armor())
	return s if s and s.weapon == weapon() else null

## A kill while wearing a whole set: its kill buff (Battle Fury) goes up a level and starts
## its time again. True if it did.
func on_kill() -> bool:
	var s := full_set()
	if s == null or s.kill_buff == null:
		return false
	var skills := character.skills
	var running: Array = skills.buffs.get(s.kill_buff.id, [0, 0])
	skills.add_buff(s.kill_buff, mini(running[0] + 1, s.kill_buff.max_level))
	return true

## Ends the kill buffs of sets no longer worn whole (a piece came off).
func _end_broken_sets() -> void:
	var whole := full_set()
	for s: GearSetDef in Content.gear_sets.values():
		if s != whole and s.kill_buff and character.skills.buffs.erase(s.kill_buff.id):
			character.recalc()

## What shows on the hero: the ids of the armor and the weapon worn, empty for none
## (HeroLookDef.frames_for).
func shown() -> Array[StringName]:
	var a := armor()
	var w := weapon()
	return [a.id if a else &"", w.id if w else &""]

## Whether this job can use gear meant for `families` (empty means anyone). A blend wears
## both its parent jobs' gear (JobDef.wear_families).
func can_use(families: Array[StringName]) -> bool:
	if families.is_empty():
		return true
	for f in character.job.wear_families():
		if f in families:
			return true
	return false

## Why the character can't wear this, or "" if they can.
func equip_problem(e: EquipDef) -> String:
	if not can_use(e.jobs):
		return "Only %s can use the %s." % [EquipDef.families_text(e.jobs), e.display_name]
	return ""

## Wears the gear in Equip slot `i`, putting whatever it replaces back in that slot.
## Returns why it couldn't, or "".
func equip(i: int, place: StringName = &"") -> String:
	var c := character
	var stack := c.inventory.at(ItemDef.Tab.EQUIP, i)
	if stack == null:
		return ""
	var e := stack.equip_def()
	var problem := equip_problem(e)
	if problem != "":
		return problem
	if place == &"" or not Equipment.fits(e, place):
		place = c.equipment.place_for(e)
	c.inventory.take(ItemDef.Tab.EQUIP, i)
	var old := c.equipment.put(place, stack)
	if old:
		c.inventory.put(ItemDef.Tab.EQUIP, i, old)
	_end_broken_sets()
	return ""

## Takes off what's worn in `place` and puts it in the bag (at slot `i` if given and free).
func unequip(place: StringName, i := -1) -> String:
	var c := character
	var stack := c.equipment.at(place)
	if stack == null:
		return ""
	var row: Array = c.inventory.tabs[ItemDef.Tab.EQUIP]
	if i < 0 or i >= Inventory.SLOTS or row[i] != null:
		i = c.inventory.first_free(ItemDef.Tab.EQUIP)
	if i < 0:
		return "Your Equip inventory is full."
	c.equipment.take(place)
	c.inventory.put(ItemDef.Tab.EQUIP, i, stack)
	_end_broken_sets()
	return ""


# ---------- runes ----------

## Why the rune in Etc slot `rune_slot` can't go in rune slot `socket` of the gear in Equip
## slot `gear_slot`, or "".
func enchant_problem(gear_slot: int, rune_slot: int, socket: int) -> String:
	var bag := character.inventory
	var gear := bag.at(ItemDef.Tab.EQUIP, gear_slot) if Inventory.valid_slot(ItemDef.Tab.EQUIP, gear_slot) else null
	var held := bag.at(ItemDef.Tab.ETC, rune_slot) if Inventory.valid_slot(ItemDef.Tab.ETC, rune_slot) else null
	if gear == null or held == null or not held.item is RuneDef or socket < 0 or socket >= ItemStack.RUNE_SLOTS:
		return "Pick a piece of gear in your bag, a rune and a rune slot."
	if character.shards < (held.item as RuneDef).fee:
		return "You don't have enough Dawnshards."
	return ""

## Sets the rune in Etc slot `rune_slot` in rune slot `socket` of the gear in Equip slot
## `gear_slot`, for its fee. It always works; a rune already there is lost. Returns why it
## couldn't, or "".
func enchant(gear_slot: int, rune_slot: int, socket: int) -> String:
	var problem := enchant_problem(gear_slot, rune_slot, socket)
	if problem != "":
		return problem
	var bag := character.inventory
	var rune := bag.take(ItemDef.Tab.ETC, rune_slot, 1).item as RuneDef
	character.shards -= rune.fee
	bag.at(ItemDef.Tab.EQUIP, gear_slot).runes[socket] = rune
	return ""


# ---------- tiers ----------

## Why the gear in Equip slot `gear_slot` can't go up a tier, or "".
func upgrade_problem(gear_slot: int) -> String:
	var gear := character.inventory.at(ItemDef.Tab.EQUIP, gear_slot) if Inventory.valid_slot(ItemDef.Tab.EQUIP, gear_slot) else null
	if gear == null:
		return "Pick a piece of gear in your bag."
	var next := gear.next_tier()
	if next == null:
		return "The %s can't go any higher." % gear.display_name()
	if character.shards < next.fee:
		return "You don't have enough Dawnshards."
	return ""

## Raises the gear in Equip slot `gear_slot` one tier for that tier's fee. It always works and
## keeps its runes and look. Returns why it couldn't, or "".
func upgrade(gear_slot: int) -> String:
	var problem := upgrade_problem(gear_slot)
	if problem != "":
		return problem
	var gear := character.inventory.at(ItemDef.Tab.EQUIP, gear_slot)
	character.shards -= gear.next_tier().fee
	gear.tier += 1
	return ""
