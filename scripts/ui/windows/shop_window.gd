class_name TDShopWindow
extends TDWindow
## A shop: what the shopkeeper sells on the left, your bag on the right. Double-click a
## line to buy, or one of your items to sell it, in the amount picked at the bottom (1, 10
## or 100). Items also sell when dragged here or double-clicked in the Inventory window while
## the shop is open; gear asks first. Only the lines you've unlocked show (ShopEntry.open_to).
## Buying and selling are requests the server answers.
## Closes when you walk away.

const ROW_H := 44.0
const LIST_W := 262.0
const LIST_Y := 44.0
const ROWS := 8
const GRID_X := PAD + LIST_W + 18
const COLS := 4
const GAP := 4.0
const GRID_Y := 74.0
const AMOUNTS: Array[int] = [1, 10, 100]
## Pixels per art pixel of the shop row and amount chip art, and where the row art's item niche is.
const ROW_SCALE := (ROW_H - 4) / 63.0
const NICHE := Rect2(11, 10, 42, 42)
const CHIP_SCALE := 0.68
## The amount chips: wide enough for "×100" between the art's end caps.
const CHIP_W := 62.0
const CHIP_CAPS := 2 * 20 * CHIP_SCALE
## Under your bag: how to sell (two lines to fit the bag's width).
const SELL_HINT: Array[String] = ["Double-click or drag", "your items here to sell"]

var npc: TDNpc
var shop: ShopDef
var tab := ItemDef.Tab.USE
var amount := 1
## The shopkeeper's lines, and your bag beside them.
var list := ScrollList.new(Vector2(PAD, LIST_Y), LIST_W, ROW_H, 4, ROWS)
var grid := SlotGrid.new(Vector2(GRID_X, GRID_Y), COLS, Inventory.SLOTS, SLOT, GAP)

func _init() -> void:
	super("Shop", Vector2(GRID_X + COLS * (SLOT + GAP) - GAP + PAD, LIST_Y + ROWS * ROW_H + 70))

func open(who: TDNpc) -> void:
	npc = who
	shop = who.def.shop
	title = shop.display_name if shop.display_name != "" else "%s's Shop" % who.def.display_name
	list.scroll = 0
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -30)
	visible = true
	raise()

func _process(delta: float) -> void:
	super(delta)
	if visible and walked_away_from(npc):
		visible = false
		hud.tooltip.clear(self)

## The places in shop.items of the lines shown, in order.
func shown() -> Array[int]:
	return shop.open_to(Game.me) if shop else []

# ---------- layout ----------

func row_rect(i: int) -> Rect2:
	return list.row_rect(i)

func _amount_rect(i: int) -> Rect2:
	return Rect2(PAD + 78 + i * (CHIP_W + 6), size.y - 42, CHIP_W, 28)

func _sell_etc_rect() -> Rect2:
	return Rect2(size.x - PAD - 132, size.y - 46, 132, 34)

# ---------- drawing ----------

