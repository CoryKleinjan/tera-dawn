class_name TDWindow
extends Control
## A draggable game window (inventory, equipment, stats) drawn in the UI sheet's style.
## Windows open over gameplay without pausing it, like MapleStory. Subclasses draw their
## body in `_draw_body` and react to clicks in `_click`; item slots share the helpers here.

const TITLE_H := 30.0
const PAD := 16.0
const SLOT := 40.0
const CLOSE_SIZE := 20.0

var hud: TDHud
var title := ""
var _dragging := false
var _drag_from := Vector2.ZERO
var _hover := Vector2(-1, -1)

func _init(window_title: String, window_size: Vector2) -> void:
	title = window_title
	size = window_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _ready() -> void:
	mouse_exited.connect(func() -> void:
		_hover = Vector2(-1, -1)
		hud.tooltip.clear(self))

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func toggle() -> void:
	visible = not visible
	if visible:
		raise()
	else:
		hud.tooltip.clear(self)

func raise() -> void:
	get_parent().move_child(self, -1)

func _draw() -> void:
	UiSkin.window_frame().draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	DrawUtil.text(self, Game.num_font, Vector2(PAD + 2, 20), title, 15, Palette.SUN, 1, 4, Palette.NIGHT)
	var c := _close_rect()
	var hot := c.has_point(_hover)
	draw_texture_rect(UiSkin.tex("window_close"), c, false, Color(1.25, 1.15, 1.0) if hot else Color.WHITE)
	_draw_body()

func _close_rect() -> Rect2:
	return Rect2(size.x - PAD - CLOSE_SIZE + 6, 4, CLOSE_SIZE, CLOSE_SIZE)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		raise()
		if mb.button_index == MOUSE_BUTTON_LEFT and _close_rect().has_point(mb.position):
			toggle()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.y < TITLE_H:
			_dragging = true
			_drag_from = mb.position
		else:
			_click(mb.position, mb.button_index, mb.double_click)
		accept_event()
	elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	var mm := event as InputEventMouseMotion
	if mm:
		_hover = mm.position
		if _dragging:
			var view := get_viewport_rect().size
			position = (position + mm.position - _drag_from).clamp(Vector2.ZERO, view - size)
		_hovered(mm.position)

## Draws the window's contents. Override.
func _draw_body() -> void:
	pass

## A click inside the window body. Override.
func _click(_at: Vector2, _button: int, _double: bool) -> void:
	pass

## The mouse moved over the window. Override to show tooltips.
func _hovered(_at: Vector2) -> void:
	pass

## An item slot: frame, icon and stack count. `dim` greys it out (being dragged, unusable).
func draw_slot(r: Rect2, stack: ItemStack, dim := false, label := "") -> void:
	var hot := r.has_point(_hover)
	draw_texture_rect(UiSkin.tex("item_slot"), r, false, Color(1.3, 1.2, 1.0) if hot else Color.WHITE)
	if hot:
		DrawUtil.round_rect(self, r.grow(-4), 5, Color(1, 0.85, 0.45, 0.16))
	if stack == null:
		if label != "":
			DrawUtil.text(self, Game.ui_font, r.get_center() + Vector2(0, 4), label, 9, Color(Palette.MIST, 0.45))
		return
	if stack.item.icon:
		draw_texture_rect(stack.item.icon, fit(stack.item.icon, r.grow(-5)), false, Color(1, 1, 1, 0.35 if dim else 1.0))
	if stack.count > 1:
		DrawUtil.text(self, Game.num_font, r.end + Vector2(-4, -3), str(stack.count), 12, Palette.MIST, -1, 4, Palette.NIGHT)

## The largest rect inside `box` with the texture's shape, centred (icons cut from a sheet
## aren't all square).
static func fit(tex: Texture2D, box: Rect2) -> Rect2:
	var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
	var s := tex.get_size() * k
	return Rect2(box.get_center() - s / 2.0, s)

## A drag preview showing an item's icon under the cursor.
func drag_preview(stack: ItemStack) -> Control:
	var holder := Control.new()
	var icon := TextureRect.new()
	icon.texture = stack.item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(SLOT, SLOT) - Vector2(10, 10)
	icon.position = -icon.size / 2.0
	icon.modulate = Color(1, 1, 1, 0.85)
	holder.add_child(icon)
	return holder

## Whether the mouse is over any open window (so a drag that ends here isn't a drop on the floor).
func mouse_over_window() -> bool:
	return hud.window_at(get_global_mouse_position()) != null
