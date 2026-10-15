extends TestCase
## Inventory: adding and stacking, full bags, tabs, taking, moving, removing, room checks
## and the save format.

var fx: UnitHelpers
var bag: Inventory

func before_each() -> void:
	fx = UnitHelpers.new()
	bag = Inventory.new()

func after_each() -> void:
	fx.cleanup()

func test_new_bag_is_empty_in_every_tab() -> void:
	check_eq(bag.tabs.size(), ItemDef.Tab.size(), "one row per tab")
	for t in ItemDef.Tab.size():
		check_eq(bag.tabs[t].size(), Inventory.SLOTS, "slots in tab %d" % t)
		check_eq(bag.free_slots(t), Inventory.SLOTS, "free slots in tab %d" % t)
		check_eq(bag.first_free(t), 0, "first free in tab %d" % t)

func test_items_go_to_their_own_tab() -> void:
	var e := fx.equip()
	var u := fx.use()
	var x := fx.etc()
	var pet := PetDef.new()
	pet.id = &"t_pet"
	bag.add(e)
	bag.add(u)
	bag.add(x)
	bag.add(pet)
	check_eq(bag.at(ItemDef.Tab.EQUIP, 0).item, e, "gear in Equip")
	check_eq(bag.at(ItemDef.Tab.USE, 0).item, u, "potion in Use")
	check_eq(bag.at(ItemDef.Tab.ETC, 0).item, x, "etc in Etc")
	check_eq(bag.at(ItemDef.Tab.SETUP, 0).item, pet, "pet in Setup")

func test_add_tops_up_existing_stack_before_new_slot() -> void:
	var x := fx.etc(&"t_etc", 10)
	check_eq(bag.add(x, 4), 0, "first add fits")
	check_eq(bag.add(x, 3), 0, "second add fits")
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 7, "merged into one stack")
	check(bag.at(ItemDef.Tab.ETC, 1) == null, "second slot unused")

func test_full_stack_spills_into_next_slot() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(x, 8)
	bag.add(x, 5)
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 10, "first stack topped to max")
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 3, "rest in the next slot")
	check_eq(bag.count_of(x), 13, "total")

func test_add_large_amount_splits_into_max_stacks() -> void:
	var x := fx.etc(&"t_etc", 10)
	check_eq(bag.add(x, 35), 0, "all fit")
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 10, "slot 0")
	check_eq(bag.at(ItemDef.Tab.ETC, 2).count, 10, "slot 2")
	check_eq(bag.at(ItemDef.Tab.ETC, 3).count, 5, "slot 3 has the rest")
	check_eq(bag.free_slots(ItemDef.Tab.ETC), Inventory.SLOTS - 4, "four slots used")

func test_add_to_full_bag_returns_what_did_not_fit() -> void:
	var x := fx.etc(&"t_etc", 10)
	check_eq(bag.add(x, Inventory.SLOTS * 10 + 7), 7, "leftover returned")
	check_eq(bag.free_slots(ItemDef.Tab.ETC), 0, "tab full")
	check_eq(bag.add(x, 1), 1, "nothing more fits")
	check_eq(bag.count_of(x), Inventory.SLOTS * 10, "count capped at capacity")

func test_full_tab_does_not_block_other_tabs() -> void:
	var x := fx.etc(&"t_etc", 1)
	bag.add(x, Inventory.SLOTS)
	check_eq(bag.add(fx.use(), 3), 0, "Use tab still has room")

func test_add_zero_changes_nothing() -> void:
	var x := fx.etc()
	var emitted := [0]
	bag.changed.connect(func() -> void: emitted[0] += 1)
	check_eq(bag.add(x, 0), 0, "nothing left over")
	check_eq(bag.free_slots(ItemDef.Tab.ETC), Inventory.SLOTS, "no slot used")
	check_eq(emitted[0], 0, "no changed signal")

func test_changed_not_emitted_when_nothing_fits() -> void:
	var x := fx.etc(&"t_etc", 1)
	bag.add(x, Inventory.SLOTS)
	var emitted := [0]
	bag.changed.connect(func() -> void: emitted[0] += 1)
	bag.add(x, 1)
	check_eq(emitted[0], 0, "no signal for a failed add")

func test_gear_takes_one_slot_each_even_when_adding_many() -> void:
	var e := fx.equip()
	check_eq(bag.add(e, 3), 0, "three swords fit")
	for i in 3:
		check_eq(bag.at(ItemDef.Tab.EQUIP, i).count, 1, "sword %d alone in its slot" % i)
	check(bag.at(ItemDef.Tab.EQUIP, 0) != bag.at(ItemDef.Tab.EQUIP, 1), "separate stacks")

