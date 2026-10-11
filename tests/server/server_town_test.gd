extends TestCase
## Town services through the server: NPC shops (buying, selling, not enough Dawnshards),
## storage and its fee, portals, paid travel (wagons and ships) and a job instructor's
## free Ability Point reset.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const MERCHANT_X := 400.0
const KEEPER_X := 800.0
const DRIVER_X := 1200.0
const PORTAL_X := 1900.0
const INSTRUCTOR_X := 1550.0

var h: ServerHarness
var p: SimPlayer
var c: Character
var red: UseDef
var leaf: ItemDef
## The test driver's one trip: 100 Dawnshards to the field.
var wagon: TravelRoute

func before_each() -> void:
	h = ServerHarness.new()
	red = Content.item(&"red_potion")
	leaf = Content.item(&"green_leaf")
	var town := ServerHarness.town_def()
	var merchant := ServerHarness.npc(town, &"test_merchant", MERCHANT_X)
	merchant.shop = ServerHarness.shop([[red, 50], [leaf, 0]])
	ServerHarness.npc(town, &"test_keeper", KEEPER_X).storage = true
	var route := TravelRoute.new()
	route.target_map = ServerHarness.FIELD
	route.target_x = 700.0
	route.price = 100
	route.by = "Wagon"
	ServerHarness.npc(town, &"test_driver", DRIVER_X).travel = [route]
	wagon = route
	ServerHarness.npc(town, &"test_instructor", INSTRUCTOR_X).instructs = [&"mage"]
	var portal := PortalDef.new()
	portal.x = PORTAL_X
	portal.target_map = ServerHarness.FIELD
	portal.target_x = 150.0
	town.portals.append(portal)
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.TOWN, MERCHANT_X)
	c = p.character

func after_each() -> void:
	h.close()

# ---------- shops ----------

func test_buying_takes_the_price_and_gives_the_items() -> void:
	c.shards = 200
	var before := c.inventory.count_of(red)
	h.ask(2, &"req_buy", [&"test_merchant", 0, 3])
	check_eq(c.shards, 50, "paid 3 x 50")
	check_eq(c.inventory.count_of(red), before + 3, "got 3")
	check(h.told(2, "Bought 3 Red Potion for 150 Dawnshards."), "told")

func test_a_price_of_zero_means_four_times_the_sell_price() -> void:
	c.shards = 1000
	h.ask(2, &"req_buy", [&"test_merchant", 1, 1])
	check_eq(c.shards, 1000 - leaf.sell_price * ShopEntry.PRICE_MARKUP, "paid the usual price")
	check_eq(c.inventory.count_of(leaf), 1, "got it")

func test_not_enough_dawnshards_buys_nothing() -> void:
	c.shards = 149
	var before := c.inventory.count_of(red)
	h.ask(2, &"req_buy", [&"test_merchant", 0, 3])
	check_eq(c.shards, 149, "kept the Dawnshards")
	check_eq(c.inventory.count_of(red), before, "no potions")
	check(h.told(2, "You don't have enough Dawnshards."), "told why")

func test_buying_into_a_full_tab_is_refused() -> void:
	c.shards = 1000
	for i in Inventory.SLOTS:
		c.inventory.put(ItemDef.Tab.ETC, i, ItemStack.create(Content.item(&"moss_tuft"), 1))
	h.ask(2, &"req_buy", [&"test_merchant", 1, 1])
	check_eq(c.shards, 1000, "not charged")
	check(h.told(2, "Your Etc inventory is full."), "told why")

func test_buying_far_from_the_shopkeeper_does_nothing() -> void:
	c.shards = 200
	h.place(p, MERCHANT_X + 161.0)
	h.ask(2, &"req_buy", [&"test_merchant", 0, 1])
	check_eq(c.shards, 200, "nothing bought")
	h.place(p, MERCHANT_X + 160.0)
	h.ask(2, &"req_buy", [&"test_merchant", 0, 1])
	check_eq(c.shards, 150, "160 px away is close enough")

func test_bad_shop_lines_are_ignored() -> void:
	c.shards = 200
	h.ask(2, &"req_buy", [&"test_merchant", 2, 1])
	h.ask(2, &"req_buy", [&"test_merchant", -1, 1])
	check_eq(c.shards, 200, "nothing bought")

func test_buying_is_limited_to_one_stack() -> void:
	c.shards = 1000000
	h.ask(2, &"req_buy", [&"test_merchant", 0, 5000])
	check_eq(c.shards, 1000000 - red.stack_size() * 50, "paid for one stack")

func test_selling_pays_the_sell_price_per_item() -> void:
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 5))
	h.ask(2, &"req_sell", [&"test_merchant", ItemDef.Tab.ETC, 0, 3])
	check_eq(c.shards, 3 * leaf.sell_price, "paid")
	check_eq(c.inventory.at(ItemDef.Tab.ETC, 0).count, 2, "two left")

