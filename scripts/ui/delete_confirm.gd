class_name TDDeleteConfirm
extends ColorRect
## Asks before deleting a character: the player types its name, and Delete only lights up
## once it matches. Shown over character select.

signal confirmed(char_name: String, typed: String)
signal cancelled

var char_name := ""
var question: Label
var field: LineEdit
var delete_button: Button
var cancel_button: Button

func _init() -> void:
	color = Color(Palette.NIGHT, 0.6)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	question = Label.new()
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.custom_minimum_size.x = 380
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.add_theme_color_override("font_color", Palette.MIST)
	question.add_theme_font_size_override("font_size", 16)
	col.add_child(question)
	field = LineEdit.new()
	field.max_length = CharacterStore.MAX_NAME
	field.custom_minimum_size = Vector2(220, 40)
	field.text_changed.connect(func(_t: String) -> void: _refresh())
	field.text_submitted.connect(func(_t: String) -> void:
		if matches():
			_confirm())
	col.add_child(field)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	cancel_button = UiSkin.menu_button("Cancel", Vector2(130, 44), 20)
	cancel_button.pressed.connect(cancel)
	row.add_child(cancel_button)
	delete_button = UiSkin.menu_button("Delete", Vector2(130, 44), 20)
	delete_button.pressed.connect(_confirm)
	row.add_child(delete_button)

## Asks about deleting `name_`.
func open(name_: String) -> void:
	char_name = name_
	question.text = "Delete %s? This can't be undone.\nType %s to confirm." % [char_name, char_name]
	field.text = ""
	UiSkin.set_hint(field, char_name)
	_refresh()
	show()
	field.grab_focus()

## Closes without deleting.
func cancel() -> void:
	hide()
	cancelled.emit()

## Whether what's typed is the character's name (any case).
func matches() -> bool:
	return field.text.strip_edges().to_lower() == char_name.to_lower()

func _refresh() -> void:
	delete_button.disabled = not matches()

func _confirm() -> void:
	hide()
	confirmed.emit(char_name, field.text)
