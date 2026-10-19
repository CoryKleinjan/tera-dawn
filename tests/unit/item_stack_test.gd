extends TestCase
## ItemStack: gear stat rolls, exact()/unrolled(), names, stacking rules, rune slots and the
## save format (older saves' scroll upgrade fields ignored, older gear with empty rune slots).

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
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20, "accuracy": 5}, 3)
	var seen := {}
	for i in 200:
		var s := ItemStack.create(e)
		check_between(s.stats.attack, 17, 23, "attack roll")
		check_between(s.stats.accuracy, 2, 8, "accuracy roll")
		check_eq(s.stats.avoid, 0, "zero stats stay zero")
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
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20, "avoid": 9}, 4)
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
	check_eq(ItemStack.unrolled(fx.use(), 4).count, 4, "other items keep their count")

func test_display_name_is_the_items_name() -> void:
	check_eq(ItemStack.exact(fx.equip(&"t_sword")).display_name(), "T Sword", "gear")
	check_eq(ItemStack.create(fx.etc(), 3).display_name(), "T Etc", "etc")

func test_can_stack_with_same_stackable_only() -> void:
	var x := fx.etc()
	var e := fx.equip()
	check(ItemStack.create(x).can_stack_with(ItemStack.create(x)), "same etc")
	check(not ItemStack.create(x).can_stack_with(ItemStack.create(fx.etc(&"t_other"))), "different items")
	check(not ItemStack.create(x).can_stack_with(null), "null")
	check(not ItemStack.create(e).can_stack_with(ItemStack.create(e)), "gear never stacks")

func test_to_dict_has_id_count_and_gear_stats() -> void:
	var d := ItemStack.exact(fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 5})).to_dict()
	check_eq(d, {"id": "t_sword", "count": 1, "stats": {"attack": 5}}, "fresh gear")
	check_eq(ItemStack.create(fx.etc(), 3).to_dict(), {"id": "t_etc", "count": 3}, "etc")

func test_round_trip_keeps_rolled_stats() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 3)
	var s := ItemStack.create(e)
	s.stats.attack = 23
	var back := ItemStack.from_dict(s.to_dict())
	check_eq(back.item, e, "item")
	check_eq(back.stats.attack, 23, "rolled stat")

func test_from_dict_unknown_item_is_null() -> void:
	check(ItemStack.from_dict({"id": "t_no_such_item"}) == null, "unknown")
	check(ItemStack.from_dict({}) == null, "no id")

func test_from_dict_clamps_bad_values() -> void:
	fx.etc(&"t_etc", 10)
	check_eq(ItemStack.from_dict({"id": "t_etc", "count": 0}).count, 1, "count floor")
	check_eq(ItemStack.from_dict({"id": "t_etc", "count": 99}).count, 10, "count cap")
	check_eq(ItemStack.from_dict({"id": "t_etc"}).count, 1, "missing count")
	fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20})
	var g := ItemStack.from_dict({"id": "t_sword", "count": 3})
	check_eq(g.count, 1, "gear count")

func test_from_dict_old_gear_without_stats_gets_listed_stats() -> void:
	fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 5)
	check_eq(ItemStack.from_dict({"id": "t_sword"}).stats.attack, 20, "listed stats")

func test_from_dict_old_scrolled_gear_keeps_its_stats() -> void:
	fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20})
	var g := ItemStack.from_dict({"id": "t_sword", "count": 1, "stats": {"attack": 26}, "slots_used": 3, "upgrades": 2})
	check_eq(g.stats.attack, 26, "the upgraded stats stay")
	check_eq(g.display_name(), "T Sword", "no +2")
	check_eq(g.to_dict(), {"id": "t_sword", "count": 1, "stats": {"attack": 26}}, "the upgrade fields aren't saved again")

func test_gear_has_three_empty_rune_slots() -> void:
	for s in [ItemStack.create(fx.equip()), ItemStack.exact(fx.equip())]:
		check_eq(s.runes.size(), ItemStack.RUNE_SLOTS, "rune slots")
		check_eq(s.runes_set(), 0, "all empty")
	check(ItemStack.create(fx.etc()).runes.is_empty(), "etc items have none")

func test_runes_add_to_the_gears_total() -> void:
	var s := ItemStack.exact(fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}))
	s.runes[0] = fx.rune(&"t_rune", {"attack": 2, "max_hp": 15})
	s.runes[2] = fx.rune(&"t_rune_2", {"attack": 1})
	check_eq(s.total().attack, 23, "attack")
	check_eq(s.total().max_hp, 15, "Max HP")
	check_eq(s.stats.attack, 20, "its own stats untouched")
	check_eq(s.runes_set(), 2, "two set")

func test_round_trip_keeps_runes_in_their_slots() -> void:
	var s := ItemStack.exact(fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}))
	var r := fx.rune()
	s.runes[1] = r
	check_eq(s.to_dict()["runes"], ["", "t_rune", ""], "saved")
	var back := ItemStack.from_dict(s.to_dict())
	check(back.runes[0] == null and back.runes[1] == r and back.runes[2] == null, "loaded")

func test_from_dict_old_gear_gets_empty_rune_slots_and_lost_runes_leave_a_gap() -> void:
	fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20})
	var old := ItemStack.from_dict({"id": "t_sword", "count": 1, "stats": {"attack": 20}})
	check_eq(old.runes.size(), ItemStack.RUNE_SLOTS, "three slots")
	check_eq(old.runes_set(), 0, "empty")
	check(not old.to_dict().has("runes"), "empty slots aren't saved")
	var lost := ItemStack.from_dict({"id": "t_sword", "runes": ["t_no_such_rune", "", "", "t_extra"]})
	check_eq(lost.runes.size(), ItemStack.RUNE_SLOTS, "still three")
	check_eq(lost.runes_set(), 0, "a rune that's gone leaves its slot empty")
