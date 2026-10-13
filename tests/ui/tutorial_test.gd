extends TestCase
## The tutorial beach in a running game: a new character wakes lying on Daybreak Shore while
## its opening cutscene plays, with a faint glow out over the water. The girl stands in one
## spot at a time, a key hint shows at the bottom for the step you're on, and the way to the
## village is hidden (and goes nowhere) until her last quest is handed in.

const GIRL := &"girl_on_beach"

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start("Dawnling", true)

func after_each() -> void:
	ui.stop()

func _girls() -> Array[TDNpc]:
	return ui.world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == GIRL)

func _exit_shown() -> bool:
	return ui.world.stage.locked_portals.keys().any(func(n: Node3D) -> bool: return n.visible)

## Hands in tutorial quests up to and including `last` on the server, as playing them would.
func _done_through(last: int) -> void:
	await ui.edit(func(c: Character) -> void:
		for id in [&"tut1_race", &"tut2_lookout", &"tut3_shell", &"tut4_tide_pool", &"tut5_dewling_jelly"].slice(0, last):
			c.quests.done[id] = true)

func test_you_wake_on_the_beach_in_its_opening_scene() -> void:
	check_eq(ui.world.map.id, Character.NEW_MAP, "a new character starts on Daybreak Shore")
	await ui.ticks(2)
	check(ui.world.scenes.playing(), "the opening cutscene plays")
	check_eq(ui.world.player._animation(), &"faint", "lying on the sand")
	check_eq(ui.world.stage.get_tree().get_nodes_in_group(&"tear").size(), 1, "a glow hangs over the water")
	ui.world.scenes.skip()
	await ui.ticks(2)
	check(not ui.world.scenes.playing(), "skipped")
	check_ne(ui.world.player._animation(), &"faint", "up on your feet")

func test_she_stands_in_one_spot_and_the_hint_follows_the_step() -> void:
	ui.world.scenes.skip()
	await ui.ticks(2)
	check_eq(_girls().size(), 1, "the girl stands in one spot")
	check_eq(_girls()[0].position.y, float(ui.world.map.ground_y), "on the sand at first")
	check_eq(ui.hud.quest_hint(), TDHud.keys_in("Walk to her and press {move_up} to talk"), "the hint says how to talk to her")
	check(not ui.hud.quest_hint().contains("{"), "keys are filled in")
	await ui.edit(func(c: Character) -> void: c.quests.accept(Content.quests[&"tut1_race"]))
	check_eq(_girls().size(), 1, "still one of her")
	check(_girls()[0].position.y < ui.world.map.ground_y, "she waits up on the big rock")
	check(ui.hud.quest_hint().contains(TDStatusBar._key_name("jump")), "the race hint names the jump key")
	check(ui.hud.keys_help.visible, "it shows")
	check(ui.hud.keys_help.position.y > TDWorld.VIEW.y / 2.0, "at the bottom of the screen")

func test_the_way_out_opens_at_the_end() -> void:
	ui.world.scenes.skip()
	await ui.ticks(2)
	check(not _exit_shown(), "no portal to the village yet")
	var portal: PortalDef = ui.world.map.portals[0]
	ui.teleport(Vector2(portal.x, ui.world.map.ground_y))
	await ui.press("move_up")
	await ui.ticks(4)
	check_eq(ui.world.map.id, Character.NEW_MAP, "Up where it will be does nothing")
	await _done_through(5)
	check(_exit_shown(), "the portal shows once she's had her jelly")
	check(_girls().is_empty(), "she's gone home")
	await ui.press("move_up")
	await ui.ticks(6)
	check_eq(ui.world.map.id, Character.START_MAP, "it leads to Dawnrise Village")
	check(ui.world.npcs().any(func(n: TDNpc) -> bool: return n.def.id == &"rowans_granddaughter"), "she's there, by her grandfather")
