class_name Inventory
extends RefCounted
## The bag: one row of slots per ItemDef.Tab (Equip, Use, Etc). Use and Etc items stack up
## to their `max_stack`; gear takes a slot each.

signal changed

const SLOTS := 24

## tabs[tab][slot] is an ItemStack or null.
var tabs: Array[Array] = []

func _init() -> void:
	clear()

func clear() -> void:
	tabs.clear()
	for t in ItemDef.Tab.size():
		var row := []
		row.resize(SLOTS)
		tabs.append(row)
	changed.emit()

func at(tab: int, i: int) -> ItemStack:
	return tabs[tab][i]

## Puts `n` of an item in the bag, topping up stacks before using empty slots.
## Returns how many didn't fit.
func add(item: ItemDef, n := 1) -> int:
	var left := n
	var row: Array = tabs[item.tab()]
	if item.stack_size() > 1:
		for s in row:
			if left > 0 and s != null and s.item == item and s.count < item.stack_size():
				var moved := mini(left, item.stack_size() - s.count)
				s.count += moved
				left -= moved
	for i in SLOTS:
		if left <= 0:
			break
		if row[i] == null:
			var s := ItemStack.create(item, mini(left, item.stack_size()))
			row[i] = s
			left -= s.count
	if left != n:
		changed.emit()
	return left

## Puts a whole stack (gear with its rolled stats) in the first free slot. False if full.
func add_stack(stack: ItemStack) -> bool:
	if stack.item.stack_size() > 1:
		var left := add(stack.item, stack.count)
		stack.count = left
		return left == 0
	var i := first_free(stack.item.tab())
	if i < 0:
		return false
	tabs[stack.item.tab()][i] = stack
	changed.emit()
	return true

## Whether `n` of an item would fit.
func has_room(item: ItemDef, n := 1) -> bool:
	var room := 0
	for s in tabs[item.tab()]:
		if s == null:
			room += item.stack_size()
		elif s.item == item:
			room += item.stack_size() - s.count
	return room >= n

func first_free(tab: int) -> int:
	return tabs[tab].find(null)

func free_slots(tab: int) -> int:
	return tabs[tab].count(null)

## Removes `n` (or all) from a slot and returns them as a stack, or null if it's empty.
func take(tab: int, i: int, n := -1) -> ItemStack:
	var s: ItemStack = tabs[tab][i]
	if s == null:
		return null
	if n < 0 or n >= s.count:
		tabs[tab][i] = null
		changed.emit()
		return s
	s.count -= n
	changed.emit()
	var out := ItemStack.create(s.item, n)
	return out

## Puts a stack straight into a slot (overwriting it).
func put(tab: int, i: int, stack: ItemStack) -> void:
	tabs[tab][i] = stack
	changed.emit()

## Drags one slot onto another: merges matching stacks, otherwise swaps them.
func move(tab: int, from: int, to: int) -> void:
	if from == to:
		return
	var a: ItemStack = tabs[tab][from]
	var b: ItemStack = tabs[tab][to]
	if a == null:
		return
	if a.can_stack_with(b) and b.count < b.item.stack_size():
		var moved := mini(a.count, b.item.stack_size() - b.count)
		b.count += moved
		a.count -= moved
		if a.count <= 0:
			tabs[tab][from] = null
	else:
		tabs[tab][from] = b
		tabs[tab][to] = a
	changed.emit()

## Takes `n` of an item out of the bag, from wherever it is. Returns how many were taken.
func remove(item: ItemDef, n: int) -> int:
	var left := n
	var row: Array = tabs[item.tab()]
	for i in SLOTS:
		var s: ItemStack = row[i]
		if left > 0 and s != null and s.item == item:
			var taken := mini(left, s.count)
			take(item.tab(), i, taken)
			left -= taken
	return n - left

func count_of(item: ItemDef) -> int:
	var n := 0
	for s in tabs[item.tab()]:
		if s != null and s.item == item:
			n += s.count
	return n

func to_dict() -> Dictionary:
	var out := {}
	for t in tabs.size():
		var row := []
		for i in SLOTS:
			var s: ItemStack = tabs[t][i]
			if s:
				var d := s.to_dict()
				d["slot"] = i
				row.append(d)
		out[ItemDef.TAB_NAMES[t]] = row
	return out

func load_dict(data: Dictionary) -> void:
	clear()
	for t in tabs.size():
		var row: Variant = data.get(ItemDef.TAB_NAMES[t], [])
		if not row is Array:
			continue
		for d in row:
			if not d is Dictionary:
				continue
			var s := ItemStack.from_dict(d)
			var i := int(d.get("slot", -1))
			if s == null or s.item.tab() != t:
				continue
			if i < 0 or i >= SLOTS or tabs[t][i] != null:
				i = first_free(t)
			if i >= 0:
				tabs[t][i] = s
	changed.emit()
