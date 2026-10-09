class_name TDInvites
extends PanelContainer
## Invitations from other players (a party, a buddy, a trade, a guild), one card at a
## time at the top of the screen with Accept and Decline.

## [id, kind, from, text], oldest first
var pending: Array = []
var label: Label

func _ready() -> void:
	add_theme_stylebox_override("panel", UiSkin.panel())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	label = Label.new()
	label.add_theme_color_override("font_color", Palette.MIST)
	label.add_theme_font_override("font", Game.ui_font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	for pair in [["Accept", true], ["Decline", false]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(100, 32)
		UiSkin.style_button(b)
		var ok: bool = pair[1]
		b.pressed.connect(func() -> void: answer(ok))
		row.add_child(b)
	visible = false

func add(id: int, kind: String, from: String, text: String) -> void:
	pending.append([id, kind, from, text])
	_show()

func _show() -> void:
	visible = not pending.is_empty()
	if visible:
		label.text = pending[0][3]
		reset_size()
		position = Vector2((TDWorld.VIEW.x - size.x) / 2.0, 64)

## Answers the oldest invitation.
func answer(ok: bool) -> void:
	if pending.is_empty():
		return
	Net.ask(&"req_invite_answer", [pending[0][0], ok])
	pending.pop_front()
	_show()

func clear() -> void:
	pending.clear()
	_show()
