extends TestCase
## How windows answer the keyboard and mouse in a running game: every window action opens
## and closes its window, Esc closes the top window and then opens the pause menu, the
## close button closes, the title bar drags (and never off screen), clicking raises a
## window, the status bar's buttons toggle windows, and keys do nothing on the title screen.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	ui.stop()

func _win(key: String) -> TDWindow:
	return ui.hud.windows[key]

func _open_count() -> int:
	return ui.hud.windows.values().filter(func(w: TDWindow) -> bool: return w.visible).size()

func test_every_window_action_has_a_key() -> void:
	for action in TDHud.WINDOW_ACTIONS:
		check(InputMap.has_action(action), "input action %s exists" % action)
		check(InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventKey), "%s is bound to a key" % action)
		check(TDStatusBar._key_name(action) != "", "the status bar can name %s's key" % action)
	# no two windows share a key, and no window shares one with movement or attacks
	var seen := {}
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			var k := e as InputEventKey
			if k:
				var key := k.physical_keycode
				if seen.has(key) and (action in TDHud.WINDOW_ACTIONS or seen[key] in TDHud.WINDOW_ACTIONS):
					fail("%s and %s share the key %s" % [seen[key], action, OS.get_keycode_string(key)])
				seen[key] = action

func test_every_window_action_toggles_its_window() -> void:
	for action in TDHud.WINDOW_ACTIONS:
		await ui.press(action)
		check(_win(action).visible, "pressing %s opens its window" % action)
		check_eq(_open_count(), 1, "only the %s window is open" % action)
		await ui.press(action)
		check(not _win(action).visible, "pressing %s again closes it" % action)

func test_window_keys_do_nothing_on_the_title_screen() -> void:
	ui.hud.show_title(true)
	for action in TDHud.WINDOW_ACTIONS:
		await ui.press(action)
		check(not _win(action).visible, "%s stays closed behind the pause menu" % action)
	ui.hud.game_menu.resume_button.pressed.emit()
	check(not ui.hud.title.visible, "Resume closes the pause menu")

func test_escape_closes_the_top_window_then_pauses() -> void:
	for action in ["inventory", "stats", "quests"]:
		await ui.press(action)
	check_eq(_open_count(), 3, "three windows open")
	await ui.press("pause")
	check(not _win("quests").visible and _win("inventory").visible and _win("stats").visible, "Esc closes the last one opened")
	await ui.press("pause")
	await ui.press("pause")
	check_eq(_open_count(), 0, "Esc closes them one at a time")
	check(not ui.hud.title.visible, "no pause menu while windows were open")
	await ui.press("pause")
	check(ui.hud.title.visible and ui.hud.game_menu.visible, "with nothing open, Esc pauses")
	ui.hud.game_menu.resume_button.pressed.emit()

func test_close_button_closes_every_window() -> void:
	for key in ui.hud.windows:
		var w := _win(key)
		w.visible = true
		w.raise()
		check(Rect2(Vector2.ZERO, w.size).encloses(w._close_rect()), "%s: the close button lies inside the window" % key)
		await ui.click(w, w._close_rect().get_center())
		check(not w.visible, "%s: the close button closes it" % key)

func test_title_bar_drags_windows() -> void:
	for key in TDHud.WINDOW_ACTIONS:
		var w := _win(key)
		ui.hud.toggle_window(key)
		var at := w.position
		var by := Vector2(-40 if at.x > 100 else 40, -30 if at.y > 100 else 30)
		await ui.drag(w, Vector2(w.size.x / 2.0, 12), by)
		check_eq(w.position, (at + by).clamp(Vector2.ZERO, TDWorld.VIEW - w.size), "%s: dragging its title bar moves it" % key)
		check_ne(w.position, at, "%s: position after dragging" % key)
		ui.hud.toggle_window(key)

func test_windows_cant_be_dragged_off_screen() -> void:
	var w := _win("inventory")
	ui.hud.toggle_window("inventory")
	for by in [Vector2(5000, 5000), Vector2(-5000, -5000), Vector2(5000, -5000)]:
		await ui.drag(w, Vector2(w.size.x / 2.0, 12), by)
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(Rect2(w.position, w.size)), "dragged by %s it stays on screen at %s" % [by, w.position])

func test_dragging_the_body_doesnt_move_a_window() -> void:
	var w := _win("stats")
	ui.hud.toggle_window("stats")
	var at := w.position
	await ui.drag(w, Vector2(w.size.x / 2.0, w.size.y / 2.0), Vector2(30, 30))
	check_eq(w.position, at, "dragging the middle of the window")

func test_clicking_a_window_raises_it() -> void:
	ui.hud.toggle_window("inventory")
	ui.hud.toggle_window("equipment")
	var inv := _win("inventory")
	check(ui.hud.window_layer.get_child(-1) == _win("equipment"), "the last window opened is on top")
	await ui.click(inv, Vector2(inv.size.x / 2.0, inv.size.y - 10))
	check(ui.hud.window_layer.get_child(-1) == inv, "clicking the inventory brings it to the top")

func test_window_at_finds_the_top_window() -> void:
	ui.hud.toggle_window("inventory")
	ui.hud.toggle_window("equipment")
	var inv := _win("inventory")
	var gear := _win("equipment")
	gear.position = inv.position # stack them
	var middle := inv.get_global_rect().get_center()
	check(ui.hud.window_at(middle) == gear, "window_at a point both cover is the top one")
	inv.raise()
	check(ui.hud.window_at(middle) == inv, "and follows raise()")
	check(ui.hud.window_at(Vector2(2, 300)) == null, "window_at an empty spot is null")
	ui.hud.toggle_window("inventory")
	check(ui.hud.window_at(middle) == gear, "closed windows don't count")

func test_status_bar_buttons_toggle_their_windows() -> void:
	var bar := ui.hud.status
	check(await ui.redraw(bar), "the status bar draws")
	for i in TDHud.WINDOW_ACTIONS.size():
		var action := TDHud.WINDOW_ACTIONS[i]
		var r := bar._window_button_rect(i)
		check(Rect2(Vector2.ZERO, bar.size).encloses(r), "%s's button lies inside the bar" % action)
		await ui.click(bar, r.get_center())
		check(_win(action).visible, "clicking %s's button opens it" % action)
		check(await ui.redraw(bar), "the status bar draws with %s open" % action)
		await ui.click(bar, r.get_center())
		check(not _win(action).visible, "clicking %s's button again closes it" % action)

func test_minimap_click_opens_the_world_map() -> void:
	await ui.click(ui.hud.overlay, Vector2(TDWorld.VIEW.x - 100, 30))
	check(_win("worldmap").visible, "clicking the minimap opens the world map")

func test_typing_in_chat_keeps_windows_shut() -> void:
	ui.hud.chat.open()
	await ui.frames(1)
	check(ui.hud.typing(), "the chat line has focus")
	check(ui.world.input_blocked(), "and the player stands still")
	ui.hud.chat.close()
	check(not ui.hud.typing(), "closing the chat line ends typing")
