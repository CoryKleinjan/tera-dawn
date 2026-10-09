class_name TDTradeWindow
extends TDWindow
## A trade with another player on the same map. Drag things from your bag onto your side
## (they're held by the server until the trade ends), set how many Dawnshards you add,
## then press Trade. When you both have, everything changes hands. Changing either offer
## takes both Trade presses back; closing the window cancels and returns everything.

const COLS := 3
const GAP := 4.0
const GRID_Y := 66.0
const GRID_W := COLS * (SLOT + GAP) - GAP
const RIGHT_X := PAD + GRID_W + 30

## The server's last word: {"partner", "mine": {...}, "theirs": {...}} (see TDSocial).
var state := {}

func _init() -> void:
	super("Trade", Vector2(RIGHT_X + GRID_W + PAD, GRID_Y + 3 * (SLOT + GAP) + 110))

func show_state(s: Dictionary) -> void:
	var was_open := not state.is_empty()
	state = s
	if s.is_empty():
		visible = false
		hud.tooltip.clear(self)
		return
	title = "Trade with %s" % s["partner"]
	if not was_open:
		position = Vector2(TDWorld.VIEW.x / 2.0 - size.x - 10, 70)
		hud.windows["inventory"].visible = true
		hud.windows["inventory"].position = Vector2(TDWorld.VIEW.x / 2.0 + 10, 70)
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
	return Rect2((RIGHT_X if theirs else PAD) + (i % COLS) * (SLOT + GAP), GRID_Y + (i / COLS) * (SLOT + GAP), SLOT, SLOT)

func _stack(side: String, i: int) -> ItemStack:
	var items: Array = state.get(side, {}).get("items", [])
	return ItemStack.from_dict(items[i]) if i < items.size() else null

func _shards_rect() -> Rect2:
	return Rect2(PAD, GRID_Y + 3 * (SLOT + GAP) + 6, GRID_W, 24)

func _trade_rect() -> Rect2:
	return Rect2(PAD, size.y - 44, (size.x - PAD * 2 - 8) / 2.0, 32)

func _cancel_rect() -> Rect2:
	var r := _trade_rect()
	return Rect2(r.end.x + 8, r.position.y, r.size.x, r.size.y)

func _draw_body() -> void:
	if state.is_empty():
		return
	for side in ["mine", "theirs"]:
		var theirs: bool = side == "theirs"
		var d: Dictionary = state[side]
		var x := RIGHT_X if theirs else PAD
		DrawUtil.text(self, Game.ui_font, Vector2(x, GRID_Y - 8), "Them" if theirs else "You", 12, Color("c9b8d9"), 1, 3, Palette.NIGHT)
		if d["ready"]:
			DrawUtil.text(self, Game.ui_font, Vector2(x + GRID_W, GRID_Y - 8), "Ready!", 12, Color("8cf0a6"), -1, 3, Palette.NIGHT)
		for i in COLS * 3:
			draw_slot(slot_rect(i, theirs), _stack(side, i))
		var sr := Rect2(x, _shards_rect().position.y, GRID_W, 24)
		DrawUtil.round_rect(self, sr, 5, Color(Palette.NIGHT, 0.4 if theirs or not sr.has_point(_hover) else 0.6))
		draw_texture_rect(UiSkin.tex("icon_dawnshard"), Rect2(sr.position + Vector2(4, 3), Vector2(20, 18)), false)
		DrawUtil.text(self, Game.num_font, sr.position + Vector2(30, 18), str(d["shards"]), 14, Palette.SUN, 1, 4, Palette.NIGHT)
		if not theirs:
			DrawUtil.text(self, Game.ui_font, sr.end + Vector2(-6, -7), "click to set", 9, Color("c9b8d9"), -1)
	draw_button(_trade_rect(), "Trade", not state["mine"]["ready"])
	draw_button(_cancel_rect(), "Cancel")

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT or state.is_empty():
		return
	if _trade_rect().has_point(at):
		Net.ask(&"req_trade_ready")
	elif _cancel_rect().has_point(at):
		cancel()
	elif _shards_rect().has_point(at):
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
	return data is Dictionary and data.get("from") == "inventory" and Rect2(PAD, GRID_Y, GRID_W, GRID_W).has_point(at)

func _drop_data(_at: Vector2, data: Variant) -> void:
	offer(data["tab"], data["index"])

## Puts the whole stack in bag slot `index` of `tab` on the table.
func offer(tab: int, index: int) -> void:
	Net.ask(&"req_trade_offer", [tab, index, -1])
