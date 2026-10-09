extends TestCase
## Player shops in the Free Market: opening one (only on a market map, not too close to
## another), browsing, buying, prices, and closing with the unsold things going back.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var ann: SimPlayer
var bob: SimPlayer
var leaf: ItemDef
var red: ItemDef

func before_each() -> void:
	h = ServerHarness.new()
	var market := ServerHarness.town_def(ServerHarness.MARKET)
	market.market = true
	h.add_map(market)
	leaf = Content.item(&"green_leaf")
	red = Content.item(&"red_potion")
	ann = h.join(2, "Ann", ServerHarness.MARKET, 300.0)
	bob = h.join(3, "Bob", ServerHarness.MARKET, 500.0)
	ann.character.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 10))
	bob.character.shards = 1000

func after_each() -> void:
	h.close()

## Ann puts 6 leaves up for 300 and 2 red potions for 20.
func _open() -> void:
	h.ask(2, &"req_shop_open", ["Leaf Stall", [[ItemDef.Tab.ETC, 0, 6, 300], [ItemDef.Tab.USE, 0, 2, 20]]])

func test_shops_open_only_in_the_free_market() -> void:
	h.move_to(ann, ServerHarness.TOWN)
	_open()
	check(not h.server.social.shops.has(2), "no shop")
	check(h.told(2, "Shops can only be opened in the Free Market."), "told")

func test_opening_puts_the_things_on_sale() -> void:
	var reds := ann.character.inventory.count_of(red)
	_open()
	check(h.server.social.shops.has(2), "open")
	check_eq(ann.character.inventory.count_of(leaf), 4, "six leaves on sale")
	check_eq(ann.character.inventory.count_of(red), reds - 2, "two potions on sale")
	var ev := h.last(2, &"ev_player_shop")
	check_eq(ev.slice(0, 3), [2, "Ann", "Leaf Stall"], "owner sees the shop")
	check_eq(ev[3], [[{"id": "green_leaf", "count": 6}, 300], [{"id": "red_potion", "count": 2}, 20]], "items and prices")

func test_the_shop_sign_shows_in_snapshots() -> void:
	_open()
	h.step(TDServer.SNAPSHOT_EVERY)
	var rows: Array = h.last(3, &"ev_snapshot")[0]["players"]
	var ann_row: Array = rows.filter(func(r: Array) -> bool: return r[0] == 2)[0]
	check_eq(ann_row[-1], "Leaf Stall", "sign over Ann")

func test_an_empty_title_names_the_shop_after_its_owner() -> void:
	h.ask(2, &"req_shop_open", ["   ", [[ItemDef.Tab.ETC, 0, 1, 5]]])
	check_eq(h.server.social.shop_title(2), "Ann's Shop", "default title")

func test_browsing_a_shop() -> void:
	_open()
	h.ask(3, &"req_shop_view", [2])
	check_eq(h.last(3, &"ev_player_shop").slice(0, 3), [2, "Ann", "Leaf Stall"], "Bob sees it")

func test_buying_pays_the_owner_and_moves_the_item() -> void:
	_open()
	h.ask(3, &"req_shop_view", [2])
	h.ask(3, &"req_shop_buy", [2, 0, &"green_leaf"])
	check_eq(bob.character.shards, 700, "Bob paid 300")
	check_eq(ann.character.shards, 300, "Ann got 300")
	check_eq(bob.character.inventory.count_of(leaf), 6, "Bob has the leaves")
	check_eq((h.last(3, &"ev_player_shop")[3] as Array).size(), 1, "one thing left on sale")
	check_eq(int(ann.character.counters.get("deals", 0)), 1, "deal counted for Ann")
	check_eq(int(bob.character.counters.get("deals", 0)), 1, "and for Bob")

func test_not_enough_dawnshards_buys_nothing() -> void:
	_open()
	bob.character.shards = 299
	h.ask(3, &"req_shop_buy", [2, 0, &"green_leaf"])
	check_eq(bob.character.shards, 299, "kept")
	check_eq(bob.character.inventory.count_of(leaf), 0, "no leaves")
	check(h.told(3, "You need 300 Dawnshards."), "told")

func test_a_stale_listing_buys_nothing() -> void:
	_open()
	h.ask(3, &"req_shop_buy", [2, 0, &"red_potion"])
	check_eq(bob.character.shards, 1000, "the item at 0 isn't a potion: nothing bought")

