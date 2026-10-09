class_name TDPlayerShopWindow
extends TDWindow
## Player shops in the Free Market. Setting one up (from the Market Clerk): drag things
## from your bag onto the list, give each a price, name the shop and open it; you stand
## behind it until you close it. Other players click you to browse and buy. Unsold
## things come back when the shop closes.

const ROW := 40.0
const LIST_Y := 64.0
const ROWS := 6

enum Mode { SETUP, OWNER, VISITOR }

var mode := Mode.SETUP
var owner_peer := 0
var shop_title := ""
## SETUP: [tab, slot, count, price] entries. OWNER / VISITOR: [stack dict, price].
var entries: Array = []
var scroll := 0

func _init() -> void:
	super("Shop", Vector2(330, LIST_Y + ROWS * ROW + 60))

## Starts setting up a shop of your own.
func setup() -> void:
	mode = Mode.SETUP
	owner_peer = multiplayer.get_unique_id()
	shop_title = "%s's Shop" % Game.me.name
	entries.clear()
	title = "Set up your shop"
	position = Vector2(TDWorld.VIEW.x / 2.0 - size.x - 10, 60)
	hud.windows["inventory"].visible = true
	hud.windows["inventory"].position = Vector2(TDWorld.VIEW.x / 2.0 + 10, 60)
	visible = true
	raise()

## The server's view of a shop (empty `items` with no title means it closed).
func show_shop(owner: int, owner_name: String, t: String, items: Array) -> void:
	if t == "" and items.is_empty():
		if owner == owner_peer and visible and mode != Mode.SETUP:
			visible = false
		return
	owner_peer = owner
	mode = Mode.OWNER if owner == multiplayer.get_unique_id() else Mode.VISITOR
	shop_title = t
	entries = items
	title = t if mode == Mode.OWNER else "%s (%s)" % [t, owner_name]
	if not visible:
		position = Vector2((TDWorld.VIEW.x - size.x) / 2.0, 60)
	visible = true
	raise()

func selling() -> bool:
	return visible and mode == Mode.OWNER

func toggle() -> void:
	if visible and mode != Mode.SETUP:
		Net.ask(&"req_shop_leave", [owner_peer])
	super()

func _row(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + i * ROW, size.x - PAD * 2, ROW - 4)

func _stack(i: int) -> ItemStack:
	if mode == Mode.SETUP:
		var e: Array = entries[i]
		var held := Game.me.inventory.at(e[0], e[1])
		return held
	return ItemStack.from_dict(entries[i][0])

func _price(i: int) -> int:
	return entries[i][3] if mode == Mode.SETUP else entries[i][1]

func _buttons() -> Array:
	var w := (size.x - PAD * 2 - 8) / 2.0
	var a := Rect2(PAD, size.y - 44, w, 32)
	var b := Rect2(a.end.x + 8, a.position.y, w, 32)
	match mode:
		Mode.SETUP:
			return [[a, "Name", _rename], [b, "Open shop", open_shop]]
		Mode.OWNER:
			return [[b, "Close shop", func() -> void: toggle()]]
	return []

func _draw_body() -> void:
	DrawUtil.text(self, Game.ui_font, Vector2(PAD, 48), shop_title if mode == Mode.SETUP else "", 13, Palette.SUN, 1, 3, Palette.NIGHT)
	if entries.is_empty():
		DrawUtil.text(self, Game.ui_font, Vector2(size.x / 2.0, LIST_Y + 40), "Drag things from your bag here" if mode == Mode.SETUP else "Sold out", 12, Color("c9b8d9"), 0, 3, Palette.NIGHT)
	for k in mini(ROWS, entries.size()):
		var i := k + scroll
		if i >= entries.size():
			break
		var r := _row(k)
		DrawUtil.round_rect(self, r, 6, Color(Palette.NIGHT, 0.32))
		var stack := _stack(i)
		draw_slot(Rect2(r.position + Vector2(2, 0), Vector2(36, 36)), stack)
		if stack == null:
			continue
		var n: int = entries[i][2] if mode == Mode.SETUP else stack.count
		DrawUtil.text(self, Game.ui_font, r.position + Vector2(46, 16), stack.display_name() + (" ×%d" % n if n > 1 else ""), 13, Palette.MIST, 1, 3, Palette.NIGHT)
		DrawUtil.text(self, Game.num_font, r.position + Vector2(46, 32), "%d Dawnshards" % _price(i), 12, Palette.SUN, 1, 3, Palette.NIGHT)
		if mode == Mode.VISITOR:
			draw_button(_buy_rect(k), "Buy", Game.me.shards >= _price(i))
		elif mode == Mode.SETUP:
			draw_button(_buy_rect(k), "Remove")
	for b in _buttons():
		draw_button(b[0], b[1], mode != Mode.SETUP or b[1] != "Open shop" or not entries.is_empty())

func _buy_rect(k: int) -> Rect2:
	var r := _row(k)
	return Rect2(r.end.x - 74, r.position.y + 4, 70, 28)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button == MOUSE_BUTTON_LEFT:
		for k in mini(ROWS, entries.size() - scroll):
			if _buy_rect(k).has_point(at):
				var i := k + scroll
				if mode == Mode.VISITOR:
					buy(i)
				elif mode == Mode.SETUP:
					entries.remove_at(i)
				return
		for b in _buttons():
			if (b[0] as Rect2).has_point(at):
				(b[2] as Callable).call()
				return
	elif button == MOUSE_BUTTON_WHEEL_DOWN:
		scroll = clampi(scroll + 1, 0, maxi(0, entries.size() - ROWS))
	elif button == MOUSE_BUTTON_WHEEL_UP:
		scroll = maxi(0, scroll - 1)

func buy(i: int) -> void:
	Net.ask(&"req_shop_buy", [owner_peer, i, StringName(entries[i][0]["id"])])

func _rename() -> void:
	hud.prompt.ask("Name your shop", shop_title, func(t: String) -> void: shop_title = t)

func open_shop() -> void:
	if not entries.is_empty():
		Net.ask(&"req_shop_open", [shop_title, entries.duplicate(true)])

## Adds bag slot `index` of `tab` to the list at `price`.
func add_entry(tab: int, index: int, price: int) -> void:
	var held := Game.me.inventory.at(tab, index)
	if held == null or entries.size() >= TDSocial.SHOP_SLOTS or entries.any(func(e: Array) -> bool: return e[0] == tab and e[1] == index):
		return
	entries.append([tab, index, held.count, maxi(1, price)])

func _hovered(at: Vector2) -> void:
	for k in mini(ROWS, entries.size() - scroll):
		if _row(k).has_point(at):
			hud.tooltip.show_item(self, _stack(k + scroll), get_global_mouse_position())
			return
	hud.tooltip.clear(self)

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return mode == Mode.SETUP and data is Dictionary and data.get("from") == "inventory"

func _drop_data(_at: Vector2, data: Variant) -> void:
	var tab: int = data["tab"]
	var index: int = data["index"]
	var held := Game.me.inventory.at(tab, index)
	if held == null:
		return
	hud.prompt.ask("Price for %s" % held.display_name(), str(maxi(1, held.item.sell_price * held.count * 2)), func(t: String) -> void:
		add_entry(tab, index, int(t)), true)