func test_max_stack_below_one_still_holds_one() -> void:
	var x := fx.etc(&"t_etc", 0)
	check_eq(x.stack_size(), 1, "stack size floor")
	bag.add(x, 2)
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 1, "second item in its own slot")

func test_add_stack_merges_stackables_and_reports_leftover() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(x, Inventory.SLOTS * 10 - 2)
	var s := ItemStack.create(x, 5)
	check(not bag.add_stack(s), "did not all fit")
	check_eq(s.count, 3, "stack keeps what didn't fit")
	check_eq(bag.count_of(x), Inventory.SLOTS * 10, "rest went in")

func test_add_stack_keeps_gear_object_with_its_stats() -> void:
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 10})
	var s := ItemStack.exact(e)
	s.stats.attack = 99
	check(bag.add_stack(s), "fits")
	check(bag.at(ItemDef.Tab.EQUIP, 0) == s, "same stack object stored")
	check_eq(bag.at(ItemDef.Tab.EQUIP, 0).stats.attack, 99, "rolled stats kept")

func test_add_stack_gear_into_full_tab_fails() -> void:
	var e := fx.equip()
	bag.add(e, Inventory.SLOTS)
	check(not bag.add_stack(ItemStack.exact(e)), "no room")
	check_eq(bag.free_slots(ItemDef.Tab.EQUIP), 0, "still full")

func test_has_room_counts_partial_stacks_and_free_slots() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(x, Inventory.SLOTS * 10 - 4)
	check(bag.has_room(x, 4), "exactly fills")
	check(not bag.has_room(x, 5), "one too many")
	check(bag.has_room(fx.etc(&"t_other", 10), 0), "zero always fits")

func test_has_room_for_other_item_ignores_partial_stacks() -> void:
	var x := fx.etc(&"t_etc", 10)
	var y := fx.etc(&"t_other", 10)
	bag.add(x, Inventory.SLOTS * 10 - 4)
	check(not bag.has_room(y, 1), "partial stack of another item is no room")

func test_room_for_needs_a_free_slot_per_stack_per_tab() -> void:
	var x := fx.etc(&"t_etc", 1)
	bag.add(x, Inventory.SLOTS - 2)
	var two := [ItemStack.create(x), ItemStack.create(x)]
	var three := [ItemStack.create(x), ItemStack.create(x), ItemStack.create(x)]
	check(bag.room_for(two), "two free slots for two stacks")
	check(not bag.room_for(three), "not three")
	check(bag.room_for([ItemStack.create(fx.use())]), "other tab has room")
	check(bag.room_for([]), "nothing always fits")

func test_tab_without_room_fits_when_everything_fits() -> void:
	check_eq(bag.tab_without_room([[fx.equip(), 1], [fx.use(), 30]]), -1, "an empty bag fits")
	check_eq(bag.tab_without_room([]), -1, "nothing always fits")

func test_tab_without_room_names_the_full_tab() -> void:
	var e := fx.equip()
	bag.add(e, Inventory.SLOTS)
	check_eq(bag.tab_without_room([[fx.use(), 1], [fx.equip(&"t_other"), 1]]), ItemDef.Tab.EQUIP, "gear has nowhere to go")

func test_tab_without_room_counts_topping_up_stacks() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(x, Inventory.SLOTS * 10 - 4)
	check_eq(bag.tab_without_room([[x, 4]]), -1, "tops up the last stack exactly")
	check_eq(bag.tab_without_room([[x, 5]]), ItemDef.Tab.ETC, "one too many")

func test_tab_without_room_adds_up_the_same_item_asked_twice() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(x, (Inventory.SLOTS - 1) * 10)
	check_eq(bag.tab_without_room([[x, 6], [x, 4]]), -1, "10 fill the one free slot")
	check_eq(bag.tab_without_room([[x, 6], [x, 5]]), ItemDef.Tab.ETC, "11 need two slots")

func test_tab_without_room_items_share_a_tabs_free_slots() -> void:
	var a := fx.etc(&"t_a", 10)
	var b := fx.etc(&"t_b", 10)
	bag.add(fx.etc(&"t_junk", 10), (Inventory.SLOTS - 1) * 10)
	check_eq(bag.tab_without_room([[a, 1]]), -1, "one item fits the free slot")
	check_eq(bag.tab_without_room([[a, 1], [b, 1]]), ItemDef.Tab.ETC, "two items can't share it")

func test_tab_without_room_rounds_stacks_up() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(fx.etc(&"t_junk", 10), (Inventory.SLOTS - 2) * 10)
	check_eq(bag.tab_without_room([[x, 20]]), -1, "two full stacks in two slots")
	check_eq(bag.tab_without_room([[x, 21]]), ItemDef.Tab.ETC, "21 need a third slot")

