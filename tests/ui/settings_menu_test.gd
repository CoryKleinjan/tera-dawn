extends TestCase
## The game menu and the settings screen in a running game: Esc opens and closes the menu,
## Settings opens from the menu and from the title screen and goes back where it came
## from, rebinding a key works in game, the sliders and toggles change the sound and the
## stage, and closing saves.

const PATH := "user://settings_menu_test.cfg"

var ui: UiHelpers

func before_each() -> void:
	Settings.path = PATH
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	ui.stop()
	DirAccess.remove_absolute(PATH)
	Settings.path = Settings.PATH
	Settings.load_file()

func _menu() -> TDSettingsMenu:
	return ui.hud.settings_menu

func test_escape_opens_and_closes_the_game_menu() -> void:
	await ui.press("pause")
	var gm := ui.hud.game_menu
	check(ui.hud.title.visible and gm.visible and not ui.hud.title.title_card.visible, "Esc opens the game menu without the title card")
	check(await ui.redraw(gm), "the game menu draws")
	await ui.press("pause")
	check(not ui.hud.title.visible, "Esc again resumes")

func test_settings_from_the_game_menu() -> void:
	await ui.press("pause")
	ui.hud.game_menu.settings_button.pressed.emit()
	check(_menu().visible and not ui.hud.game_menu.visible, "Settings replaces the game menu")
	for i in _menu().pages.size():
		_menu().tab_buttons[i].pressed.emit()
		check(_menu().pages[i].visible, "tab %d shows its page" % i)
		check(await ui.redraw(_menu().pages[i]), "page %d draws" % i)
	await ui.press("pause")
	check(not _menu().visible and ui.hud.game_menu.visible, "Esc goes back to the game menu")
	check(FileAccess.file_exists(PATH), "closing saves the settings")
	await ui.press("pause")
	check(not ui.hud.title.visible, "and Esc again resumes")

func test_settings_from_the_title_screen() -> void:
	ui.world.stop()
	ui.hud.show_title(false)
	ui.hud.open_settings()
	check(_menu().visible and not ui.hud.title.title_card.visible, "Settings replaces the title card")
	_menu().back_button.pressed.emit()
	check(not _menu().visible and ui.hud.title.title_card.visible and not ui.hud.game_menu.visible, "Back shows the title card again")

func test_rebinding_a_key_works_in_game() -> void:
	await ui.press("pause")
	ui.hud.open_settings()
	var button: Button = _menu().key_buttons["inventory:0"]
	check_eq(button.text, "I", "the inventory key shows")
	button.pressed.emit()
	check_eq(_menu().listening, "inventory", "clicking it waits for a key")
	_menu().bind_pressed_key(KEY_E)
	check_eq(button.text, "E", "the new key shows")
	check_eq((_menu().key_buttons["equipment:0"] as Button).text, "I", "equipment got the old key")
	check(_menu().note.text.contains("Equipment"), "the note says what was swapped")
	check_eq(TDStatusBar._key_name("inventory"), "E", "the status bar follows")
	_menu().reset_button.pressed.emit()
	check_eq(button.text, "I", "Reset puts the default back")
	button.pressed.emit()
	_menu().bind_pressed_key(KEY_ESCAPE)
	check(_menu().listening == "" and button.text == "I", "Esc cancels")

func test_audio_and_video_change_the_game() -> void:
	ui.hud.open_settings()
	var music: HSlider = _menu().sliders["Music"][0]
	music.value = 30
	check_near(Settings.audio.volume["Music"], 0.3, "the slider sets the volume")
	check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.3), "and the bus", 0.01)
	var env := ui.world.stage.env
	_menu().bloom_box.button_pressed = false
	_menu().fog_box.button_pressed = false
	check(not env.glow_enabled and not env.fog_enabled and env.ssao_enabled, "toggles turn the stage's effects off")
	_menu().show_tab(2)
	_menu().reset_button.pressed.emit()
	check(env.glow_enabled and env.fog_enabled and _menu().bloom_box.button_pressed, "Reset turns them back on")
	_menu().close()
	var saved := ConfigFile.new()
	saved.load(PATH)
	check_near(float(saved.get_value("audio", "music")), 0.3, "the volume was saved")
