extends TestCase
## The Greenbough tear with the real content: its way in is a glow on a secret ledge of Oak
## Crown, shut until "A Closer Look" is done, that sends the hero into the Stilled Grove; Old
## Fenwick's three quests follow it in order; the tear's maps never decline, and beating the
## Petrified Warden's quest takes the world a step into its decline.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const TEAR := &"greenbough_tear"
const ENTRANCE := &"oak_crown"
const GROVE := &"stilled_grove"

var h: ServerHarness
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", ENTRANCE, 300.0)
	c = p.character

func after_each() -> void:
	h.close()

func _way_in() -> SceneSpot:
	var t: TearDef = Content.tears[TEAR]
	return Content.map(ENTRANCE).scene_spots.filter(func(s: SceneSpot) -> bool: return s.tear == t)[0]

## Stands on the way in, as a Dash there would.
func _stand_in_it() -> void:
	var s := _way_in()
	var def := p.map.def
	h.place(p, def.platforms[s.platform - 1].x + def.platforms[s.platform - 1].width / 2.0, def.surface_y(s.platform))
	h.server.on_move(2, p.position, 1, &"stand")
	h.step()

func test_the_way_in_is_sealed_until_a_closer_look() -> void:
	check(not _way_in().open_to(c), "no tear before the story")
	_stand_in_it()
	check_eq(p.map.def.id, ENTRANCE, "standing there does nothing yet")
	c.quests.done[&"story_a_closer_look"] = 1
	check(_way_in().open_to(c), "the tear shows once the story has taken them through one")
	_stand_in_it()
	check_eq(p.map.def.id, GROVE, "and takes them into the Stilled Grove")

func test_old_fenwicks_quests_follow_one_another() -> void:
	var q1: QuestDef = Content.quests[&"tear_greenbough_1"]
	var q2: QuestDef = Content.quests[&"tear_greenbough_2"]
	var q3: QuestDef = Content.quests[&"tear_greenbough_3"]
	for q in [q1, q2, q3]:
		check_eq(q.giver, &"greenbough_forager", "%s is Old Fenwick's" % q.id)
	check_eq(c.quests.status(q1, c), QuestLog.Status.LOCKED, "the first waits for the story")
	c.quests.done[&"story_a_closer_look"] = 1
	check_eq(c.quests.status(q1, c), QuestLog.Status.AVAILABLE, "then opens")
	check_eq(c.quests.status(q2, c), QuestLog.Status.LOCKED, "the second waits for the first")
	c.quests.done[q1.id] = 1
	check_eq(c.quests.status(q2, c), QuestLog.Status.AVAILABLE, "then opens")
	check_eq(c.quests.status(q3, c), QuestLog.Status.LOCKED, "the third waits for the second")
	c.quests.done[q2.id] = 1
	check_eq(c.quests.status(q3, c), QuestLog.Status.AVAILABLE, "then opens")

func test_finishing_it_declines_the_world_but_not_the_tear() -> void:
	var t: TearDef = Content.tears[TEAR]
	check_eq(TearState.decline(c), 0, "the world as it is")
	c.quests.done[t.finish_quest] = 1
	check(TearState.finished(t, c), "the Warden's quest finishes the tear")
	check_eq(TearState.decline(c), 1, "the world declines a step")
	check_eq(TearState.decline_of(Content.map(ENTRANCE), c), 1, "Oak Crown with it")
	for id in [GROVE, &"ivory_hollow", &"silent_stair", &"wardens_ring"]:
		check_eq(TearState.decline_of(Content.map(id), c), 0, "%s, inside the tear, doesn't" % id)
