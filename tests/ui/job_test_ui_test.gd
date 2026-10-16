extends TestCase
## The job test's Trial Ground in a running game: the tear isn't there until you reach the
## far end, then it hangs over the arena and its scene plays; the boss steps out once it ends.
## The world map shows you in the job town, and the hall's trial gate only shows during the test.

const TRIAL := &"trial_greenbough"
const HALL := &"greenbough_hall"

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start("Trialist")

func after_each() -> void:
	ui.stop()

func _tears() -> Array[Node]:
	return ui.world.stage.get_tree().get_nodes_in_group(&"tear")

func _gate_shown() -> bool:
	return ui.world.stage.locked_portals.keys().any(func(n: Node3D) -> bool: return n.visible)

func test_the_tear_opens_at_the_far_end() -> void:
	await ui.enter_map(TRIAL, 180.0)
	check_eq(ui.world.map.outside(), &"greenbough", "on the world map you're in Greenbough")
	check_eq(_tears().size(), 1, "the tear is there")
	check(not (_tears()[0] as Node3D).visible, "but hidden")
	var map := ui.world.map
	ui.teleport(Vector2(map.tears[0].x, map.surface_y(map.tear_platform)))
	await ui.ticks(6)
	check((_tears()[0] as Node3D).visible, "it opens over the arena")
	check(ui.world.scenes.playing(), "its scene plays")
	ui.world.scenes.skip()
	await ui.ticks(6)
	var boss := ui.world.mobs().filter(func(m: TDMob) -> bool: return m.def.id == &"tear_boss")
	check(not boss.is_empty() and boss[0].visible, "the boss steps out")

func test_the_trial_gate_shows_only_during_the_test() -> void:
	await ui.enter_map(HALL, 700.0)
	check(not _gate_shown(), "no gate before the test")
	await ui.edit(func(c: Character) -> void: c.quests.accept(Content.quests[&"jtest_archer"]))
	await ui.ticks(2)
	check(_gate_shown(), "the gate shows during the test")
