class_name TDHud
extends CanvasLayer
## The screen UI: the status bar (level, HP, MP, EXP, skills, Dawnshards), the in-game
## overlay, the game windows (inventory, equipment, character), and the title / pause menu.
## Art comes from UiSkin.

## Input actions that open and close a window, in the order the status bar shows them.
const WINDOW_ACTIONS: Array[String] = ["inventory", "equipment", "stats"]

var world: TDWorld
var overlay: TDOverlay
var status: TDStatusBar
var title: Control
var play_button: Button
var ui_theme: Theme
## Holds the windows so raising one never lifts it above the tooltip or the title menu.
var window_layer: Control
## action -> TDWindow
var windows := {}
var tooltip: TDItemTooltip

func _ready() -> void:
	layer = 10
	ui_theme = Theme.new()
	ui_theme.default_font = Game.ui_font
	ui_theme.default_font_size = 14
	UiSkin.use_cursor()

	overlay = TDOverlay.new()
	overlay.world = world
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	status = TDStatusBar.new()
	status.world = world
	status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -TDStatusBar.HEIGHT
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(status)
	_build_windows()
	_build_title()

func _build_windows() -> void:
	window_layer = Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window_layer)
	var view := TDWorld.VIEW
	var inventory := TDInventoryWindow.new()
	inventory.position = Vector2(view.x - inventory.size.x - 16, 70)
	var equipment := TDEquipmentWindow.new()
	equipment.position = Vector2(inventory.position.x - equipment.size.x - 10, 70)
	var stats := TDStatsWindow.new()
	stats.position = Vector2(16, 56)
	for pair in [["inventory", inventory], ["equipment", equipment], ["stats", stats]]:
		var w: TDWindow = pair[1]
		w.hud = self
		windows[pair[0]] = w
		window_layer.add_child(w)
	tooltip = TDItemTooltip.new()
	tooltip.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip)

func toggle_window(action: String) -> void:
	if windows.has(action):
		windows[action].toggle()

## Closes the window on top (Esc). False if none was open.
func close_top_window() -> bool:
	for i in range(window_layer.get_child_count() - 1, -1, -1):
		var w := window_layer.get_child(i) as TDWindow
		if w.visible:
			w.toggle()
			return true
	return false

## The open window under a screen point, or null.
func window_at(pos: Vector2) -> TDWindow:
	for i in range(window_layer.get_child_count() - 1, -1, -1):
		var w := window_layer.get_child(i) as TDWindow
		if w.visible and w.get_global_rect().has_point(pos):
			return w
	return null

func _build_title() -> void:
	title = ColorRect.new()
	(title as ColorRect).color = Color(Palette.NIGHT, 0.45)
	title.theme = ui_theme
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var heading := Label.new()
	heading.text = "Tera Dawn"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", Game.num_font)
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", Palette.SUN)
	heading.add_theme_color_override("font_outline_color", Palette.PLUM)
	heading.add_theme_constant_override("outline_size", 18)
	heading.add_theme_color_override("font_shadow_color", Palette.EMBER)
	heading.add_theme_constant_override("shadow_offset_y", 6)
	heading.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(heading)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	col.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	var blurb := Label.new()
	blurb.text = "The sun is rising over Dawnrise Meadow. Clear out the Dewlings, climb the ropes, and follow the portal east to Ember Hollow."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 500
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_color_override("font_color", Palette.MIST)
	blurb.add_theme_font_size_override("font_size", 16)
	inner.add_child(blurb)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	inner.add_child(buttons)
	play_button = _menu_button("Play")
	play_button.pressed.connect(_on_play)
	buttons.add_child(play_button)
	var quit := _menu_button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)

	var keys := Label.new()
	keys.text = "Arrows move and climb · Space jump · X attack · A Dawn Slash · Z loot · Up talks and enters portals\nI inventory · E equipment · S character · Esc menu · F11 fullscreen\nGamepad: stick · A jump · X attack · Y Dawn Slash · B loot · Back inventory · Start menu"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color("c9b8d9"))
	inner.add_child(keys)
	play_button.call_deferred("grab_focus")

func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", 22)
	UiSkin.style_button(b)
	return b

func _on_play() -> void:
	title.hide()
	world.start()

func show_title(paused: bool) -> void:
	play_button.text = "Resume" if paused else "Play"
	title.show()
	play_button.grab_focus()
