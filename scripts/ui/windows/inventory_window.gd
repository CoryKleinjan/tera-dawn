class_name TDInventoryWindow
extends TDWindow
## The bag (I): Equip, Use and Etc tabs of item slots. Double-click gear to wear it or a
## potion to use it, drag to rearrange, drag onto the equipment window to equip, and drag
## out of every window to drop it on the ground. Double-clicking an upgrade scroll picks it
## up: the next click on a piece of gear uses it there (right-click puts it back).

const COLS := 4
const GAP := 4.0
const TAB_Y := 36.0
const GRID_Y := 66.0

var tab := ItemDef.Tab.EQUIP
## The drag this window started, kept for NOTIFICATION_DRAG_END (the viewport has
## already forgotten it by then).
var _pending: Variant = null
## The Use slot of the scroll waiting for a piece of gear, or -1.
var scrolling := -1

func _init() -> void:
	var rows := ceili(Inventory.SLOTS / float(COLS))
	super("Inventory", Vector2(PAD * 2 + COLS * (SLOT + GAP) - GAP, GRID_Y + rows * (SLOT + GAP) + 40))

func _tab_rect(t: int) -> Rect2:
	var w := (size.x - PAD * 2) / ItemDef.Tab.size()
	return Rect2(PAD + t * w - 3, TAB_Y - 1, w + 6, 26)

func slot_rect(i: int) -> Rect2:
	return Rect2(PAD + (i % COLS) * (SLOT + GAP), GRID_Y + (i / COLS) * (SLOT + GAP), SLOT, SLOT)

func slot_at(at: Vector2) -> int:
	for i in Inventory.SLOTS:
		if slot_rect(i).has_point(at):
			return i
	return -1

func _draw_body() -> void:
	for t in ItemDef.Tab.size():
		draw_tab(_tab_rect(t), ItemDef.TAB_NAMES[t], t == tab)
	var dragged := _dragged_index()
	for i in Inventory.SLOTS:
		draw_slot(slot_rect(i), Game.me.inventory.at(tab, i), i == dragged)
	var scroll := _scroll()
	if scroll:
		for i in Inventory.SLOTS:
			var g := Game.me.inventory.at(ItemDef.Tab.EQUIP, i) if tab == ItemDef.Tab.EQUIP else null
			if g and scroll.fits(g.equip_def()) and g.slots_left() > 0:
				draw_rect(slot_rect(i).grow(1), Color(1, 0.85, 0.4, 0.9), false, 2.0)
		DrawUtil.text(self, Game.ui_font, Vector2(size.x / 2.0, GRID_Y - 4), "Click gear for the %s" % scroll.display_name, 11, Palette.SUN, 0, 3, Palette.NIGHT)
	# Dawnshards and free space
	var y := size.y - 22
	draw_texture_rect(UiSkin.tex("icon_dawnshard"), Rect2(PAD, y - 16, 22, 20), false)
	DrawUtil.text(self, Game.num_font, Vector2(PAD + 28, y), str(Game.me.shards), 15, Palette.SUN, 1, 4, Palette.NIGHT)
	DrawUtil.text(self, Game.ui_font, Vector2(size.x - PAD, y), "%d free" % Game.me.inventory.free_slots(tab), 11, Color(Palette.MIST, 0.7), -1)

func _dragged_index() -> int:
	if not get_viewport().gui_is_dragging():
		return -1
	var d: Variant = get_viewport().gui_get_drag_data()
	if d is Dictionary and d.get("from") == "inventory" and d.get("tab") == tab:
		return d["index"]
	return -1

## The scroll picked up for upgrading, if it's still there.
func _scroll() -> ScrollDef:
	if scrolling < 0:
		return null
	var s := Game.me.inventory.at(ItemDef.Tab.USE, scrolling)
	if s == null or not s.item is ScrollDef:
		scrolling = -1
		return null
	return s.item as ScrollDef

func _click(at: Vector2, button: int, double: bool) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		scrolling = -1
	if button != MOUSE_BUTTON_LEFT:
		return
	for t in ItemDef.Tab.size():
		if _tab_rect(t).has_point(at):
			tab = t as ItemDef.Tab
			return
	var i := slot_at(at)
	if i >= 0 and _scroll() and tab == ItemDef.Tab.EQUIP:
		if Game.me.inventory.at(tab, i):
			use_scroll_on(i)
		return
	if i >= 0 and double:
		use_slot(i)

## Uses the picked-up scroll on the gear in Equip slot `i`.
func use_scroll_on(i: int) -> void:
	Net.ask(&"req_scroll", [scrolling, i])
	scrolling = -1

## What double-clicking a slot does: wear gear, drink a potion. The server does it and
## sends back the result (or why not).
func use_slot(i: int) -> void:
	if Game.me.inventory.at(tab, i) == null:
		return
	match tab:
		ItemDef.Tab.EQUIP:
			Net.ask(&"req_equip", [i, &""])
		ItemDef.Tab.USE:
			if Game.me.inventory.at(tab, i).item is ScrollDef:
				scrolling = i
				tab = ItemDef.Tab.EQUIP
			else:
				Net.ask(&"req_use_item", [i])
	hud.tooltip.clear(self)

func _hovered(at: Vector2) -> void:
	var i := slot_at(at)
	var stack := Game.me.inventory.at(tab, i) if i >= 0 else null
	var hint := ""
	match tab:
		ItemDef.Tab.EQUIP:
			hint = "Click to use the scroll here" if _scroll() else "Double-click to equip"
		ItemDef.Tab.USE:
			hint = "" if stack and stack.item is AmmoDef else "Double-click to use"
			if stack and stack.item is ScrollDef:
				hint = "Double-click, then click the gear"
	hud.tooltip.show_item(self, stack, get_global_mouse_position(), hint, true)

func _get_drag_data(at: Vector2) -> Variant:
	var i := slot_at(at)
	if i < 0 or Game.me.inventory.at(tab, i) == null:
		return null
	set_drag_preview(drag_preview(Game.me.inventory.at(tab, i)))
	hud.tooltip.clear(self)
	_pending = {"from": "inventory", "tab": tab, "index": i}
	return _pending

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or slot_at(at) < 0:
		return false
	if data["from"] == "inventory":
		return data["tab"] == tab
	return data["from"] == "equipment" and tab == ItemDef.Tab.EQUIP

func _drop_data(at: Vector2, data: Variant) -> void:
	var i := slot_at(at)
	if data["from"] == "inventory":
		# move it here right away so it doesn't jump back while the server answers
		Game.me.inventory.move(tab, data["index"], i)
		Net.ask(&"req_move_item", [tab, data["index"], i])
	else:
		Net.ask(&"req_unequip", [data["place"], i])

func _notification(what: int) -> void:
	# dragged out of every window: drop it on the ground
	if what != NOTIFICATION_DRAG_END:
		return
	var d: Variant = _pending
	_pending = null
	if d != null and not get_viewport().gui_is_drag_successful() and not mouse_over_window():
		var world := hud.world
		if world.started and not world.player.fainted():
			Net.ask(&"req_drop_item", [d["tab"], d["index"]])
