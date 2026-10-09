class_name TDItemTooltip
extends Control
## The card that follows the mouse over an item slot: name, kind, requirements (red when
## not met), stats, how gear compares with what's worn in its slot, what a potion restores,
## the description and what double-clicking does. Drawn above every window.

const W := 220.0

var stack: ItemStack
var at := Vector2.ZERO
var _owner: Control
var hint := ""
## Gear only: also list how it differs from what's worn where it would go.
var compare := false

func _process(_delta: float) -> void:
	queue_redraw()

## Shows `s` near `mouse` on behalf of `owner_window` (null hides it), with a `hint` line
## at the bottom, and for gear in the bag a comparison with what's worn if `compare_worn`.
func show_item(owner_window: Control, s: ItemStack, mouse: Vector2, hint_text := "", compare_worn := false) -> void:
	_owner = owner_window
	stack = s
	at = mouse
	hint = hint_text
	compare = compare_worn

## Hides the tooltip if `owner_window` is the one showing it.
func clear(owner_window: Control) -> void:
	if _owner == owner_window:
		stack = null

func _lines() -> Array:
	var out := []  # [text, colour, size]
	var item := stack.item
	out.append([item.display_name, Palette.SUN, 15])
	var e := item as EquipDef
	if e:
		out.append(["Equip · %s" % e.slot_name(), Color("c9b8d9"), 11])
		var reqs := e.requirements()
		for key in reqs:
			var have := Game.level if key == &"level" else Game.stats.value(key)
			var label: String = "Level" if key == &"level" else StatBlock.LABELS[key]
			out.append(["Requires %s %d" % [label, reqs[key]], Palette.MIST if have >= reqs[key] else Color("ff6b7d"), 12])
		var base := e.stats if e.stats else StatBlock.new()
		for f in stack.stats.nonzero():
			var v := stack.stats.value(f)
			var col := Palette.MIST
			if v > base.value(f):
				col = Color("8cf0a6")
			elif v < base.value(f):
				col = Color("ffb38a")
			out.append(["%s: %s" % [StatBlock.LABELS[f], StatBlock.format(f, v)], col, 12])
		out.append(["Upgrades available: %d" % e.upgrade_slots, Color("c9b8d9"), 11])
		if compare:
			out.append_array(_comparison(e))
	elif item is UseDef:
		var u := item as UseDef
		out.append(["Use", Color("c9b8d9"), 11])
		var hp := u.hp_for(Game.max_hp())
		var mp := u.mp_for(Game.max_mp())
		if hp > 0:
			out.append(["Restores %d HP" % hp, Palette.HP, 12])
		if mp > 0:
			out.append(["Restores %d MP" % mp, Palette.MP, 12])
	else:
		out.append(["Etc", Color("c9b8d9"), 11])
	if item.description != "":
		for l in UiSkin.wrap_text(Game.ui_font, item.description, 11, W - 28):
			out.append([l, Color(Palette.MIST, 0.8), 11])
	if hint != "":
		out.append([hint, Color(Palette.SUN, 0.75), 11])
	return out

## How wearing this would change each stat, against what's worn where it would go.
func _comparison(e: EquipDef) -> Array:
	var worn := Game.equipment.at(Game.equipment.place_for(e))
	if worn == null:
		return [["Nothing worn in this slot", Color("8cf0a6"), 11]]
	var out := [["vs. worn %s:" % worn.item.display_name, Color("c9b8d9"), 11]]
	var changed := false
	for f in StatBlock.FIELDS:
		var diff := stack.stats.value(f) - worn.stats.value(f)
		if diff != 0:
			changed = true
			out.append(["  %s %s" % [StatBlock.format(f, diff), StatBlock.LABELS[f]], Color("8cf0a6") if diff > 0 else Color("ff6b7d"), 12])
	if not changed:
		out.append(["  Same stats", Palette.MIST, 12])
	return out

func _draw() -> void:
	if stack == null or stack.item == null or _owner == null or not _owner.visible:
		return
	var lines := _lines()
	var h := 22.0
	for l in lines:
		h += l[2] + 5
	var view := get_viewport_rect().size
	var pos := at + Vector2(18, 12)
	if pos.x + W > view.x:
		pos.x = at.x - W - 12
	pos.y = clampf(pos.y, 4, view.y - h - 4)
	var r := Rect2(pos, Vector2(W, h))
	UiSkin.tooltip_frame().draw(get_canvas_item(), r)
	var y := pos.y + 10
	for l in lines:
		y += l[2] + 5
		DrawUtil.text(self, Game.ui_font, Vector2(pos.x + 14, y), l[0], l[2], l[1], 1)
