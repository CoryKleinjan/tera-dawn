class_name TDTradeWindow
extends TDWindow
## A trade with another player on the same map. Drag things from your bag onto your side
## (they're held by the server until the trade ends), set how many Dawnshards you add,
## then press Trade. When you both have, everything changes hands. Changing either offer
## takes both Trade presses back; closing the window cancels and returns everything.

const COLS := 3
## The trade panel art (two 3 x 3 grids under a handshake), drawn at its own size here.
const PANEL := "dialogue/trade_panel"
const PANEL_AT := Vector2(PAD - 6, TITLE_H + 4)
## Where the painted slots are on the panel art, in texels: each grid's first slot, and the
## step to the next column and row.
const GRID_LEFT := Vector2(26, 73)
const GRID_RIGHT := Vector2(218, 73)
const PITCH := Vector2(50, 50)
const SHARDS_H := 28.0

## The server's last word: {"partner", "mine": {...}, "theirs": {...}} (see TDSocial).
var state := {}

func _init() -> void:
	var panel := UiSkin.tex(PANEL).get_size()
	super("Trade", Vector2(panel.x + PANEL_AT.x * 2, PANEL_AT.y + panel.y + SHARDS_H + 64))

func show_state(s: Dictionary) -> void:
	var was_open := not state.is_empty()
	state = s
	if s.is_empty():
		visible = false
		hud.tooltip.clear(self)
		return
	title = "Trade with %s" % s["partner"]
	if not was_open:
		place_beside_inventory(70)
	visible = true
	raise()

func toggle() -> void:
	if visible:
		cancel()
	else:
		super()

func cancel() -> void:
	if not state.is_empty():
		Net.ask(&"req_trade_cancel")
	visible = false

func slot_rect(i: int, theirs: bool) -> Rect2:
	var first := PANEL_AT + (GRID_RIGHT if theirs else GRID_LEFT)
	return Rect2(first + Vector2(i % COLS, i / COLS) * PITCH, Vector2(SLOT, SLOT))

## Your side's grid, where items from your bag can be dropped.
func _my_grid() -> Rect2:
	return slot_rect(0, false).merge(slot_rect(COLS * 3 - 1, false))

func _stack(side: String, i: int) -> ItemStack:
	var items: Array = state.get(side, {}).get("items", [])
	return ItemStack.from_dict(items[i]) if i < items.size() else null

## A side's Dawnshard counter, under its grid.
func _shards_rect(theirs := false) -> Rect2:
	var grid := slot_rect(0, theirs).merge(slot_rect(COLS * 3 - 1, theirs))
	var top := PANEL_AT.y + UiSkin.tex(PANEL).get_height() + 6
	return Rect2(grid.position.x - 6, top, grid.size.x + 12, SHARDS_H)

func _trade_rect() -> Rect2:
	return Rect2(PAD, size.y - 44, (size.x - PAD * 2 - 8) / 2.0, 32)

func _cancel_rect() -> Rect2:
	var r := _trade_rect()
	return Rect2(r.end.x + 8, r.position.y, r.size.x, r.size.y)

func _draw_body() -> void:
	if state.is_empty():
		return
	draw_texture_rect(UiSkin.tex(PANEL), Rect2(PANEL_AT, UiSkin.tex(PANEL).get_size()), false)
	for side in ["mine", "theirs"]:
		var theirs: bool = side == "theirs"
		var d: Dictionary = state[side]
		var first := slot_rect(0, theirs)
		draw_label(first.position + Vector2(2, -8), "Them" if theirs else "You", Palette.MUTED)
		if d["ready"]:
			UiSkin.draw_icon(self, "dialogue/trade_ready", Rect2(slot_rect(2, theirs).end.x - 26, first.position.y - 30, 26, 26))
		for i in COLS * 3:
			draw_slot(slot_rect(i, theirs), _stack(side, i))
		var sr := _shards_rect(theirs)
		var lit := not theirs and sr.has_point(_hover)
		UiSkin.draw_box(self, UiSkin.shard_counter(), sr, 0.5)
		if lit:
			draw_hilite(sr.grow(-3), sr.size.y / 2.0)
		DrawUtil.text(self, Game.num_font, sr.position + Vector2(34, 20), str(d["shards"]), 15, Palette.SUN, 1, 4, Palette.NIGHT)
		if not theirs:
			DrawUtil.text(self, Game.ui_font, sr.end + Vector2(-12, -9), "click to set", 9, Palette.MUTED, -1)
	draw_button(_trade_rect(), "Trade", not state["mine"]["ready"])
	draw_button(_cancel_rect(), "Cancel")

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT or state.is_empty():
		return
	if _trade_rect().has_point(at):
		Net.ask(&"req_trade_ready")
	elif _cancel_rect().has_point(at):
		cancel()
	elif _shards_rect(false).has_point(at):
		hud.prompt.ask("How many Dawnshards?", str(state["mine"]["shards"]), func(t: String) -> void:
			Net.ask(&"req_trade_shards", [maxi(0, int(t))]), true)

func _hovered(at: Vector2) -> void:
	for side in ["mine", "theirs"]:
		for i in COLS * 3:
			if slot_rect(i, side == "theirs").has_point(at):
				hud.tooltip.show_item(self, _stack(side, i), get_global_mouse_position())
				return
	hud.tooltip.clear(self)

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "inventory" and _my_grid().has_point(at)

func _drop_data(_at: Vector2, data: Variant) -> void:
	offer(data["tab"], data["index"])

## Puts the whole stack in bag slot `index` of `tab` on the table.
func offer(tab: int, index: int) -> void:
	Net.ask(&"req_trade_offer", [tab, index, -1])
