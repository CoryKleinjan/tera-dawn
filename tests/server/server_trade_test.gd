extends TestCase
## Trading through the server: offers are held by the server, nothing changes hands until
## both press Trade, changing the offer un-readies both, and cancelling (or leaving)
## hands everything back.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var ann: SimPlayer
var bob: SimPlayer
var leaf: ItemDef

func before_each() -> void:
	h = ServerHarness.new()
	leaf = Content.item(&"green_leaf")
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	bob = h.join(3, "Bob", ServerHarness.FIELD, 400.0)
	ann.character.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 10))
	bob.character.shards = 500
	h.ask(2, &"req_social", [&"trade", "Bob"])
	h.ask(3, &"req_invite_answer", [h.last(3, &"ev_invite")[0], true])

func after_each() -> void:
	h.close()

func _state(peer: int) -> Dictionary:
	return h.last(peer, &"ev_trade")[0]

func test_accepting_opens_the_trade_for_both() -> void:
	check(h.server.social.trades.has(2) and h.server.social.trades.has(3), "trade open")
	check_eq(_state(2)["partner"], "Bob", "Ann trades with Bob")
	check_eq(_state(3)["partner"], "Ann", "Bob trades with Ann")

func test_offered_items_leave_the_bag_and_show_on_both_sides() -> void:
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 0, 4])
	check_eq(ann.character.inventory.count_of(leaf), 6, "four on the table")
	check_eq(_state(2)["mine"]["items"], [{"id": "green_leaf", "count": 4}], "Ann's side")
	check_eq(_state(3)["theirs"]["items"], [{"id": "green_leaf", "count": 4}], "what Bob sees")

func test_nothing_changes_hands_until_both_press_trade() -> void:
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 0, 4])
	h.ask(3, &"req_trade_shards", [120])
	h.ask(2, &"req_trade_ready")
	check_eq(bob.character.inventory.count_of(leaf), 0, "Bob has no leaves yet")
	check_eq(ann.character.shards, 0, "Ann has no Dawnshards yet")
	check(_state(3)["theirs"]["ready"], "Bob sees Ann is ready")
	h.ask(3, &"req_trade_ready")
	check_eq(bob.character.inventory.count_of(leaf), 4, "Bob got the leaves")
	check_eq(ann.character.inventory.count_of(leaf), 6, "Ann kept the rest")
	check_eq(ann.character.shards, 120, "Ann got the Dawnshards")
	check_eq(bob.character.shards, 380, "Bob paid")
	check(h.server.social.trades.is_empty(), "trade over")
	check_eq(h.last(2, &"ev_trade"), [{}], "Ann's window closes")
	check_eq(h.last(3, &"ev_trade"), [{}], "Bob's window closes")

func test_a_finished_trade_counts_as_a_deal() -> void:
	h.ask(2, &"req_trade_ready")
	h.ask(3, &"req_trade_ready")
	check_eq(int(ann.character.counters.get("deals", 0)), 1, "Ann's tally")
	h.step(1)
	check_has(h.events(3, &"ev_achievement"), ["dealmaker"], "Bob earns Dealmaker")

func test_changing_the_offer_unreadies_both() -> void:
	h.ask(2, &"req_trade_ready")
	h.ask(3, &"req_trade_shards", [10])
	check(not _state(2)["mine"]["ready"], "Ann has to press again")
	h.ask(3, &"req_trade_ready")
	check_eq(ann.character.shards, 0, "nothing swapped on Bob's press alone")

func test_a_new_dawnshard_offer_replaces_the_old_one() -> void:
	h.ask(3, &"req_trade_shards", [100])
	h.ask(3, &"req_trade_shards", [30])
	check_eq(bob.character.shards, 470, "only 30 held")
	check_eq(_state(3)["mine"]["shards"], 30, "shown")

func test_you_cant_offer_more_dawnshards_than_you_have() -> void:
	h.ask(3, &"req_trade_shards", [9999])
	check_eq(bob.character.shards, 0, "all of them held")
	check_eq(_state(3)["mine"]["shards"], 500, "500 offered")

