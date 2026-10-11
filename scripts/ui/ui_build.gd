class_name UiBuild
extends RefCounted
## Builds the small controls the menus and screens are made of (labels, buttons, rows,
## text boxes), styled with UiStyle. Every size, font and colour is an argument, so each
## screen keeps its own look while sharing one way of making them.

## Space between the buttons of a centred row, and between a small title and its box.
const ROW_SEPARATION := 12
const TITLED_SEPARATION := 2
## The menu headings' outline ("Menu", "Settings", "Choose your character").
const HEADING_OUTLINE := 8
## The small muted titles over the title screen's boxes.
const SMALL_TITLE_SIZE := 12
## A text box's size when the screen doesn't ask for another.
const FIELD_SIZE := Vector2(164, 36)

## A label in `color`; `font_size` 0 keeps the theme's size.
static func label(text: String, font_size := 0, color := Palette.MIST, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

## A menu's heading: big sunny title-font letters with a plum outline, centred.
static func heading(text: String, font_size: int) -> Label:
	var l := label(text, font_size, Palette.SUN, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Game.num_font)
	l.add_theme_color_override("font_outline_color", Palette.PLUM)
	l.add_theme_constant_override("outline_size", HEADING_OUTLINE)
	return l

## A small muted label, like the titles over the title card's boxes.
static func small_title(text: String) -> Label:
	return label(text, SMALL_TITLE_SIZE, Palette.MUTED)

## A big gold menu button (UiStyle.menu_button) that calls `on_press` when pressed.
static func button(text: String, on_press: Callable, min_size := Vector2(150, 48), font_size := 22) -> Button:
	var b := UiStyle.menu_button(text, min_size, font_size)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b

## A small gold button (UiStyle.style_button) that calls `on_press`; `font_size` above 0
## writes it in the title font at that size, and `focusable` false keeps the keyboard
## focus where it is when it's clicked.
static func gold_button(text: String, on_press: Callable, min_size: Vector2, font_size := 0, focusable := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if font_size > 0:
		b.add_theme_font_override("font", Game.num_font)
		b.add_theme_font_size_override("font_size", font_size)
	if not focusable:
		b.focus_mode = Control.FOCUS_NONE
	UiStyle.style_button(b)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b

## A row with `children` in the middle, `separation` pixels apart.
static func centered_row(children: Array = [], separation := ROW_SEPARATION) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", separation)
	for c: Control in children:
		row.add_child(c)
	return row

## A column with its children `separation` pixels apart.
static func column(separation: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", separation)
	return col

## A text box starting at `text`, with a placeholder `hint` (UiStyle.set_hint).
static func field(text: String, hint: String, max_length: int, min_size := FIELD_SIZE) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	UiStyle.set_hint(f, hint)
	f.max_length = max_length
	f.custom_minimum_size = min_size
	return f

## `control` (a text box) with a small title over it.
static func titled(title_text: String, control: Control) -> VBoxContainer:
	var col := column(TITLED_SEPARATION)
	col.add_child(small_title(title_text))
	col.add_child(control)
	return col
