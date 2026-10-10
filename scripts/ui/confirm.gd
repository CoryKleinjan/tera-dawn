class_name TDConfirm
extends ColorRect
## A yes-or-no question over the menus ("Log out and end it for them?"): Cancel, or a
## button that does it. Cancel (or Esc, see TDHud.escape) puts the focus back where it was.

var question: Label
var cancel_button: Button
var ok_button: Button
var _on_ok := Callable()
var _focus_before: Control

func _init() -> void:
	color = Color(Palette.NIGHT, 0.6)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	question = Label.new()
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.custom_minimum_size.x = 380
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.add_theme_color_override("font_color", Palette.MIST)
	question.add_theme_font_size_override("font_size", 16)
	col.add_child(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	cancel_button = UiSkin.menu_button("Cancel", Vector2(130, 44), 20)
	cancel_button.pressed.connect(cancel)
	row.add_child(cancel_button)
	ok_button = UiSkin.menu_button("OK", Vector2(130, 44), 20)
	ok_button.pressed.connect(func() -> void:
		hide()
		_on_ok.call())
	row.add_child(ok_button)

## Asks `text`; the `ok_text` button runs `on_ok`. Cancel starts with the focus.
func open(text: String, ok_text: String, on_ok: Callable) -> void:
	question.text = text
	ok_button.text = ok_text
	_on_ok = on_ok
	_focus_before = get_viewport().gui_get_focus_owner()
	show()
	cancel_button.grab_focus()

## Closes without doing it.
func cancel() -> void:
	hide()
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
