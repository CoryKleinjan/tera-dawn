class_name TDGameMenu
extends CenterContainer
## The menu Esc opens while playing: Resume, Settings, Character select, Log out and Quit
## to desktop.
## The game carries on behind it (it's online); TDHud decides what each button does.

signal resumed
signal settings_requested
## Back to character select, still logged in.
signal to_characters
signal logged_out
signal quit

var resume_button: Button
var settings_button: Button
var characters_button: Button
var logout_button: Button
var quit_button: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.ARCH_PANEL, Vector4(34, 58, 34, 36))
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var heading := Label.new()
	heading.text = "Menu"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", Game.num_font)
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Palette.SUN)
	heading.add_theme_color_override("font_outline_color", Palette.PLUM)
	heading.add_theme_constant_override("outline_size", 8)
	col.add_child(heading)
	col.add_child(UiSkin.divider())
	resume_button = _button(col, "Resume", resumed)
	settings_button = _button(col, "Settings", settings_requested)
	characters_button = _button(col, "Character select", to_characters)
	logout_button = _button(col, "Log out", logged_out)
	quit_button = _button(col, "Quit to desktop", quit)

func _button(col: VBoxContainer, text: String, sig: Signal) -> Button:
	var b := UiSkin.menu_button(text, Vector2(240, 46))
	b.pressed.connect(func() -> void: sig.emit())
	col.add_child(b)
	return b

## Shows the menu with Resume ready for Enter.
func open() -> void:
	show()
	resume_button.grab_focus()
