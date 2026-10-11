extends TestCase
## Equipment and wearing gear: places on the body, rings, job, level and stat restrictions,
## stat bonuses reaching the character, swapping with the bag, taking off, and saves.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func test_every_slot_kind_has_a_place() -> void:
	for slot in EquipDef.Slot.values():
		check(Equipment.PLACES_FOR.has(slot), "slot %d has places" % slot)
		for p in Equipment.PLACES_FOR[slot]:
			check_has(Equipment.PLACES, p, "place exists")

func test_fits_only_matching_places() -> void:
	var ring := fx.equip(&"t_ring", EquipDef.Slot.RING)
	check(Equipment.fits(ring, &"ring_1"), "ring_1")
	check(Equipment.fits(ring, &"ring_2"), "ring_2")
	check(not Equipment.fits(ring, &"hat"), "not hat")
	check(not Equipment.fits(fx.equip(), &"shield"), "sword not in shield")

func test_rings_fill_both_ring_places_then_first() -> void:
	var eq := Equipment.new()
	var ring := fx.equip(&"t_ring", EquipDef.Slot.RING)
	check_eq(eq.place_for(ring), &"ring_1", "first ring")
	eq.put(&"ring_1", ItemStack.exact(ring))
	check_eq(eq.place_for(ring), &"ring_2", "second ring")
	eq.put(&"ring_2", ItemStack.exact(ring))
	check_eq(eq.place_for(ring), &"ring_1", "both full: first again")

func test_put_returns_previous_and_take_removes() -> void:
	var eq := Equipment.new()
	var a := ItemStack.exact(fx.equip(&"t_a"))
	var b := ItemStack.exact(fx.equip(&"t_b"))
	check(eq.put(&"weapon", a) == null, "nothing before")
	check(eq.put(&"weapon", b) == a, "old one returned")
	check(eq.take(&"weapon") == b, "take returns worn")
	check(eq.at(&"weapon") == null, "now empty")
	check(eq.take(&"weapon") == null, "taking nothing")

func test_bonus_sums_every_worn_piece() -> void:
	var eq := Equipment.new()
	eq.put(&"weapon", ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 10, "strength": 2})))
	eq.put(&"hat", ItemStack.exact(fx.equip(&"t_b", EquipDef.Slot.HAT, {"defense": 5, "strength": 3})))
	var b := eq.bonus()
	check_eq(b.attack, 10, "attack")
	check_eq(b.defense, 5, "defense")
	check_eq(b.strength, 5, "strength adds up")
	check_eq(Equipment.new().bonus().nonzero().size(), 0, "nothing worn, nothing added")

func test_changed_emitted_on_put_and_take() -> void:
	var eq := Equipment.new()
	var n := [0]
	eq.changed.connect(func() -> void: n[0] += 1)
	eq.put(&"weapon", ItemStack.exact(fx.equip()))
	eq.take(&"weapon")
	eq.clear()
	check_eq(n[0], 3, "three changes")

func test_save_round_trip() -> void:
	var eq := Equipment.new()
	var s := ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 10}))
	s.stats.attack = 12
	eq.put(&"weapon", s)
	eq.put(&"ring_2", ItemStack.exact(fx.equip(&"t_r", EquipDef.Slot.RING)))
	var back := Equipment.new()
	back.load_dict(eq.to_dict())
	check_eq(back.at(&"weapon").stats.attack, 12, "rolled stats kept")
	check_eq(back.at(&"ring_2").item.id, &"t_r", "ring in ring_2")
	check(back.at(&"ring_1") == null, "ring_1 empty")

func test_load_drops_bad_places_and_misfits() -> void:
	fx.equip(&"t_a", EquipDef.Slot.WEAPON)
	fx.etc(&"t_etc")
	var eq := Equipment.new()
	eq.load_dict({
		"wings": {"id": "t_a"},
		"hat": {"id": "t_a"},
		"weapon": {"id": "t_etc"},
		"shield": "junk",
		"shoes": {"id": "t_unknown"},
	})
	check_eq(eq.worn.size(), 0, "nothing loaded")

# ---------- wearing through the character ----------

func test_equip_moves_gear_from_bag_and_adds_stats() -> void:
	var c := fx.character(null, {"strength": 10})
	c.inventory.add_stack(ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 15, "strength": 4, "max_hp": 30})))
	var hp_before := c.max_hp()
	check_eq(c.gear.equip(0), "", "equipped")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 0) == null, "left the bag")
	check_eq(c.stats.attack, 15, "attack")
	check_eq(c.stats.strength, 14, "strength")
	check_eq(c.base.strength, 10, "base unchanged")
	check_eq(c.max_hp(), hp_before + 30, "max HP")

func test_equip_swaps_old_gear_into_same_bag_slot() -> void:
	var c := fx.character()
	var a := ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 5}))
	var b := ItemStack.exact(fx.equip(&"t_b", EquipDef.Slot.WEAPON, {"attack": 9}))
	c.inventory.put(ItemDef.Tab.EQUIP, 0, a)
	c.inventory.put(ItemDef.Tab.EQUIP, 7, b)
	c.gear.equip(0)
	c.gear.equip(7)
	check(c.equipment.at(&"weapon") == b, "new one worn")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 7) == a, "old one where the new one was")
	check_eq(c.stats.attack, 9, "stats follow")

