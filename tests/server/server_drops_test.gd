extends TestCase
## Items on the ground: what monsters drop, who may pick it up and when, Dawnshards going
## straight to the wallet, full bags, drops expiring, and dropping things from the bag.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var map: MapInstance
var ann: SimPlayer
var bob: SimPlayer
var leaf: ItemDef

func before_each() -> void:
	h = ServerHarness.new()
	leaf = Content.item(&"green_leaf")
	var d := ServerHarness.monster(&"dropper", 1)
	d.drops.append(ServerHarness.drop(leaf, 3))
	map = h.field_with([ServerHarness.spawn(d)])
	map.mobs[0].position.x = 340.0
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	bob = h.join(3, "Bob", ServerHarness.FIELD, 900.0)
	ServerHarness.no_cards(ann, d)

func after_each() -> void:
	h.close()

## Ann defeats the monster; returns its drop once it has landed.
func _kill() -> SimDrop:
	h.ask(2, &"req_skill", [&"basic_attack", ann.position, 1])
	h.step(60)
	return map.drops.values()[0] if not map.drops.is_empty() else null

func _drop_here(item: ItemDef, amount: int, owner: int, x: float) -> SimDrop:
	map.spawn_drop(item, amount, null, DropFlight.create(Vector2(x, 580), ServerHarness.GROUND, x), owner)
	return map.drops.values()[-1]

func test_a_defeated_monster_drops_its_loot_for_the_killer() -> void:
	var d := _kill()
	check(d != null, "something dropped")
	check_eq(d.item.id, leaf.id, "the listed item")
	check_eq(d.amount, 3, "the listed amount")
	check_eq(d.owner, 2, "owned by Ann")
	check_eq(d.flight.position, Vector2(340, ServerHarness.GROUND), "landed under the monster")
	check_eq(h.count(3, &"ev_drop"), 1, "everyone on the map sees it fall")

func test_the_owner_picks_up_with_the_loot_key() -> void:
	var d := _kill()
	h.place(ann, 345.0)
	h.ask(2, &"req_loot")
	check_eq(ann.character.inventory.count_of(leaf), 3, "in Ann's bag")
	check(not map.drops.has(d.id), "gone from the ground")
	check_eq(h.last(3, &"ev_drop_gone"), [d.id, 2], "everyone sees Ann take it")
	check_eq(h.last(2, &"ev_pickup"), [leaf.id, 3], "told what was picked up")
	check(not h.told(2, "Picked up"), "not as a log line: the client merges pickups")

func test_others_cant_take_your_drop_at_first() -> void:
	var d := _kill()
	h.place(bob, 340.0)
	h.ask(3, &"req_loot")
	check_eq(bob.character.inventory.count_of(leaf), 0, "Bob gets nothing")
	check(map.drops.has(d.id), "still there")

func test_anyone_can_take_a_drop_once_ownership_runs_out() -> void:
	var d := _kill()
	h.place(bob, 340.0)
	d.t = SimDrop.OWNER_TICKS
	h.ask(3, &"req_loot")
	check(map.drops.has(d.id), "at exactly OWNER_TICKS it's still Ann's")
	d.t = SimDrop.OWNER_TICKS + 1
	h.ask(3, &"req_loot")
	check_eq(bob.character.inventory.count_of(leaf), 3, "Bob took it after")

func test_drops_cant_be_taken_before_they_settle() -> void:
	h.ask(2, &"req_skill", [&"basic_attack", ann.position, 1])
	var d: SimDrop = map.drops.values()[0]
	h.step(SimDrop.SETTLE_TICKS)
	h.place(ann, d.flight.position.x)
	h.ask(2, &"req_loot")
	check(map.drops.has(d.id), "too soon")
	h.step(1)
	h.place(ann, d.flight.position.x)
	h.ask(2, &"req_loot")
	check(not map.drops.has(d.id), "taken once settled")

func test_you_must_stand_by_a_drop_to_loot_it() -> void:
	var d := _kill()
	h.place(ann, 340.0 + 40.0)
	h.ask(2, &"req_loot")
	check(map.drops.has(d.id), "40 px is too far")
	h.place(ann, 340.0 - 39.0)
	h.ask(2, &"req_loot")
	check(not map.drops.has(d.id), "39 px is close enough")

func test_the_loot_key_reaches_further_than_it_used_to() -> void:
	check_eq(SimDrop.LOOT_REACH, 40.0, "40 px either side")
	var d := _kill()
	h.place(ann, 340.0 + 30.0)
	h.ask(2, &"req_loot")
	check(not map.drops.has(d.id), "30 px away is in reach")

func test_holding_the_loot_key_picks_up_a_pile_one_by_one() -> void:
	# the client asks again every TDPlayer.LOOT_EVERY ticks while the key is held
	for x in [330.0, 345.0, 360.0]:
		_drop_here(leaf, 1, 2, x)
	h.step(SimDrop.SETTLE_TICKS + 1)
	h.place(ann, 345.0)
	for i in 3:
		h.ask(2, &"req_loot")
		h.step(TDPlayer.LOOT_EVERY)
	check(map.drops.is_empty(), "everything in reach taken")
	check_eq(ann.character.inventory.count_of(leaf), 3, "all three in the bag")

