extends TestCase
## The home-world tear on the server, with the real content: Aldous's "Lights on the Ridge"
## waits for Report to Celest (or the Magician's Job Test) and the Grotto Tusker; the light
## over Starfall Ridge shows only during the two quests; standing in it during "A Closer
## Look" plays its scene and pulls the hero into the silent home world, alone; the light at
## its far end sends them back; handing the quest in to Celest marks the story step done.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const LIGHTS := &"story_lights_on_the_ridge"
const CLOSER := &"story_a_closer_look"
const RIDGE := &"starfall_ridge"
const HOME := &"home_world"
const TOWN := &"lumewood"
const HALL := &"lumewood_hall"
const ALDOUS := &"lumewood_stargazer"
const CELEST := &"lumewood_instructor"

var h: ServerHarness
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", TOWN, 300.0)
	c = p.character

func after_each() -> void:
	h.close()

## Done with Report to Celest and the Grotto Tusker, as a hero around Lv 25 would be.
func _ready_for_it() -> void:
	c.quests.done[&"jreport_warrior"] = 1
	c.book.record_kill(Content.monster(&"grotto_tusker"))

## Stands by `npc` where they stand in Lumewood (the town, or a hall in it).
func _by(npc: StringName) -> void:
	for map in [TOWN, HALL]:
		var at: Array = Content.map(map).npcs.filter(func(n: NpcPlacement) -> bool: return n.npc.id == npc)
		if not at.is_empty():
			if p.map.def.id != map:
				h.move_to(p, map)
			h.place(p, at[0].x, p.map.def.surface_y(at[0].platform))
			return
	fail("%s isn't in Lumewood" % npc)

## Stands on scene spot `s` of the map they're on, as walking there would.
func _stand_on(s: SceneSpot) -> void:
	var def := p.map.def
	var x := (s.from_x + s.to_x) * 0.5 if s.to_x > 0.0 else def.platforms[s.platform - 1].x + 40.0
	h.place(p, x, def.surface_y(s.platform))
	h.server.on_move(2, p.position, 1, &"stand")
	h.step()

func _spot(map: StringName, scene: StringName) -> SceneSpot:
	return Content.map(map).scene_spots.filter(func(s: SceneSpot) -> bool: return s.scene and s.scene.id == scene)[0]

func _glow() -> SceneSpot:
	return Content.map(RIDGE).scene_spots.filter(func(s: SceneSpot) -> bool: return s.glow != Vector2.ZERO)[0]

func _end_scene() -> void:
	h.ask(2, &"req_scene_done", [p.scene])
	h.step()

func test_lights_on_the_ridge_waits_for_the_report_and_the_tusker() -> void:
	var q := Content.quests[LIGHTS] as QuestDef
	check_eq(c.quests.status(q, c), QuestLog.Status.LOCKED, "locked at first")
	c.quests.done[&"jreport_warrior"] = 1
	check_eq(c.quests.status(q, c), QuestLog.Status.LOCKED, "still locked before the Grotto Tusker")
	c.book.record_kill(Content.monster(&"grotto_tusker"))
	check_eq(c.quests.status(q, c), QuestLog.Status.AVAILABLE, "open after both")
	c.quests.done.erase(&"jreport_warrior")
	c.quests.done[&"jtest_mage"] = 1
	check_eq(c.quests.status(q, c), QuestLog.Status.AVAILABLE, "a Magician's Job Test counts as the report")

func test_the_light_shows_only_during_the_two_quests() -> void:
	_ready_for_it()
	check(not _glow().open_to(c), "no light before the quest")
	_by(ALDOUS)
	h.ask(2, &"req_quest_accept", [ALDOUS, LIGHTS])
	check(_glow().open_to(c), "the light is there once Aldous asks")
	h.move_to(p, RIDGE)
	_stand_on(_glow())
	check(c.quests.is_ready(Content.quests[LIGHTS], c), "reaching it is what Aldous asked")
	check_eq(p.map.def.id, RIDGE, "it doesn't pull anyone in yet")

func test_a_closer_look_pulls_the_hero_through_and_back() -> void:
	_ready_for_it()
	c.quests.done[LIGHTS] = 1
	_by(CELEST)
	h.ask(2, &"req_quest_accept", [CELEST, CLOSER])
	check(c.quests.active.has(CLOSER), "Celest asks for a closer look")
	h.move_to(p, RIDGE)
	var pull := _spot(RIDGE, &"home_pull")
	_stand_on(pull)
	check_eq(p.scene, &"home_pull", "the light's scene plays")
	_end_scene()
	check_eq(p.map.def.id, HOME, "pulled into the home world")
	check(p.map.def.solo and p.map.def.spawns.is_empty(), "alone, with no monsters")
	check_eq(p.scene, &"home_arrive", "and the hero wonders where this is")
	_end_scene()
	check(c.quests.is_ready(Content.quests[CLOSER], c), "seeing it is what Celest asked")
	check(not pull.open_to(c), "the light won't pull them in again")
	_stand_on(_spot(HOME, &"home_way_back"))
	check_eq(p.scene, &"home_way_back", "the light at the far end")
	_end_scene()
	check_eq(p.map.def.id, RIDGE, "back on Starfall Ridge")
	_end_scene()
	_by(CELEST)
	h.ask(2, &"req_quest_complete", [CELEST, CLOSER])
	check(c.quests.done.has(CLOSER), "told Celest: the story step is done")
	check(not _glow().open_to(c), "the light is gone")

func test_the_way_back_works_after_its_scene_was_seen() -> void:
	c.saw(&"home_way_back")
	h.move_to(p, HOME)
	_stand_on(_spot(HOME, &"home_way_back"))
	check_eq(p.map.def.id, RIDGE, "straight back, no scene")

func test_a_thought_plays_once() -> void:
	h.move_to(p, HOME)
	var beach := _spot(HOME, &"home_beach")
	_stand_on(beach)
	check_eq(p.scene, &"home_beach", "a thought on the beach")
	_end_scene()
	_stand_on(beach)
	check_eq(p.scene, &"", "not again")
	check_eq(p.map.def.id, HOME, "and it goes nowhere")

func test_the_home_world_is_silent() -> void:
	check_eq(Content.map(HOME).music_id(), &"", "no music")
