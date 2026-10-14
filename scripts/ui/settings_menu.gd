class_name TDSettingsMenu
extends CenterContainer
## The settings screen, opened from the title screen and the game menu. One page per tab:
##   Controls  two keys for every action (Keybinds); click one, then press the new key
##   Audio     a volume slider for each bus and a mute (AudioSettings)
##   Video     the window, frame rate and lighting effects (VideoSettings)
##   Developer test characters (DevSettings); debug builds only
## Every change is applied at once through the Settings autoload and saved when the screen
## closes. To add a tab, write a `_build_<name>` page and list it in `_init`.

## Back (or Esc) was pressed; the settings are saved.
signal closed

## Every page is this big (the Controls list scrolls), so the screen keeps its size from tab
## to tab.
const TAB_SIZE := Vector2(640, 280)

var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
## The section each page edits, for Reset to defaults.
var page_sections: Array[SettingsSection] = []
var tab := 0
var reset_button: Button
var back_button: Button
## A line under the pages: how to rebind, and which action a key was taken from.
var note: Label

## Controls: "action:slot" -> its key button, and the slot waiting for a key ("" if none).
var key_buttons := {}
var listening := ""
var listening_slot := 0

## Audio: bus -> [slider, percent label].
var sliders := {}
var mute_box: CheckBox

## Video
var mode_pick: OptionButton
var size_pick: OptionButton
var fps_pick: OptionButton
var vsync_box: CheckBox
var bloom_box: CheckBox
var ao_box: CheckBox
var fog_box: CheckBox
var shake_box: CheckBox
var _sizes: Array[Vector2i] = []

## Developer
var test_box: CheckBox
var rebuild_note: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.ARCH_PANEL, Vector4(30, 40, 30, 40), 0.7)
	add_child(card)
	var col := UiBuild.column(8)
	card.add_child(col)

	col.add_child(UiBuild.heading("Settings", 30))

	var tabs_row := UiBuild.centered_row([], 8)
	col.add_child(tabs_row)
	var group := ButtonGroup.new()
	var page_list := [["Controls", _build_controls(), Settings.keybinds, "menu/icon_controls"], ["Audio", _build_audio(), Settings.audio, "menu/icon_audio"],
			["Video", _build_video(), Settings.video, "menu/icon_video"]]
	if TestCharacters.allowed():
		page_list.append(["Developer", _build_developer(), Settings.dev, ""])
	for page in page_list:
		var b := Button.new()
		b.text = page[0]
		b.custom_minimum_size = Vector2(140, 38)
		b.add_theme_font_size_override("font_size", 16)
		UiStyle.style_tab(b, page[3])
		b.toggle_mode = true
		b.button_group = group
		var i := tab_buttons.size()
		b.pressed.connect(func() -> void: show_tab(i))
		tabs_row.add_child(b)
		tab_buttons.append(b)
		var p: Control = page[1]
		p.custom_minimum_size = TAB_SIZE
		col.add_child(p)
		pages.append(p)
		page_sections.append(page[2])

	note = UiBuild.label("", 12, Palette.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)
	reset_button = UiBuild.button("Reset to defaults", _reset_tab, Vector2(220, 42), 18)
	reset_button.icon = UiSkin.sized("menu/icon_reset", 20)
	back_button = UiBuild.button("Back", close, Vector2(150, 42), 18)
	col.add_child(UiBuild.centered_row([reset_button, back_button]))
	show_tab(0)

## Puts the open tab's settings back to their defaults.
func _reset_tab() -> void:
	_stop_listening()
	Settings.reset(page_sections[tab])
	refresh()

func _ready() -> void:
	Settings.changed.connect(_on_settings_changed)

# F11 changes the video settings from outside this screen.
func _on_settings_changed(_section: SettingsSection) -> void:
	if visible and listening == "":
		refresh()

func open() -> void:
	refresh()
	show()
	show_tab(tab)
	tab_buttons[tab].grab_focus()

func close() -> void:
	_stop_listening()
	Settings.save()
	hide()
	closed.emit()

func show_tab(i: int) -> void:
	_stop_listening()
	tab = i
	for j in pages.size():
		pages[j].visible = j == i
	tab_buttons[i].button_pressed = true
	note.text = "Click a key, then press the new one. Right-click clears it." if i == 0 else ""

