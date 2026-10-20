class_name TDInvites
extends PanelContainer
## Invitations from other players (a party or a trade), one card at a
## time at the top of the screen with Accept and Decline.

## [id, kind, from, text], oldest first
var pending: Array = []
var label: Label

func _ready() -> void:
	var card := UiSkin.box("social/invite_card", 14, 14)
	card.texture_margin_left = 52
	card.texture_margin_top = 38
	card.content_margin_left = 22
	card.content_margin_right = 20
	card.content_margin_top = 34
	card.content_margin_bottom = 16
	add_theme_stylebox_override("panel", card)
	var col := UiBuild.column(8)
	add_child(col)
	label = TDModal.question_label(Palette.INK, 300, 0, Game.ui_font)
	col.add_child(label)
	col.add_child(TDModal.answer_row("Accept", "Decline", answer, Vector2(100, 32), 10))
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
