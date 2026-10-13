class_name TDGameMenu
extends CenterContainer
## The menu Esc opens while playing: Resume, Settings, Character select, Leave game and Quit
## to desktop.
## The game carries on behind it (it's online); TDHud decides what each button does.

signal resumed
signal settings_requested
## Back to character select, still in the game.
signal to_characters
signal left
signal quit

var resume_button: Button
var settings_button: Button
var characters_button: Button
var leave_button: Button
var quit_button: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.ARCH_PANEL, Vector4(34, 58, 34, 52))
	add_child(card)
	var col := UiBuild.column(10)
	card.add_child(col)
	col.add_child(UiBuild.heading("Menu", 30))
	col.add_child(UiSkin.divider())
	resume_button = _button(col, "Resume", resumed)
	settings_button = _button(col, "Settings", settings_requested)
	characters_button = _button(col, "Character select", to_characters)
	leave_button = _button(col, "Leave game", left)
	quit_button = _button(col, "Quit to desktop", quit)

func _button(col: VBoxContainer, text: String, sig: Signal) -> Button:
	var b := UiBuild.button(text, func() -> void: sig.emit(), Vector2(240, 46))
	col.add_child(b)
	return b

## Shows the menu with Resume ready for Enter.
func open() -> void:
	show()
	resume_button.grab_focus()