## Shows the current settings in every widget.
func refresh() -> void:
	for id in key_buttons:
		var parts: PackedStringArray = id.split(":")
		var text := Keybinds.key_text(Settings.keybinds.key(parts[0], int(parts[1])))
		(key_buttons[id] as Button).text = text if text != "" else "-"
		UiStyle.set_keycap(key_buttons[id], "keycap" if text != "" else "keycap_empty")
	for bus in sliders:
		var v: float = Settings.audio.volume[bus]
		(sliders[bus][0] as HSlider).set_value_no_signal(roundf(v * 100.0))
		(sliders[bus][1] as Label).text = "%d%%" % roundi(v * 100.0)
	mute_box.set_pressed_no_signal(Settings.audio.muted)
	var v: VideoSettings = Settings.video
	mode_pick.select(v.window_mode)
	size_pick.select(maxi(0, _sizes.find(v.window_size)))
	size_pick.disabled = v.window_mode != VideoSettings.WindowMode.WINDOWED
	fps_pick.select(maxi(0, VideoSettings.FPS_CAPS.find(v.max_fps)))
	vsync_box.set_pressed_no_signal(v.vsync)
	bloom_box.set_pressed_no_signal(v.bloom)
	ao_box.set_pressed_no_signal(v.ambient_occlusion)
	fog_box.set_pressed_no_signal(v.fog)
	shake_box.set_pressed_no_signal(v.screen_shake)
	if test_box:
		test_box.set_pressed_no_signal(Settings.dev.test_characters)
		rebuild_note.text = "They'll be made again the next time you play." if Settings.dev.rebuild_next else ""

# ---------- controls ----------

func _build_controls() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiStyle.style_scroll(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for group in Keybinds.GROUPS:
		list.add_child(UiBuild.label(group, 16, Palette.SUN))
		for action in Keybinds.in_group(group):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			list.add_child(row)
			var name_label := UiBuild.label(Keybinds.info(action)["label"], 14, Palette.MIST)
			name_label.custom_minimum_size.x = 260
			row.add_child(name_label)
			if action in Keybinds.FIXED:
				var fixed := UiBuild.label("%s (always)" % Keybinds.key_text(Settings.keybinds.key(action, 0)), 14, Palette.MUTED)
				row.add_child(fixed)
				continue
			for slot in Keybinds.SLOTS:
				row.add_child(_key_button(action, slot))
	return scroll

func _key_button(action: String, slot: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 32)
	b.add_theme_font_size_override("font_size", 14)
	UiStyle.style_key_button(b)
	b.pressed.connect(func() -> void: _listen(action, slot))
	b.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_stop_listening()
			Settings.keybinds.clear_key(action, slot)
			Settings.apply(Settings.keybinds)
			refresh()
			b.accept_event())
	key_buttons["%s:%d" % [action, slot]] = b
	return b

## Waits for the next key press to put in `action`'s `slot`.
func _listen(action: String, slot: int) -> void:
	_stop_listening()
	listening = action
	listening_slot = slot
	key_buttons["%s:%d" % [action, slot]].text = "Press a key..."
	UiStyle.set_keycap(key_buttons["%s:%d" % [action, slot]], "keycap_listening")
	note.text = "Press the new key for %s, or Esc to cancel." % Keybinds.info(action)["label"]

func _stop_listening() -> void:
	if listening != "":
		listening = ""
		refresh()

