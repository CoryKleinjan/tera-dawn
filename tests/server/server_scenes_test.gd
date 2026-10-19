extends TestCase
## Cutscenes on the server (ServerScenes): a map's intro plays the first time a character
## arrives and never again once their game says it ended, even after the server restarts;
## one that didn't end plays again next time; quests play theirs when taken and handed in;
## monsters leave a player alone while one plays, until they attack or it runs too long.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const GIVER_X := 400.0

var h: ServerHarness
var intro: CutsceneDef
var p: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()
	intro = h.add_cutscene(_scene(&"test_intro"))
	var town := ServerHarness.town_def()
	town.intro_scene = intro
	ServerHarness.npc(town, &"test_giver", GIVER_X)
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	h.clear()

func after_each() -> void:
	h.close()

func _scene(id: StringName) -> CutsceneDef:
	var d := CutsceneDef.new()
	d.id = id
	var wait := CutsceneStep.new()
	wait.kind = CutsceneStep.Kind.WAIT
	d.steps = [wait]
	return d

func _scenes_sent() -> Array:
	return h.events(2, &"ev_scene").map(func(a: Array) -> StringName: return a[0])

func test_a_maps_intro_plays_on_the_first_visit_only() -> void:
	h.move_to(p, ServerHarness.TOWN, 500.0)
	check_eq(_scenes_sent(), [&"test_intro"], "the intro plays")
	check(p.in_scene(), "watching it")
	h.ask(2, &"req_scene_done", [&"test_intro"])
	check(not p.in_scene(), "it ended")
	check(p.character.has_seen(&"test_intro"), "noted as seen")
	h.move_to(p, ServerHarness.FIELD, 300.0)
	h.move_to(p, ServerHarness.TOWN, 500.0)
	check_eq(_scenes_sent().size(), 1, "not again")

func test_seen_survives_a_restart() -> void:
	h.move_to(p, ServerHarness.TOWN, 500.0)
	h.ask(2, &"req_scene_done", [&"test_intro"])
	h.leave(2)
	h.restart()
	var again := h.join(2, "Ann", ServerHarness.TOWN, 500.0)
	check_eq(again.map.def.id, ServerHarness.TOWN, "back in town")
	check(not again.in_scene(), "a seen intro stays seen")

func test_an_intro_that_never_ended_plays_again() -> void:
	h.move_to(p, ServerHarness.TOWN, 500.0)
	h.move_to(p, ServerHarness.FIELD, 300.0)
	check(not p.in_scene(), "leaving the map stops it")
	h.move_to(p, ServerHarness.TOWN, 500.0)
	check_eq(_scenes_sent().size(), 2, "played again")

func test_only_the_scene_playing_can_be_ended() -> void:
	h.move_to(p, ServerHarness.TOWN, 500.0)
	h.ask(2, &"req_scene_done", [&"some_other_scene"])
	check(p.in_scene(), "still playing")
	check(not p.character.has_seen(&"some_other_scene"), "nothing else noted")

func test_quests_play_their_scenes_when_taken_and_handed_in() -> void:
	p.character.saw(&"test_intro")
	var q := QuestDef.new()
	q.id = &"test_q_scene"
	q.title = "Scene Quest"
	q.giver = &"test_giver"
	q.start_scene = h.add_cutscene(_scene(&"test_start"))
	q.finish_scene = h.add_cutscene(_scene(&"test_finish"))
	h.add_quest(q)
	h.move_to(p, ServerHarness.TOWN, GIVER_X)
	h.ask(2, &"req_quest_accept", [&"test_giver", q.id])
	check_eq(_scenes_sent(), [&"test_start"], "taking it plays its start")
	h.ask(2, &"req_scene_done", [&"test_start"])
	h.ask(2, &"req_quest_complete", [&"test_giver", q.id])
	check_eq(_scenes_sent(), [&"test_start", &"test_finish"], "handing it in plays its finish")

func test_monsters_leave_you_alone_while_a_scene_plays() -> void:
	var brute := ServerHarness.monster(&"brute", 100000, 1)
	var field := h.field_with([ServerHarness.spawn(brute)], &"test_brute_field")
	field.mobs[0].position.x = 300.0
	field.def.intro_scene = h.add_cutscene(_scene(&"test_brute_intro"))
	h.move_to(p, &"test_brute_field", 300.0)
	h.step(20)
	check_eq(h.count(2, &"ev_hurt"), 0, "not touched while watching")
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check(not p.in_scene(), "attacking means it isn't playing")
	h.step(5)
	check(h.count(2, &"ev_hurt") > 0, "monsters touch them again")

func test_a_scene_that_never_ends_stops_protecting_you() -> void:
	h.move_to(p, ServerHarness.TOWN, 500.0)
	h.step(ServerScenes.MAX_TICKS - 1)
	check(p.in_scene(), "still playing one tick early")
	h.step(1)
	check(not p.in_scene(), "stopped")
	check(not p.character.has_seen(&"test_intro"), "but not noted as seen")
