extends TestCase
## Enchanting through the server: an enchanter sets a rune from the bag in a rune slot of a
## piece of gear in the bag for the rune's fee, always; one set over another is lost; it takes
## an enchanter close by and the fee; runes in worn gear add to the stats; and monsters drop
## their zone's runes.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const ENCHANTER_X := 400.0
const MERCHANT_X := 900.0

var h: ServerHarness
var p: SimPlayer
var c: Character
var rune: RuneDef
var other: RuneDef
var cap: EquipDef

func before_each() -> void:
	h = ServerHarness.new()
	rune = h.add_item(_rune(&"test_rune", "Test Rune", 150)) as RuneDef
	other = h.add_item(_rune(&"test_other_rune", "Other Rune", 50)) as RuneDef
	cap = EquipDef.new()
	cap.id = &"test_cap"
	cap.display_name = "Test Cap"
	cap.slot = EquipDef.Slot.HAT
	cap.stats = StatBlock.new()
	cap.stats.attack = 2
	h.add_item(cap)
	var town := ServerHarness.town_def()
	ServerHarness.npc(town, &"test_enchanter", ENCHANTER_X).enchants = true
	ServerHarness.npc(town, &"test_merchant", MERCHANT_X).shop = ServerHarness.shop([])
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.TOWN, ENCHANTER_X)
	c = p.character
	c.inventory.clear()
	c.inventory.put(ItemDef.Tab.EQUIP, 0, ItemStack.exact(cap))
	c.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(rune, 2))
	c.inventory.put(ItemDef.Tab.ETC, 1, ItemStack.create(other, 1))
	c.shards = 500

func after_each() -> void:
	h.close()

static func _rune(id: StringName, name: String, fee: int) -> RuneDef:
	var r := RuneDef.new()
	r.id = id
	r.display_name = name
	r.fee = fee
	r.stats = StatBlock.new()
	r.stats.attack = 3
	return r

func _gear() -> ItemStack:
	return c.inventory.at(ItemDef.Tab.EQUIP, 0)

func test_setting_a_rune_takes_its_fee_and_one_rune() -> void:
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 1])
	check(_gear().runes[1] == rune, "set in the second slot")
	check(_gear().runes[0] == null and _gear().runes[2] == null, "the others still empty")
	check_eq(c.inventory.count_of(rune), 1, "one rune used")
	check_eq(c.shards, 500 - 150, "fee paid")
	check(h.told(2, "The Test Rune is set in the %s." % cap.display_name), "told")
	check(h.saved("Ann").inventory.at(ItemDef.Tab.EQUIP, 0).runes[1] != null, "saved at once")

func test_a_rune_set_over_another_replaces_it() -> void:
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 0])
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 1, 0])
	check(_gear().runes[0] == other, "the new one is there")
	check_eq(c.inventory.count_of(rune), 1, "the old one is gone, not back in the bag")
	check_eq(_gear().total().attack, cap.stats.attack + 3, "only one rune counts")

func test_it_takes_the_fee() -> void:
	c.shards = 149
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 0])
	check(_gear().runes[0] == null, "not set")
	check_eq(c.inventory.count_of(rune), 2, "rune kept")
	check_eq(c.shards, 149, "nothing taken")
	check(h.told(2, "You don't have enough Dawnshards."), "told why")

func test_it_takes_an_enchanter_close_by() -> void:
	h.place(p, MERCHANT_X)
	h.ask(2, &"req_enchant", [&"test_merchant", 0, 0, 0])
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 0])
	check(_gear().runes[0] == null, "a shopkeeper doesn't, and the enchanter is too far away")
	check_eq(c.shards, 500, "nothing taken")

func test_it_takes_a_rune_and_a_real_slot() -> void:
	c.inventory.put(ItemDef.Tab.ETC, 2, ItemStack.create(Content.item(&"green_leaf"), 1))
	for args in [[0, 2, 0], [0, 5, 0], [3, 0, 0], [0, 0, ItemStack.RUNE_SLOTS], [0, 0, -1], [-1, 0, 0], [99, 0, 0]]:
		h.ask(2, &"req_enchant", [&"test_enchanter"] + args)
	check(_gear().runes.all(func(r: RuneDef) -> bool: return r == null), "nothing set")
	check_eq(c.shards, 500, "nothing taken")

func test_runes_in_worn_gear_add_to_the_stats() -> void:
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 0])
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 2])
	var before := c.stats.attack
	h.ask(2, &"req_equip", [0, &""])
	check_eq(c.stats.attack - before, cap.stats.attack + 6, "the cap and both runes")

func test_monsters_drop_their_zones_runes() -> void:
	var zone := RegionDef.new()
	zone.id = &"test_zone"
	zone.drops = [ServerHarness.drop(rune)]
	h.add_region(zone)
	var mob := ServerHarness.monster()
	var field := ServerHarness.field_def()
	field.region = zone.id
	field.spawns.append(ServerHarness.spawn(mob))
	h.add_map(field)
	h.server.maps.erase(ServerHarness.FIELD)
	var map := h.server.map_instance(ServerHarness.FIELD)
	map.mobs[0].position.x = 340.0
	h.move_to(p, ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(p, mob)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	h.step(60)
	check(map.drops.values().any(func(d: SimDrop) -> bool: return d.item == rune), "a rune dropped")

# ---------- tiers ----------

func test_upgrading_raises_a_tier_for_its_fee_and_keeps_runes() -> void:
	h.ask(2, &"req_enchant", [&"test_enchanter", 0, 0, 0])
	c.shards = 5000
	var fee := Content.gear_tier(2).fee
	h.ask(2, &"req_upgrade", [&"test_enchanter", 0])
	check_eq(_gear().tier, 2, "one tier up")
	check_eq(c.shards, 5000 - fee, "fee paid")
	check(_gear().runes[0] == rune, "its rune stays")
	check_eq(_gear().total().attack, roundi(cap.stats.attack * Content.gear_tier(2).stat_scale) + 3,
		"its own stats grow, its rune's don't")
	check(h.told(2, "The Test Cap is now %s." % Content.gear_tier(2).display_name), "told")
	check_eq(h.saved("Ann").inventory.at(ItemDef.Tab.EQUIP, 0).tier, 2, "saved at once")

func test_upgrading_takes_the_fee_an_enchanter_and_stops_at_the_top() -> void:
	c.shards = Content.gear_tier(2).fee - 1
	h.ask(2, &"req_upgrade", [&"test_enchanter", 0])
	check_eq(_gear().tier, 1, "not enough Dawnshards")
	check(h.told(2, "You don't have enough Dawnshards."), "told why")
	c.shards = 999999
	h.ask(2, &"req_upgrade", [&"test_merchant", 0])
	h.ask(2, &"req_upgrade", [&"test_enchanter", 5])
	check_eq(_gear().tier, 1, "a shopkeeper doesn't, and an empty slot can't")
	for i in Content.top_gear_tier() + 2:
		h.ask(2, &"req_upgrade", [&"test_enchanter", 0])
	check_eq(_gear().tier, Content.top_gear_tier(), "stops at the top tier")
	check(h.told(2, "The Test Cap can't go any higher."), "told why")
