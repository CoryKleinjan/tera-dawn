class_name TDCreator
extends CenterContainer
## The character creator, opened from character select: a name and a row of arrows for
## each starting outfit choice. Every new character starts in the starting job
## (Character.START_JOB); the options come from the job's `creator_gear`. (No starting outfits
## are painted yet, so there is no preview or appearance to pick for now.)

## Create was pressed with this name and these choices.
signal created(char_name: String, made: NewCharacter)
## Back was pressed.
signal cancelled

## The two bars on the creator sheet (cut as one cell, so numbered by the slicer).
const BUTTON_PLAIN := "creator/buttons_2"  # the new sheet has the gold (orange) one on top
const BUTTON_GOLD := "creator/buttons_1"

var made: NewCharacter
var job: JobDef
var heading: Label
var name_field: LineEdit
var create_button: Button
## Why the last Create was turned down (a name that's taken...).
var message: Label
## Every choice row's value label, keyed by "outfit:<slot>".
var values := {}
## Waiting for a Create to be answered; another Create meanwhile is ignored.
var pending := false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	job = Content.job(Character.START_JOB)
	made = NewCharacter.new(job.id)
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.CREATOR_FRAME, Vector4(30, 44, 30, 24), 0.8)
	add_child(card)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	card.add_child(cols)

	# left: the name and the starting job
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	heading = UiBuild.label("", 20, Palette.INK)
	heading.add_theme_font_override("font", Game.num_font)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_stylebox_override("normal", UiSkin.box("creator/banner", 44, 16, 52, 8))
	left.add_child(heading)
	name_field = LineEdit.new()
	UiStyle.set_hint(name_field, "Character name")
	name_field.max_length = CharacterStore.MAX_NAME
	name_field.custom_minimum_size = Vector2(250, 34)
	name_field.text_submitted.connect(func(_t: String) -> void: _create())
	_style_name_field()
	left.add_child(name_field)
	left.add_child(UiBuild.centered_row([
		_icon_button("creator/random", "Random outfit", func() -> void:
			made.roll(job)
			_refresh()),
		_icon_button("creator/reset", "Start over", func() -> void:
			made = NewCharacter.new(job.id)
			_refresh()),
	], 8))
	var job_line := UiBuild.label("Starting job: %s" % job.display_name, 14, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(job_line)
	var job_text := UiBuild.label(job.description, 11, Palette.INK_SOFT)
	job_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_text.custom_minimum_size.x = 250
	job_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(job_text)

	# right: a row per choice, then the buttons
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(right)
	right.add_child(UiBuild.label("Outfit", 15, Palette.EMBER))
	for kind in NewCharacter.outfit_kinds(job):
		right.add_child(_row("outfit:%d" % kind, EquipDef.SLOT_NAMES[kind], func(step: int) -> void:
			made.cycle_outfit(job, kind, step)))
	var back := _wide_button("Back", BUTTON_PLAIN, func() -> void: cancelled.emit())
	create_button = _wide_button("Create", BUTTON_GOLD, _create)
	right.add_child(Control.new()) # a little space
	right.add_child(UiBuild.centered_row([back, create_button], 10))
	message = UiBuild.label("", 13, Palette.BAD)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 300
	message.hide()
	right.add_child(message)
	_refresh()

## Starts over for a new character.
func open() -> void:
	made = NewCharacter.new(job.id)
	heading.text = "New character"
	name_field.text = ""
	show_message("")
	_set_pending(false)
	_refresh()
	show()
	name_field.grab_focus()

## A light box with dark ink, to sit on the creator's parchment.
func _style_name_field() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.92, 0.85)
	sb.border_color = Palette.INK_SOFT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	name_field.add_theme_stylebox_override("normal", sb)
	var lit := sb.duplicate() as StyleBoxFlat
	lit.border_color = Palette.GOLD_TRIM
	name_field.add_theme_stylebox_override("focus", lit)
	name_field.add_theme_font_override("font", Game.num_font)
	name_field.add_theme_font_size_override("font_size", 18)
	name_field.add_theme_color_override("font_color", Palette.INK)
	name_field.add_theme_color_override("font_placeholder_color", Color(Palette.INK_SOFT, 0.7))
	name_field.add_theme_color_override("caret_color", Palette.INK)

func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""

## The Create was turned down: says why and lets the player try again.
func refused(reason: String) -> void:
	_set_pending(false)
	show_message(reason)

## Create: asks for a name first if there isn't one. Once sent, waits for the answer.
func _create() -> void:
	if pending:
		return
	var n := CharacterStore.clean_name(name_field.text)
	if n == "":
		show_message("Please pick a name.")
		name_field.grab_focus()
		return
	show_message("")
	_set_pending(true)
	created.emit(n, made)

func _set_pending(on: bool) -> void:
	pending = on
	create_button.disabled = on

## The text a choice row shows now.
func value_text(key: String) -> String:
	return (values[key] as Label).text

## Steps one choice row (see `values` for the keys).
func step(key: String, by: int) -> void:
	made.cycle_outfit(job, int(key.split(":")[1]), by)
	_refresh()

func _refresh() -> void:
	for kind in NewCharacter.outfit_kinds(job):
		var e: EquipDef = made.outfit.get(kind)
		(values["outfit:%d" % kind] as Label).text = e.display_name if e else "-"

func _row(key: String, title: String, change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_label := UiBuild.label(title, 13, Palette.INK_SOFT)
	name_label.custom_minimum_size.x = 84
	row.add_child(name_label)
	row.add_child(_arrow_button("creator/arrow_left", func() -> void:
		change.call(-1)
		_refresh()))
	var value := UiBuild.label("", 13, Palette.INK)
	value.custom_minimum_size.x = 118
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	values[key] = value
	row.add_child(_arrow_button("creator/arrow_right", func() -> void:
		change.call(1)
		_refresh()))
	return row

## A round art button (the arrows, dice and reset) that brightens under the mouse.
func _icon_button(art: String, tip: String, pressed: Callable, size := Vector2(34, 30)) -> Button:
	var b := Button.new()
	b.icon = UiSkin.tex(art)
	b.expand_icon = true
	b.tooltip_text = tip
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_color_override("icon_hover_color", UiSkin.LIT)
	b.add_theme_color_override("icon_pressed_color", UiSkin.PRESSED)
	b.pressed.connect(pressed)
	return b

func _arrow_button(art: String, pressed: Callable) -> Button:
	return _icon_button(art, "", pressed, Vector2(28, 26))

## A Back or Create button on the creator's own bar art.
func _wide_button(text: String, art: String, pressed: Callable) -> Button:
	var b := _small_button(text, pressed)
	b.custom_minimum_size = Vector2(104, 32)
	var sb := UiSkin.box(art, 22, 12)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", UiSkin.lit(sb))
	b.add_theme_stylebox_override("focus", UiSkin.lit(sb))
	b.add_theme_stylebox_override("pressed", UiSkin.pressed(sb))
	if art == BUTTON_PLAIN:  # the plain bar is dark leather: light letters
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			b.add_theme_color_override(state, Palette.MIST)
	return b

func _small_button(text: String, pressed: Callable) -> Button:
	return UiBuild.gold_button(text, pressed, Vector2(32 if text.length() == 1 else 76, 28), 14)
