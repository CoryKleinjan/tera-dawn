class_name UiHelpers
extends RefCounted
## A running game for UI tests: scenes/world.tscn in single player (its own server, saves
## in a throwaway folder), plus ways to fill the character on the server, push mouse
## clicks and drags through the viewport, and make sure a Control really drew.
##
##   var ui := UiHelpers.new(self)
##   await ui.start()
##   await ui.edit(func(c: Character) -> void: c.inventory.add(Content.item(&"red_potion"), 5))
##   await ui.click(ui.hud.windows["inventory"], Vector2(40, 50))
##   ui.stop()

const SAVE_DIR := "user://ui_test_characters"

var test: Node
var world: TDWorld
var hud: TDHud
var _save_dir := ""
var _username := ""

func _init(owner: Node) -> void:
	test = owner

## Starts single player as `char_name` and waits until the server has put them on the
## starting map. Monsters can't hurt the player.
func start(char_name := "Uitester") -> void:
	await open_title()
	Net.play_single()
	Net.create_character(char_name, NewCharacter.new())
	Net.play(char_name)
	await ticks(3)
	player().inv = 100000000

## Opens the game on its title screen, not playing yet.
func open_title() -> void:
	_save_dir = Net.save_dir
	_username = Game.last_username
	Net.save_dir = SAVE_DIR
	clear_saves()
	world = load("res://scenes/world.tscn").instantiate() as TDWorld
	test.add_child(world)
	hud = world.hud
	await frames(2)

## Leaves the game, frees the world and puts Net and Game back as they were.
func stop() -> void:
	if world:
		world.stop()
		world.free()
		world = null
		hud = null
	Net.stop()
	Net.save_dir = _save_dir
	Game.social = {}
	Game.last_username = _username
	Game.me = Character.create("")
	clear_saves()
	DirAccess.remove_absolute(SAVE_DIR)

static func clear_saves() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	for d in DirAccess.get_directories_at(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR.path_join(d)):
			DirAccess.remove_absolute(SAVE_DIR.path_join(d).path_join(f))
		DirAccess.remove_absolute(SAVE_DIR.path_join(d))
	for f in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR.path_join(f))

## The server's side of this game's player.
func player() -> SimPlayer:
	return Net.server.sessions.get(test.multiplayer.get_unique_id())

## Changes the real character on the server and waits until Game.me has the new copy.
func edit(change: Callable) -> void:
	var c := player().character
	change.call(c)
	c.recalc()
	player().dirty_character = true
	await ticks(2)

## Sends the player to map `id` at `x` and waits until the game has built it.
func enter_map(id: StringName, x: float) -> void:
	Net.server._enter_map(player(), id, x)
	await ticks(3)

## Moves the player instantly on both sides.
func teleport(at: Vector2) -> void:
	world.player.position = at
	world.player.vel = Vector2.ZERO
	player().position = at

## An NPC view for `def` standing next to the player (so its windows stay open).
func npc_beside(def: NpcDef) -> TDNpc:
	var place := NpcPlacement.new()
	place.npc = def
	place.x = world.player.position.x + 20
	var n := TDNpc.create(world, place, world.platforms[0])
	world.npc_layer.add_child(n)
	n.position = world.player.position + Vector2(20, 0)
	return n

func ticks(n: int) -> void:
	for i in n:
		await test.get_tree().physics_frame

func frames(n: int) -> void:
	for i in n:
		await test.get_tree().process_frame

## Redraws `c` and waits for it. True if its draw ran (it has to be visible).
func redraw(c: CanvasItem) -> bool:
	var drawn := [0]
	var count := func() -> void: drawn[0] += 1
	c.draw.connect(count)
	c.queue_redraw()
	await frames(2)
	c.draw.disconnect(count)
	return drawn[0] > 0

## The screen position of a point inside a Control.
static func screen(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform() * local

## A mouse button press and release at `local` inside `c`, sent through the viewport the
## way a real click arrives (so the Control under the point gets it).
func click(c: Control, local: Vector2, button := MOUSE_BUTTON_LEFT, double := false) -> void:
	var at := screen(c, local)
	_button(at, button, true, double)
	_button(at, button, false, false)
	await frames(1)

## Holds the left button at `from` inside `c`, moves by `by` and lets go.
func drag(c: Control, from: Vector2, by: Vector2) -> void:
	var at := screen(c, from)
	_button(at, MOUSE_BUTTON_LEFT, true, false)
	var steps := 4
	for i in steps:
		var m := InputEventMouseMotion.new()
		m.position = at + by * (i + 1) / steps
		m.global_position = m.position
		m.relative = by / steps
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		test.get_viewport().push_input(m, true)
	_button(at + by, MOUSE_BUTTON_LEFT, false, false)
	await frames(1)

## The mouse moving to `local` inside `c`.
func hover(c: Control, local: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = screen(c, local)
	m.global_position = m.position
	test.get_viewport().push_input(m, true)
	await frames(1)

func _button(at: Vector2, button: int, pressed: bool, double: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button
	e.pressed = pressed
	e.double_click = double
	if pressed and button == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	test.get_viewport().push_input(e, true)

## Presses and releases an input action, as a key would.
func press(action: String) -> void:
	for down in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = down
		Input.parse_input_event(e)
		await frames(1)
	await frames(1)
