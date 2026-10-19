extends TestCase
## The tears (TearState): a tear stays sealed until its story quest is done, and each tear
## the host has finished takes the whole world a step further into its decline (DeclineDef):
## each step's dangerous kinds spawn in place of the ones they replace, every monster is
## STRENGTH_PER_STEP stronger per step, and the map says how far it has declined. A tear's
## own maps never decline.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var boar: MonsterDef
var wisp: MonsterDef
var fierce_boar: MonsterDef
var dread_boar: MonsterDef
var first: TearDef
var second: TearDef
var step1: DeclineDef
var step2: DeclineDef

func before_each() -> void:
	h = ServerHarness.new()
	boar = ServerHarness.monster(&"test_boar", 10)
	wisp = ServerHarness.monster(&"test_wisp", 10)
	fierce_boar = ServerHarness.monster(&"test_fierce_boar", 10)
	dread_boar = ServerHarness.monster(&"test_dread_boar", 10)
	var field := Content.map(ServerHarness.FIELD)
	field.region = &"test_zone"
	field.spawns.append(ServerHarness.spawn(boar))
	field.spawns.append(ServerHarness.spawn(wisp))
	first = _tear(&"test_tear_a", &"test_finish_a")
	second = _tear(&"test_tear_b", &"test_finish_b")
	step1 = _step(&"test_decline_1", 1, {&"test_boar": fierce_boar}, 0.4)
	step2 = _step(&"test_decline_2", 2, {&"test_fierce_boar": dread_boar}, -1.0)

func after_each() -> void:
	Content.map(ServerHarness.FIELD).region = &""
	Content.map(ServerHarness.FIELD).spawns.clear()
	Content.map(ServerHarness.FIELD).biome = null
	h.close()

func _tear(id: StringName, finish: StringName) -> TearDef:
	var t := TearDef.new()
	t.id = id
	t.region = &"test_zone"
	t.inside = StringName("%s_inside" % id)
	t.seal_quest = &"test_seal"
	t.finish_quest = finish
	h._register("tears", t.id, t)
	return t

func _step(id: StringName, n: int, dangerous: Dictionary[StringName, MonsterDef], light: float) -> DeclineDef:
	var d := DeclineDef.new()
	d.id = id
	d.step = n
	d.dangerous = dangerous
	d.look = BiomeVariantDef.new()
	d.look.light_energy = light
	h._register("declines", d.id, d)
	return d

## Ann in town, with quests `done` handed in, then walking out to the field.
func _ann_on_field(done: Array) -> MapInstance:
	var ann := h.join(1, "Ann", ServerHarness.TOWN)
	for q in done:
		ann.character.quests.done[q] = 1
	h.server.maps.erase(ServerHarness.FIELD)
	h.move_to(ann, ServerHarness.FIELD)
	return ann.map

func test_a_tear_is_sealed_until_its_story_quest_is_done() -> void:
	var c := Character.new()
	check(not TearState.open(first, c), "sealed at first")
	c.quests.done[&"test_seal"] = 1
	check(TearState.open(first, c), "open once the story quest is done")
	check(not TearState.finished(first, c), "open isn't finished")

func test_the_world_stays_as_it_is_until_a_tear_is_finished() -> void:
	var map := _ann_on_field([&"test_seal"])
	check_eq(map.decline, 0, "no decline")
	check_eq(map.mobs[0].def, boar, "the usual boar")
	check_eq(map.mobs[0].max_hp(), 10, "its usual HP")
	check_eq(map.full_state()["decline"], 0, "the client is told")

func test_the_first_finished_tear_turns_the_world() -> void:
	var map := _ann_on_field([&"test_seal", &"test_finish_a"])
	check_eq(map.decline, 1, "one step")
	check_eq(map.mobs[0].def, fierce_boar, "the boar's dangerous version spawns in its place")
	check_eq(map.mobs[0].max_hp(), 15, "and is stronger")
	check_eq(map.mobs[1].def, wisp, "a kind with no dangerous version stays")
	check_eq(map.mobs[1].max_hp(), 15, "but is stronger too")
	check_eq(map.full_state()["decline"], 1, "the client is told")

func test_each_tear_after_takes_it_further() -> void:
	var map := _ann_on_field([&"test_seal", &"test_finish_a", &"test_finish_b"])
	check_eq(map.decline, 2, "two steps")
	check_eq(map.mobs[0].def, dread_boar, "the second step replaces the first step's boar")
	check_eq(map.mobs[0].max_hp(), 20, "stronger again")

func test_a_tears_own_maps_never_decline() -> void:
	var c := Character.new()
	c.quests.done[&"test_finish_a"] = 1
	var inside := ServerHarness.field_def(&"test_inside")
	inside.region = first.inside
	check_eq(TearState.decline_of(inside, c), 0, "inside the tear")
	check_eq(TearState.decline_of(Content.map(ServerHarness.TOWN), c), 1, "towns are part of the world")

func test_a_tear_with_no_finish_quest_never_finishes() -> void:
	var c := Character.new()
	first.finish_quest = &""
	c.quests.done[&""] = 1
	check(not TearState.finished(first, c), "nothing to finish yet")

func test_a_declined_map_shows_each_steps_light_and_fog() -> void:
	var field := Content.map(ServerHarness.FIELD)
	field.biome = load("res://data/biomes/greenwood.tres")
	check_eq(TearState.look(field, 1).light_energy, 0.4, "step 1's light")
	check_eq(TearState.look(field, 2).light_energy, 0.4, "step 2 keeps what it doesn't set")
	check(field.look().light_energy != 0.4, "the map's own look is unchanged")
	check_eq(TearState.look(field, 0), field.look(), "no decline: the map's own look")
