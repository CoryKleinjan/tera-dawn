class_name TDPadMenu
extends CenterContainer
## The gamepad's window menu (Back): a button for every window in TDHud.WINDOW_ACTIONS, picked
## with the D-pad and A. The game carries on behind it; TDPad opens and closes it.

const BUTTON_SIZE := Vector2(220, 40)
const FONT_SIZE := 18

signal picked(action: String)

var buttons: Array[Button] = []

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var card := PanelContainer.new()
	UiSkin.use_panel(card, UiSkin.ARCH_PANEL, Vector4(30, 50, 30, 44))
	add_child(card)
	var col := UiBuild.column(6)
	card.add_child(col)
	col.add_child(UiBuild.heading("Windows", 24))
	col.add_child(UiSkin.divider())
	for action in TDHud.WINDOW_ACTIONS:
		var b := UiBuild.button(Keybinds.info(action)["label"], func() -> void: picked.emit(action), BUTTON_SIZE, FONT_SIZE)
		col.add_child(b)
		buttons.append(b)

## Shows the menu with the first window ready for A.
func open() -> void:
	show()
	buttons[0].grab_focus()