func test_tab_without_room_skips_empty_entries() -> void:
	bag.add(fx.equip(), Inventory.SLOTS)
	check_eq(bag.tab_without_room([[null, 5]]), -1, "an empty gift line asks for nothing")

func test_take_all_empties_slot_and_returns_same_stack() -> void:
	var x := fx.etc()
	bag.add(x, 7)
	var s := bag.at(ItemDef.Tab.ETC, 0)
	var taken := bag.take(ItemDef.Tab.ETC, 0)
	check(taken == s, "returns the stack itself")
	check(bag.at(ItemDef.Tab.ETC, 0) == null, "slot empty")

func test_take_part_splits_stack() -> void:
	var x := fx.etc()
	bag.add(x, 7)
	var taken := bag.take(ItemDef.Tab.ETC, 0, 3)
	check_eq(taken.count, 3, "taken count")
	check_eq(taken.item, x, "taken item")
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 4, "left behind")

func test_take_more_than_stack_takes_whole_stack() -> void:
	var x := fx.etc()
	bag.add(x, 7)
	check_eq(bag.take(ItemDef.Tab.ETC, 0, 50).count, 7, "whole stack")
	check(bag.at(ItemDef.Tab.ETC, 0) == null, "slot empty")

func test_take_from_empty_slot_is_null() -> void:
	check(bag.take(ItemDef.Tab.ETC, 5) == null, "nothing to take")

func test_put_overwrites_slot() -> void:
	var x := fx.etc()
	var y := fx.etc(&"t_other")
	bag.add(x, 2)
	bag.put(ItemDef.Tab.ETC, 0, ItemStack.create(y, 1))
	check_eq(bag.at(ItemDef.Tab.ETC, 0).item, y, "replaced")
	check_eq(bag.count_of(x), 0, "old one gone")

func test_move_into_empty_slot() -> void:
	var x := fx.etc()
	bag.add(x, 5)
	bag.move(ItemDef.Tab.ETC, 0, 9)
	check(bag.at(ItemDef.Tab.ETC, 0) == null, "source empty")
	check_eq(bag.at(ItemDef.Tab.ETC, 9).count, 5, "moved")

func test_move_merges_matching_stacks() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.put(ItemDef.Tab.ETC, 0, ItemStack.create(x, 4))
	bag.put(ItemDef.Tab.ETC, 1, ItemStack.create(x, 3))
	bag.move(ItemDef.Tab.ETC, 0, 1)
	check(bag.at(ItemDef.Tab.ETC, 0) == null, "source emptied")
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 7, "merged")

func test_move_merge_leaves_remainder_when_target_fills() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.put(ItemDef.Tab.ETC, 0, ItemStack.create(x, 6))
	bag.put(ItemDef.Tab.ETC, 1, ItemStack.create(x, 7))
	bag.move(ItemDef.Tab.ETC, 0, 1)
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 10, "target full")
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 3, "remainder stays")

func test_move_onto_full_matching_stack_swaps() -> void:
	var x := fx.etc(&"t_etc", 10)
	var a := ItemStack.create(x, 2)
	var b := ItemStack.create(x, 10)
	bag.put(ItemDef.Tab.ETC, 0, a)
	bag.put(ItemDef.Tab.ETC, 1, b)
	bag.move(ItemDef.Tab.ETC, 0, 1)
	check(bag.at(ItemDef.Tab.ETC, 0) == b and bag.at(ItemDef.Tab.ETC, 1) == a, "swapped")

func test_move_different_items_swaps() -> void:
	var a := ItemStack.create(fx.etc(), 2)
	var b := ItemStack.create(fx.etc(&"t_other"), 3)
	bag.put(ItemDef.Tab.ETC, 0, a)
	bag.put(ItemDef.Tab.ETC, 1, b)
	bag.move(ItemDef.Tab.ETC, 0, 1)
	check(bag.at(ItemDef.Tab.ETC, 0) == b and bag.at(ItemDef.Tab.ETC, 1) == a, "swapped")

func test_move_gear_never_merges() -> void:
	var e := fx.equip()
	bag.add(e, 2)
	var a := bag.at(ItemDef.Tab.EQUIP, 0)
	var b := bag.at(ItemDef.Tab.EQUIP, 1)
	bag.move(ItemDef.Tab.EQUIP, 0, 1)
	check(bag.at(ItemDef.Tab.EQUIP, 0) == b and bag.at(ItemDef.Tab.EQUIP, 1) == a, "swapped, not merged")

