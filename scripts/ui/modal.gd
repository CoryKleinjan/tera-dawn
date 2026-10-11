class_name TDModal
extends ColorRect
## A question over everything else (TDConfirm, TDDeleteConfirm, TDPrompt): the screen dims
## behind a centred panel holding the question, an optional text box and a row of buttons.
## A subclass calls `build`, then `add_question`, `add_field` and `add_buttons` in the order
## they stand in the panel, and puts its buttons in the row.

## How dark the screen behind goes, and the space between the panel's parts.
const DIM := 0.6
const SEPARATION := 12
## The yes-or-no questions' (TDConfirm, TDDeleteConfirm) wrapping width and text size, and
## their buttons' size and text size.
const QUESTION_W := 380.0
const QUESTION_SIZE := 16
const BUTTON_SIZE := Vector2(130, 44)
const BUTTON_FONT := 20

## The question.
var question: Label
## The panel's column: question, text box and buttons, top to bottom.
var column: VBoxContainer
## The control that had the keyboard focus before `remember_focus`.
var _focus_before: Control

## Dims the screen `dim` dark and puts the empty panel in the middle, its parts
## `separation` pixels apart.
func build(dim := DIM, separation := SEPARATION) -> void:
	color = Color(Palette.NIGHT, dim)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	center.add_child(card)
	column = UiBuild.column(separation)
	card.add_child(column)

## Adds the question label (see `question_label`).
func add_question(width := 0.0, font_size := 0, font: Font = null) -> Label:
	question = question_label(Palette.MIST, width, font_size, font)
	column.add_child(question)
	return question

## Adds a text box `min_size` big that takes at most `max_length` letters.
func add_field(min_size: Vector2, max_length: int) -> LineEdit:
	var f := LineEdit.new()
	f.max_length = max_length
	f.custom_minimum_size = min_size
	column.add_child(f)
	return f

## Adds the centred row the buttons go in, `separation` pixels apart.
func add_buttons(separation := SEPARATION) -> HBoxContainer:
	var row := UiBuild.centered_row([], separation)
	column.add_child(row)
	return row

## Notes where the keyboard focus is, for `restore_focus` when the question closes.
func remember_focus() -> void:
	_focus_before = get_viewport().gui_get_focus_owner()

## Puts the focus back where `remember_focus` found it, if that's still on screen.
func restore_focus() -> void:
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()

## A centred question in `color`: wrapped at `width` pixels when that's above 0, at
## `font_size` and in `font` when those are given (0 and null keep the theme's).
static func question_label(color: Color, width := 0.0, font_size := 0, font: Font = null) -> Label:
	var l := UiBuild.label("", font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	if width > 0.0:
		l.custom_minimum_size.x = width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font:
		l.add_theme_font_override("font", font)
	return l

## A row of two small gold buttons that keep the focus where it is: `yes` calls
## `on_answer(true)` and `no` calls `on_answer(false)` (TDPrompt, TDInvites).
static func answer_row(yes: String, no: String, on_answer: Callable, min_size: Vector2, separation: int) -> HBoxContainer:
	var row := UiBuild.centered_row([], separation)
	for pair in [[yes, true], [no, false]]:
		var ok: bool = pair[1]
		row.add_child(UiBuild.gold_button(pair[0], func() -> void: on_answer.call(ok), min_size, 0, false))
	return row
