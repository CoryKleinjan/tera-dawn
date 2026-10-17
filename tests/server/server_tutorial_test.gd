extends TestCase
## The tutorial on the server, start to finish with the real content: a new character wakes on
## Daybreak Shore (its intro plays), races the girl to the big rock, jumps up to her lookout, is
## given a shell, clears her tide pool and brings her Dewling jelly. Each step after the race
## starts by itself as the last is handed in. The way to the village stays shut until the end.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const SHORE := Character.NEW_MAP
const GIRL := &"girl_on_beach"

var h: ServerHarness
var p: SimPlayer
var c: Character
var shore: MapDef

func before_each() -> void:
	h = ServerHarness.new()
	h.play(2, "Dawnling")
	p = h.server.sessions.get(2)
	c = p.character
	shore = Content.map(SHORE)

func after_each() -> void:
	h.close()

func _quest(id: StringName) -> QuestDef:
	return Content.quests[id]

func _status(id: StringName) -> QuestLog.Status:
	return c.quests.status(_quest(id), c)

## Stands on `platform` at `x` and tells the server, as moving there would.
func _stand(x: float, platform: int) -> void:
	h.place(p, x, shore.surface_y(platform))
	h.server.quests.reached(p)
	h.step()

## Talks to the girl where she stands now, and takes or hands in `id`.
func _talk(id: StringName, hand_in: bool) -> void:
	var spot := _girl()
	check(spot != null, "the girl stands somewhere for %s" % id)
	if spot == null:
		return
	h.place(p, spot.x, shore.surface_y(spot.platform))
	h.ask(2, &"req_quest_complete" if hand_in else &"req_quest_accept", [GIRL, id])
	_end_scene()

## Where the girl stands for this character now.
func _girl() -> NpcPlacement:
	var found: NpcPlacement = null
	for n in shore.npcs:
		if n.npc.id == GIRL and n.shown_to(c):
			check(found == null, "she stands in one spot at a time")
			found = n
	return found

## Finishes the cutscene playing, as the game does when it ends.
func _end_scene() -> void:
	h.step()
	if p.scene != &"":
		h.ask(2, &"req_scene_done", [p.scene])

func _portal_open() -> bool:
	return shore.portals[0].open_to(c)

func test_a_new_character_wakes_on_the_shore() -> void:
	check_eq(p.map.def.id, SHORE, "starts on Daybreak Shore")
	check_eq(p.scene, shore.intro_scene.id, "its opening scene plays")
	check(not _portal_open(), "the way to the village is shut")
	check_eq(_status(&"tut1_race"), QuestLog.Status.AVAILABLE, "the girl has her race for you")

func test_the_way_out_stays_shut_until_the_end() -> void:
	_end_scene()
	h.place(p, shore.portals[0].x, shore.ground_y)
	h.ask(2, &"req_portal")
	h.step()
	check_eq(p.map.def.id, SHORE, "a shut portal goes nowhere")

func test_the_whole_tutorial() -> void:
	_end_scene()
	_talk(&"tut1_race", false)
	check_eq(_status(&"tut1_race"), QuestLog.Status.ACTIVE, "the race is on")
	_stand(780.0, 1)
	check_eq(_status(&"tut1_race"), QuestLog.Status.READY, "reaching the big rock wins it")
	_talk(&"tut1_race", true)
	check_eq(_status(&"tut2_lookout"), QuestLog.Status.ACTIVE, "the lookout starts by itself")
	_stand(1150.0, 2)
	check_eq(_status(&"tut2_lookout"), QuestLog.Status.READY, "up on her lookout")
	_talk(&"tut2_lookout", true)
	check_eq(_status(&"tut3_shell"), QuestLog.Status.ACTIVE, "she throws you a shell")
	var shell := _quest(&"tut3_shell").gift_on_accept
	check(p.map.drops.values().any(func(d: SimDrop) -> bool: return d.item == shell), "the shell lands by you")
	h.step(90)
	h.ask(2, &"req_loot")
	h.step(5)
	check_eq(c.inventory.count_of(shell), 1, "picked up")
	check_eq(_status(&"tut3_shell"), QuestLog.Status.READY, "holding it is enough")
	_talk(&"tut3_shell", true)
	check_eq(c.inventory.count_of(shell), 1, "and it's yours to keep")
	check_eq(_status(&"tut4_tide_pool"), QuestLog.Status.ACTIVE, "the tide pool starts by itself")
	var dewling := Content.monster(&"dewling")
	for i in 3:
		h.server.quests.record_kill(p, dewling)
	check_eq(_status(&"tut4_tide_pool"), QuestLog.Status.READY, "three Dewlings cleared")
	_talk(&"tut4_tide_pool", true)
	check_eq(_status(&"tut5_dewling_jelly"), QuestLog.Status.AVAILABLE, "the jelly quest waits for you to ask")
	_talk(&"tut5_dewling_jelly", false)
	c.inventory.add(Content.item(&"dewling_droplet"), 3)
	check(not _portal_open(), "still shut")
	_talk(&"tut5_dewling_jelly", true)
	check(c.quests.done.has(&"tut5_dewling_jelly"), "all done")
	check(_girl() == null, "she's gone home")
	check(_portal_open(), "the way to the village is open")
	h.place(p, shore.portals[0].x, shore.ground_y)
	h.ask(2, &"req_portal")
	h.step()
	check_eq(p.map.def.id, Character.START_MAP, "through to Dawnrise Village")