func test_you_cant_buy_from_yourself() -> void:
	_open()
	ann.character.shards = 1000
	h.ask(2, &"req_shop_buy", [2, 0, &"green_leaf"])
	check_eq(ann.character.shards, 1000, "nothing")

func test_selling_out_closes_the_shop() -> void:
	_open()
	h.ask(3, &"req_shop_view", [2])
	h.ask(3, &"req_shop_buy", [2, 1, &"red_potion"])
	h.ask(3, &"req_shop_buy", [2, 0, &"green_leaf"])
	check(not h.server.social.shops.has(2), "closed")
	check_eq(ann.character.shards, 320, "paid for both")
	check_eq(h.last(3, &"ev_player_shop"), [2, "", "", []], "Bob's window closes")

func test_closing_hands_back_what_didnt_sell() -> void:
	var reds := ann.character.inventory.count_of(red)
	_open()
	h.ask(3, &"req_shop_buy", [2, 1, &"red_potion"])
	h.ask(2, &"req_shop_leave", [2])
	check(not h.server.social.shops.has(2), "closed")
	check_eq(ann.character.inventory.count_of(leaf), 10, "leaves back")
	check_eq(ann.character.inventory.count_of(red), reds - 2, "the sold potions stay sold")
	check(h.told(2, "Your shop is closed."), "told")

func test_leaving_the_game_closes_the_shop_and_keeps_the_things() -> void:
	_open()
	h.leave(2)
	check(not h.server.social.shops.has(2), "closed")
	check_eq(h.server.store.load_character("Ann").inventory.count_of(leaf), 10, "saved with the leaves")

func test_shop_keepers_stay_put() -> void:
	_open()
	h.step(10)
	h.ask(2, &"req_move", [Vector2(340, 600), 1, &"walk", false])
	check_eq(ann.position.x, 300.0, "didn't move")
	check_eq(h.last(2, &"ev_place"), [300.0, 600.0], "put back")

func test_shops_cant_be_opened_too_close_together() -> void:
	_open()
	bob.character.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 1))
	h.place(bob, 389.0)
	h.ask(3, &"req_shop_open", ["Bob's", [[ItemDef.Tab.ETC, 0, 1, 5]]])
	check(not h.server.social.shops.has(3), "too close")
	check(h.told(3, "You're too close to Ann's shop."), "told")
	h.place(bob, 390.0)
	h.ask(3, &"req_shop_open", ["Bob's", [[ItemDef.Tab.ETC, 0, 1, 5]]])
	check(h.server.social.shops.has(3), "90 px away is fine")

func test_a_bad_entry_moves_nothing() -> void:
	var token := ItemDef.new()
	token.id = &"test_token"
	token.quest_item = true
	ann.character.inventory.put(ItemDef.Tab.ETC, 1, ItemStack.create(token, 1))
	h.ask(2, &"req_shop_open", ["Stall", [[ItemDef.Tab.ETC, 0, 6, 300], [ItemDef.Tab.ETC, 1, 1, 50]]])
	check(not h.server.social.shops.has(2), "not opened")
	check_eq(ann.character.inventory.count_of(leaf), 10, "the good entry didn't move either")
	check(h.told(2, "Something on your list can't be sold."), "told")

func test_a_free_price_is_refused() -> void:
	h.ask(2, &"req_shop_open", ["Stall", [[ItemDef.Tab.ETC, 0, 6, 0]]])
	check(not h.server.social.shops.has(2), "not opened")

func test_too_many_entries_are_refused() -> void:
	var entries := []
	for i in TDSocial.SHOP_SLOTS + 1:
		entries.append([ItemDef.Tab.ETC, 0, 1, 5])
	h.ask(2, &"req_shop_open", ["Stall", entries])
	check(not h.server.social.shops.has(2), "not opened")
	check(h.told(2, "Put up 1 to 12 things for sale."), "told")

func test_the_shop_closes_when_its_owner_leaves_the_market() -> void:
	_open()
	h.move_to(ann, ServerHarness.TOWN)
	check(not h.server.social.shops.has(2), "the shop doesn't follow its owner out of the market")
	check_eq(ann.character.inventory.count_of(leaf), 10, "unsold leaves back")
