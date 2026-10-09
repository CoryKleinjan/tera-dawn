class_name TDShopWindow
extends TDWindow
## A shop: what the shopkeeper sells on the left, your bag on the right. Double-click a
## line to buy, or one of your items to sell it, in the amount picked at the bottom (1, 10
## or 100). Buying and selling are requests the server answers. Closes when you walk away.

const ROW_H := 44.0
const LIST_W := 262.0
const LIST_Y := 44.0
const ROWS := 8
const GRID_X := PAD + LIST_W + 18
const COLS := 4
const GAP := 4.0
const GRID_Y := 74.0
const AMOUNTS: Array[int] = [1, 10, 100]
const REACH := 170.0
## Pixels per texel of the shop row and amount chip art, and where the row art's item niche is.
const ROW_SCALE := (ROW_H - 4) / 63.0
const NICHE := Rect2(11, 10, 42, 42)
const CHIP_SCALE := 0.68

var npc: TDNpc
var shop: ShopDef
var tab := ItemDef.Tab.USE
var amount := 1
var scroll := 0

func _init() -> void:
	super("Shop", Vector2(GRID_X + COLS * (SLOT + GAP) - GAP + PAD, LIST_Y + ROWS * ROW_H + 70))

func open(who: TDNpc) -> void:
	npc = who
	shop = who.def.shop
	title = shop.display_name if shop.display_name != "" else "%s's Shop" % who.def.display_name
	scroll = 0
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -30)
	visible = true
	raise()

func _process(delta: float) -> void:
	super(delta)
	if visible and (npc == null or not is_instance_valid(npc) or hud.world.player.position.distance_to(npc.position) > REACH):
		visible = false
		hud.tooltip.clear(self)

# ---------- layout ----------

func row_rect(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + (i - scroll) * ROW_H, LIST_W, ROW_H - 4)

func _row_at(at: Vector2) -> int:
	for i in range(scroll, mini(scroll + ROWS, shop.items.size())):
		if row_rect(i).has_point(at):
			return i
	return -1

func slot_rect(i: int) -> Rect2:
	return Rect2(GRID_X + (i % COLS) * (SLOT + GAP), GRID_Y + (i / COLS) * (SLOT + GAP), SLOT, SLOT)

func _slot_at(at: Vector2) -> int:
	for i in Inventory.SLOTS:
		if slot_rect(i).has_point(at):
			return i
	return -1

func _amount_rect(i: int) -> Rect2:
	return Rect2(PAD + 78 + i * 52, size.y - 42, 46, 28)

func _sell_etc_rect() -> Rect2:
	return Rect2(size.x - PAD - 132, size.y - 46, 132, 34)

# ---------- drawing ----------

func _draw_body() -> void:
	if shop == null:
		return
	var shards := Game.me.shards
	for i in range(scroll, mini(scroll + ROWS, shop.items.size())):
		var e := shop.items[i]
		var r := row_rect(i)
		UiSkin.draw_box(self, UiSkin.shop_row(r.has_point(_hover)), r, ROW_SCALE)
		if e.item.icon:
			draw_texture_rect(e.item.icon, fit(e.item.icon, Rect2(r.position + NICHE.position * ROW_SCALE, NICHE.size * ROW_SCALE).grow(-1)), false)
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + SLOT + 8, r.position.y + 17), e.item.display_name, 13, Palette.MIST, 1, 3, Palette.NIGHT)
		var afford := shards >= e.cost()
		DrawUtil.text(self, Game.num_font, Vector2(r.position.x + SLOT + 8, r.position.y + 35), "%d" % e.cost(), 13,
			Palette.SUN if afford else Palette.BAD, 1, 3, Palette.NIGHT)
	if shop.items.size() > ROWS:
		DrawUtil.text(self, Game.ui_font, Vector2(PAD + LIST_W, LIST_Y + ROWS * ROW_H + 8), "scroll for more (%d/%d)" % [scroll + 1, shop.items.size() - ROWS + 1], 10, Color(Palette.MIST, 0.6), -1)
	draw_tabs(ItemDef.TAB_NAMES, tab, TAB_Y, GRID_X)
	for i in Inventory.SLOTS:
		draw_slot(slot_rect(i), Game.me.inventory.at(tab, i))
	# amount, Dawnshards and Sell all Etc
	DrawUtil.text(self, Game.ui_font, Vector2(PAD, size.y - 22), "Amount", 12, Palette.MUTED, 1)
	for i in AMOUNTS.size():
		var r := _amount_rect(i)
		var on := AMOUNTS[i] == amount
		UiSkin.draw_box(self, UiSkin.amount_chip(on), r, CHIP_SCALE)
		DrawUtil.text(self, Game.num_font, r.get_center() + Vector2(0, 5), "×%d" % AMOUNTS[i], 13, Palette.INK if on else Palette.MIST, 0, 0 if on else 3, Palette.NIGHT)
	var purse_y := GRID_Y + ceili(Inventory.SLOTS / float(COLS)) * (SLOT + GAP) + 8
	draw_shards(Vector2(GRID_X, purse_y + 16), shards)
	draw_button(_sell_etc_rect(), "Sell all Etc", Game.me.inventory.free_slots(ItemDef.Tab.ETC) < Inventory.SLOTS)

# ---------- input ----------

func _click(at: Vector2, button: int, double: bool) -> void:
	if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
		var most := maxi(0, shop.items.size() - ROWS)
		scroll = clampi(scroll + (1 if button == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, most)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	var t := tab_at(at)
	if t >= 0:
		tab = t as ItemDef.Tab
		return
	for i in AMOUNTS.size():
		if _amount_rect(i).has_point(at):
			amount = AMOUNTS[i]
			return
	if _sell_etc_rect().has_point(at):
		Net.ask(&"req_sell_all_etc", [npc.def.id])
		return
	if not double:
		return
	var row := _row_at(at)
	if row >= 0:
		buy(row)
		return
	var slot := _slot_at(at)
	if slot >= 0:
		sell(slot)

## Asks to buy the current amount of line `i`.
func buy(i: int) -> void:
	Net.ask(&"req_buy", [npc.def.id, i, amount])

## Asks to sell the current amount from bag slot `i` of the open tab.
func sell(i: int) -> void:
	if Game.me.inventory.at(tab, i):
		Net.ask(&"req_sell", [npc.def.id, tab, i, amount])
		hud.tooltip.clear(self)

func _hovered(at: Vector2) -> void:
	var row := _row_at(at)
	if row >= 0:
		var e := shop.items[row]
		hud.tooltip.show_item(self, ItemStack.unrolled(e.item), get_global_mouse_position(), "Double-click to buy (%d Dawnshards each)" % e.cost(), true)
		return
	var slot := _slot_at(at)
	var stack := Game.me.inventory.at(tab, slot) if slot >= 0 else null
	var hint := "Double-click to sell (%d each)" % stack.item.sell_price if stack else ""
	hud.tooltip.show_item(self, stack, get_global_mouse_position(), hint)
