extends TestCase
## CutsceneDef and CutsceneStep: a good cutscene has no problems; empty cutscenes, steps
## with no time, lines with no words and people who don't exist are caught; the NPCs a
## cutscene needs are listed once each; a character remembers what it has seen, and the save
## keeps it.

const NPC := &"village_elder"

func _step(kind: CutsceneStep.Kind) -> CutsceneStep:
	var s := CutsceneStep.new()
	s.kind = kind
	return s

func _say(speaker: StringName, text := "Hello.") -> CutsceneStep:
	var s := _step(CutsceneStep.Kind.SAY)
	s.speaker = speaker
	s.text = text
	return s

func _scene(steps: Array[CutsceneStep]) -> CutsceneDef:
	var d := CutsceneDef.new()
	d.id = &"t_scene"
	d.steps = steps
	return d

func test_a_good_cutscene_has_no_problems() -> void:
	var walk := _step(CutsceneStep.Kind.MOVE)
	walk.who = NPC
	walk.x = 500
	var turn := _step(CutsceneStep.Kind.FACE)
	turn.who = CutsceneStep.HERO
	turn.face = -1
	var d := _scene([_step(CutsceneStep.Kind.BARS), _say(NPC), _say(CutsceneStep.HERO), _say(&"", "Far away..."), walk, turn,
			_step(CutsceneStep.Kind.CAMERA_BACK)])
	check_eq(d.problems(), [] as Array[String], "no problems")

func test_problems_are_caught() -> void:
	check_eq(_scene([]).problems().size(), 1, "no steps")
	var wait := _step(CutsceneStep.Kind.WAIT)
	wait.ticks = 0
	check_eq(_scene([wait]).problems().size(), 1, "a wait with no time")
	check_eq(_scene([_say(NPC, "  ")]).problems().size(), 1, "a line with no words")
	check_eq(_scene([_say(&"nobody_by_that_name")]).problems().size(), 1, "a speaker who doesn't exist")
	var walk := _step(CutsceneStep.Kind.MOVE)
	check_eq(_scene([walk]).problems().size(), 1, "a walk with nobody walking")
	var turn := _step(CutsceneStep.Kind.FACE)
	turn.who = NPC
	turn.face = 0
	check_eq(_scene([turn]).problems().size(), 1, "facing neither way")
	var music := _step(CutsceneStep.Kind.MUSIC)
	music.sound = &"no_such_track"
	check_eq(_scene([music]).problems().size(), 1, "a track that doesn't exist")
	var bad: Array[CutsceneStep] = [null]
	check_eq(_scene(bad).problems().size(), 1, "an empty step")

func test_it_lists_the_npcs_it_needs_once_each() -> void:
	var walk := _step(CutsceneStep.Kind.MOVE)
	walk.who = NPC
	var hero := _step(CutsceneStep.Kind.SHOW)
	hero.who = CutsceneStep.HERO
	var d := _scene([_say(NPC), walk, hero, _say(&"", "Narrated.")])
	check_eq(d.npcs(), [NPC] as Array[StringName], "only the NPC, once")

func test_a_character_remembers_what_it_has_seen_and_the_save_keeps_it() -> void:
	var c := Character.create("Seer")
	check(not c.has_seen(&"t_scene"), "nothing seen yet")
	c.saw(&"t_scene")
	c.saw(&"t_scene")
	check(c.has_seen(&"t_scene"), "seen")
	check_eq(c.scenes_seen.size(), 1, "noted once")
	var again := Character.create("Seer")
	again.load_dict(c.to_dict())
	check(again.has_seen(&"t_scene"), "the save keeps it")
