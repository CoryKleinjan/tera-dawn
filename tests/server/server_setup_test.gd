extends TestCase
## Sitting on the ground (and its faster regeneration) and the Setup tab through the
## server: pets coming out, picking up loot, getting hungry and being fed. Also achievements
## reaching the player as ev_achievement.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var p: SimPlayer
var c: Character
var sprout: PetDef

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	c = p.character
	sprout = Content.item(&"pet_sprout")
	c.inventory.put(ItemDef.Tab.SETUP, 1, ItemStack.create(sprout))

func after_each() -> void:
	h.close()

## Steps once so that the map's next tick is an MP regeneration tick.
func _regen_tick() -> void:
	p.map.tick = SimPlayer.REGEN_EVERY - 1
	h.step(1)

## Steps once so that the map's next tick is a heart regeneration tick (standing).
func _heart_tick() -> void:
	p.map.tick = SimPlayer.HEART_REGEN_EVERY - 1
	h.step(1)

# ---------- sitting ----------

func test_sitting_down() -> void:
	h.ask(2, &"req_sit", [true])
	check(p.sitting, "sitting")
	check_eq(h.last(2, &"ev_sit"), [true], "client told")
	check_eq(int(c.counters.get(Counters.SAT, 0)), 1, "counted")

func test_sitting_doubles_regeneration() -> void:
	c.mp = 0
	_regen_tick()
	check_eq(c.mp, 2, "2 MP standing")
	h.ask(2, &"req_sit", [true])
	_regen_tick()
	check_eq(c.mp, 2 + 4, "4 MP sitting")

func test_a_heart_comes_back_on_its_own() -> void:
	c.health.set_hp(1)
	_heart_tick()
	check_eq(c.health.hp, 2, "a heart back standing")
	h.ask(2, &"req_sit", [true])
	p.map.tick = SimPlayer.HEART_REGEN_EVERY / 2 - 1
	h.step(1)
	check_eq(c.health.hp, 3, "twice as often sitting")

func test_no_regeneration_between_regen_ticks() -> void:
	c.health.set_hp(1)
	c.mp = 0
	p.map.tick = 0
	h.step(SimPlayer.REGEN_EVERY - 1)
	check_eq(c.mp, 0, "no MP until its tick")
	h.step(SimPlayer.HEART_REGEN_EVERY - SimPlayer.REGEN_EVERY)
	check_eq(c.health.hp, 1, "no heart until its tick")

func test_getting_up() -> void:
	h.ask(2, &"req_sit", [true])
	h.ask(2, &"req_sit", [false])
	check(not p.sitting, "standing")
	check_eq(h.last(2, &"ev_sit"), [false], "client told")

func test_you_cant_sit_in_the_air() -> void:
	h.place(p, 300.0, 500.0)
	h.ask(2, &"req_sit", [true])
	check(not p.sitting, "not sitting")
	check(h.told(2, "You can't sit here."), "told why")
	check_eq(h.last(2, &"ev_sit"), [false], "client kept standing")

func test_moving_gets_you_up() -> void:
	h.ask(2, &"req_sit", [true])
	h.ask(2, &"req_move", [Vector2(301, 600), 1, &"sit"])
	check(p.sitting, "a pixel of drift is fine")
	h.ask(2, &"req_move", [Vector2(310, 600), 1, &"walk"])
	check(not p.sitting, "walking off")

func test_getting_hit_gets_you_up() -> void:
	h.ask(2, &"req_sit", [true])
	p.map.hurt_player(p, Content.monster(&"dewling"), 340.0)
	check(not p.sitting, "knocked up")
	check_eq(h.last(2, &"ev_sit"), [false], "client told")

func test_changing_maps_gets_you_up() -> void:
	h.ask(2, &"req_sit", [true])
	h.move_to(p, ServerHarness.TOWN)
	check(not p.sitting, "standing")

# ---------- pets ----------

func _drop_at(x: float, owner := 2) -> SimDrop:
	var leaf := Content.item(&"green_leaf")
	p.map.spawn_drop(leaf, 1, null, DropFlight.create(Vector2(x, 580), ServerHarness.GROUND, x), owner)
	return p.map.drops.values()[-1]

func test_bringing_out_a_pet() -> void:
	h.ask(2, &"req_setup", [1])
	check_eq(c.pet, sprout.id, "out")
	check_eq(int(c.counters.get(Counters.PETS, 0)), 1, "counted")
	check(h.told(2, "came out to play"), "told")

func test_a_pet_says_hello_when_it_comes_out() -> void:
	check(not sprout.chatter.is_empty(), "the pet has lines")
	h.ask(2, &"req_setup", [1])
	var chat := h.last(2, &"ev_chat")
	check(chat.size() == 4 and chat[0] == "pet" and chat[1] == sprout.display_name, "it says hello")

func test_a_pet_picks_up_loot_within_reach() -> void:
	h.ask(2, &"req_setup", [1])
	var d := _drop_at(300.0 + sprout.loot_reach - 10.0)
	h.step(SimDrop.SETTLE_TICKS + sprout.loot_every)
	check(not p.map.drops.has(d.id), "picked up")
	check_eq(c.inventory.count_of(d.item), 1, "in the bag")

