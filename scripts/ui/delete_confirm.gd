class_name TDDeleteConfirm
extends TDModal
## Asks before deleting a character: the player types its name, and Delete only lights up
## once it matches. Shown over character select.

signal confirmed(char_name: String, typed: String)
signal cancelled

var char_name := ""
var field: LineEdit
var delete_button: Button
var cancel_button: Button

func _init() -> void:
	build()
	add_question(QUESTION_W, QUESTION_SIZE)
	field = add_field(Vector2(220, 40), CharacterStore.MAX_NAME)
	field.text_changed.connect(func(_t: String) -> void: _refresh())
	field.text_submitted.connect(func(_t: String) -> void:
		if matches():
			_confirm())
	cancel_button = UiBuild.button("Cancel", cancel, BUTTON_SIZE, BUTTON_FONT)
	delete_button = UiBuild.button("Delete", _confirm, BUTTON_SIZE, BUTTON_FONT)
	var row := add_buttons()
	row.add_child(cancel_button)
	row.add_child(delete_button)

## Asks about deleting `name_`.
func open(name_: String) -> void:
	char_name = name_
	question.text = "Delete %s? This can't be undone.\nType %s to confirm." % [char_name, char_name]
	field.text = ""
	UiStyle.set_hint(field, char_name)
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