func test_equip_empty_slot_does_nothing() -> void:
	var c := fx.character()
	check_eq(c.gear.equip(3), "", "no problem")
	check_eq(c.equipment.worn.size(), 0, "nothing worn")

func test_equip_refused_for_other_job_line() -> void:
	var c := fx.character()
	var e := fx.equip(&"t_bow", EquipDef.Slot.WEAPON)
	e.jobs = [&"archer"]
	c.inventory.add_stack(ItemStack.exact(e))
	check_ne(c.gear.equip(0), "", "wrong job")
	check(c.equipment.at(&"weapon") == null, "not worn")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 0) != null, "still in bag")

func test_equip_allowed_for_listed_family() -> void:
	var c := fx.character(fx.job(&"t_job", &"archer"))
	var e := fx.equip(&"t_bow", EquipDef.Slot.WEAPON)
	e.jobs = [&"warrior", &"archer"]
	check_eq(c.gear.equip_problem(e), "", "archer family listed")
	check(c.gear.can_use([]), "empty list is anyone")

func test_equip_level_requirement_boundary() -> void:
	var c := fx.character()
	var e := fx.equip()
	e.required_level = 5
	c.level = 4
	check_ne(c.gear.equip_problem(e), "", "level 4 too low")
	c.level = 5
	check_eq(c.gear.equip_problem(e), "", "level 5 enough")

func test_equip_stat_requirement_uses_total_stats() -> void:
	var c := fx.character(null, {"dexterity": 20})
	var e := fx.equip(&"t_bow")
	e.required_dexterity = 25
	check_ne(c.gear.equip_problem(e), "", "20 DEX too low")
	c.equipment.put(&"hat", ItemStack.exact(fx.equip(&"t_hat", EquipDef.Slot.HAT, {"dexterity": 5})))
	check_eq(c.gear.equip_problem(e), "", "gear DEX counts")

func test_requirements_lists_only_nonzero() -> void:
	var e := fx.equip()
	check_eq(e.requirements(), {}, "none")
	e.required_level = 10
	e.required_luck = 30
	check_eq(e.requirements(), {&"level": 10, &"luck": 30}, "level and luck")

func test_equip_to_named_place_and_invalid_place_falls_back() -> void:
	var c := fx.character()
	var ring := fx.equip(&"t_ring", EquipDef.Slot.RING)
	c.inventory.add(ring, 2)
	c.gear.equip(0, &"ring_2")
	check(c.equipment.at(&"ring_2") != null, "went to ring_2")
	c.gear.equip(1, &"hat")
	check(c.equipment.at(&"ring_1") != null, "a hat place isn't for rings: first free ring place")

func test_unequip_to_chosen_free_slot() -> void:
	var c := fx.character()
	var s := ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 7}))
	c.equipment.put(&"weapon", s)
	check_eq(c.stats.attack, 7, "worn")
	check_eq(c.gear.unequip(&"weapon", 5), "", "taken off")
	check(c.inventory.at(ItemDef.Tab.EQUIP, 5) == s, "in slot 5")
	check_eq(c.stats.attack, 0, "stats gone")

func test_unequip_to_taken_or_invalid_slot_uses_first_free() -> void:
	var c := fx.character()
	c.inventory.add(fx.equip(&"t_b"), 1)
	c.equipment.put(&"weapon", ItemStack.exact(fx.equip(&"t_a")))
	c.gear.unequip(&"weapon", 0)
	check_eq(c.inventory.at(ItemDef.Tab.EQUIP, 1).item.id, &"t_a", "slot 0 taken: went to 1")
	c.equipment.put(&"hat", ItemStack.exact(fx.equip(&"t_h", EquipDef.Slot.HAT)))
	c.gear.unequip(&"hat", 99)
	check_eq(c.inventory.at(ItemDef.Tab.EQUIP, 2).item.id, &"t_h", "bad index: first free")

func test_unequip_with_full_bag_is_refused() -> void:
	var c := fx.character()
	c.inventory.add(fx.equip(&"t_b"), Inventory.SLOTS)
	c.equipment.put(&"weapon", ItemStack.exact(fx.equip(&"t_a")))
	check_ne(c.gear.unequip(&"weapon"), "", "no room")
	check(c.equipment.at(&"weapon") != null, "still worn")

func test_unequip_nothing_is_fine() -> void:
	check_eq(fx.character().gear.unequip(&"cape"), "", "no problem")

func test_families_text() -> void:
	check_eq(EquipDef.families_text([]), "", "none")
	check_eq(EquipDef.families_text([&"warrior"]), "Warriors", "one")
	check_eq(EquipDef.families_text([&"warrior", &"pirate"]), "Warriors and Pirates", "two")
	check_eq(EquipDef.families_text([&"mage", &"warrior", &"archer"]), "Mages, Warriors and Archers", "three")