func test_selling_more_than_you_have_sells_the_stack() -> void:
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 2))
	h.ask(2, &"req_sell", [&"test_merchant", ItemDef.Tab.ETC, 0, 99])
	check_eq(c.shards, 2 * leaf.sell_price, "paid for two")
	check(c.inventory.at(ItemDef.Tab.ETC, 0) == null, "slot empty")

func test_quest_items_cant_be_sold() -> void:
	var token := ItemDef.new()
	token.id = &"test_token"
	token.quest_item = true
	token.sell_price = 100
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(token, 1))
	h.ask(2, &"req_sell", [&"test_merchant", ItemDef.Tab.ETC, 0, 1])
	check_eq(c.shards, 0, "not paid")
	check(c.inventory.at(ItemDef.Tab.ETC, 0) != null, "kept")
	check(h.told(2, "You can't sell quest items."), "told why")

func test_selling_all_etc_skips_quest_items() -> void:
	var token := ItemDef.new()
	token.id = &"test_token"
	token.quest_item = true
	token.sell_price = 100
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 4))
	c.inventory.put(ItemDef.Tab.ETC, 1, ItemStack.create(token, 1))
	c.inventory.put(ItemDef.Tab.ETC, 2, ItemStack.create(Content.item(&"moss_tuft"), 10))
	h.ask(2, &"req_sell_all_etc", [&"test_merchant"])
	check_eq(c.shards, 4 * leaf.sell_price + 10 * Content.item(&"moss_tuft").sell_price, "paid for both stacks")
	check(c.inventory.at(ItemDef.Tab.ETC, 1) != null, "quest item kept")
	check(c.inventory.at(ItemDef.Tab.ETC, 0) == null, "leaves sold")

func test_npcs_without_a_shop_dont_buy() -> void:
	h.place(p, KEEPER_X)
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 1))
	h.ask(2, &"req_sell", [&"test_keeper", ItemDef.Tab.ETC, 0, 1])
	check_eq(c.shards, 0, "not sold")

# ---------- storage ----------

func test_storing_costs_a_fee() -> void:
	h.place(p, KEEPER_X)
	c.shards = 25
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 6))
	h.ask(2, &"req_store", [&"test_keeper", ItemDef.Tab.ETC, 0])
	check_eq(c.shards, 25 - Character.STORE_FEE, "fee paid")
	check_eq(c.storage.count_of(leaf), 6, "in storage")
	check(c.inventory.at(ItemDef.Tab.ETC, 0) == null, "out of the bag")
	check(h.server.store.load_character("Ann").storage.count_of(leaf) == 6, "saved at once")

func test_storing_without_the_fee_is_refused() -> void:
	h.place(p, KEEPER_X)
	c.shards = Character.STORE_FEE - 1
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 6))
	h.ask(2, &"req_store", [&"test_keeper", ItemDef.Tab.ETC, 0])
	check_eq(c.storage.count_of(leaf), 0, "nothing stored")
	check_eq(c.shards, Character.STORE_FEE - 1, "nothing taken")
	check(h.told(2, "Storing costs 10 Dawnshards."), "told why")

func test_taking_out_of_storage_is_free() -> void:
	h.place(p, KEEPER_X)
	c.storage.put(ItemDef.Tab.ETC, 3, ItemStack.create(leaf, 2))
	h.ask(2, &"req_retrieve", [&"test_keeper", ItemDef.Tab.ETC, 3])
	check_eq(c.inventory.count_of(leaf), 2, "back in the bag")
	check_eq(c.shards, 0, "no fee")

func test_storage_only_works_at_the_storage_keeper() -> void:
	c.shards = 100
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(leaf, 1))
	h.ask(2, &"req_store", [&"test_merchant", ItemDef.Tab.ETC, 0])
	check_eq(c.storage.count_of(leaf), 0, "a shopkeeper doesn't store")
	h.ask(2, &"req_store", [&"test_keeper", ItemDef.Tab.ETC, 0])
	check_eq(c.storage.count_of(leaf), 0, "the keeper is too far away")

# ---------- portals and travel ----------

func test_a_portal_takes_you_to_its_map() -> void:
	h.place(p, PORTAL_X + 20.0)
	h.ask(2, &"req_portal")
	check_eq(p.map.def.id, ServerHarness.FIELD, "on the field")
	check_eq(p.position, Vector2(150, ServerHarness.GROUND), "at the portal's target")
	check_eq(h.last(2, &"ev_enter_map").slice(0, 2), [ServerHarness.FIELD, 150.0], "client told")
	check(not h.server.maps[ServerHarness.TOWN].players.has(2), "left the town")

func test_no_portal_no_travel() -> void:
	h.place(p, PORTAL_X - 40.0)
	h.ask(2, &"req_portal")
	check_eq(p.map.def.id, ServerHarness.TOWN, "still in town")

