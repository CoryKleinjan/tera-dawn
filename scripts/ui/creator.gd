class_name TDCreator
extends CenterContainer
## The character creator, shown when you play a name that has no character yet: a live
## preview of your hero and a row of arrows for each choice (skin, face, eyes, hair, hair
## colour and the starting outfit). Every new character starts in the starting job
## (Character.START_JOB); the options come from data/looks/ and the job's `creator_gear`.

## Create was pressed with these choices.
signal created(made: NewCharacter)
## Back was pressed.
signal cancelled

## Preview animations the Pose button steps through.
const POSES: Array[StringName] = [&"idle", &"walk", &"attack", &"level_up"]

var made: NewCharacter
var job: JobDef
var preview := PaperdollView.new()
var heading: Label
var create_button: Button
## Every choice row's value label, keyed by "look:<kind>" or "outfit:<slot>".
var values := {}
var _pose := 0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	job = Content.job(Character.START_JOB)
	made = NewCharacter.new(job.id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	add_child(card)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	card.add_child(cols)

	# left: the preview
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	heading = _label("", 22, Palette.SUN)
	heading.add_theme_font_override("font", Game.num_font)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(heading)
	var stage := Panel.new()
	stage.custom_minimum_size = Vector2(250, 176)
	stage.add_theme_stylebox_override("panel", UiSkin.box("equip_doll_bg", 12, 12))
	left.add_child(stage)
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.offset_bottom = -8
	stage.add_child(preview)
	var turns := HBoxContainer.new()
	turns.alignment = BoxContainer.ALIGNMENT_CENTER
	turns.add_theme_constant_override("separation", 8)
	turns.add_child(_small_button("Turn", func() -> void: preview.facing = -preview.facing))
	turns.add_child(_small_button("Pose", _next_pose))
	left.add_child(turns)
	var job_line := _label("Starting job: %s" % job.display_name, 14, Palette.MIST)
	job_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(job_line)
	var job_text := _label(job.description, 11, Palette.MUTED)
	job_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_text.custom_minimum_size.x = 250
	job_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(job_text)

	# right: a row per choice, then the buttons
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(right)
	right.add_child(_label("Appearance", 15, Palette.SUN))
	for kind in LookDef.Kind.values():
		right.add_child(_row("look:%d" % kind, LookDef.KIND_NAMES[kind], func(step: int) -> void:
			made.appearance.cycle(kind, step)))
	right.add_child(_label("Outfit", 15, Palette.SUN))
	for kind in NewCharacter.outfit_kinds(job):
		right.add_child(_row("outfit:%d" % kind, EquipDef.SLOT_NAMES[kind], func(step: int) -> void:
			made.cycle_outfit(job, kind, step)))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	buttons.add_child(_small_button("Random", func() -> void:
		made.roll(job)
		_refresh()))
	buttons.add_child(_small_button("Back", func() -> void: cancelled.emit()))
	create_button = _small_button("Create", func() -> void: created.emit(made))
	create_button.custom_minimum_size.x = 100
	buttons.add_child(create_button)
	right.add_child(Control.new()) # a little space
	right.add_child(buttons)
	_refresh()

## Starts over for a new character called `char_name`.
func open(char_name: String) -> void:
	made = NewCharacter.new(job.id)
	heading.text = "Create %s" % char_name
	preview.facing = 1
	_pose = 0
	preview.play(POSES[0])
	_refresh()
	show()
	create_button.grab_focus()

## The text a choice row shows now.
func value_text(key: String) -> String:
	return (values[key] as Label).text

## Steps one choice row (see `values` for the keys).
func step(key: String, by: int) -> void:
	var parts := key.split(":")
	var kind := int(parts[1])
	if parts[0] == "look":
		made.appearance.cycle(kind, by)
	else:
		made.cycle_outfit(job, kind, by)
	_refresh()

## What the preview wears: the chosen look and outfit, plus the rest of the starting gear.
func look() -> Dictionary:
	var gear := {}
	for e in made.starting_gear(job):
		for place in Equipment.PLACES_FOR[e.slot]:
			if not gear.has(String(place)):
				gear[String(place)] = String(e.id)
				break
	return {"appearance": made.appearance.to_dict(), "gear": gear}

func _refresh() -> void:
	for kind in LookDef.Kind.values():
		var l := made.appearance.part(kind)
		(values["look:%d" % kind] as Label).text = l.display_name if l else "-"
	for kind in NewCharacter.outfit_kinds(job):
		var e: EquipDef = made.outfit.get(kind)
		(values["outfit:%d" % kind] as Label).text = e.display_name if e else "-"
	preview.set_look(look())

func _next_pose() -> void:
	_pose = (_pose + 1) % POSES.size()
	preview.play(POSES[_pose])

func _row(key: String, title: String, change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_label := _label(title, 13, Palette.MIST)
	name_label.custom_minimum_size.x = 84
	row.add_child(name_label)
	row.add_child(_small_button("<", func() -> void:
		change.call(-1)
		_refresh()))
	var value := _label("", 13, Palette.SUN)
	value.custom_minimum_size.x = 118
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	values[key] = value
	row.add_child(_small_button(">", func() -> void:
		change.call(1)
		_refresh()))
	return row

func _small_button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(32 if text.length() == 1 else 76, 28)
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", 14)
	UiSkin.style_button(b)
	b.pressed.connect(pressed)
	return b

func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l
