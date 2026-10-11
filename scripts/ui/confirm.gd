class_name TDConfirm
extends TDModal
## A yes-or-no question over the menus ("Log out and end it for them?"): Cancel, or a
## button that does it. Cancel (or Esc, see TDHud.escape) puts the focus back where it was.

var cancel_button: Button
var ok_button: Button
var _on_ok := Callable()

func _init() -> void:
	build()
	add_question(QUESTION_W, QUESTION_SIZE)
	cancel_button = UiBuild.button("Cancel", cancel, BUTTON_SIZE, BUTTON_FONT)
	ok_button = UiBuild.button("OK", _ok, BUTTON_SIZE, BUTTON_FONT)
	var row := add_buttons()
	row.add_child(cancel_button)
	row.add_child(ok_button)

## Asks `text`; the `ok_text` button runs `on_ok`. Cancel starts with the focus.
func open(text: String, ok_text: String, on_ok: Callable) -> void:
	question.text = text
	ok_button.text = ok_text
	_on_ok = on_ok
	remember_focus()
	show()
	cancel_button.grab_focus()

## Closes without doing it.
func cancel() -> void:
	hide()
	restore_focus()

func _ok() -> void:
	hide()
	_on_ok.call()
