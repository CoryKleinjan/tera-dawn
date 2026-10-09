class_name TDPlayerShopWindow
extends TDWindow
## Player shops in the Free Market. Setting one up (from the Market Clerk): drag things
## from your bag onto the list, give each a price, name the shop and open it; you stand
## behind it until you close it. Other players click you to browse and buy. Unsold
## things come back when the shop closes.

const ROW_H := 40.0
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
	super("Shop", Vector2(330, LIST_Y + ROWS * ROW_H + 60))

## Starts setting up a shop of your own.
func setup() -> void:
	mode = Mode.SETUP
	owner_peer = multiplayer.get_unique_id()
	shop_title = "%s's Shop" % Game.me.name
	entries.clear()
	title = "Set up your shop"
	place_beside_inventory(60)
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
	return Rect2(PAD, LIST_Y + i * ROW_H, size.x - PAD * 2, ROW_H - 4)

func _stack(i: int) -> ItemStack:
	if mode == Mode.SETUP:
		return Game.me.inventory.at(entries[i][0], entries[i][1])
	return ItemStack.from_dict(entries[i][0])

func _price(i: int) -> int:
	return entries[i][3] if mode == Mode.SETUP else entries[i][1]

func _draw_body() -> void:
	draw_label(Vector2(PAD, 48), shop_title if mode == Mode.SETUP else "", Palette.SUN, 13)
	if entries.is_empty():
		draw_hint(Vector2(size.x / 2.0, LIST_Y + 40), "Drag things from your bag here" if mode == Mode.SETUP else "Sold out", 0)
	for k in mini(ROWS, entries.size()):
		var i := k + scroll
		if i >= entries.size():
			break
		var r := _row(k)
		var stack := _stack(i)
		var k_art := r.size.y / UiSkin.tex("dialogue/shop_row").get_height()
		UiSkin.draw_box(self, UiSkin.shop_row(r.has_point(_hover)), r, k_art)
		if stack and stack.item.icon:
			var niche := Rect2(r.position + TDShopWindow.NICHE.position * k_art, TDShopWindow.NICHE.size * k_art)
			draw_texture_rect(stack.item.icon, fit(stack.item.icon, niche.grow(-1)), false)
		if mode == Mode.VISITOR:
			add_button(_buy_rect(k), "Buy", buy.bind(i), Game.me.shards >= _price(i))
		elif mode == Mode.SETUP:
			add_button(_buy_rect(k), "Remove", func() -> void: entries.remove_at(i))
		if stack == null:
			continue
		var n: int = entries[i][2] if mode == Mode.SETUP else stack.count
		draw_label(r.position + Vector2(46, 16), stack.display_name() + (" ×%d" % n if n > 1 else ""), Palette.MIST, 13)
		DrawUtil.text(self, Game.num_font, r.position + Vector2(46, 32), "%d Dawnshards" % _price(i), 12, Palette.SUN, 1, 3, Palette.NIGHT)
	var w := (size.x - PAD * 2 - 8) / 2.0
	var left := Rect2(PAD, size.y - 44, w, 32)
	var right := Rect2(left.end.x + 8, left.position.y, w, 32)
	match mode:
		Mode.SETUP:
			add_button(left, "Name", _rename)
			add_button(right, "Open shop", open_shop, not entries.is_empty())
		Mode.OWNER:
			add_button(right, "Close shop", toggle)

func _buy_rect(k: int) -> Rect2:
	var r := _row(k)
	return Rect2(r.end.x - 74, r.position.y + 4, 70, 28)

func _click(_at: Vector2, button: int, _double: bool) -> void:
	if button == MOUSE_BUTTON_WHEEL_DOWN:
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
