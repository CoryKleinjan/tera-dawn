class_name TDInventoryWindow
extends TDWindow
## The bag (I): Equip, Use, Etc and Setup tabs of item slots. Double-click gear to wear it, a
## potion to use it, a pet to bring it out, drag to rearrange, drag onto the equipment window to equip, and drag
## out of every window to drop it on the ground.

const COLS := 4
const GAP := 4.0
const GRID_Y := 66.0

var tab := ItemDef.Tab.EQUIP
## The bag's slots.
var grid := SlotGrid.new(Vector2(PAD, GRID_Y), COLS, Inventory.SLOTS, SLOT, GAP)
## The drag this window started, for when it ends (see `_notification`).
var _drag := DragPayload.Tracker.new()

func _init() -> void:
	var rows := ceili(Inventory.SLOTS / float(COLS))
	super("Inventory", Vector2(PAD * 2 + COLS * (SLOT + GAP) - GAP, GRID_Y + rows * (SLOT + GAP) + 40))

func slot_rect(i: int) -> Rect2:
	return grid.rect(i)

func slot_at(at: Vector2) -> int:
	return grid.at(at)

func _draw_body() -> void:
	draw_tabs(ItemDef.TAB_NAMES, tab)
	var dragged := _dragged_index()
	for i in Inventory.SLOTS:
		draw_slot(slot_rect(i), Game.me.inventory.at(tab, i), i == dragged)
	# Dawnshards and free space
	var y := size.y - 22
	draw_shards(Vector2(PAD, y), Game.me.shards)
	DrawUtil.text(self, Game.ui_font, Vector2(size.x - PAD, y), "%d free" % Game.me.inventory.free_slots(tab), 11, Color(Palette.MIST, 0.7), -1)

func _dragged_index() -> int:
	var d := DragPayload.dragging(self)
	return d.index if d and DragPayload.is_bag_item(d, tab) else -1

func _click(at: Vector2, button: int, double: bool) -> void:
	var i := slot_at(at)
	if button == MOUSE_BUTTON_RIGHT:
		if i >= 0 and _shop():
			_shop().sell_from(tab, i)
	if button != MOUSE_BUTTON_LEFT:
		return
	if i >= 0 and double:
		if _shop():
			_shop().sell_from(tab, i)
		else:
			use_slot(i)

## The shop window while a shop is open (double-click and right-click then sell), or null.
func _shop() -> TDShopWindow:
	var shop: TDShopWindow = hud.windows.get("shop")
	return shop if shop and shop.visible else null

func _tab_clicked(i: int) -> void:
	tab = i as ItemDef.Tab

## What double-clicking a slot does: wear gear, drink a potion. The server does it and
## sends back the result (or why not).
func use_slot(i: int) -> void:
	if Game.me.inventory.at(tab, i) == null:
		return
	match tab:
		ItemDef.Tab.EQUIP:
			Net.ask(&"req_equip", [i, &""])
		ItemDef.Tab.USE:
			Net.ask(&"req_use_item", [i])
		ItemDef.Tab.SETUP:
			Net.ask(&"req_setup", [i])
	hud.tooltip.clear(self)

func _tooltip_at(at: Vector2) -> Tip:
	var i := slot_at(at)
	var stack := Game.me.inventory.at(tab, i) if i >= 0 else null
	var hint := ""
	if stack and _shop():
		return Tip.new(stack, "Double-click to sell (%d each)" % stack.item.sell_price, true)
	match tab:
		ItemDef.Tab.EQUIP:
			hint = "Double-click to equip"
		ItemDef.Tab.USE:
			hint = "Double-click to use"
		ItemDef.Tab.SETUP:
			if stack and stack.item is PetDef:
				hint = "Double-click to bring out or send home"
	return Tip.new(stack, hint, true)

func _get_drag_data(at: Vector2) -> Variant:
	var i := slot_at(at)
	if i < 0 or Game.me.inventory.at(tab, i) == null:
		return null
	hud.tooltip.clear(self)
	return _drag.start(self, DragPayload.bag_item(tab, i), drag_preview(Game.me.inventory.at(tab, i).item.icon))

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var d := DragPayload.of(data)
	if d == null or slot_at(at) < 0:
		return false
	if d.from == DragPayload.From.INVENTORY:
		return d.tab == tab
	return d.from == DragPayload.From.EQUIPMENT and tab == ItemDef.Tab.EQUIP

func _drop_data(at: Vector2, data: Variant) -> void:
	var d := DragPayload.of(data)
	var i := slot_at(at)
	if d.from == DragPayload.From.INVENTORY:
		# move it here right away so it doesn't jump back while the server answers
		Game.me.inventory.move(tab, d.index, i)
		Net.ask(&"req_move_item", [tab, d.index, i])
	else:
		Net.ask(&"req_unequip", [d.place, i])

func _notification(what: int) -> void:
	# dragged out of every window: drop it on the ground
	if what != NOTIFICATION_DRAG_END:
		return
	var d := _drag.ended_unplaced(self)
	if d != null and not mouse_over_window():
		var world := hud.world
		if world.started and not world.player.fainted():
			Net.ask(&"req_drop_item", [d.tab, d.index])
