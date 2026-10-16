extends TestCase
## Playing with a gamepad (TDPad): the left trigger turns to the second page of quickslots,
## Back opens the window menu, and while a window is open a pad cursor clicks, drags and
## closes windows with the hero standing still; the mouse takes over again when it moves.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	TDPad.using_pad = false
	Keybinds.use_pad_page(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.stop()

func _button(index: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = down
	Input.parse_input_event(e)
	await ui.frames(2)

func _tap(index: int) -> void:
	await _button(index, true)
	await _button(index, false)

func _trigger(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await ui.frames(2)

func _has_pad(action: String, index: int) -> bool:
	return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton and e.button_index == index)

func test_the_left_trigger_turns_to_quickslots_4_to_8() -> void:
	check(_has_pad("quick_1", JOY_BUTTON_Y) and not _has_pad("quick_4", JOY_BUTTON_Y), "Y is quickslot 1")
	check(_has_pad("loot", JOY_BUTTON_B), "B picks up")
	await _trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	check_eq(Keybinds.pad_page, 1, "holding the trigger turns the page")
	for pair in [["quick_4", JOY_BUTTON_Y], ["quick_5", JOY_BUTTON_RIGHT_SHOULDER], ["quick_6", JOY_BUTTON_LEFT_SHOULDER], ["quick_8", JOY_BUTTON_B]]:
		check(_has_pad(pair[0], pair[1]), "%s is on its page 2 button" % pair[0])
	check(InputMap.action_get_events("quick_7").any(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion and e.axis == JOY_AXIS_TRIGGER_RIGHT), "the right trigger is quickslot 7")
	check(not _has_pad("quick_1", JOY_BUTTON_Y) and not _has_pad("loot", JOY_BUTTON_B), "page 1's uses of those buttons are off")
	check(_has_pad("jump", JOY_BUTTON_A) and _has_pad("attack", JOY_BUTTON_X), "jump and attack still work")
	await _button(JOY_BUTTON_Y, true)
	check(Input.is_action_pressed("quick_4") and not Input.is_action_pressed("quick_1"), "Y uses quickslot 4")
	await _button(JOY_BUTTON_Y, false)
	await _trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check_eq(Keybinds.pad_page, 0, "letting go turns back")
	check(_has_pad("quick_1", JOY_BUTTON_Y) and _has_pad("loot", JOY_BUTTON_B), "page 1 is back")

func test_the_quickslots_show_pad_buttons_and_light_the_page() -> void:
	check_eq(TDQuickslots.key_label(0), TDStatusBar._key_name("quick_1"), "keys before the pad is touched")
	await _trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	check(TDPad.using_pad, "the pad is in use")
	check_eq(TDQuickslots.key_label(0), "Y", "slot 1 says Y")
	check_eq(TDQuickslots.key_label(3), "Y", "slot 4 says Y too (it's on the other page)")
	check_eq(TDQuickslots.key_label(6), "RT", "slot 7 says RT")
	check(TDQuickslots.off_page(0) and not TDQuickslots.off_page(3), "page 2 is lit while the trigger is held")
	await _trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(not TDQuickslots.off_page(0) and TDQuickslots.off_page(3), "page 1 is lit after")
	check(TDQuickslots.off_page(7), "slot 8 is page 2")
	check_eq(TDStatusBar._key_name("jump"), "A", "hints name the pad's buttons")

func test_back_opens_the_window_menu() -> void:
	await _tap(JOY_BUTTON_BACK)
	var menu := ui.hud.pad.menu
	check(menu.visible, "Back opens the menu")
	check_eq(menu.buttons.size(), TDHud.WINDOW_ACTIONS.size(), "a button for every window")
	check(menu.buttons[0].has_focus(), "the first is ready for A")
	check(ui.world.input_blocked(), "the hero stands still")
	await _tap(JOY_BUTTON_A)
	check(ui.hud.windows["inventory"].visible, "A opens the bag")
	check(not menu.visible, "and closes the menu")
	await ui.frames(2)
	check(ui.hud.pad.cursor_on, "the pad cursor is on")
	check(ui.world.input_blocked(), "the hero still stands still")
	await _tap(JOY_BUTTON_BACK)
	await _tap(JOY_BUTTON_B)
	check(not menu.visible and ui.hud.windows["inventory"].visible, "B closes the menu, not the window")

func test_the_cursor_clicks_drags_and_closes() -> void:
	var stats: TDWindow = ui.hud.windows["stats"]
	var bag: TDWindow = ui.hud.windows["inventory"]
	TDPad.using_pad = true
	ui.hud.toggle_window("stats")
	ui.hud.toggle_window("inventory")
	stats.settle()
	bag.settle()
	await ui.frames(2)
	var pad := ui.hud.pad
	check(pad.cursor_on, "a window open with the pad turns the cursor on")
	check(bag.get_global_rect().has_point(pad.cursor), "it starts on the top window")
	# hold A on the title bar and move: the window follows
	pad.move_cursor(bag.global_position + Vector2(bag.size.x / 2.0, 12) - pad.cursor)
	var was := bag.position
	await _button(JOY_BUTTON_A, true)
	for i in 4:
		pad.move_cursor(Vector2(-10, 5))
		await ui.frames(1)
	await _button(JOY_BUTTON_A, false)
	check_eq(bag.position, was + Vector2(-40, 20), "A drags a window by its title bar")
	# A on the close button
	pad.move_cursor(bag.global_position + bag._close_rect().get_center() - pad.cursor)
	await _tap(JOY_BUTTON_A)
	check(not bag.visible, "A clicks the close button")
	check(pad.cursor_on, "the cursor stays while a window is open")
	await _tap(JOY_BUTTON_B)
	check(not stats.visible, "B closes the top window")
	await ui.frames(2)
	check(not pad.cursor_on, "no windows, no cursor")
	check(not ui.world.input_blocked(), "the hero moves again")

func test_the_stick_moves_the_cursor_and_the_mouse_takes_over() -> void:
	TDPad.using_pad = true
	ui.hud.toggle_window("stats")
	await ui.frames(2)
	var pad := ui.hud.pad
	var from := pad.cursor
	Input.action_press("move_right")
	await ui.frames(5)
	Input.action_release("move_right")
	check(pad.cursor.x > from.x and is_equal_approx(pad.cursor.y, from.y), "right on the stick moves it right")
	var m := InputEventMouseMotion.new()
	m.position = Vector2(100, 100)
	m.relative = Vector2(20, 0)
	Input.parse_input_event(m)
	await ui.frames(2)
	check(not TDPad.using_pad and not pad.cursor_on, "moving the mouse hands back to it")
	check(ui.hud.windows["stats"].visible, "the window stays open")
	check(not ui.world.input_blocked(), "and the hero can move")
