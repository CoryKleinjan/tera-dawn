class_name TDItemTooltip
extends Control
## The card that follows the mouse over an item slot: name, kind, requirements (red when
## not met), stats, what a potion restores and the description. Drawn above every window.

const W := 220.0

var stack: ItemStack
var at := Vector2.ZERO
var _owner: Control

func _process(_delta: float) -> void:
	queue_redraw()

## Shows `s` near `mouse` on behalf of `owner_window` (null hides it).
func show_item(owner_window: Control, s: ItemStack, mouse: Vector2) -> void:
	_owner = owner_window
	stack = s
	at = mouse

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
			out.append(["%s: +%d%s" % [StatBlock.LABELS[f], v, "%" if f in [&"speed", &"jump"] else ""], col, 12])
		out.append(["Upgrades available: %d" % e.upgrade_slots, Color("c9b8d9"), 11])
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
	DrawUtil.round_rect(self, r, 10, Color(0.08, 0.05, 0.16, 0.94))
	draw_rect(r.grow(-3), Color(Palette.SUN, 0.3), false, 1.0)
	var y := pos.y + 10
	for l in lines:
		y += l[2] + 5
		DrawUtil.text(self, Game.ui_font, Vector2(pos.x + 14, y), l[0], l[2], l[1], 1)