## A key pressed while waiting for one, given to the action (Esc cancels).
func bind_pressed_key(keycode: int) -> void:
	var action := listening
	var slot := listening_slot
	listening = ""
	if Settings.keybinds.reserved(keycode):
		note.text = "Kept the old key."
	else:
		var other := Settings.keybinds.set_key(action, slot, keycode)
		Settings.apply(Settings.keybinds)
		note.text = "%s was on %s, so they swapped." % [Keybinds.key_text(keycode), Keybinds.info(other)["label"]] if other != "" else ""
	refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if listening != "" and k and k.pressed and not k.echo:
		bind_pressed_key(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
		get_viewport().set_input_as_handled()
	elif listening == "" and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()

# ---------- audio ----------

func _build_audio() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	page.add_child(grid)
	for bus in AudioSettings.BUSES:
		var name_label := UiBuild.label(bus, 16, Palette.MIST)
		name_label.custom_minimum_size.x = 140
		grid.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(340, 28)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiStyle.style_slider(slider)
		grid.add_child(slider)
		var percent := UiBuild.label("", 16, Palette.MIST)
		percent.custom_minimum_size.x = 56
		grid.add_child(percent)
		sliders[bus] = [slider, percent]
		slider.value_changed.connect(func(value: float) -> void:
			Settings.audio.volume[bus] = value / 100.0
			percent.text = "%d%%" % roundi(value)
			Settings.apply(Settings.audio))
	mute_box = _check_box("Mute all sound", func(on: bool) -> void:
		Settings.audio.muted = on
		Settings.apply(Settings.audio), "menu/icon_mute")
	page.add_child(mute_box)
	return page

# ---------- video ----------

func _build_video() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	var v: VideoSettings = Settings.video

	mode_pick = _option_button(VideoSettings.WINDOW_MODE_NAMES, func(i: int) -> void:
		v.window_mode = i as VideoSettings.WindowMode
		Settings.apply(v)
		refresh())
	_grid_row(grid, "Window", mode_pick)

	_sizes = VideoSettings.sizes_that_fit()
	if not v.window_size in _sizes:
		_sizes.append(v.window_size)
	var size_names: Array[String] = []
	for s in _sizes:
		size_names.append("%d x %d" % [s.x, s.y])
	size_pick = _option_button(size_names, func(i: int) -> void:
		v.window_size = _sizes[i]
		Settings.apply(v))
	_grid_row(grid, "Window size", size_pick)

	var fps_names: Array[String] = []
	for f in VideoSettings.FPS_CAPS:
		fps_names.append("No limit" if f == 0 else "%d" % f)
	fps_pick = _option_button(fps_names, func(i: int) -> void:
		v.max_fps = VideoSettings.FPS_CAPS[i]
		Settings.apply(v))
	_grid_row(grid, "Frame rate limit", fps_pick)

	vsync_box = _video_toggle("VSync", "vsync")
	bloom_box = _video_toggle("Bloom (glowing lights and sun)", "bloom")
	ao_box = _video_toggle("Ambient occlusion (soft contact shadows)", "ambient_occlusion")
	fog_box = _video_toggle("Depth fog", "fog")
	shake_box = _video_toggle("Screen shake", "screen_shake")
	# the switches in two columns (short names left, the long effect names right), so the
	# page is no taller than the others
	var switches := GridContainer.new()
	switches.columns = 2
	switches.add_theme_constant_override("h_separation", 18)
	page.add_child(switches)
	for box in [vsync_box, bloom_box, fog_box, ao_box, shake_box]:
		switches.add_child(box)
	var hint := UiBuild.label("Turning off bloom, ambient occlusion or fog helps slower computers.", 12, Palette.MUTED)
	page.add_child(hint)
	return page

func _video_toggle(text: String, property: String) -> CheckBox:
	return _check_box(text, func(on: bool) -> void:
		Settings.video.set(property, on)
		Settings.apply(Settings.video))

func _grid_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := UiBuild.label(text, 16, Palette.MIST)
	l.custom_minimum_size.x = 180
	grid.add_child(l)
	grid.add_child(control)

# ---------- developer ----------

func _build_developer() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	test_box = _check_box("Test characters", func(on: bool) -> void:
		Settings.dev.test_characters = on
		Settings.apply(Settings.dev))
	page.add_child(test_box)
	page.add_child(UiBuild.label("Character select lists a Lv %d test character of every job in its best gear.\nYour own characters stay as they are; turn this off to get back to them." % TestCharacters.LEVEL, 12, Palette.MUTED))
	var rebuild := UiStyle.menu_button("Rebuild test characters", Vector2(280, 40), 16)
	rebuild.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rebuild.pressed.connect(func() -> void:
		Settings.dev.rebuild_next = true
		refresh())
	page.add_child(rebuild)
	rebuild_note = UiBuild.label("", 12, Palette.MUTED)
	page.add_child(rebuild_note)
	page.add_child(UiBuild.label("Only in debug builds; a release build never shows or uses this.", 12, Palette.MUTED))
	return page

# ---------- little builders ----------

func _option_button(items: Array[String], on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(260, 34)
	UiStyle.style_option_button(o)
	for it in items:
		o.add_item(it)
	o.item_selected.connect(on_pick)
	return o

func _check_box(text: String, on_toggle: Callable, icon := "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	UiStyle.style_check_box(c, icon)
	c.add_theme_font_size_override("font_size", 15)
	c.add_theme_color_override("font_color", Palette.MIST)
	c.add_theme_color_override("font_hover_color", Palette.SUN)
	c.add_theme_color_override("font_pressed_color", Palette.MIST)
	c.add_theme_color_override("font_hover_pressed_color", Palette.SUN)
	c.add_theme_color_override("font_focus_color", Palette.MIST)
	c.toggled.connect(on_toggle)
	return c
