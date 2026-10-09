class_name TDInventoryWindow
extends TDWindow
## The bag (I): Equip, Use and Etc tabs of item slots. Double-click gear to wear it or a
## potion to use it, drag to rearrange, drag onto the equipment window to equip, and drag
## out of every window to drop it on the ground.

const COLS := 4
const GAP := 4.0
const TAB_Y := 36.0
const GRID_Y := 66.0

var tab := ItemDef.Tab.EQUIP
## The drag this window started, kept for NOTIFICATION_DRAG_END (the viewport has
## already forgotten it by then).
var _pending: Variant = null

func _init() -> void:
	var rows := ceili(Inventory.SLOTS / float(COLS))
	super("Inventory", Vector2(PAD * 2 + COLS * (SLOT + GAP) - GAP, GRID_Y + rows * (SLOT + GAP) + 40))

func _tab_rect(t: int) -> Rect2:
	var w := (size.x - PAD * 2) / ItemDef.Tab.size()
	return Rect2(PAD + t * w, TAB_Y, w - 3, 24)

func slot_rect(i: int) -> Rect2:
	return Rect2(PAD + (i % COLS) * (SLOT + GAP), GRID_Y + (i / COLS) * (SLOT + GAP), SLOT, SLOT)

func slot_at(at: Vector2) -> int:
	for i in Inventory.SLOTS:
		if slot_rect(i).has_point(at):
			return i
	return -1

func _draw_body() -> void:
	for t in ItemDef.Tab.size():
		var r := _tab_rect(t)
		var on := t == tab
		DrawUtil.round_rect(self, r, 7, Color(Palette.SUN, 0.95) if on else Color(Palette.PLUM, 0.85))
		DrawUtil.text(self, Game.ui_font, r.get_center() + Vector2(0, 5), ItemDef.TAB_NAMES[t], 13,
			Color("3b2208") if on else Palette.MIST)
	var dragged := _dragged_index()
	for i in Inventory.SLOTS:
		draw_slot(slot_rect(i), Game.inventory.at(tab, i), i == dragged)
	# Dawnshards and free space
	var y := size.y - 22
	draw_texture_rect(UiSkin.tex("icon_dawnshard"), Rect2(PAD, y - 16, 22, 20), false)
	DrawUtil.text(self, Game.num_font, Vector2(PAD + 28, y), str(Game.shards), 15, Palette.SUN, 1, 4, Palette.NIGHT)
	DrawUtil.text(self, Game.ui_font, Vector2(size.x - PAD, y), "%d free" % Game.inventory.free_slots(tab), 11, Color(Palette.MIST, 0.7), -1)

func _dragged_index() -> int:
	if not get_viewport().gui_is_dragging():
		return -1
	var d: Variant = get_viewport().gui_get_drag_data()
	if d is Dictionary and d.get("from") == "inventory" and d.get("tab") == tab:
		return d["index"]
	return -1

func _click(at: Vector2, button: int, double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	for t in ItemDef.Tab.size():
		if _tab_rect(t).has_point(at):
			tab = t as ItemDef.Tab
			return
	var i := slot_at(at)
	if i >= 0 and double:
		use_slot(i)

## What double-clicking a slot does: wear gear, drink a potion.
func use_slot(i: int) -> void:
	var problem := ""
	match tab:
		ItemDef.Tab.EQUIP:
			problem = Game.equip(i)
		ItemDef.Tab.USE:
			problem = hud.world.use_item(i)
	if problem != "":
		hud.world.add_log(problem, Color("ff8a99"))
	hud.tooltip.clear(self)

func _hovered(at: Vector2) -> void:
	var i := slot_at(at)
	var stack := Game.inventory.at(tab, i) if i >= 0 else null
	var hint := ""
	match tab:
		ItemDef.Tab.EQUIP:
			hint = "Double-click to equip"
		ItemDef.Tab.USE:
			hint = "Double-click to use"
	hud.tooltip.show_item(self, stack, get_global_mouse_position(), hint, true)

func _get_drag_data(at: Vector2) -> Variant:
	var i := slot_at(at)
	if i < 0 or Game.inventory.at(tab, i) == null:
		return null
	set_drag_preview(drag_preview(Game.inventory.at(tab, i)))
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
		Game.inventory.move(tab, data["index"], i)
	else:
		var problem := Game.unequip(data["place"], i)
		if problem != "":
			hud.world.add_log(problem, Color("ff8a99"))

func _notification(what: int) -> void:
	# dragged out of every window: drop it on the ground
	if what != NOTIFICATION_DRAG_END:
		return
	var d: Variant = _pending
	_pending = null
	if d != null and not get_viewport().gui_is_drag_successful() and not mouse_over_window():
		var world := hud.world
		if world.started and not world.player.fainted():
			var stack := Game.inventory.take(d["tab"], d["index"])
			if stack:
				world.drop_from_player(stack)