func _draw_body() -> void:
	if shop == null:
		return
	var shards := Game.me.shards
	var lines := shown()
	for i in list.shown(lines.size()):
		var e := shop.items[lines[i]]
		var r := row_rect(i)
		UiSkin.draw_box(self, UiSkin.shop_row(r.has_point(_hover)), r, ROW_SCALE)
		if e.item.icon:
			draw_texture_rect(e.item.icon, fit(e.item.icon, Rect2(r.position + NICHE.position * ROW_SCALE, NICHE.size * ROW_SCALE).grow(-1)), false)
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + SLOT + 8, r.position.y + 17), e.item.display_name, 13, Palette.MIST, 1, 3, Palette.NIGHT)
		var afford := shards >= e.cost()
		DrawUtil.text(self, Game.num_font, Vector2(r.position.x + SLOT + 8, r.position.y + 35), "%d" % e.cost(), 13,
			Palette.SUN if afford else Palette.BAD, 1, 3, Palette.NIGHT)
	list.draw_more(self, lines.size())
	draw_tabs(ItemDef.TAB_NAMES, tab, TAB_Y, GRID_X)
	for i in Inventory.SLOTS:
		draw_slot(grid.rect(i), Game.me.inventory.at(tab, i))
	# amount, Dawnshards and Sell all Etc
	DrawUtil.text(self, Game.ui_font, Vector2(PAD, size.y - 22), "Amount", 12, Palette.MUTED, 1)
	for i in AMOUNTS.size():
		var r := _amount_rect(i)
		var on := AMOUNTS[i] == amount
		UiSkin.draw_box(self, UiSkin.amount_chip(on), r, CHIP_SCALE)
		var label := "×%d" % AMOUNTS[i]
		DrawUtil.text(self, Game.num_font, r.get_center() + Vector2(0, 5), label, DrawUtil.fit_size(Game.num_font, label, 13, CHIP_W - CHIP_CAPS), Palette.INK if on else Palette.MIST, 0, 0 if on else 3, Palette.NIGHT)
	var purse_y := GRID_Y + grid.rows() * (SLOT + GAP) + 8
	draw_shards(Vector2(GRID_X, purse_y + 16), shards)
	for i in SELL_HINT.size():
		DrawUtil.text(self, Game.ui_font, Vector2(GRID_X, purse_y + 40 + i * 15), SELL_HINT[i],
			DrawUtil.fit_size(Game.ui_font, SELL_HINT[i], 12, size.x - PAD - GRID_X), Palette.MUTED, 1)
	draw_button(_sell_etc_rect(), "Sell all Etc", Game.me.inventory.free_slots(ItemDef.Tab.ETC) < Inventory.SLOTS)

# ---------- input ----------

func _click(at: Vector2, button: int, double: bool) -> void:
	var lines := shown()
	if list.wheel(button, lines.size()) or button != MOUSE_BUTTON_LEFT:
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
	var row := list.row_at(at, lines.size())
	if row >= 0:
		buy(lines[row])
		return
	var slot := grid.at(at)
	if slot >= 0:
		sell(slot)

func _tab_clicked(i: int) -> void:
	tab = i as ItemDef.Tab

## Asks to buy the current amount of shop.items[`i`].
func buy(i: int) -> void:
	Net.ask(&"req_buy", [npc.def.id, i, amount])

## Asks to sell the current amount from bag slot `i` of the open tab.
func sell(i: int) -> void:
	sell_from(tab, i)

## Asks to sell the current amount from bag slot `i` of tab `from_tab`. Gear asks first,
## since a piece sold is gone for good.
func sell_from(from_tab: int, i: int) -> void:
	var held := Game.me.inventory.at(from_tab, i)
	if held == null or npc == null:
		return
	hud.tooltip.clear(self)
	var ask_server := func() -> void: Net.ask(&"req_sell", [npc.def.id, from_tab, i, amount])
	if from_tab != ItemDef.Tab.EQUIP:
		ask_server.call()
		return
	hud.confirm.open("Sell %s for %d Dawnshards?" % [held.display_name(), held.item.sell_price], "Sell", func() -> void:
		# only if the same piece is still there and the shop still open
		var now := Game.me.inventory.at(from_tab, i)
		if visible and now and now.item == held.item:
			ask_server.call())

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return DragPayload.is_bag_item(data)

func _drop_data(_at: Vector2, data: Variant) -> void:
	var d := DragPayload.of(data)
	sell_from(d.tab, d.index)

func _tooltip_at(at: Vector2) -> Tip:
	var lines := shown()
	var row := list.row_at(at, lines.size())
	if row >= 0:
		var e := shop.items[lines[row]]
		return Tip.new(ItemStack.unrolled(e.item), "Double-click to buy (%d Dawnshards each)" % e.cost(), true)
	var slot := grid.at(at)
	var stack := Game.me.inventory.at(tab, slot) if slot >= 0 else null
	return Tip.new(stack, "Double-click to sell (%d each)" % stack.item.sell_price if stack else "")
