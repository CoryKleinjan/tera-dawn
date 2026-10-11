extends TestCase
## Using and wearing items through requests: potions and their cooldown, return scrolls,
## equipping and taking off gear, upgrade scrolls, moving items and Ability Points.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	c = p.character

func after_each() -> void:
	h.close()

func _red_slot() -> int:
	return c.inventory.find(Content.item(&"red_potion"))

func test_a_potion_heals_and_is_used_up() -> void:
	var red: UseDef = Content.item(&"red_potion")
	c.health.set_hp(1)
	var before := c.inventory.count_of(red)
	h.ask(2, &"req_use_item", [_red_slot()])
	check_eq(c.health.hp, mini(c.max_hp(), 1 + red.hp_for(c.max_hp())), "healed by the potion's amount")
	check_eq(c.inventory.count_of(red), before - 1, "one used")
	check(p.dirty_character, "character marked to be sent")

func test_healing_stops_at_max_hp() -> void:
	c.health.set_hp(c.max_hp() - 3)
	h.ask(2, &"req_use_item", [_red_slot()])
	check_eq(c.health.hp, c.max_hp(), "capped")

func test_a_mana_potion_restores_mp() -> void:
	var blue: UseDef = Content.item(&"blue_potion")
	c.inventory.put(ItemDef.Tab.USE, 3, ItemStack.create(blue, 2))
	c.mp = 0
	h.ask(2, &"req_use_item", [3])
	check_eq(c.mp, mini(c.max_mp(), blue.mp_for(c.max_mp())), "MP restored")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 3).count, 1, "one left")

func test_potions_wait_for_the_item_cooldown() -> void:
	var red: UseDef = Content.item(&"red_potion")
	var before := c.inventory.count_of(red)
	h.ask(2, &"req_use_item", [_red_slot()])
	h.ask(2, &"req_use_item", [_red_slot()])
	check_eq(c.inventory.count_of(red), before - 1, "second one refused")
	check(h.told(2, "You can't use another item yet."), "told why")
	h.step(red.cooldown)
	h.ask(2, &"req_use_item", [_red_slot()])
	check_eq(c.inventory.count_of(red), before - 2, "allowed after the cooldown")

func test_fainted_players_cant_use_items() -> void:
	var red: UseDef = Content.item(&"red_potion")
	var before := c.inventory.count_of(red)
	p.faint_t = 10
	h.ask(2, &"req_use_item", [_red_slot()])
	check_eq(c.inventory.count_of(red), before, "not used")
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
	h.ask(2, &"req_equip", [2, &"hat"])
	check(c.equipment.at(&"hat") != null and c.equipment.at(&"hat").item == cap, "wearing it")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 2) == null, "out of the bag")
	check_eq(c.stats.defense, def_before + cap.stats.defense, "stats added")
	h.step(1)
	check_eq(h.last(2, &"ev_character")[0]["equipment"]["hat"]["id"], "leaf_cap", "client told")

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

func test_gear_above_your_level_is_refused() -> void:
	var cap := (Content.item(&"leaf_cap") as EquipDef).duplicate() as EquipDef
	cap.required_level = 5
	c.inventory.put(ItemDef.Tab.EQUIP, 0, ItemStack.exact(cap))
	h.ask(2, &"req_equip", [0, &"hat"])
	check(c.equipment.at(&"hat") == null, "not worn")
	check(h.told(2, "You need to be level 5"), "told why")

func test_taking_gear_off_puts_it_in_the_bag() -> void:
	var top := c.equipment.at(&"top")
	h.ask(2, &"req_unequip", [&"top", 7])
	check(c.equipment.at(&"top") == null, "not worn")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 7) == top, "in the chosen slot")

func test_taking_gear_off_into_a_full_bag_is_refused() -> void:
	for i in Inventory.SLOTS:
		c.inventory.put(ItemDef.Tab.EQUIP, i, ItemStack.exact(Content.item(&"leaf_cap")))
	h.ask(2, &"req_unequip", [&"top", -1])
	check(c.equipment.at(&"top") != null, "still worn")
	check(h.told(2, "Your Equip inventory is full."), "told why")

func test_a_sure_scroll_upgrades_gear() -> void:
	var scroll := ScrollDef.new()
	scroll.id = &"test_scroll"
	scroll.display_name = "Test Scroll"
	scroll.chance = 1.0
	scroll.stats = StatBlock.new()
	scroll.stats.attack = 2
	var sword := ItemStack.exact(Content.item(&"training_sword"))
	scroll.slots = [sword.equip_def().slot]
	c.inventory.put(ItemDef.Tab.USE, 5, ItemStack.create(scroll, 1))
	c.inventory.put(ItemDef.Tab.EQUIP, 0, sword)
	var attack := sword.stats.attack
	h.ask(2, &"req_scroll", [5, 0])
	check_eq(sword.stats.attack, attack + 2, "attack added")
	check_eq(sword.upgrades, 1, "one upgrade")
	check_eq(sword.slots_used, 1, "one slot used")
	check(c.inventory.at(ItemDef.Tab.USE, 5) == null, "scroll used up")
	check(h.told(2, "The scroll worked!"), "told")
	check_eq(int(c.counters.get("scrolls", 0)), 1, "counted for achievements")

func test_moving_items_in_the_bag() -> void:
	var slot := _red_slot()
	h.ask(2, &"req_move_item", [ItemDef.Tab.USE, slot, 10])
	check(c.inventory.at(ItemDef.Tab.USE, slot) == null, "moved out")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 10).item.id, &"red_potion", "moved in")

func test_moving_items_to_a_bad_slot_is_ignored() -> void:
	var slot := _red_slot()
	h.ask(2, &"req_move_item", [ItemDef.Tab.USE, slot, Inventory.SLOTS])
	check(c.inventory.at(ItemDef.Tab.USE, slot) != null, "stayed")

func test_spending_ability_points() -> void:
	c.ap.points = 2
	var strength := c.base.strength
	h.ask(2, &"req_add_ap", [&"strength"])
	check_eq(c.base.strength, strength + 1, "STR raised")
	check_eq(c.ap.points, 1, "point spent")
	h.ask(2, &"req_add_ap", [&"attack"])
	check_eq(c.ap.points, 1, "only main stats take points")

func test_spending_many_ability_points_at_once() -> void:
	c.ap.points = 5
	var luck := c.base.luck
	h.ask(2, &"req_add_ap_many", [&"luck", 3])
	check_eq(c.base.luck, luck + 3, "LUK raised by 3")
	check_eq(c.ap.points, 2, "three points spent")
	h.ask(2, &"req_add_ap_many", [&"luck", 50])
	check_eq(c.base.luck, luck + 5, "never more than the points left")
	check_eq(c.ap.points, 0, "all spent")
	c.ap.points = 4
	h.ask(2, &"req_add_ap_many", [&"luck", -3])
	h.ask(2, &"req_add_ap_many", [&"attack", 2])
	check_eq(c.ap.points, 4, "a negative amount or a non-base stat spends nothing")
	check_eq(c.base.luck, luck + 5, "LUK unchanged")
