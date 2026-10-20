class_name TDPrompt
extends TDModal
## A question with a text box (a price, a player to invite). Enter or OK
## answers, Esc or Cancel doesn't. Only one is open at a time.

## Lighter than the other questions' dim (play goes on behind it), and closer together.
const DIM_ALPHA := 0.35
const SPACING := 10
## The most letters, or digits when it asks for a number.
const MAX_TEXT := 24
const MAX_DIGITS := 9

var field: LineEdit
var _answer: Callable

func _ready() -> void:
	build(DIM_ALPHA, SPACING)
	visible = false
	add_question(0.0, 0, Game.ui_font)
	field = add_field(Vector2(260, 36), MAX_TEXT)
	field.text_submitted.connect(func(_t: String) -> void: answer(true))
	column.add_child(TDModal.answer_row("OK", "Cancel", answer, Vector2(100, 34), SPACING))

## Asks `text`, starting the box at `start`; `on_answer` gets what was typed.
func ask(text: String, start: String, on_answer: Callable, numbers := false) -> void:
	question.text = text
	field.text = start
	field.max_length = MAX_DIGITS if numbers else MAX_TEXT
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
