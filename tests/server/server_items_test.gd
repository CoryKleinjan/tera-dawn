extends TestCase
## Using and wearing items through requests: the item cooldown, return scrolls,
## equipping and taking off gear, and moving items (no stats to buy, no upgrade scrolls).

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var u := UnitHelpers.new()
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	c = p.character

func after_each() -> void:
	h.close()
	u.cleanup()

## A Use item made for the test (it does nothing but get used up), two of them in slot 3.
func _thing() -> UseDef:
	var it := u.use()
	c.inventory.put(ItemDef.Tab.USE, 3, ItemStack.create(it, 2))
	return it

func test_items_wait_for_the_item_cooldown() -> void:
	var it := _thing()
	h.ask(2, &"req_use_item", [3])
	check_eq(c.inventory.count_of(it), 1, "one used")
	check(p.dirty_character, "character marked to be sent")
	h.ask(2, &"req_use_item", [3])
	check_eq(c.inventory.count_of(it), 1, "second one refused")
	check(h.told(2, "You can't use another item yet."), "told why")
	h.step(it.cooldown)
	h.ask(2, &"req_use_item", [3])
	check_eq(c.inventory.count_of(it), 0, "allowed after the cooldown")

func test_fainted_players_cant_use_items() -> void:
	var it := _thing()
	p.faint_t = 10
	h.ask(2, &"req_use_item", [3])
	check_eq(c.inventory.count_of(it), 2, "not used")
	check(h.told(2, "You can't do that right now."), "told why")

func test_using_an_empty_slot_does_nothing() -> void:
	h.ask(2, &"req_use_item", [20])
	check_eq(h.api.sent.size(), 0, "nothing")

func test_a_return_scroll_takes_you_to_town() -> void:
	c.inventory.put(ItemDef.Tab.USE, 4, ItemStack.create(Content.item(&"return_scroll"), 1))
	h.ask(2, &"req_use_item", [4])
	check_eq(p.map.def.id, ServerHarness.TOWN, "in town")
	check_eq(h.last(2, &"ev_enter_map").slice(0, 2), [ServerHarness.TOWN, 500.0], "arrived at the town's start")
	check(c.inventory.at(ItemDef.Tab.USE, 4) == null, "scroll used")

func test_a_return_scroll_in_town_is_kept() -> void:
	h.move_to(p, ServerHarness.TOWN)
	c.inventory.put(ItemDef.Tab.USE, 4, ItemStack.create(Content.item(&"return_scroll"), 1))
	h.ask(2, &"req_use_item", [4])
	check(h.told(2, "You're already in town."), "told why")
	check(c.inventory.at(ItemDef.Tab.USE, 4) != null, "scroll kept")

func test_equipping_gear_from_the_bag() -> void:
	var cap: EquipDef = Content.item(&"leaf_cap")
	c.inventory.put(ItemDef.Tab.EQUIP, 2, ItemStack.exact(cap))
	var def_before := c.stats.defense
	var old := c.equipment.at(&"armor")
	h.ask(2, &"req_equip", [2, &"armor"])
	check(c.equipment.at(&"armor") != null and c.equipment.at(&"armor").item == cap, "wearing it")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 2) == old, "out of the bag, the armor it replaced in its slot")
	check_eq(c.stats.defense, def_before - old.total().defense + cap.stats.defense, "stats swapped")
	h.step(1)
	check_eq(h.last(2, &"ev_character")[0]["equipment"]["armor"]["id"], "leaf_cap", "client told")

func test_equipping_swaps_with_what_was_worn() -> void:
	var old := c.equipment.at(&"weapon")
	var sword: EquipDef = Content.item(&"training_sword")
	var spare := ItemStack.exact(sword)
	spare.stats.attack = 1
	c.inventory.put(ItemDef.Tab.EQUIP, 0, spare)
	h.ask(2, &"req_equip", [0, &"weapon"])
	check(c.equipment.at(&"weapon") == spare, "new one worn")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 0) == old, "old one in its slot")

func test_gear_for_another_job_is_refused() -> void:
	c.inventory.put(ItemDef.Tab.EQUIP, 0, ItemStack.exact(Content.item(&"bronze_sword")))
	h.ask(2, &"req_equip", [0, &"weapon"])
	check(c.equipment.at(&"weapon").item.id == &"training_sword", "still the old weapon")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 0) != null, "still in the bag")
	check(h.told(2, "can use the Bronze Sword"), "told why")

func test_gear_has_no_level_to_wear_it() -> void:
	var cap := (Content.item(&"leaf_cap") as EquipDef).duplicate() as EquipDef
	cap.required_level = 5
	c.inventory.put(ItemDef.Tab.EQUIP, 0, ItemStack.exact(cap))
	h.ask(2, &"req_equip", [0, &"armor"])
	check(c.equipment.at(&"armor") != null and c.equipment.at(&"armor").item == cap, "worn: levels are gone")

func test_taking_gear_off_puts_it_in_the_bag() -> void:
	var top := c.equipment.at(&"armor")
	h.ask(2, &"req_unequip", [&"armor", 7])
	check(c.equipment.at(&"armor") == null, "not worn")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 7) == top, "in the chosen slot")

func test_taking_gear_off_into_a_full_bag_is_refused() -> void:
	for i in Inventory.SLOTS:
		c.inventory.put(ItemDef.Tab.EQUIP, i, ItemStack.exact(Content.item(&"leaf_cap")))
	h.ask(2, &"req_unequip", [&"armor", -1])
	check(c.equipment.at(&"armor") != null, "still worn")
	check(h.told(2, "Your Equip inventory is full."), "told why")

func test_moving_items_in_the_bag() -> void:
	var it := _thing()
	h.ask(2, &"req_move_item", [ItemDef.Tab.USE, 3, 10])
	check(c.inventory.at(ItemDef.Tab.USE, 3) == null, "moved out")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 10).item, it, "moved in")

func test_moving_items_to_a_bad_slot_is_ignored() -> void:
	_thing()
	h.ask(2, &"req_move_item", [ItemDef.Tab.USE, 3, Inventory.SLOTS])
	check(c.inventory.at(ItemDef.Tab.USE, 3) != null, "stayed")

func test_there_is_nothing_to_buy_stats_or_use_upgrade_scrolls_with() -> void:
	for gone in [&"req_buy_stat", &"req_auto_stats", &"req_scroll"]:
		check(not Net.has_method(gone), "no %s" % gone)
