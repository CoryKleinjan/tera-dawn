extends TestCase
## ItemStack: gear stat rolls, exact()/unrolled(), upgrade slots, names, stacking rules,
## the save format, and scrolls used through Gear.use_scroll with a fixed roll.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func test_create_stackable_keeps_count_and_has_no_stats() -> void:
	var s := ItemStack.create(fx.etc(), 12)
	check_eq(s.count, 12, "count")
	check(s.stats == null, "no stats on etc items")
	check(s.equip_def() == null, "not gear")

func test_create_gear_forces_count_one() -> void:
	var s := ItemStack.create(fx.equip(), 5)
	check_eq(s.count, 1, "gear count")

func test_create_gear_rolls_within_variance() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20, "strength": 5}, 3)
	var seen := {}
	for i in 200:
		var s := ItemStack.create(e)
		check_between(s.stats.attack, 17, 23, "attack roll")
		check_between(s.stats.strength, 2, 8, "strength roll")
		check_eq(s.stats.dexterity, 0, "zero stats stay zero")
		seen[s.stats.attack] = true
	check_eq(seen.size(), 7, "every value in the range turns up")

func test_rolled_stats_never_go_below_zero() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 1}, 5)
	for i in 100:
		check(ItemStack.create(e).stats.attack >= 0, "not negative")

func test_zero_variance_gives_exact_stats() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 0)
	check_eq(ItemStack.create(e).stats.attack, 20, "exact")

func test_rolled_stats_do_not_change_the_def() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 3)
	var s := ItemStack.create(e)
	s.stats.attack = 500
	check_eq(e.stats.attack, 20, "def untouched")

func test_gear_without_stats_gets_empty_block() -> void:
	var e := fx.equip()
	e.stats = null
	check(ItemStack.create(e).stats != null, "create gives a block")
	check(ItemStack.exact(e).stats != null, "exact gives a block")
	check_eq(ItemStack.exact(e).stats.nonzero().size(), 0, "all zero")

func test_same_seed_rolls_same_stats() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20, "luck": 9}, 4)
	seed(99)
	var a := ItemStack.create(e).stats.to_dict()
	seed(99)
	var b := ItemStack.create(e).stats.to_dict()
	check_eq(a, b, "identical rolls")

func test_exact_copies_listed_stats() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20, "speed": 3}, 9)
	var s := ItemStack.exact(e)
	check_eq(s.stats.to_dict(), {"attack": 20, "speed": 3}, "listed stats")
	check_eq(s.count, 1, "one")
	s.stats.attack = 1
	check_eq(e.stats.attack, 20, "a copy, not the def's block")

func test_unrolled_gear_is_exact_and_others_keep_count() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 9)
	check_eq(ItemStack.unrolled(e, 4).stats.attack, 20, "gear exact")
	check_eq(ItemStack.unrolled(e, 4).count, 1, "gear one")
	check_eq(ItemStack.unrolled(fx.use(), 4).count, 4, "potions keep count")

func test_slots_left_counts_down_and_never_negative() -> void:
	var e := fx.equip()
	e.upgrade_slots = 3
	var s := ItemStack.exact(e)
	check_eq(s.slots_left(), 3, "fresh")
	s.slots_used = 2
	check_eq(s.slots_left(), 1, "after two")
	s.slots_used = 9
	check_eq(s.slots_left(), 0, "floored at zero")
	check_eq(ItemStack.create(fx.etc()).slots_left(), 0, "non-gear has none")

func test_display_name_shows_upgrades() -> void:
	var s := ItemStack.exact(fx.equip(&"t_sword"))
	check_eq(s.display_name(), "T Sword", "plain")
	s.upgrades = 3
	check_eq(s.display_name(), "T Sword +3", "with upgrades")

func test_can_stack_with_same_stackable_only() -> void:
	var x := fx.etc()
	var e := fx.equip()
	check(ItemStack.create(x).can_stack_with(ItemStack.create(x)), "same etc")
	check(not ItemStack.create(x).can_stack_with(ItemStack.create(fx.etc(&"t_other"))), "different items")
	check(not ItemStack.create(x).can_stack_with(null), "null")
	check(not ItemStack.create(e).can_stack_with(ItemStack.create(e)), "gear never stacks")

func test_to_dict_omits_upgrade_fields_when_unused() -> void:
	var d := ItemStack.exact(fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 5})).to_dict()
	check_eq(d, {"id": "t_sword", "count": 1, "stats": {"attack": 5}}, "fresh gear")
	check_eq(ItemStack.create(fx.etc(), 3).to_dict(), {"id": "t_etc", "count": 3}, "etc")

func test_round_trip_keeps_rolled_stats_and_upgrades() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 3)
	var s := ItemStack.create(e)
	s.stats.attack = 23
	s.slots_used = 4
	s.upgrades = 2
	var back := ItemStack.from_dict(s.to_dict())
	check_eq(back.item, e, "item")
	check_eq(back.stats.attack, 23, "rolled stat")
	check_eq(back.slots_used, 4, "slots used")
	check_eq(back.upgrades, 2, "upgrades")

func test_from_dict_unknown_item_is_null() -> void:
	check(ItemStack.from_dict({"id": "t_no_such_item"}) == null, "unknown")
	check(ItemStack.from_dict({}) == null, "no id")

