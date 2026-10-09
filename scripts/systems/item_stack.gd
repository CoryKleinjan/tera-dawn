class_name ItemStack
extends RefCounted
## One inventory slot's worth of an item: what it is, how many, and for gear the stats this
## particular copy rolled when it dropped.

var item: ItemDef
var count := 1
## Gear only: this copy's stats (its EquipDef's stats, rolled).
var stats: StatBlock

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

func can_stack_with(other: ItemStack) -> bool:
	return other != null and other.item == item and item.stack_size() > 1

func to_dict() -> Dictionary:
	var d := {"id": String(item.id), "count": count}
	if stats:
		d["stats"] = stats.to_dict()
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
	return s
