extends TestCase
## Gear tiers on one piece (ItemStack.tier): a higher tier makes its own stats bigger but not
## its runes', and the tier is saved (pieces from before tiers load at tier 1).

var cap: EquipDef

func before_each() -> void:
	cap = EquipDef.new()
	cap.id = &"test_cap"
	cap.slot = EquipDef.Slot.HAT
	cap.stats = StatBlock.new()
	cap.stats.attack = 10
	cap.stats.defense = 4

func test_a_higher_tier_scales_its_own_stats_not_its_runes() -> void:
	var s := ItemStack.exact(cap)
	check_eq(s.total().attack, 10, "tier 1 is as listed")
	var rune := RuneDef.new()
	rune.stats = StatBlock.new()
	rune.stats.attack = 3
	s.runes[0] = rune
	s.tier = 3
	var k := Content.gear_tier(3).stat_scale
	check_eq(s.own_stats().attack, roundi(10 * k), "attack grows")
	check_eq(s.own_stats().defense, roundi(4 * k), "defense grows")
	check_eq(s.total().attack, roundi(10 * k) + 3, "the rune adds what it always does")
	check_eq(s.stats.attack, 10, "the rolled stats stay as rolled")

func test_the_top_tier_has_no_next() -> void:
	var s := ItemStack.exact(cap)
	check(s.next_tier() == Content.gear_tier(2), "tier 1 goes to 2")
	s.tier = Content.top_gear_tier()
	check(s.next_tier() == null, "nothing past the top")
	check(ItemStack.create(Content.item(&"green_leaf")).next_tier() == null, "only gear has tiers")

func test_the_tier_is_saved_and_old_saves_load_at_tier_1() -> void:
	var real: EquipDef = Content.item(&"squire_helm")
	var s := ItemStack.exact(real)
	s.tier = 4
	check_eq(ItemStack.from_dict(s.to_dict()).tier, 4, "round trip")
	var old := ItemStack.exact(real).to_dict()
	check(not old.has("tier"), "tier 1 isn't written")
	check_eq(ItemStack.from_dict(old).tier, 1, "no tier loads as 1")
	old["tier"] = 99
	check_eq(ItemStack.from_dict(old).tier, Content.top_gear_tier(), "a tier past the top is cut to it")