func test_without_a_pet_loot_stays_put() -> void:
	var d := _drop_at(300.0 + sprout.loot_reach - 10.0)
	h.step(SimDrop.SETTLE_TICKS + sprout.loot_every)
	check(p.map.drops.has(d.id), "still there")

func test_a_pet_doesnt_reach_further_than_its_reach() -> void:
	h.ask(2, &"req_setup", [1])
	var d := _drop_at(300.0 + sprout.loot_reach + 10.0)
	h.step(SimDrop.SETTLE_TICKS + sprout.loot_every * 2)
	check(p.map.drops.has(d.id), "too far")

func test_a_pet_respects_ownership() -> void:
	h.ask(2, &"req_setup", [1])
	var d := _drop_at(400.0, 3)
	h.step(SimDrop.SETTLE_TICKS + sprout.loot_every * 2)
	check(p.map.drops.has(d.id), "someone else's drop is left alone")

func test_a_pet_leaves_what_wont_fit() -> void:
	for i in Inventory.SLOTS:
		c.inventory.put(ItemDef.Tab.ETC, i, ItemStack.create(Content.item(&"moss_tuft"), 1))
	h.ask(2, &"req_setup", [1])
	var d := _drop_at(400.0)
	h.step(SimDrop.SETTLE_TICKS + sprout.loot_every * 2)
	check(p.map.drops.has(d.id), "left on the ground")
	check(not h.told(2, "inventory is full"), "and no complaint")

func test_a_hungry_pet_goes_home() -> void:
	h.ask(2, &"req_setup", [1])
	c.pet_full = 5
	p.map.tick = sprout.hunger_ticks - 1
	h.step(1)
	check_eq(c.pet_full, 0, "empty")
	check_eq(c.pet, &"", "gone home")
	check(h.told(2, "got hungry and went home"), "told")

func test_feeding_a_pet() -> void:
	h.ask(2, &"req_setup", [1])
	c.pet_full = 50
	var snack: UseDef = Content.item(&"pet_snack")
	c.inventory.put(ItemDef.Tab.USE, 9, ItemStack.create(snack, 2))
	h.ask(2, &"req_use_item", [9])
	check_eq(c.pet_full, 50 + snack.pet_food, "fuller")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 9).count, 1, "one snack eaten")

func test_pet_food_needs_a_hungry_pet_out() -> void:
	var snack: UseDef = Content.item(&"pet_snack")
	c.inventory.put(ItemDef.Tab.USE, 9, ItemStack.create(snack, 2))
	h.ask(2, &"req_use_item", [9])
	check(h.told(2, "You have no pet out to feed."), "no pet")
	h.ask(2, &"req_setup", [1])
	c.pet_full = 100
	h.ask(2, &"req_use_item", [9])
	check(h.told(2, "isn't hungry"), "full pet")
	check_eq(c.inventory.at(ItemDef.Tab.USE, 9).count, 2, "nothing eaten")

func test_using_the_pet_again_sends_it_home() -> void:
	h.ask(2, &"req_setup", [1])
	h.ask(2, &"req_setup", [1])
	check_eq(c.pet, &"", "home")

# ---------- achievements ----------

func test_sitting_down_earns_take_a_seat_once() -> void:
	h.ask(2, &"req_sit", [true])
	h.step(1)
	check_eq(h.events(2, &"ev_achievement"), [["take_a_seat"]], "sent once")
	check_has(c.achievements, "take_a_seat", "kept on the character")
	h.ask(2, &"req_sit", [false])
	h.ask(2, &"req_sit", [true])
	h.step(61)
	check_eq(h.count(2, &"ev_achievement"), 1, "not sent again")

func test_reaching_level_5_earns_an_achievement() -> void:
	var need := 0
	for lvl in range(c.level, 5):
		need += c.xp_need(lvl)
	h.server.give_xp(p, need - c.xp)
	check_eq(c.level, 5, "level 5")
	h.step(1)
	check_has(h.events(2, &"ev_achievement"), ["level_5"], "Growing Up")

func test_achievements_are_noticed_on_the_minute_too() -> void:
	c.shards = 100000
	h.step(59)
	check_eq(h.count(2, &"ev_achievement"), 0, "not yet")
	h.step(1)
	check_eq(h.last(2, &"ev_achievement"), ["nest_egg"], "checked every 60 ticks")

func test_others_see_the_achievement_sparkle() -> void:
	h.join(3, "Bob", ServerHarness.FIELD, 800.0)
	h.ask(2, &"req_setup", [1])
	h.step(1)
	check_eq(h.last(2, &"ev_achievement"), ["best_friend"], "pet achievement")
	check_eq(h.last(3, &"ev_effect")[0], EffectDef.CELEBRATE, "Bob sees the sparkle")
	check_eq(h.count(3, &"ev_achievement"), 0, "but isn't sent the achievement")

func test_a_first_kill_earns_first_hunt() -> void:
	var d := ServerHarness.monster()
	var map := h.field_with([ServerHarness.spawn(d)], &"test_hunt")
	map.mobs[0].position.x = 340.0
	h.move_to(p, &"test_hunt", 300.0)
	ServerHarness.no_cards(p, d)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	h.step(1)
	check_eq(h.last(2, &"ev_achievement"), ["first_hunt"], "first hunt")
