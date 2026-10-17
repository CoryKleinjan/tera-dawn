class_name ItemStack
extends RefCounted
## One inventory slot's worth of an item: what it is, how many, and for gear the stats this
## particular copy rolled when it dropped and the runes set in it.

## Rune slots on every piece of gear.
const RUNE_SLOTS := 3

var item: ItemDef
var count := 1
## Gear only: this copy's stats (its EquipDef's stats, rolled).
var stats: StatBlock
## Gear only: the rune in each of its RUNE_SLOTS slots, null where it's empty.
var runes: Array[RuneDef] = []

## A new stack of `n`; gear rolls its stats here.
static func create(it: ItemDef, n := 1) -> ItemStack:
	var s := ItemStack.new()
	s.item = it
	s.count = n
	var e := it as EquipDef
	if e:
		s.count = 1
		s.stats = e.stats.rolled(e.variance) if e.stats else StatBlock.new()
		s.runes.resize(RUNE_SLOTS)
	return s

## Gear with exactly its listed stats (starting gear).
static func exact(e: EquipDef) -> ItemStack:
	var s := ItemStack.new()
	s.item = e
	s.stats = e.stats.copy() if e.stats else StatBlock.new()
	s.runes.resize(RUNE_SLOTS)
	return s

## A new stack of `n` with gear at exactly its listed stats (what shops sell).
static func unrolled(it: ItemDef, n := 1) -> ItemStack:
	if it is EquipDef:
		return exact(it)
	return create(it, n)

func equip_def() -> EquipDef:
	return item as EquipDef

func display_name() -> String:
	return item.display_name

## Gear only: what it adds while worn, its stats and its runes'.
func total() -> StatBlock:
	var out := stats.copy() if stats else StatBlock.new()
	for r in runes:
		if r:
			out.add(r.stats)
	return out

## Gear only: how many of its rune slots hold a rune.
func runes_set() -> int:
	return runes.size() - runes.count(null)

func can_stack_with(other: ItemStack) -> bool:
	return other != null and other.item == item and item.stack_size() > 1

func to_dict() -> Dictionary:
	var d := {"id": String(item.id), "count": count}
	if stats:
		d["stats"] = stats.to_dict()
	if runes.any(func(r: RuneDef) -> bool: return r != null):
		d["runes"] = runes.map(func(r: RuneDef) -> String: return String(r.id) if r else "")
	return d

## Rebuilds a saved stack, or null if its item no longer exists (an upgrade scroll). Gear
## keeps the stats it was saved with, scroll upgrades and all, and its runes (none in saves
## from before runes; a rune that no longer exists leaves its slot empty).
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
		s.runes.resize(RUNE_SLOTS)
		var set_in: Variant = d.get("runes")
		if set_in is Array:
			for i in mini(RUNE_SLOTS, set_in.size()):
				s.runes[i] = Content.items.get(StringName(str(set_in[i]))) as RuneDef
	return s
