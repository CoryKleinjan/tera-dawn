class_name TDPad
extends Control
## Playing with a gamepad everywhere, the way Terraria and Stardew Valley do it on a pad:
## - Holding the left trigger turns the pad to its second page (Keybinds.use_pad_page), for
##   quickslots 4-8.
## - Back opens the window menu (TDPadMenu).
## - While a window is open and the pad is what you last used, a pad cursor stands in for the
##   mouse: the stick or D-pad moves it, A clicks (hold to drag), X right-clicks, Y
##   double-clicks, B closes the top window. The hero stands still meanwhile (`blocking`).
##   Its clicks go through the viewport like real ones, so every window works with it as it
##   does with the mouse. Touching the mouse or keyboard hands back to them.

## How far the trigger goes down before the second page shows.
const PAGE_AT := 0.5
## How fast the cursor moves at full tilt (view pixels a second); a light tilt is slower
## (speed grows with the square of the tilt), for aiming at small slots.
const CURSOR_SPEED := 650.0
## The cursor picture's point, as UiStyle.use_cursor sets it for the mouse.
const CURSOR_HOT := Vector2(3, 3)
## The pad buttons that stand for mouse buttons while the cursor is on.
const CLICK := JOY_BUTTON_A
const RIGHT_CLICK := JOY_BUTTON_X
const DOUBLE_CLICK := JOY_BUTTON_Y
const CLOSE := JOY_BUTTON_B
const MENU := JOY_BUTTON_BACK

## Whether the last thing pressed or moved was the pad (key names show the pad's buttons).
static var using_pad := false

var hud: TDHud
var menu: TDPadMenu
var cursor_on := false
## Where the cursor is, in view pixels.
var cursor := Vector2.ZERO
var _left_held := false
## True while this pushes its own mouse events, so they don't count as the mouse being used.
var _pushing := false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	Keybinds.use_pad_page(0)
	menu = TDPadMenu.new()
	menu.theme = hud.ui_theme
	menu.picked.connect(func(action: String) -> void:
		close_menu()
		if not hud.windows[action].visible:
			hud.toggle_window(action))
	add_child(menu)

## Whether the pad is busy with windows, so the hero shouldn't move.
func blocking() -> bool:
	return cursor_on or menu.visible or (using_pad and hud.any_window_open())

func open_menu() -> void:
	if hud.world.started and not hud.title.visible:
		menu.open()

func close_menu() -> void:
	menu.hide()

func _input(event: InputEvent) -> void:
	if _pushing:
		return
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > PAGE_AT):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_pad = false
		if cursor_on:
			set_cursor(false)
	var motion := event as InputEventJoypadMotion
	if motion and motion.axis == Keybinds.PAGE_AXIS:
		Keybinds.use_pad_page(1 if motion.axis_value > PAGE_AT else 0)
	var b := event as InputEventJoypadButton
	if b == null or not hud.world.started or hud.title.visible:
		return
	if menu.visible:
		if b.pressed and (b.button_index == MENU or b.button_index == CLOSE):
			close_menu()
			get_viewport().set_input_as_handled()
		return
	if b.button_index == MENU:
		if b.pressed:
			open_menu()
		get_viewport().set_input_as_handled()
	elif cursor_on:
		match b.button_index:
			CLICK:
				_left_held = b.pressed
				_push_button(MOUSE_BUTTON_LEFT, b.pressed, false)
			RIGHT_CLICK:
				_push_button(MOUSE_BUTTON_RIGHT, b.pressed, false)
			DOUBLE_CLICK:
				_push_button(MOUSE_BUTTON_LEFT, b.pressed, b.pressed)
			CLOSE:
				if b.pressed:
					hud.close_top_window()
			_:
				return
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var open := hud.world.started and not hud.title.visible and hud.any_window_open()
	if open and using_pad and not cursor_on:
		set_cursor(true)
	elif cursor_on and not open:
		set_cursor(false)
	if menu.visible and (not hud.world.started or hud.title.visible):
		close_menu()
	if cursor_on:
		var tilt := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if tilt != Vector2.ZERO:
			move_cursor(tilt * tilt.length() * CURSOR_SPEED * delta)
	queue_redraw()

## Turns the pad cursor on (at the middle of the top window) or off.
func set_cursor(on: bool) -> void:
	if on == cursor_on:
		return
	cursor_on = on
	if _left_held:
		_left_held = false
		_push_button(MOUSE_BUTTON_LEFT, false, false)
	if on:
		var top := _top_window()
		cursor = top.get_global_rect().get_center() if top else TDWorld.VIEW / 2.0
		_push_motion(Vector2.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if on else Input.MOUSE_MODE_VISIBLE

## Moves the cursor by `by` view pixels, kept on screen.
func move_cursor(by: Vector2) -> void:
	var to := (cursor + by).clamp(Vector2.ZERO, TDWorld.VIEW - Vector2.ONE)
	var moved := to - cursor
	cursor = to
	if moved != Vector2.ZERO:
		_push_motion(moved)

func _top_window() -> TDWindow:
	for i in range(hud.window_layer.get_child_count() - 1, -1, -1):
		var w := hud.window_layer.get_child(i) as TDWindow
		if w.visible:
			return w
	return null

func _push_motion(relative: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = cursor
	m.global_position = cursor
	m.relative = relative
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if _left_held else 0
	_push(m)

func _push_button(button: int, pressed: bool, double: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = cursor
	e.global_position = cursor
	e.button_index = button
	e.pressed = pressed
	e.double_click = double
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _left_held else 0
	_push.call_deferred(e)

func _push(e: InputEvent) -> void:
	_pushing = true
	get_viewport().push_input(e, true)
	_pushing = false

func _draw() -> void:
	if cursor_on:
		draw_texture(UiSkin.tex("cursor"), cursor - CURSOR_HOT)
