class_name Gear
extends CharacterPart
## The rules for a character's gear (Character.gear): who can wear what, putting gear on
## and taking it off between the bag's Equip tab and what's worn (Character.equipment),
## and upgrade scrolls.

## The weapon worn, or null.
func weapon() -> EquipDef:
	var w := character.equipment.at(&"weapon")
	return w.equip_def() if w else null

## What's worn in the off-hand slot (a shield, stars, a book, a quiver or a pistol), or null.
func offhand() -> EquipDef:
	var o := character.equipment.at(&"shield")
	return o.equip_def() if o else null

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
	var c := character
	if not can_use(e.jobs):
		return "Only %s can use the %s." % [EquipDef.families_text(e.jobs), e.display_name]
	if c.level < e.required_level:
		return "You need to be level %d to wear the %s." % [e.required_level, e.display_name]
	var reqs := e.requirements()
	for stat in StatBlock.BASE:
		if reqs.has(stat) and c.stats.value(stat) < reqs[stat]:
			return "You need %d %s to wear the %s." % [reqs[stat], StatBlock.LABELS[stat], e.display_name]
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
	return ""

# ---------- upgrade scrolls ----------

## Why the scroll in Use slot `use_slot` can't go on the gear in Equip slot `equip_slot`, or "".
func scroll_problem(use_slot: int, equip_slot: int) -> String:
	var bag := character.inventory
	var held := bag.at(ItemDef.Tab.USE, use_slot)
	var gear := bag.at(ItemDef.Tab.EQUIP, equip_slot)
	if held == null or not held.item is ScrollDef or gear == null:
		return "Pick a piece of gear in your bag to use the scroll on."
	var scroll := held.item as ScrollDef
	if not scroll.fits(gear.equip_def()):
		return "The %s only works on %s gear." % [scroll.display_name, scroll.slot_text()]
	if gear.slots_left() <= 0:
		return "The %s has no upgrades left." % gear.display_name()
	return ""

## Uses the scroll in Use slot `use_slot` on the gear in Equip slot `equip_slot`: it spends
## an upgrade slot and works if `roll` is under the scroll's chance. Returns
## {"problem": why it couldn't, or "", "worked": whether the gear got the stats}.
func use_scroll(use_slot: int, equip_slot: int, roll := randf()) -> Dictionary:
	var problem := scroll_problem(use_slot, equip_slot)
	if problem != "":
		return {"problem": problem, "worked": false}
	var bag := character.inventory
	var scroll := bag.at(ItemDef.Tab.USE, use_slot).item as ScrollDef
	var gear := bag.at(ItemDef.Tab.EQUIP, equip_slot)
	bag.take(ItemDef.Tab.USE, use_slot, 1)
	gear.slots_used += 1
	var worked := roll < scroll.chance
	if worked:
		gear.upgrades += 1
		if scroll.stats:
			gear.stats.add(scroll.stats)
	return {"problem": "", "worked": worked}
