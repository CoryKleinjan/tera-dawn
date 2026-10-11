class_name Gear
extends CharacterPart
## The rules for a character's gear (Character.gear): who can wear what, putting gear on
## and taking it off between the bag's Equip tab and what's worn (Character.equipment),
## upgrade scrolls, and the ammo the weapon fires.

## The weapon worn, or null.
func weapon() -> EquipDef:
	var w := character.equipment.at(&"weapon")
	return w.equip_def() if w else null

## Whether this job can use gear meant for `families` (empty means anyone).
func can_use(families: Array[StringName]) -> bool:
	return families.is_empty() or character.job.family in families

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

## The most of `stat` any gear this character wears, or could wear at this level, asks for.
func most_needed(stat: StringName) -> int:
	var c := character
	var gear: Array[EquipDef] = []
	for s: ItemStack in c.equipment.worn.values():
		gear.append(s.equip_def())
	for i in Inventory.SLOTS:
		var s := c.inventory.at(ItemDef.Tab.EQUIP, i)
		if s and can_use(s.equip_def().jobs) and s.equip_def().required_level <= c.level:
			gear.append(s.equip_def())
	var most := 0
	for e in gear:
		most = maxi(most, e.requirements().get(stat, 0))
	return most

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

# ---------- ammo ----------

## The Use-tab slot of the ammo the weapon fires (first in the bag), or -1.
func ammo_slot() -> int:
	var w := weapon()
	if w == null or w.ammo == &"":
		return -1
	var bag := character.inventory
	for i in Inventory.SLOTS:
		var s := bag.at(ItemDef.Tab.USE, i)
		if s and s.item is AmmoDef and (s.item as AmmoDef).kind == w.ammo:
			return i
	return -1

## The extra Weapon Attack of the ammo that would be fired next.
func ammo_attack() -> int:
	var i := ammo_slot()
	return (character.inventory.at(ItemDef.Tab.USE, i).item as AmmoDef).attack if i >= 0 else 0

## How much of the weapon's ammo is in the bag.
func ammo_count() -> int:
	var w := weapon()
	if w == null or w.ammo == &"":
		return 0
	var n := 0
	for s in character.inventory.tabs[ItemDef.Tab.USE]:
		if s and s.item is AmmoDef and (s.item as AmmoDef).kind == w.ammo:
			n += s.count
	return n

## Spends `n` of the weapon's ammo, first stacks first.
func spend_ammo(n: int) -> void:
	var bag := character.inventory
	while n > 0:
		var i := ammo_slot()
		if i < 0:
			return
		var taken := bag.take(ItemDef.Tab.USE, i, mini(n, bag.at(ItemDef.Tab.USE, i).count))
		n -= taken.count if taken else n
