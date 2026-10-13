extends TestCase
## A cutscene in a running game (TDCutscenePlayer): the HUD and your controls go away, the
## bars slide in, the camera glides, a line waits for you to press on, an NPC walks, and at
## the end everyone the cutscene moved is back where they stood and the server notes it as
## seen. Holding the menu key skips it; changing maps stops it unseen.
## Runs in Dawnrise Village with Elder Rowan.

const ELDER := &"village_elder"
const SCENE := &"test_ui_scene"
const BAR_TICKS := 10
const CAM_TICKS := 20
const WALK := 60.0

var ui: UiHelpers
var scene: CutsceneDef
var elder: TDNpc

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	await ui.enter_map(&"dawnrise_village", 600.0)
	elder = ui.world.scenes._npc(ELDER)
	scene = _scene()
	Content.cutscenes[SCENE] = scene

func after_each() -> void:
	Input.action_release("pause")
	Content.cutscenes.erase(SCENE)
	ui.stop()

func _step(kind: CutsceneStep.Kind, ticks := 1) -> CutsceneStep:
	var s := CutsceneStep.new()
	s.kind = kind
	s.ticks = ticks
	return s

func _scene() -> CutsceneDef:
	var d := CutsceneDef.new()
	d.id = SCENE
	var bars := _step(CutsceneStep.Kind.BARS, BAR_TICKS)
	var cam := _step(CutsceneStep.Kind.CAMERA, CAM_TICKS)
	cam.at = elder.position + Vector2(200, -100)
	var say := _step(CutsceneStep.Kind.SAY)
	say.speaker = ELDER
	say.text = "A test line."
	var walk := _step(CutsceneStep.Kind.MOVE)
	walk.who = ELDER
	walk.x = elder.position.x + WALK
	walk.speed = 3.0
	var stroll := _step(CutsceneStep.Kind.MOVE)
	stroll.who = CutsceneStep.HERO
	stroll.x = ui.world.player.position.x + WALK
	var turn := _step(CutsceneStep.Kind.FACE)
	turn.who = CutsceneStep.HERO
	turn.face = -1
	d.steps = [bars, cam, say, walk, stroll, turn, _step(CutsceneStep.Kind.WAIT, 5), _step(CutsceneStep.Kind.CAMERA_BACK, 5)]
	return d

func _play() -> void:
	Net.server.scenes.play(ui.player(), scene)
	await ui.ticks(2)

func test_it_plays_through_and_puts_everyone_back() -> void:
	check(elder != null, "Elder Rowan stands in the village")
	var home := elder.position.x
	var start := ui.world.player.position.x
	await _play()
	var scenes := ui.world.scenes
	check(scenes.playing(), "playing")
	check(not ui.hud.visible, "the HUD is put away")
	check(ui.world.input_blocked(), "your keys don't move you")
	check(ui.player().in_scene(), "the server knows")
	await ui.ticks(BAR_TICKS + CAM_TICKS + 4)
	check_near(scenes.overlay.bars, 1.0, "the bars are in")
	check_eq(scenes.def.steps[scenes.index].kind, CutsceneStep.Kind.SAY, "on the line")
	check(ui.world.camera.scene_center is Vector2, "the cutscene holds the camera")
	check_near((ui.world.camera.scene_center as Vector2).distance_to(scene.steps[1].at), 0.0, "the camera reached its spot", 0.5)
	check(scenes.overlay.speaking(), "the speech box shows")
	await ui.ticks(30)
	check_eq(scenes.def.steps[scenes.index].kind, CutsceneStep.Kind.SAY, "a line waits for you")
	scenes.advance()
	check(not scenes.overlay.typing(), "the first press shows the whole line")
	scenes.advance()
	await ui.ticks(8)
	check(elder.position.x > home + 5.0, "Rowan walks")
	await ui.ticks(90)
	check(not scenes.playing(), "it ended")
	check(ui.world.player.position.x > start + WALK - 10.0, "your hero walked where the cutscene sent them")
	check_eq(ui.world.player.face, -1, "your hero stays as the cutscene left them")
	check_near(elder.position.x, home, "Rowan is back where he stood")
	check(ui.hud.visible, "the HUD is back")
	check(ui.world.camera.scene_center == null, "the camera follows you again")
	check(not ui.world.input_blocked(), "your keys work again")
	await ui.ticks(2)
	check(ui.player().character.has_seen(SCENE), "the server noted it as seen")
	check(not ui.player().in_scene(), "and stopped protecting you")

func test_holding_the_menu_key_skips_it() -> void:
	await _play()
	Input.action_press("pause")
	await ui.ticks(TDCutscenePlayer.SKIP_HOLD + 2)
	Input.action_release("pause")
	check(not ui.world.scenes.playing(), "skipped")
	check(not ui.hud.title.visible, "the menu didn't open")
	await ui.ticks(2)
	check(ui.player().character.has_seen(SCENE), "a skipped cutscene counts as seen")

func test_changing_maps_stops_it_unseen() -> void:
	await _play()
	await ui.enter_map(&"meadow", 400.0)
	check(not ui.world.scenes.playing(), "stopped")
	check(ui.hud.visible, "the HUD is back")
	check(not ui.player().character.has_seen(SCENE), "not seen")
