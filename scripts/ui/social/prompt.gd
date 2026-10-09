class_name TDPrompt
extends ColorRect
## A question with a text box (a guild's name, a price, a buddy to add). Enter or OK
## answers, Esc or Cancel doesn't. Only one is open at a time.

var question: Label
var field: LineEdit
var _answer: Callable

func _ready() -> void:
	color = Color(Palette.NIGHT, 0.35)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	question = Label.new()
	question.add_theme_color_override("font_color", Palette.MIST)
	question.add_theme_font_override("font", Game.ui_font)
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(question)
	field = LineEdit.new()
	field.custom_minimum_size = Vector2(260, 36)
	field.max_length = 24
	field.text_submitted.connect(func(_t: String) -> void: answer(true))
	col.add_child(field)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	for pair in [["OK", true], ["Cancel", false]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(100, 34)
		b.focus_mode = Control.FOCUS_NONE
		UiSkin.style_button(b)
		var ok: bool = pair[1]
		b.pressed.connect(func() -> void: answer(ok))
		row.add_child(b)

## Asks `text`, starting the box at `start`; `on_answer` gets what was typed.
func ask(text: String, start: String, on_answer: Callable, numbers := false) -> void:
	question.text = text
	field.text = start
	field.max_length = 9 if numbers else 24
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if numbers else LineEdit.KEYBOARD_TYPE_DEFAULT
	_answer = on_answer
	visible = true
	field.grab_focus()
	field.select_all()

func answer(ok: bool) -> void:
	if not visible:
		return
	visible = false
	field.release_focus()
	if ok and _answer.is_valid() and field.text.strip_edges() != "":
		_answer.call(field.text.strip_edges())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		answer(false)
		get_viewport().set_input_as_handled()
