extends TestCase
## The job test on the server, with the real content (Greenbough's, the others are the
## same): a Beginner can't advance without it; the tutor's Job Test opens a way to a Trial
## Ground each player has to themselves; reaching the far end opens a tear and the boss steps
## out once its scene ends; beating it and handing the test in makes you an Archer and sends
## you to Celest; a Warrior may take it too and switch. Leaving starts the Trial Ground fresh, and fainting there sends you to town.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const TEST := &"jtest_archer"
const TUTOR := &"greenbough_instructor"
const HALL := &"greenbough_hall"
const TRIAL := &"trial_greenbough"

var h: ServerHarness
var p: SimPlayer
var c: Character
var archer: JobDef

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann", HALL, 700.0)
	c = p.character
	archer = Content.job(&"archer")

func after_each() -> void:
	h.close()

## Puts `who` on their map's floor at `x`.
func _put(who: SimPlayer, x: float) -> void:
	h.place(who, x, who.map.def.ground_y)

func _gate() -> PortalDef:
	return Content.map(HALL).portals.filter(func(d: PortalDef) -> bool: return d.target_map == TRIAL)[0]

## Takes the test from the tutor and walks through the hall's trial gate.
func _into_trial(who := p, peer := 2) -> void:
	_put(who, 700.0)
	h.ask(peer, &"req_quest_accept", [TUTOR, TEST])
	check(who.character.quests.active.has(TEST), "%s takes the test" % who.character.name)
	_put(who, _gate().x)
	h.ask(peer, &"req_portal")
	h.step()

func _boss(m: MapInstance) -> SimMob:
	return m.mobs.filter(func(b: SimMob) -> bool: return b.def.id == &"tear_boss")[0]

## Stands on the arena at the far end, as getting there would.
func _reach_the_end() -> void:
	var def := p.map.def
	h.place(p, def.tears[0].x, def.surface_y(def.tear_platform))
	h.server.on_move(2, p.position, 1, &"stand")
	h.step()

func test_advancing_needs_the_job_test() -> void:
	h.ask(2, &"req_advance", [TUTOR, &"archer"])
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "Pass the Job Test first."), "told why")

func test_the_trial_gate_opens_only_during_the_test() -> void:
	check(not _gate().open_to(c), "no way in before the test")
	_put(p, _gate().x)
	h.ask(2, &"req_portal")
	h.step()
	check_eq(p.map.def.id, HALL, "a shut gate goes nowhere")
	_into_trial()
	check_eq(p.map.def.id, TRIAL, "through to the Trial Ground")

func test_each_player_has_their_own_trial_ground() -> void:
	var other := h.join(3, "Bo", HALL, 700.0)
	_into_trial()
	_into_trial(other, 3)
	check_eq(other.map.def.id, TRIAL, "both on the Trial Ground")
	check(p.map != other.map, "each in their own copy")
	check(not p.map.players.has(3), "alone in it")

func test_reaching_the_end_opens_the_tear_and_the_boss_steps_out() -> void:
	_into_trial()
	var boss := _boss(p.map)
	check(boss.dead and boss.asleep, "nothing there yet")
	check(not p.map.full_state()["tear"], "no tear yet")
	_reach_the_end()
	check(p.map.tear_open, "the tear opens")
	check_eq(h.count(2, &"ev_tear"), 1, "and shows")
	check_eq(p.scene, &"trial_tear_greenbough", "its scene plays")
	check(boss.dead, "the boss waits for the scene")
	h.ask(2, &"req_scene_done", [p.scene])
	h.step()
	check(not boss.dead, "then steps out of the tear")
	check_eq(boss.target, 2, "after you")

func test_beating_it_makes_you_an_archer_and_sends_you_to_celest() -> void:
	_into_trial()
	_reach_the_end()
	h.ask(2, &"req_scene_done", [p.scene])
	h.step()
	var boss := _boss(p.map)
	p.map.kill_mob(boss, p)
	check_eq(c.quests.status(Content.quests[TEST], c), QuestLog.Status.READY, "the test is passed")
	h.step(3000)
	check(boss.dead, "and it doesn't come back")
	# the tutor watches from the start of the course, and takes it in there
	_put(p, 330.0)
	h.ask(2, &"req_quest_complete", [TUTOR, TEST])
	check_eq(c.job, archer, "an Archer now")
	check(c.quests.active.has(&"jreport_archer"), "off to tell Celest")

func test_a_warrior_can_take_it_and_switch() -> void:
	c.job = Content.job(&"warrior")
	c.jobs_passed.assign(["warrior"])
	c.recalc()
	var strike := Content.skill(&"power_strike")
	c.essence = c.skills.price()
	check_eq(c.skills.learn(strike), "", "Power Strike bought")
	var paid := int(c.skills.paid[strike.id])
	_into_trial()
	_reach_the_end()
	h.ask(2, &"req_scene_done", [p.scene])
	h.step()
	p.map.kill_mob(_boss(p.map), p)
	_put(p, 330.0)
	h.ask(2, &"req_quest_complete", [TUTOR, TEST])
	check_eq(c.job, archer, "an Archer now")
	check_eq(c.skills.level(strike), 0, "Power Strike forgotten")
	check(h.told(2, "You forget Power Strike, and %d Dawn Essence comes back to you." % paid), "its essence back")
	check(c.has_passed(archer) and c.has_passed(Content.job(&"warrior")), "both passed")

func test_leaving_starts_it_fresh_and_fainting_sends_you_to_town() -> void:
	_into_trial()
	_reach_the_end()
	h.ask(2, &"req_scene_done", [p.scene])
	var first := p.map
	h.server.revive(p)
	check_eq(p.map.def.id, &"greenbough", "back in Greenbough")
	check(not h.server.maps.has(h.server.instance_key(TRIAL, p)), "the copy is gone")
	h.move_to(p, HALL, _gate().x)
	h.ask(2, &"req_portal")
	h.step()
	check(p.map != first and not p.map.tear_open, "a fresh Trial Ground")
	check(_boss(p.map).asleep, "the boss waits again")
	_reach_the_end()
	check_eq(p.scene, &"", "the scene doesn't play twice")
	check(not _boss(p.map).dead, "so it steps out at once")

func test_a_fresh_beginner_can_beat_it() -> void:
	# a Beginner ready for their job (Balance tier 10)'s basic attack, every stat point
	# bought in STR as the Auto button would
	var hero := Character.create("Tester", Character.START_JOB)
	hero.base.strength += 9 * CharacterStats.GROWTH_POINTS
	hero.recalc()
	var boss: MonsterDef = Content.monster(&"tear_boss")
	var skill: SkillDef = Content.skills[Character.BASIC_ATTACK]
	var dealt := 0
	var swings := 400
	for i in swings:
		var hit := Combat.player_hit(skill, boss, hero)
		if not hit["miss"]:
			dealt += hit["damage"]
	var seconds := boss.max_hp / (float(dealt) / swings) * maxi(skill.cooldown, 1) / 60.0
	check(seconds > 40.0 and seconds < 150.0, "a long but winnable fight: %.0f s of swinging" % seconds)
	var taken := Combat.monster_hit(boss, hero, 1.0)
	check(taken < hero.max_hp() / 4, "a touch takes under a quarter of their HP (%d of %d)" % [taken, hero.max_hp()])
