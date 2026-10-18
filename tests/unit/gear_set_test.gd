extends TestCase
## Job sets (GearSetDef): the Vanguard's two pieces, and Battle Fury while both are worn (a
## stack per kill up to five, faster swings, gone when a piece comes off).

var fx: UnitHelpers
var c: Character
var set_def: GearSetDef
var fury: SkillDef

func before_each() -> void:
	fx = UnitHelpers.new()
	c = fx.character(Content.job(&"warrior"))
	set_def = Content.gear_sets[&"vanguard"]
	fury = set_def.kill_buff

func after_each() -> void:
	fx.cleanup()

func _wear(e: EquipDef) -> void:
	c.inventory.add_stack(ItemStack.exact(e))
	for i in Inventory.SLOTS:
		var s := c.inventory.at(ItemDef.Tab.EQUIP, i)
		if s and s.item == e:
			check_eq(c.gear.equip(i), "", "wears the %s" % e.display_name)
			return

func test_the_vanguard_is_one_armor_and_one_sword_for_warriors() -> void:
	check_eq(set_def.armor.slot, EquipDef.Slot.ARMOR, "the armor")
	check_eq(set_def.weapon.slot, EquipDef.Slot.WEAPON, "the weapon")
	check_eq(set_def.weapon.weapon_kind, &"sword", "a sword")
	for e in [set_def.armor, set_def.weapon]:
		check_eq(e.jobs, [&"warrior"] as Array[StringName], "%s: Warriors only" % e.id)
		check(e.icon != null, "%s has its painted icon" % e.id)
		check(GearSetDef.of(e) == set_def, "%s belongs to the set" % e.id)

func test_battle_fury_needs_both_pieces() -> void:
	_wear(set_def.armor)
	check(not c.gear.on_kill(), "the armor alone gives no fury")
	check(not c.skills.buffs.has(fury.id), "no buff")
	_wear(set_def.weapon)
	check(c.gear.full_set() == set_def, "both worn")
	check(c.gear.on_kill(), "a kill with both on")
	check_eq(c.skills.buffs[fury.id][0], 1, "one stack")

func test_each_kill_adds_a_stack_up_to_five_and_starts_the_time_again() -> void:
	_wear(set_def.armor)
	_wear(set_def.weapon)
	var plain := c.stats.attack_speed
	for i in 7:
		c.gear.on_kill()
		c.skills.tick_buffs(60)
	check_eq(c.skills.buffs[fury.id][0], 5, "five stacks at most")
	check_eq(c.skills.buffs[fury.id][1], 8 * 60 - 60, "eight seconds from the last kill")
	check_eq(c.stats.attack_speed, plain + 30, "6% faster swings a stack")
	c.skills.tick_buffs(8 * 60)
	check(not c.skills.buffs.has(fury.id), "gone eight seconds after the last kill")
	check_eq(c.stats.attack_speed, plain, "back to the plain speed")

func test_taking_a_piece_off_ends_the_fury() -> void:
	_wear(set_def.armor)
	_wear(set_def.weapon)
	c.gear.on_kill()
	check(c.skills.buffs.has(fury.id), "running")
	check_eq(c.gear.unequip(&"weapon"), "", "the sword comes off")
	check(not c.skills.buffs.has(fury.id), "the fury ends with it")

func test_battle_fury_is_never_learned() -> void:
	check_eq(fury.job, &"", "in no job's skill book")
	check_eq(fury.kind, SkillDef.Kind.BUFF, "a buff")

func test_the_emberforge_armory_sells_the_vanguard_set_for_what_the_squire_set_cost() -> void:
	var shop := Content.shop(&"forge_armory")
	var items := shop.items.map(func(l: ShopEntry) -> ItemDef: return l.item)
	check_eq(items, [set_def.armor, set_def.weapon], "the two pieces")
	var total := 0
	for l: ShopEntry in shop.items:
		check(l.open_to(c), "%s on sale from the start" % l.item.id)
		total += l.cost()
	check_eq(total, 7400, "the Squire set's price")
