class_name TDCharacterSelect
extends CenterContainer
## Character select, shown after logging in to a server: a slot for each of the account's
## characters on that server (their hero, name, level and job) and empty slots up to the
## limit, with Play, Create, Delete and Log out. TDHud decides what the buttons do; the
## list comes from the server (Net.characters).

signal play_requested(char_name: String)
signal create_requested
signal delete_requested(char_name: String)
signal logged_out

const SLOT_SIZE := Vector2(112, 168)
## All the slots fit in one row.
const COLUMNS := TDLobby.MAX_CHARACTERS

var heading: Label
## Which server and account this is.
var subheading: Label
var grid: GridContainer
## One button per slot, in order (empty slots too).
var slots: Array[Button] = []
var play_button: Button
var create_button: Button
var delete_button: Button
var logout_button: Button
var message: Label
## The characters shown: {name, level, job, look} like Net.characters.
var characters: Array = []
## The picked character's name ("" for none).
var selected := ""

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.ARCH_PANEL, Vector4(40, 62, 40, 36))
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	heading = _label("Choose your character", 26, Palette.SUN)
	heading.add_theme_font_override("font", Game.num_font)
	heading.add_theme_color_override("font_outline_color", Palette.PLUM)
	heading.add_theme_constant_override("outline_size", 8)
	col.add_child(heading)
	subheading = _label("", 14, Palette.MUTED)
	col.add_child(subheading)
	col.add_child(UiSkin.divider())
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in TDLobby.MAX_CHARACTERS:
		var slot := _slot_button(i)
		slots.append(slot)
		grid.add_child(slot)
	message = _label("", 14, Palette.BAD)
	message.hide()
	col.add_child(message)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	play_button = _button(buttons, "Play", func() -> void: play_requested.emit(selected))
	create_button = _button(buttons, "Create", func() -> void: create_requested.emit())
	delete_button = _button(buttons, "Delete", func() -> void: delete_requested.emit(selected))
	logout_button = _button(buttons, "Log out", func() -> void: logged_out.emit())

## Shows the account's characters, picking `pick` (or keeping the one picked, or the first).
## `where` names the server and account under the heading.
func show_characters(list: Array, pick := "", where := "") -> void:
	characters = list
	if where != "":
		subheading.text = where
	var names := list.map(func(c: Dictionary) -> String: return c["name"])
	if pick != "" and names.has(pick):
		selected = pick
	elif not names.has(selected):
		selected = names[0] if not names.is_empty() else ""
	for i in slots.size():
		_fill_slot(slots[i], list[i] if i < list.size() else {})
	show_message("")
	_refresh()
	show()
	(play_button if selected != "" else create_button).grab_focus()

## Picks a character by name.
func select(char_name: String) -> void:
	selected = char_name
	_refresh()

func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""

func _refresh() -> void:
	for i in slots.size():
		var on: bool = i < characters.size() and characters[i]["name"] == selected
		slots[i].button_pressed = on
		if i < characters.size(): # dark text on the lit slot, light text on the others
			(slots[i].find_child("Title", true, false) as Label).add_theme_color_override("font_color", Palette.INK if on else Palette.SUN)
			(slots[i].find_child("Line", true, false) as Label).add_theme_color_override("font_color", Palette.INK_SOFT if on else Palette.MIST)
	play_button.disabled = selected == ""
	delete_button.disabled = selected == ""
	create_button.disabled = characters.size() >= TDLobby.MAX_CHARACTERS

func _slot_button(i: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = SLOT_SIZE
	b.add_theme_stylebox_override("normal", UiSkin.option_row(false))
	b.add_theme_stylebox_override("hover", UiSkin.option_row(true))
	b.add_theme_stylebox_override("pressed", UiSkin.option_row(true))
	b.add_theme_stylebox_override("hover_pressed", UiSkin.option_row(true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_right = -8
	col.offset_top = 8
	col.offset_bottom = -6
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	b.add_child(col)
	var stage := Panel.new()
	stage.name = "Stage"
	stage.custom_minimum_size = Vector2(0, 108)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", UiSkin.box("equip_doll_bg", 12, 12))
	col.add_child(stage)
	var preview := PaperdollView.new()
	preview.name = "Preview"
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.offset_bottom = -6
	preview.max_zoom = 2.0
	stage.add_child(preview)
	var title := _label("", 15, Palette.SUN)
	title.name = "Title"
	title.add_theme_font_override("font", Game.num_font)
	col.add_child(title)
	var line := _label("", 11, Palette.MIST)
	line.name = "Line"
	col.add_child(line)
	b.pressed.connect(func() -> void:
		if i < characters.size():
			select(characters[i]["name"])
		else:
			_refresh()
			create_requested.emit())
	return b

## Shows one character in a slot, or an empty slot for {}.
func _fill_slot(b: Button, c: Dictionary) -> void:
	var preview := b.find_child("Preview", true, false) as PaperdollView
	var title := b.find_child("Title", true, false) as Label
	var line := b.find_child("Line", true, false) as Label
	preview.visible = not c.is_empty()
	if c.is_empty():
		title.text = "Empty slot"
		title.add_theme_color_override("font_color", Palette.MUTED)
		line.add_theme_color_override("font_color", Palette.MIST)
		line.text = "Create one"
		b.tooltip_text = "Make a new character here"
		return
	preview.set_look(c["look"])
	preview.play(&"idle")
	title.text = c["name"]
	line.text = "Lv %d %s" % [int(c["level"]), c["job"]]
	b.tooltip_text = ""

func _button(row: HBoxContainer, text: String, pressed: Callable) -> Button:
	var b := UiSkin.menu_button(text, Vector2(120, 42), 20)
	b.pressed.connect(pressed)
	row.add_child(b)
	return b

func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l