func test_dawnshards_go_to_the_wallet_by_walking_over_them() -> void:
	var shard := Content.item(&"dawnshard")
	var d := _drop_here(shard, 40, 2, 300.0)
	h.step(SimDrop.SETTLE_TICKS + 1)
	check_eq(ann.character.shards, 40, "picked up without the loot key")
	check(not map.drops.has(d.id), "gone")
	check_eq(h.last(2, &"ev_vitals")[2], 40, "wallet sent")
	check_eq(h.last(2, &"ev_gain"), [&"shards", 40], "shown rising over Ann")
	check(h.events(2, &"ev_pickup").is_empty() and not h.told(2, "Picked up"), "not in the message log")

func test_others_dont_walk_off_with_your_dawnshards() -> void:
	var shard := Content.item(&"dawnshard")
	var d := _drop_here(shard, 40, 2, 900.0)
	h.step(SimDrop.SETTLE_TICKS + 5)
	check_eq(bob.character.shards, 0, "Bob stands on them but gets none")
	check(map.drops.has(d.id), "still there")

func test_a_full_tab_leaves_the_drop_on_the_ground() -> void:
	var etc := Content.item(&"moss_tuft")
	for i in Inventory.SLOTS:
		ann.character.inventory.put(ItemDef.Tab.ETC, i, ItemStack.create(etc, etc.stack_size()))
	var d := _kill()
	h.place(ann, 340.0)
	h.ask(2, &"req_loot")
	check(map.drops.has(d.id), "left on the ground")
	check(h.told(2, "Your Etc inventory is full."), "told why")

func test_a_drop_that_tops_up_a_stack_fits_in_a_full_tab() -> void:
	for i in Inventory.SLOTS:
		ann.character.inventory.put(ItemDef.Tab.ETC, i, ItemStack.create(leaf, 1))
	var d := _kill()
	h.place(ann, 340.0)
	h.ask(2, &"req_loot")
	check(not map.drops.has(d.id), "taken")
	check_eq(ann.character.inventory.count_of(leaf), Inventory.SLOTS + 3, "stacked on top")

func test_drops_disappear_after_their_lifetime() -> void:
	var d := _kill()
	d.t = SimDrop.LIFETIME - 1
	h.step(1)
	check(map.drops.has(d.id), "still there at LIFETIME")
	h.step(1)
	check(not map.drops.has(d.id), "gone after")
	check_eq(h.last(3, &"ev_drop_gone"), [d.id, 0], "everyone told, taken by nobody")

func test_dropping_from_the_bag_puts_it_on_the_ground_for_anyone() -> void:
	ann.character.inventory.put(ItemDef.Tab.ETC, 5, ItemStack.create(leaf, 7))
	h.ask(2, &"req_drop_item", [ItemDef.Tab.ETC, 5])
	check(ann.character.inventory.at(ItemDef.Tab.ETC, 5) == null, "out of the bag")
	var d: SimDrop = map.drops.values()[0]
	check_eq(d.amount, 7, "the whole stack")
	check_eq(d.owner, 0, "nobody's")
	h.step(SimDrop.SETTLE_TICKS + 30)
	h.place(bob, d.flight.position.x)
	h.ask(3, &"req_loot")
	check_eq(bob.character.inventory.count_of(leaf), 7, "Bob can take it at once")

func test_dropped_gear_keeps_its_rolled_stats() -> void:
	var cap: EquipDef = Content.item(&"leaf_cap")
	var stack := ItemStack.create(cap)
	stack.stats.defense = 99
	ann.character.inventory.put(ItemDef.Tab.EQUIP, 0, stack)
	h.ask(2, &"req_drop_item", [ItemDef.Tab.EQUIP, 0])
	var d: SimDrop = map.drops.values()[0]
	h.step(SimDrop.SETTLE_TICKS + 30)
	h.place(bob, d.flight.position.x)
	h.ask(3, &"req_loot")
	var got := bob.character.inventory.at(ItemDef.Tab.EQUIP, 0)
	check(got != null and got.stats.defense == 99, "same copy of the gear")

func test_quest_items_cant_be_dropped() -> void:
	var token := ItemDef.new()
	token.id = &"test_token"
	token.display_name = "Token"
	token.quest_item = true
	ann.character.inventory.put(ItemDef.Tab.ETC, 0, ItemStack.create(token, 1))
	h.ask(2, &"req_drop_item", [ItemDef.Tab.ETC, 0])
	check(ann.character.inventory.at(ItemDef.Tab.ETC, 0) != null, "still in the bag")
	check(map.drops.is_empty(), "nothing on the ground")
	check(h.told(2, "Quest items can't be dropped."), "told why")
