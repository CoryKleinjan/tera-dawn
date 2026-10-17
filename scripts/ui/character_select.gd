class_name TDCharacterSelect
extends CenterContainer
## Character select, shown once a game is started or joined: a slot for each character
## saved on this computer (their name and job) and empty slots up to the
## limit, with Play, Create, Delete and Back. TDTitleScreen decides what the buttons do;
## the list is Net.characters.

signal play_requested(char_name: String)
signal create_requested
signal delete_requested(char_name: String)
signal left

const SLOT_SIZE := Vector2(112, 64)
## All the slots fit in one row.
const COLUMNS := CharacterStore.MAX_CHARACTERS

var heading: Label
## Which game this is: solo, hosting, or a friend's.
var subheading: Label
## While hosting: the address friends type to join, and the firewall button.
var host_panel: TDHostPanel
var grid: GridContainer
## One button per slot, in order (empty slots too).
var slots: Array[Button] = []
var play_button: Button
var create_button: Button
var delete_button: Button
var leave_button: Button
var message: Label
## The characters shown: {name, job} like Net.characters.
var characters: Array = []
## The picked character's name ("" for none).
var selected := ""

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.ARCH_PANEL, Vector4(40, 62, 40, 52))
	add_child(card)
	var col := UiBuild.column(10)
	card.add_child(col)
	heading = UiBuild.heading("Choose your character", 26)
	col.add_child(heading)
	subheading = UiBuild.label("", 14, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(subheading)
	host_panel = TDHostPanel.new()
	host_panel.hide()
	col.add_child(host_panel)
	col.add_child(UiSkin.divider())
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in CharacterStore.MAX_CHARACTERS:
		var slot := _slot_button(i)
		slots.append(slot)
		grid.add_child(slot)
	message = UiBuild.label("", 14, Palette.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	message.hide()
	col.add_child(message)
	play_button = _button("Play", func() -> void: play_requested.emit(selected))
	create_button = _button("Create", func() -> void: create_requested.emit())
	delete_button = _button("Delete", func() -> void: delete_requested.emit(selected))
	leave_button = _button("Back", func() -> void: left.emit())
	col.add_child(UiBuild.centered_row([play_button, create_button, delete_button, leave_button]))

## Shows the characters, picking `pick` (or keeping the one picked, or the first).
## `where` names the game under the heading.
func show_characters(list: Array, pick := "", where := "") -> void:
	characters = list
	if where != "":
		subheading.text = where
	host_panel.visible = Net.mode == Net.Mode.HOST
	if host_panel.visible:
		host_panel.refresh(Net.port)
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
	focus_button()

## Puts the keyboard focus on Play, or on Create when there's nothing to play.
func focus_button() -> void:
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
	create_button.disabled = characters.size() >= CharacterStore.MAX_CHARACTERS

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
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	b.add_child(col)
	var title := UiBuild.label("", 15, Palette.SUN, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	title.add_theme_font_override("font", Game.num_font)
	col.add_child(title)
	var line := UiBuild.label("", 11, Palette.MIST, HORIZONTAL_ALIGNMENT_CENTER)
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
	var title := b.find_child("Title", true, false) as Label
	var line := b.find_child("Line", true, false) as Label
	if c.is_empty():
		title.text = "Empty slot"
		title.add_theme_color_override("font_color", Palette.MUTED)
		line.add_theme_color_override("font_color", Palette.MIST)
		line.text = "Create one"
		b.tooltip_text = "Make a new character here"
		return
	title.text = c["name"]
	line.text = "Lv %d %s" % [int(c.get("level", 1)), c["job"]]
	b.tooltip_text = ""

## One of the buttons along the bottom.
func _button(text: String, pressed: Callable) -> Button:
	return UiBuild.button(text, pressed, Vector2(120, 42), 20)
