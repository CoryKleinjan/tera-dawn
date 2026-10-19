extends TestCase
## Boss relics on the server: a boss drops its relic for everyone at the fight who hasn't got
## its move, only they can take theirs and it never expires, picking it up unlocks the move
## (not a bag item), and a Slam breaks what it lands on, a cracked floor included, which
## blows only shake.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const FLOOR_X := 1000.0

var h: ServerHarness
var map: MapInstance
var ann: SimPlayer
var bob: SimPlayer
var charm: RelicDef
var heart: RelicDef

func before_each() -> void:
	h = ServerHarness.new()
	charm = Content.item(&"tusk_charm") as RelicDef
	heart = Content.item(&"magma_heart") as RelicDef
	var boss := ServerHarness.monster(&"test_boss", 1)
	boss.boss = true
	boss.relic = charm
	var field := ServerHarness.field_def()
	field.spawns.append(ServerHarness.spawn(boss))
	var floor := BreakableDef.new()
	floor.id = &"test_crack"
	floor.x = FLOOR_X
	floor.height = 20.0
	floor.slam_only = true
	field.breakables.append(floor)
	h.add_map(field)
	h.server.maps.erase(ServerHarness.FIELD)
	map = h.server.map_instance(ServerHarness.FIELD)
	map.mobs[0].position.x = 340.0
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	bob = h.join(3, "Bob", ServerHarness.FIELD, 900.0)
	ServerHarness.no_cards(ann, boss)

func after_each() -> void:
	h.close()

func _kill() -> void:
	h.ask(2, &"req_skill", [&"basic_attack", ann.position, 1])
	h.step(60)

func _relics() -> Array[SimDrop]:
	var out: Array[SimDrop] = []
	for d: SimDrop in map.drops.values():
		if d.item is RelicDef:
			out.append(d)
	return out

func test_a_boss_drops_its_relic_for_everyone_at_the_fight() -> void:
	_kill()
	var owners := _relics().map(func(d: SimDrop) -> int: return d.owner)
	owners.sort()
	check_eq(owners, [2, 3], "one each for Ann and Bob")

func test_no_relic_for_someone_who_has_its_move() -> void:
	bob.character.learn_relic(charm)
	_kill()
	check_eq(_relics().map(func(d: SimDrop) -> int: return d.owner), [2], "only Ann's")

func test_picking_it_up_unlocks_the_move_not_a_bag_item() -> void:
	_kill()
	check(not ann.character.has_move(RelicDef.Move.DASH), "locked before")
	h.place(ann, 345.0)
	h.ask(2, &"req_loot")
	check(ann.character.has_move(RelicDef.Move.DASH), "Dash unlocked")
	check_eq(ann.character.inventory.count_of(charm), 0, "not in the bag")
	check(h.told(2, "New move: Dash."), "told")

func test_only_its_owner_can_take_it_and_it_never_expires() -> void:
	_kill()
	h.step(SimDrop.LIFETIME + 10)
	check_eq(_relics().size(), 2, "both still lying there")
	h.place(bob, 345.0)
	h.ask(3, &"req_loot")
	h.ask(3, &"req_loot")
	check(bob.character.has_move(RelicDef.Move.DASH), "Bob took his")
	check_eq(_relics().map(func(d: SimDrop) -> int: return d.owner), [2], "Ann's is left for her")

func test_a_relic_is_saved() -> void:
	ann.character.learn_relic(charm)
	var back := Character.new()
	CharacterCodec.load_dict(back, CharacterCodec.to_dict(ann.character))
	check(back.has_move(RelicDef.Move.DASH), "kept")
	check(not back.has_move(RelicDef.Move.SLAM), "nothing else")

func test_blows_only_shake_a_cracked_floor() -> void:
	h.place(ann, FLOOR_X - 30.0)
	for i in 3:
		h.ask(2, &"req_skill", [&"basic_attack", ann.position, 1])
		h.step(60)
	check(not ann.character.found_secret(&"test_crack"), "still whole")
	check_eq(h.last(2, &"ev_struck"), [0, false], "it shakes")

func test_a_slam_breaks_a_cracked_floor() -> void:
	ann.character.learn_relic(heart)
	h.place(ann, FLOOR_X)
	h.ask(2, &"req_slam", [ann.position])
	check(ann.character.found_secret(&"test_crack"), "broken for good")
	check(not bob.character.found_secret(&"test_crack"), "not for Bob")

func test_no_slam_without_its_relic() -> void:
	h.place(ann, FLOOR_X)
	h.ask(2, &"req_slam", [ann.position])
	check(not ann.character.found_secret(&"test_crack"), "still whole")

func test_a_slam_far_from_where_you_are_does_nothing() -> void:
	ann.character.learn_relic(heart)
	h.place(ann, 300.0)
	h.ask(2, &"req_slam", [Vector2(FLOOR_X, ServerHarness.GROUND)])
	check(not ann.character.found_secret(&"test_crack"), "still whole")
