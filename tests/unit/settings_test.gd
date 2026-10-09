extends TestCase
## The player's settings: every action has default keys that fit its slots, keys swap
## instead of being shared, Esc stays on the menu, every section saves and loads through
## settings.cfg (ignoring bad values), and applying writes the InputMap and audio buses.

func after_each() -> void:
	# put the real settings back the way the game started them
	Settings.load_file()

func test_every_action_has_defaults_that_fit() -> void:
	var seen := {}
	for a in Keybinds.ACTIONS:
		var action: String = a["action"]
		check(a["group"] in Keybinds.GROUPS, "%s is in a known group" % action)
		check(a["keys"].size() >= 1 and a["keys"].size() <= Keybinds.SLOTS, "%s has 1 to %d default keys" % [action, Keybinds.SLOTS])
		for k in a["keys"]:
			check(not seen.has(k), "%s and %s share a default key" % [seen.get(k, ""), action])
			seen[k] = action
	for action in Game.QUICKSLOT_ACTIONS + TDHud.WINDOW_ACTIONS:
		check(not Keybinds.info(action).is_empty(), "%s can be rebound" % action)

func test_setting_a_used_key_swaps_it() -> void:
	var k := Keybinds.new()
	k.reset()
	var other := k.set_key("attack", 0, KEY_SPACE)
	check_eq(other, "jump", "Space came from Jump")
	check_eq(k.key("attack", 0), KEY_SPACE, "Attack has Space")
	check_eq(k.key("jump", 0), KEY_X, "Jump got Attack's old X")
	check_eq(k.set_key("attack", 0, KEY_P), "", "a free key takes nothing from anyone")
	check_eq(k.key("attack", 0), KEY_P, "Attack has P")
	k.set_key("attack", 1, KEY_P)
	check_eq([k.key("attack", 0), k.key("attack", 1)], [KEY_CTRL, KEY_P], "moving a key between an action's own slots swaps them")

func test_escape_always_opens_the_menu() -> void:
	var k := Keybinds.new()
	k.reset()
	check_eq(k.set_key("attack", 0, KEY_ESCAPE), "", "Esc can't be taken")
	check_eq(k.key("attack", 0), KEY_X, "Attack keeps X")
	k.set_key("pause", 0, KEY_P)
	k.clear_key("pause", 0)
	check_eq(k.key("pause", 0), KEY_ESCAPE, "the menu key can't be changed or cleared")

func test_keys_save_and_load() -> void:
	var k := Keybinds.new()
	k.reset()
	k.set_key("loot", 1, KEY_P)
	k.clear_key("jump", 1)
	var cfg := ConfigFile.new()
	k.save_to(cfg)
	check(not cfg.has_section_key("keys", "pause"), "the fixed menu key isn't saved")
	cfg.set_value("keys", "attack", "not a list")
	cfg.set_value("keys", "stats", [KEY_S])
	var back := Keybinds.new()
	back.reset()
	back.load_from(cfg)
	check_eq(back.key("loot", 1), KEY_P, "a new key comes back")
	check_eq(back.key("jump", 1), 0, "a cleared slot comes back empty")
	check_eq(back.key("attack", 0), KEY_X, "a bad entry keeps the default")
	check_eq(back.key("stats", 0), KEY_S, "an entry with the wrong number of slots keeps the default")

func test_apply_writes_the_input_map() -> void:
	Settings.keybinds.set_key("loot", 0, KEY_P)
	Settings.keybinds.clear_key("attack", 1)
	Settings.apply(Settings.keybinds)
	var loot := InputMap.action_get_events("loot")
	check(loot.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_P), "loot is on P")
	check(not loot.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_Z), "and no longer on Z")
	check(loot.any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton), "the gamepad button stays")
	check_eq(InputMap.action_get_events("attack").filter(func(e: InputEvent) -> bool: return e is InputEventKey).size(), 1, "attack has one key left")
	check_eq(TDStatusBar._key_name("loot"), "P", "the status bar names the new key")

func test_audio_saves_loads_and_sets_the_buses() -> void:
	for bus in AudioSettings.BUSES:
		check(AudioServer.get_bus_index(bus) >= 0, "the %s bus exists" % bus)
	var a := AudioSettings.new()
	a.reset()
	a.volume["Music"] = 0.25
	a.muted = true
	var cfg := ConfigFile.new()
	a.save_to(cfg)
	cfg.set_value("audio", "effects", 7.0)
	var back := AudioSettings.new()
	back.reset()
	back.load_from(cfg)
	check_near(back.volume["Music"], 0.25, "music volume comes back")
	check_near(back.volume["Effects"], 1.0, "a volume over full is clamped")
	check(back.muted, "mute comes back")
	back.apply()
	check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.25), "the Music bus is turned down", 0.01)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute silences the Master bus")
	back.volume["Effects"] = 0.0
	back.muted = false
	back.apply()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "a bus at zero is muted on its own")

func test_video_saves_and_loads() -> void:
	var v := VideoSettings.new()
	v.reset()
	v.window_mode = VideoSettings.WindowMode.FULLSCREEN
	v.window_size = Vector2i(1280, 720)
	v.max_fps = 60
	v.vsync = false
	v.bloom = false
	v.fog = false
	var cfg := ConfigFile.new()
	v.save_to(cfg)
	var back := VideoSettings.new()
	back.reset()
	back.load_from(cfg)
	check_eq(back.window_mode, VideoSettings.WindowMode.FULLSCREEN, "window mode")
	check_eq(back.window_size, Vector2i(1280, 720), "window size")
	check_eq([back.max_fps, back.vsync, back.bloom, back.ambient_occlusion, back.fog], [60, false, false, true, false], "frame cap, vsync and effects")
	cfg.set_value("video", "window_mode", 9)
	cfg.set_value("video", "window_size", Vector2i(123, 45))
	cfg.set_value("video", "max_fps", 77)
	var fresh := VideoSettings.new()
	fresh.reset()
	fresh.load_from(cfg)
	check_eq([fresh.window_mode, fresh.window_size, fresh.max_fps], [VideoSettings.WindowMode.WINDOWED, Vector2i(1600, 900), 0], "values the menu doesn't offer keep the defaults")
	fresh.toggle_fullscreen()
	check_eq(fresh.window_mode, VideoSettings.WindowMode.BORDERLESS, "F11 goes fullscreen")
	fresh.toggle_fullscreen()
	check_eq(fresh.window_mode, VideoSettings.WindowMode.WINDOWED, "and back")

func test_the_file_keeps_other_sections() -> void:
	var path := "user://settings_test.cfg"
	Settings.path = path
	Settings.file.set_value("player", "name", "Keeper")
	Settings.audio.volume["Music"] = 0.5
	Settings.save()
	Settings.audio.reset()
	Settings.load_file()
	check_near(Settings.audio.volume["Music"], 0.5, "the saved volume loads")
	check_eq(Settings.file.get_value("player", "name"), "Keeper", "Game's section is still there")
	DirAccess.remove_absolute(path)
	Settings.path = Settings.PATH