func test_from_dict_clamps_bad_values() -> void:
	fx.etc(&"t_etc", 10)
	check_eq(ItemStack.from_dict({"id": "t_etc", "count": 0}).count, 1, "count floor")
	check_eq(ItemStack.from_dict({"id": "t_etc", "count": 99}).count, 10, "count cap")
	check_eq(ItemStack.from_dict({"id": "t_etc"}).count, 1, "missing count")
	fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20})
	var g := ItemStack.from_dict({"id": "t_sword", "count": 3, "slots_used": -2, "upgrades": 5})
	check_eq(g.count, 1, "gear count")
	check_eq(g.slots_used, 0, "negative slots used")
	check_eq(g.upgrades, 0, "upgrades can't pass slots used")
	var h := ItemStack.from_dict({"id": "t_sword", "slots_used": 2, "upgrades": 5})
	check_eq(h.upgrades, 2, "upgrades capped at slots used")

func test_from_dict_old_gear_without_stats_gets_listed_stats() -> void:
	fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 5)
	check_eq(ItemStack.from_dict({"id": "t_sword"}).stats.attack, 20, "listed stats")

# ---------- scrolls ----------

func _scroll_setup(chance := 0.6) -> Array:
	var c := fx.character()
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 10})
	e.upgrade_slots = 2
	var sc := fx.scroll(&"t_scroll", [EquipDef.Slot.WEAPON], chance, {"attack": 3, "strength": 1})
	c.inventory.add_stack(ItemStack.exact(e))
	c.inventory.add(sc, 5)
	return [c, c.inventory.at(ItemDef.Tab.EQUIP, 0)]

func test_scroll_success_adds_stats_and_spends_slot() -> void:
	var setup := _scroll_setup(0.6)
	var c: Character = setup[0]
	var gear: ItemStack = setup[1]
	var r := c.gear.use_scroll(0, 0, 0.59)
	check_eq(r, {"problem": "", "worked": true}, "result")
	check_eq(gear.stats.attack, 13, "attack added")
	check_eq(gear.stats.strength, 1, "strength added")
	check_eq(gear.slots_used, 1, "slot spent")
	check_eq(gear.upgrades, 1, "upgrade counted")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 0).count, 4, "one scroll used")

func test_scroll_failure_spends_slot_without_stats() -> void:
	var setup := _scroll_setup(0.6)
	var c: Character = setup[0]
	var gear: ItemStack = setup[1]
	var r := c.gear.use_scroll(0, 0, 0.6)
	check_eq(r, {"problem": "", "worked": false}, "roll equal to chance fails")
	check_eq(gear.stats.attack, 10, "no stats")
	check_eq(gear.slots_used, 1, "slot still spent")
	check_eq(gear.upgrades, 0, "no upgrade")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 0).count, 4, "scroll still used")

func test_scroll_with_no_slots_left_is_refused() -> void:
	var setup := _scroll_setup(1.0)
	var c: Character = setup[0]
	var gear: ItemStack = setup[1]
	c.gear.use_scroll(0, 0, 0.0)
	c.gear.use_scroll(0, 0, 0.0)
	var r := c.gear.use_scroll(0, 0, 0.0)
	check_ne(r["problem"], "", "refused")
	check_eq(gear.slots_used, 2, "no more slots spent")
	check_eq(gear.stats.attack, 16, "two scrolls worked")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 0).count, 3, "third scroll kept")

func test_scroll_on_wrong_slot_kind_is_refused() -> void:
	var c := fx.character()
	var hat := fx.equip(&"t_hat", EquipDef.Slot.HAT)
	c.inventory.add_stack(ItemStack.exact(hat))
	c.inventory.add(fx.scroll(), 1)
	var r := c.gear.use_scroll(0, 0, 0.0)
	check_ne(r["problem"], "", "weapon scroll on a hat")
	check_eq(c.inventory.at(ItemDef.Tab.EQUIP, 0).slots_used, 0, "no slot spent")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 0).count, 1, "scroll kept")

func test_scroll_problem_for_missing_scroll_or_gear() -> void:
	var c := fx.character()
	c.inventory.add(fx.use(), 1)
	c.inventory.add_stack(ItemStack.exact(fx.equip()))
	check_ne(c.gear.scroll_problem(0, 0), "", "a potion isn't a scroll")
	check_ne(c.gear.scroll_problem(5, 0), "", "empty use slot")
	c.inventory.add(fx.scroll(), 1)
	check_ne(c.gear.scroll_problem(1, 5), "", "empty equip slot")
	check_eq(c.gear.scroll_problem(1, 0), "", "scroll on a sword is fine")

func test_scroll_with_no_stats_still_counts_upgrade() -> void:
	var setup := _scroll_setup(1.0)
	var c: Character = setup[0]
	var gear: ItemStack = setup[1]
	(c.inventory.at(ItemDef.Tab.USE, 0).item as ScrollDef).stats = null
	check(c.gear.use_scroll(0, 0, 0.5)["worked"], "worked")
	check_eq(gear.upgrades, 1, "upgrade counted")
	check_eq(gear.stats.attack, 10, "stats unchanged")

func test_scroll_default_roll_is_deterministic_with_seed() -> void:
	var a := _scroll_setup(0.5)
	seed(4242)
	var ra: bool = (a[0] as Character).gear.use_scroll(0, 0)["worked"]
	var b := _scroll_setup(0.5)
	seed(4242)
	var rb: bool = (b[0] as Character).gear.use_scroll(0, 0)["worked"]
	check_eq(ra, rb, "same seed same outcome")

func test_scrolled_gear_survives_save() -> void:
	var setup := _scroll_setup(1.0)
	var c: Character = setup[0]
	c.gear.use_scroll(0, 0, 0.0)
	var back := ItemStack.from_dict((setup[1] as ItemStack).to_dict())
	check_eq(back.stats.attack, 13, "scrolled stats")
	check_eq(back.slots_left(), 1, "slots left")
	check_eq(back.display_name(), "T Sword +1", "name")