func test_move_to_same_slot_or_from_empty_is_noop() -> void:
	var x := fx.etc()
	bag.add(x, 5)
	bag.move(ItemDef.Tab.ETC, 0, 0)
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 5, "same slot")
	bag.move(ItemDef.Tab.ETC, 4, 0)
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 5, "empty source")
	check(bag.at(ItemDef.Tab.ETC, 4) == null, "empty source stays empty")

func test_remove_takes_across_stacks() -> void:
	var x := fx.etc(&"t_etc", 10)
	bag.add(x, 25)
	check_eq(bag.remove(x, 14), 14, "taken")
	check_eq(bag.count_of(x), 11, "left")
	check(bag.at(ItemDef.Tab.ETC, 0) == null, "first stack used up first")

func test_remove_more_than_held_returns_what_was_there() -> void:
	var x := fx.etc()
	bag.add(x, 3)
	check_eq(bag.remove(x, 10), 3, "only three")
	check_eq(bag.count_of(x), 0, "none left")
	check_eq(bag.remove(x, 1), 0, "nothing to remove")

func test_find_and_count_of() -> void:
	var x := fx.etc()
	var y := fx.etc(&"t_other")
	bag.put(ItemDef.Tab.ETC, 5, ItemStack.create(x, 2))
	bag.put(ItemDef.Tab.ETC, 9, ItemStack.create(x, 4))
	check_eq(bag.find(x), 5, "first slot")
	check_eq(bag.find(y), -1, "missing item")
	check_eq(bag.find(null), -1, "null item")
	check_eq(bag.count_of(x), 6, "count across slots")

func test_clear_empties_everything() -> void:
	bag.add(fx.etc(), 5)
	bag.add(fx.equip())
	bag.clear()
	for t in ItemDef.Tab.size():
		check_eq(bag.free_slots(t), Inventory.SLOTS, "tab %d empty" % t)

func test_save_round_trip_keeps_slots_counts_and_stats() -> void:
	var x := fx.etc()
	var e := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 10})
	bag.put(ItemDef.Tab.ETC, 3, ItemStack.create(x, 17))
	var g := ItemStack.exact(e)
	g.stats.attack = 13
	bag.put(ItemDef.Tab.EQUIP, 20, g)
	var back := Inventory.new()
	back.load_dict(bag.to_dict())
	check_eq(back.at(ItemDef.Tab.ETC, 3).count, 17, "etc slot and count")
	check_eq(back.at(ItemDef.Tab.EQUIP, 20).stats.attack, 13, "gear stats")
	check_eq(back.free_slots(ItemDef.Tab.ETC), Inventory.SLOTS - 1, "nothing else")

func test_load_skips_unknown_wrong_tab_and_bad_entries() -> void:
	var x := fx.etc()
	var data := {
		"Etc": [{"id": "t_missing_item", "count": 1, "slot": 0}, "junk", {"id": "t_etc", "count": 2, "slot": 1}],
		"Use": [{"id": "t_etc", "count": 5, "slot": 0}],
		"Equip": "not a list",
	}
	bag.load_dict(data)
	check(bag.at(ItemDef.Tab.ETC, 0) == null, "unknown item dropped")
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 2, "good entry loaded")
	check(bag.at(ItemDef.Tab.USE, 0) == null, "item in the wrong tab dropped")
	check_eq(bag.count_of(x), 2, "only the good one")

func test_load_bad_or_taken_slot_moves_to_first_free() -> void:
	fx.etc()
	bag.load_dict({"Etc": [
		{"id": "t_etc", "count": 1, "slot": 2},
		{"id": "t_etc", "count": 2, "slot": 2},
		{"id": "t_etc", "count": 3, "slot": 999},
		{"id": "t_etc", "count": 4},
	]})
	check_eq(bag.at(ItemDef.Tab.ETC, 2).count, 1, "first claim wins")
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 2, "duplicate slot moves to first free")
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 3, "out of range slot moves")
	check_eq(bag.at(ItemDef.Tab.ETC, 3).count, 4, "missing slot moves")

func test_load_clamps_counts_to_stack_size() -> void:
	fx.etc(&"t_etc", 10)
	bag.load_dict({"Etc": [{"id": "t_etc", "count": 500, "slot": 0}, {"id": "t_etc", "count": -3, "slot": 1}]})
	check_eq(bag.at(ItemDef.Tab.ETC, 0).count, 10, "clamped to max stack")
	check_eq(bag.at(ItemDef.Tab.ETC, 1).count, 1, "at least one")

func test_load_replaces_existing_contents() -> void:
	bag.add(fx.etc(), 5)
	bag.load_dict({})
	check_eq(bag.free_slots(ItemDef.Tab.ETC), Inventory.SLOTS, "cleared")