func test_cancelling_hands_everything_back() -> void:
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 0, -1])
	h.ask(3, &"req_trade_shards", [200])
	h.ask(2, &"req_trade_ready")
	h.ask(3, &"req_trade_cancel")
	check_eq(ann.character.inventory.count_of(leaf), 10, "Ann's leaves back")
	check_eq(bob.character.shards, 500, "Bob's Dawnshards back")
	check_eq(ann.character.shards, 0, "Ann got nothing")
	check(h.server.social.trades.is_empty(), "trade over")
	check(h.told(2, "The trade was cancelled."), "Ann told")

func test_leaving_the_map_cancels_the_trade() -> void:
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 0, 3])
	h.move_to(ann, ServerHarness.TOWN)
	check(h.server.social.trades.is_empty(), "trade over")
	check_eq(ann.character.inventory.count_of(leaf), 10, "leaves back")
	check(h.told(3, "Ann left the map."), "Bob told")

func test_disconnecting_cancels_the_trade() -> void:
	h.ask(3, &"req_trade_shards", [200])
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 0, 3])
	h.leave(2)
	check_eq(bob.character.shards, 500, "Bob's Dawnshards back")
	check_eq(h.server.store.load_character("Ann").inventory.count_of(leaf), 10, "Ann saved with her leaves")
	check(h.told(3, "Ann left."), "Bob told")

func test_quest_items_cant_be_offered() -> void:
	var token := ItemDef.new()
	token.id = &"test_token"
	token.quest_item = true
	ann.character.inventory.put(ItemDef.Tab.ETC, 5, ItemStack.create(token, 1))
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 5, 1])
	check(ann.character.inventory.at(ItemDef.Tab.ETC, 5) != null, "kept")
	check(h.told(2, "Quest items can't be traded."), "told")

func test_the_trade_window_holds_nine_things() -> void:
	for i in 10:
		ann.character.inventory.put(ItemDef.Tab.USE, i, ItemStack.create(Content.item(&"red_potion"), 1))
	for i in 10:
		h.ask(2, &"req_trade_offer", [ItemDef.Tab.USE, i, 1])
	check_eq((_state(2)["mine"]["items"] as Array).size(), TDSocial.TRADE_SLOTS, "nine")
	check(ann.character.inventory.at(ItemDef.Tab.USE, 9) != null, "the tenth stays in the bag")
	check(h.told(2, "The trade window is full."), "told")

func test_no_room_means_no_swap() -> void:
	for i in Inventory.SLOTS:
		bob.character.inventory.put(ItemDef.Tab.ETC, i, ItemStack.create(Content.item(&"moss_tuft"), 1))
	h.ask(2, &"req_trade_offer", [ItemDef.Tab.ETC, 0, 2])
	h.ask(2, &"req_trade_ready")
	h.ask(3, &"req_trade_ready")
	check(h.server.social.trades.has(2), "still open")
	check_eq(bob.character.inventory.count_of(leaf), 0, "nothing moved")
	check(not _state(2)["mine"]["ready"], "both unreadied")
	check(h.told(2, "Bob doesn't have room for that."), "told")

func test_trading_needs_both_on_one_map() -> void:
	h.ask(3, &"req_trade_cancel")
	var cat := h.join(4, "Cat", ServerHarness.TOWN)
	h.ask(2, &"req_social", [&"trade", "Cat"])
	check_eq(h.count(4, &"ev_invite"), 0, "not asked")
	check(h.told(2, "Cat needs to be on this map to trade."), "told")
	check(cat != null, "Cat is online")

func test_one_trade_at_a_time() -> void:
	h.join(4, "Cat", ServerHarness.FIELD, 500.0)
	h.ask(4, &"req_social", [&"trade", "Ann"])
	check_eq(h.count(2, &"ev_invite"), 0, "Ann isn't asked")
	check(h.told(4, "One of you is already trading."), "told")