func test_others_see_you_leave_through_a_portal() -> void:
	h.join(3, "Bob", ServerHarness.TOWN, 600.0)
	h.place(p, PORTAL_X)
	h.ask(2, &"req_portal")
	check_eq(h.last(3, &"ev_player_left"), [2], "Bob told")

func test_travel_charges_the_fare_and_moves_you() -> void:
	h.place(p, DRIVER_X)
	c.shards = 150
	h.ask(2, &"req_travel", [&"test_driver", 0])
	check_eq(c.shards, 50, "fare paid")
	check_eq(p.map.def.id, ServerHarness.FIELD, "arrived")
	check_eq(p.position.x, 700.0, "at the stop")
	check(h.told(2, "Wagon to Test Field."), "told")

func test_travel_without_the_fare_is_refused() -> void:
	h.place(p, DRIVER_X)
	c.shards = 99
	h.ask(2, &"req_travel", [&"test_driver", 0])
	check_eq(c.shards, 99, "nothing paid")
	check_eq(p.map.def.id, ServerHarness.TOWN, "still in town")
	check(h.told(2, "You don't have enough Dawnshards."), "told why")

## The test driver's wagon made free for Beginners ready for a job (like Rook's coaches).
func _free_for_beginners() -> void:
	wagon.free_for_beginners = true

func test_a_free_coach_costs_a_beginner_ready_for_a_job_nothing() -> void:
	_free_for_beginners()
	h.place(p, DRIVER_X)
	c.level = JobDef.first_advance_level(Character.START_JOB)
	c.shards = 0
	h.ask(2, &"req_travel", [&"test_driver", 0])
	check_eq(p.map.def.id, ServerHarness.FIELD, "arrived for free")
	check_eq(c.shards, 0, "nothing paid")

func test_a_free_coach_still_charges_a_beginner_below_the_job_level() -> void:
	_free_for_beginners()
	h.place(p, DRIVER_X)
	c.level = JobDef.first_advance_level(Character.START_JOB) - 1
	c.shards = 150
	h.ask(2, &"req_travel", [&"test_driver", 0])
	check_eq(c.shards, 50, "the full fare")

func test_a_free_coach_charges_someone_with_a_job() -> void:
	_free_for_beginners()
	h.place(p, DRIVER_X)
	c.job = Content.job(&"warrior")
	c.level = 20
	c.shards = 150
	h.ask(2, &"req_travel", [&"test_driver", 0])
	check_eq(c.shards, 50, "the full fare")
	check_eq(p.map.def.id, ServerHarness.FIELD, "arrived")

func test_travel_needs_you_by_the_driver() -> void:
	c.shards = 150
	h.ask(2, &"req_travel", [&"test_driver", 0])
	check_eq(p.map.def.id, ServerHarness.TOWN, "still in town")
	check_eq(c.shards, 150, "nothing paid")

# ---------- job instructors ----------

## A Beginner who put 20 points into STR instead of the INT a Magician needs.
func _misbuilt() -> int:
	var start := c.job.starting_stats.strength
	c.base.strength = start + 20
	c.ap.points = 0
	c.recalc()
	return start

func test_an_instructor_resets_a_misbuilt_beginners_ap_once() -> void:
	var start := _misbuilt()
	h.place(p, INSTRUCTOR_X)
	h.ask(2, &"req_reset_ap", [&"test_instructor", &"mage"])
	check_eq(c.base.strength, start, "STR back where it started")
	check_eq(c.ap.points, 20, "every point back")
	check(c.ap.reset_used, "used up")
	check(h.told(2, "Your Ability Points are back: 20 to spend."), "told")
	c.ap.spend(&"strength", 20)
	h.ask(2, &"req_reset_ap", [&"test_instructor", &"mage"])
	check_eq(c.ap.points, 0, "no second reset")
	check(h.told(2, "You've already had your free reset."), "told why")

func test_no_ap_reset_once_the_stats_are_there() -> void:
	_misbuilt()
	c.base.intelligence = 20
	h.place(p, INSTRUCTOR_X)
	h.ask(2, &"req_reset_ap", [&"test_instructor", &"mage"])
	check_eq(c.ap.points, 0, "nothing back")
	check(not c.ap.reset_used, "still unused")

func test_ap_reset_needs_you_by_an_instructor_of_that_job() -> void:
	_misbuilt()
	h.ask(2, &"req_reset_ap", [&"test_instructor", &"mage"])
	check_eq(c.ap.points, 0, "too far away")
	h.place(p, INSTRUCTOR_X)
	h.ask(2, &"req_reset_ap", [&"test_instructor", &"warrior"])
	check_eq(c.ap.points, 0, "they don't teach Warriors")
	check(not c.ap.reset_used, "still unused")
