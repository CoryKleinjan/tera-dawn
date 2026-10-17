extends TestCase
## The tears (TearState): a tear stays sealed until its story quest is done, and once the
## host has finished one its zone's fields turn: the more dangerous kinds spawn in place of
## the ones they replace, every monster there is TearState.STRENGTH stronger, and the map
## says it's dark. Towns and other zones never change.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const ZONE := &"test_zone"

var h: ServerHarness
var boar: MonsterDef
var wisp: MonsterDef
var fierce_boar: MonsterDef
var tear: TearDef

func before_each() -> void:
	h = ServerHarness.new()
	boar = ServerHarness.monster(&"test_boar", 10, 10)
	wisp = ServerHarness.monster(&"test_wisp", 10, 10)
	fierce_boar = ServerHarness.monster(&"test_fierce_boar", 10, 10)
	var field := ServerHarness.field_def()
	field.region = ZONE
	field.spawns.append(ServerHarness.spawn(boar))
	field.spawns.append(ServerHarness.spawn(wisp))
	h.add_map(field)
	Content.map(ServerHarness.TOWN).region = ZONE
	tear = TearDef.new()
	tear.id = &"test_tear"
	tear.region = ZONE
	tear.seal_quest = &"test_seal"
	tear.finish_quest = &"test_finish"
	tear.dangerous = {&"test_boar": fierce_boar}
	tear.dark_look = BiomeVariantDef.new()
	tear.dark_look.light_energy = 0.4
	h._register("tears", tear.id, tear)

func after_each() -> void:
	Content.map(ServerHarness.TOWN).region = &""
	h.close()

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
	check(not TearState.open(tear, c), "sealed at first")
	c.quests.done[&"test_seal"] = 1
	check(TearState.open(tear, c), "open once the story quest is done")
	check(not TearState.finished(tear, c), "open isn't finished")

func test_a_zone_stays_as_it_is_until_the_tear_is_finished() -> void:
	var map := _ann_on_field([&"test_seal"])
	check(not map.dark, "not dark")
	check_eq(map.mobs[0].def, boar, "the usual boar")
	check_eq(map.mobs[0].max_hp(), 10, "its usual HP")
	check_eq(map.full_state()["dark"], false, "the client is told it isn't dark")

func test_a_finished_tear_turns_its_zone() -> void:
	var map := _ann_on_field([&"test_seal", &"test_finish"])
	check(map.dark, "dark")
	check_eq(map.mobs[0].def, fierce_boar, "the boar's dangerous version spawns in its place")
	check_eq(map.mobs[0].max_hp(), 15, "and is stronger")
	check_eq(map.mobs[1].def, wisp, "a kind with no dangerous version stays")
	check_eq(map.mobs[1].max_hp(), 15, "but is stronger too")
	check_eq(map.mobs[1].essence(), 15, "and gives more essence to match")
	check_eq(map.full_state()["dark"], true, "the client is told it's dark")

func test_towns_and_other_zones_never_turn() -> void:
	var c := Character.new()
	c.quests.done[&"test_finish"] = 1
	check(not TearState.dark(Content.map(ServerHarness.TOWN), c), "the town stays")
	var other := ServerHarness.field_def(&"test_other")
	other.region = &"test_elsewhere"
	check(not TearState.dark(other, c), "another zone stays")
	check(TearState.dark(Content.map(ServerHarness.FIELD), c), "the tear's own field turns")

func test_a_tear_with_no_finish_quest_never_finishes() -> void:
	var c := Character.new()
	tear.finish_quest = &""
	c.quests.done[&""] = 1
	check(not TearState.finished(tear, c), "nothing to finish yet")

func test_a_turned_map_shows_its_zones_darker_light_and_fog() -> void:
	var field := Content.map(ServerHarness.FIELD)
	field.biome = load("res://data/biomes/greenwood.tres")
	var dark := TearState.look(field, true)
	check_eq(dark.light_energy, 0.4, "darker light")
	check(field.look().light_energy != 0.4, "the map's own look is unchanged")
	check_eq(TearState.look(field, false), field.look(), "unturned, it's the map's own look")
	field.biome = null
