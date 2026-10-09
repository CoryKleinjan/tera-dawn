class_name ItemStack
extends RefCounted
## One inventory slot's worth of an item: what it is, how many, and for gear the stats this
## particular copy rolled when it dropped.

var item: ItemDef
var count := 1
## Gear only: this copy's stats (its EquipDef's stats, rolled).
var stats: StatBlock
## Gear only: upgrade slots spent on scrolls, and how many of those scrolls worked.
var slots_used := 0
var upgrades := 0

## A new stack of `n`; gear rolls its stats here.
static func create(it: ItemDef, n := 1) -> ItemStack:
	var s := ItemStack.new()
	s.item = it
	s.count = n
	var e := it as EquipDef
	if e:
		s.count = 1
		s.stats = e.stats.rolled(e.variance) if e.stats else StatBlock.new()
	return s

## Gear with exactly its listed stats (starting gear).
static func exact(e: EquipDef) -> ItemStack:
	var s := ItemStack.new()
	s.item = e
	s.stats = e.stats.copy() if e.stats else StatBlock.new()
	return s

## A new stack of `n` with gear at exactly its listed stats (what shops sell).
static func unrolled(it: ItemDef, n := 1) -> ItemStack:
	if it is EquipDef:
		return exact(it)
	return create(it, n)

func equip_def() -> EquipDef:
	return item as EquipDef

## The item's name, with "+3" for gear that took three scrolls.
func display_name() -> String:
	return "%s +%d" % [item.display_name, upgrades] if upgrades > 0 else item.display_name

## Gear only: upgrade slots it has left for scrolls.
func slots_left() -> int:
	var e := equip_def()
	return maxi(0, e.upgrade_slots - slots_used) if e else 0

func can_stack_with(other: ItemStack) -> bool:
	return other != null and other.item == item and item.stack_size() > 1

func to_dict() -> Dictionary:
	var d := {"id": String(item.id), "count": count}
	if stats:
		d["stats"] = stats.to_dict()
	if slots_used > 0:
		d["slots_used"] = slots_used
		d["upgrades"] = upgrades
	return d

## Rebuilds a saved stack, or null if its item no longer exists.
static func from_dict(d: Dictionary) -> ItemStack:
	var id := StringName(str(d.get("id", "")))
	if not Content.items.has(id):
		return null
	var s := ItemStack.new()
	s.item = Content.items[id]
	s.count = clampi(int(d.get("count", 1)), 1, s.item.stack_size())
	if s.item is EquipDef:
		var saved: Variant = d.get("stats")
		s.stats = StatBlock.from_dict(saved) if saved is Dictionary else ItemStack.exact(s.item).stats
		s.slots_used = maxi(0, int(d.get("slots_used", 0)))
		s.upgrades = clampi(int(d.get("upgrades", 0)), 0, s.slots_used)
	return s
