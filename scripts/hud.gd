class_name TDHud
extends CanvasLayer
## Status bar (level, HP, MP, EXP, Dawnshards), the in-game overlay and the title menu.

var world: TDWorld
var overlay: TDOverlay
var level_label: Label
var shard_label: Label
var bars := {}
var title: Control
var play_button: Button
var ui_theme: Theme

func _ready() -> void:
	layer = 10
	ui_theme = Theme.new()
	ui_theme.default_font = Game.ui_font
	ui_theme.default_font_size = 14

	overlay = TDOverlay.new()
	overlay.world = world
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_build_status_bar()
	_build_title()

func _process(_delta: float) -> void:
	level_label.text = "Lv. %d" % Game.level
	shard_label.text = "◆ %d" % Game.shards
	_set_bar("hp", Game.hp, Game.max_hp(), "HP %d / %d" % [Game.hp, Game.max_hp()])
	_set_bar("mp", Game.mp, Game.max_mp(), "MP %d / %d" % [Game.mp, Game.max_mp()])
	var need := Game.xp_need()
	_set_bar("xp", Game.xp, need, "EXP %d / %d (%.1f%%)" % [Game.xp, need, 100.0 * Game.xp / need])

func _set_bar(id: String, value: int, max_value: int, text: String) -> void:
	var b: ProgressBar = bars[id][0]
	b.max_value = max_value
	b.value = value
	(bars[id][1] as Label).text = text

func _flat(col: Color, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	return sb

func _build_status_bar() -> void:
	var panel := PanelContainer.new()
	panel.theme = ui_theme
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -34
	var sb := _flat(Color(GameData.PLUM, 0.92), 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	level_label = Label.new()
	level_label.custom_minimum_size.x = 56
	level_label.add_theme_font_override("font", Game.num_font)
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", GameData.SUN)
	row.add_child(level_label)
	for spec in [["hp", GameData.HP], ["mp", GameData.MP], ["xp", GameData.XP]]:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.y = 18
		bar.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 0.45), 5))
		bar.add_theme_stylebox_override("fill", _flat(spec[1], 5))
		var label := Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", GameData.MIST)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 4)
		bar.add_child(label)
		row.add_child(bar)
		bars[spec[0]] = [bar, label]
	shard_label = Label.new()
	shard_label.custom_minimum_size.x = 70
	shard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shard_label.add_theme_color_override("font_color", GameData.SUN)
	row.add_child(shard_label)

func _build_title() -> void:
	title = ColorRect.new()
	(title as ColorRect).color = Color(GameData.NIGHT, 0.55)
	title.theme = ui_theme
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var heading := Label.new()
	heading.text = "Tera Dawn"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", Game.num_font)
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", GameData.SUN)
	heading.add_theme_color_override("font_outline_color", GameData.PLUM)
	heading.add_theme_constant_override("outline_size", 18)
	heading.add_theme_color_override("font_shadow_color", GameData.EMBER)
	heading.add_theme_constant_override("shadow_offset_y", 6)
	heading.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(heading)

	var blurb := Label.new()
	blurb.text = "The sun is rising over Dawnrise Meadow. Clear out the Dewlings, climb the ropes, and follow the portal east to Ember Hollow."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 520
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_color_override("font_color", GameData.MIST)
	blurb.add_theme_font_size_override("font_size", 16)
	col.add_child(blurb)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	play_button = _menu_button("Play")
	play_button.pressed.connect(_on_play)
	buttons.add_child(play_button)
	var quit := _menu_button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)

	var keys := Label.new()
	keys.text = "Arrows move and climb · Space jump · X attack · A Dawn Slash · Up enters portals · Esc menu · F11 fullscreen\nGamepad: stick or d-pad · A jump · X attack · Y Dawn Slash · Start menu"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color("c9b8d9"))
	col.add_child(keys)
	play_button.call_deferred("grab_focus")

func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 44)
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", GameData.NIGHT)
	b.add_theme_color_override("font_hover_color", GameData.NIGHT)
	b.add_theme_color_override("font_focus_color", GameData.NIGHT)
	b.add_theme_color_override("font_pressed_color", GameData.NIGHT)
	b.add_theme_stylebox_override("normal", _flat(Color("ffc98a"), 22))
	b.add_theme_stylebox_override("hover", _flat(GameData.SUN, 22))
	var focus := _flat(GameData.SUN, 22)
	focus.set_border_width_all(3)
	focus.border_color = GameData.MIST
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", _flat(GameData.EMBER, 22))
	return b

func _on_play() -> void:
	title.hide()
	world.start()

func show_title(paused: bool) -> void:
	play_button.text = "Resume" if paused else "Play"
	title.show()
	play_button.grab_focus()
