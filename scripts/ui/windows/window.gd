class_name TDWindow
extends Control
## A draggable game window (inventory, equipment, stats) drawn in the UI sheet's style.
## Windows open over gameplay without pausing it, like MapleStory. Subclasses draw their
## body in `_draw_body` and react to clicks in `_click`; tabs, list rows, buttons and item
## slots share the helpers here so every window looks alike.

const TITLE_H := 30.0
const PAD := 16.0
const SLOT := 40.0
const CLOSE_SIZE := 20.0
## Where a window's row of tabs sits, and how big a tab can be.
const TAB_Y := 36.0
const TAB_H := 26.0
const TAB_MAX_W := 150.0
## Tabs fill their row unless that makes them wider than TAB_MAX_W by more than this share:
## then they're TAB_MAX_W, from the left.
const TAB_STRETCH := 1.25
## The share of a tab's width between the brass studs at its art's ends (texels 30 to 140
## of 179), where the label goes, less a little room on each side.
const TAB_TEXT_SHARE := 0.58
## List rows and panels: one darkness and one corner radius everywhere.
const ROW_ALPHA := 0.4
const ROW_RADIUS := 6.0
const PLUS_SIZE := 20.0
## The button art's ends in texels (curl and stud, kept unstretched), and the middle of the
## face between its stitched lines.
const BUTTON_END := 16.0
const BUTTON_FACE_MID := 23.0
## Buttons along a window's bottom: how tall, and how far up from the window's bottom edge
## (clear of the frame's bottom trim).
const BOTTOM_BUTTON_H := 32.0
const BOTTOM_BUTTON_INSET := 16.0
## Opening: the window grows from OPEN_SCALE to full size and fades in over OPEN_TIME seconds.
const OPEN_TIME := 0.12
const OPEN_SCALE := 0.94

var hud: TDHud
var title := ""
var _dragging := false
var _drag_from := Vector2.ZERO
var _hover := Vector2(-1, -1)
## The tabs drawn last frame, for `tab_at`.
var _tab_rects: Array[Rect2] = []
## Their labels, in the same order.
var _tab_labels: Array = []
## The buttons drawn this frame and what they do: [Rect2, Callable].
var _buttons: Array = []
## 0 when the window has just opened, 1 once it has finished growing in.
var _open_t := 1.0

func _init(window_title: String, window_size: Vector2) -> void:
	title = window_title
	size = window_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	visibility_changed.connect(func() -> void:
		if visible:
			_open_t = 0.0
			_apply_open())

func _ready() -> void:
	mouse_exited.connect(func() -> void:
		_hover = Vector2(-1, -1)
		hud.tooltip.clear(self))

func _process(delta: float) -> void:
	if visible:
		keep_on_screen()  # however it was placed or has grown, never under the status bar
		if _open_t < 1.0:
			_open_t = minf(1.0, _open_t + delta / OPEN_TIME)
			_apply_open()
		queue_redraw()

## Skips the opening animation (and anything else still settling, in subclasses).
func settle() -> void:
	_open_t = 1.0
	_apply_open()
	queue_redraw()

func _apply_open() -> void:
	var k := ease(_open_t, 0.4)  # fast at first, gentle at the end
	pivot_offset = size / 2.0
	scale = Vector2.ONE * lerpf(OPEN_SCALE, 1.0, k)
	modulate.a = k

func toggle() -> void:
	visible = not visible
	if visible:
		raise()
	else:
		hud.tooltip.clear(self)

## The part of the screen windows stay inside: all of it above the status bar.
static func room() -> Rect2:
	return Rect2(Vector2.ZERO, TDWorld.VIEW - Vector2(0, TDStatusBar.HEIGHT))

## Moves the window back inside `room` if any of it is outside (its top left wins when it's
## bigger than the room).
func keep_on_screen() -> void:
	position = clamp_to_room(position)

## Where a window at `at` goes to stay inside `room`.
func clamp_to_room(at: Vector2) -> Vector2:
	var r := room()
	return at.clamp(r.position, (r.end - size).max(r.position))

func raise() -> void:
	get_parent().move_child(self, -1)

func _draw() -> void:
	UiSkin.window_frame().draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	DrawUtil.text(self, Game.num_font, Vector2(PAD + 2, 20), title, 15, Palette.SUN, 1, 4, Palette.NIGHT)
	var c := _close_rect()
	var hot := c.has_point(_hover)
	draw_texture_rect(UiSkin.tex("window_close"), c, false, Color(1.25, 1.15, 1.0) if hot else Color.WHITE)
	_buttons.clear()
	_draw_body()

func _close_rect() -> Rect2:
	return Rect2(size.x - PAD - CLOSE_SIZE + 6, 4, CLOSE_SIZE, CLOSE_SIZE)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		settle()  # a window still growing in would move under the mouse
		raise()
		if mb.button_index == MOUSE_BUTTON_LEFT and _close_rect().has_point(mb.position):
			toggle()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.y < TITLE_H:
			_dragging = true
			# in the parent's space, so a window still growing in drags without a jump
			_drag_from = mb.global_position - position
		elif not (mb.button_index == MOUSE_BUTTON_LEFT and _press_button(mb.position)):
			_click(mb.position, mb.button_index, mb.double_click)
		accept_event()
	elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	var mm := event as InputEventMouseMotion
	if mm:
		_hover = mm.position
		if _dragging:
			position = clamp_to_room(mm.global_position - _drag_from)
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
		draw_hilite(r.grow(-4), 5)
	if stack == null:
		if label != "":
			DrawUtil.text(self, Game.ui_font, r.get_center() + Vector2(0, 4), label,
				DrawUtil.fit_size(Game.ui_font, label, 9, r.size.x - 8, 7), Color(Palette.MIST, 0.45))
		return
	if stack.item.icon:
		draw_texture_rect(stack.item.icon, fit(stack.item.icon, r.grow(-5)), false, Color(1, 1, 1, 0.35 if dim else 1.0))
	if stack.count > 1:
		DrawUtil.text(self, Game.num_font, r.end + Vector2(-4, -3), str(stack.count), 12, Palette.MIST, -1, 4, Palette.NIGHT)

## A button drawn with the UI sheet's button art; dimmed when it can't be used. `small` is
## the short kind that fits in a list row. The art is scaled to the button's height (only its
## middle stretches sideways), so its stitching keeps its shape and the label sits between
## the stitched lines. Use `add_button` to make it do something.
func draw_button(r: Rect2, label: String, enabled := true, small := false) -> void:
	var hot := enabled and r.has_point(_hover)
	var art := "button_hover" if hot else "button_normal"
	var k := r.size.y / UiSkin.tex(art).get_height()
	UiSkin.draw_box(self, UiSkin.box(art, BUTTON_END, 0), r, k)
	var font_size := 11 if small else 15
	var mid := r.position.y + BUTTON_FACE_MID * k
	DrawUtil.text(self, Game.num_font if not small else Game.ui_font, Vector2(r.get_center().x, DrawUtil.cap_baseline(mid, font_size)), label,
		font_size, Palette.INK if enabled else Color(Palette.INK, 0.4), 0)

## Where a window's button along its bottom edge goes: `x` from the left, `w` wide, inside
## the frame's bottom trim.
func bottom_button_rect(x: float, w: float) -> Rect2:
	return Rect2(x, size.y - BOTTOM_BUTTON_INSET - BOTTOM_BUTTON_H, w, BOTTOM_BUTTON_H)

## A button that calls `action` when clicked (only while `enabled`). Call it while drawing:
## the buttons drawn last are the ones a click can press.
func add_button(r: Rect2, label: String, action: Callable, enabled := true, small := false) -> void:
	draw_button(r, label, enabled, small)
	if enabled:
		_buttons.append([r, action])

## A button that's only a picture from the UI art (a whisper bubble), brighter on hover.
func icon_button(r: Rect2, art: String, action: Callable) -> void:
	UiSkin.draw_icon(self, art, r, UiSkin.LIT if r.has_point(_hover) else Color.WHITE)
	_buttons.append([r, action])

## The "+" that spends a point (Ability Points, Skill Points), `side` pixels square with its
## top left at `at`.
func plus_button(at: Vector2, action: Callable, side := PLUS_SIZE) -> void:
	var r := Rect2(at, Vector2(side, side))
	draw_texture_rect(UiSkin.tex("stat_plus"), r, false, Color(1.25, 1.2, 1.1) if r.has_point(_hover) else Color.WHITE)
	_buttons.append([r, action])

## Presses the button under `at`, if there is one.
func _press_button(at: Vector2) -> bool:
	for b in _buttons:
		if (b[0] as Rect2).has_point(at):
			(b[1] as Callable).call()
			return true
	return false

## A tab along the top of a window: lit when `on`.
## The label shrinks to fit between the brass studs at the tab art's ends.
func draw_tab(r: Rect2, label: String, on: bool) -> void:
	draw_texture_rect(UiSkin.tex("window_tab_on" if on else "window_tab_off"), r, false)
	var font_size := tab_font_size(r, label)
	DrawUtil.text(self, Game.ui_font, Vector2(r.get_center().x, DrawUtil.cap_baseline(r.get_center().y, font_size)), label, font_size,
		Palette.INK if on else Palette.MIST, 0, 0 if on else 3, Palette.NIGHT)

## The font size of a tab's label: 13, or smaller when the tab is too narrow for it.
static func tab_font_size(r: Rect2, label: String) -> int:
	return DrawUtil.fit_size(Game.ui_font, label, 13, tab_text_width(r))

## How much of a tab's width is free for its label: the room between its studs.
static func tab_text_width(r: Rect2) -> float:
	return r.size.x * TAB_TEXT_SHARE

## A row of tabs at `y` sharing the width from `left` to `right` (the window's padding by
## default), with `current` lit. `tab_at` says which one a click hit.
func draw_tabs(labels: Array, current: int, y := TAB_Y, left := PAD, right := -1.0) -> void:
	if right < 0.0:
		right = size.x - PAD
	var w := (right - left) / labels.size()
	if w > TAB_MAX_W * TAB_STRETCH:
		w = TAB_MAX_W
	_tab_rects.clear()
	_tab_labels = labels.duplicate()
	for i in labels.size():
		var r := Rect2(left + i * w - 3, y - 1, w + 6, TAB_H)
		_tab_rects.append(r)
		draw_tab(r, labels[i], i == current)

## The tab under `at` (as drawn by `draw_tabs`), or -1.
func tab_at(at: Vector2) -> int:
	for i in _tab_rects.size():
		if _tab_rects[i].has_point(at):
			return i
	return -1

## The background of a list row or panel; `lit` (hovered, selected) shows the highlight.
func draw_row(r: Rect2, lit := false) -> void:
	if lit:
		draw_hilite(r)
	else:
		DrawUtil.round_rect(self, r, ROW_RADIUS, Color(Palette.NIGHT, ROW_ALPHA))

## The hover / selection highlight.
func draw_hilite(r: Rect2, radius := ROW_RADIUS) -> void:
	DrawUtil.round_rect(self, r, radius, Color(Palette.HILITE, Palette.HILITE_ALPHA))

## Text with the windows' dark outline. align: -1 right, 0 center, 1 left.
func draw_label(at: Vector2, s: String, col := Palette.MIST, sz := 12, align := 1) -> void:
	DrawUtil.text(self, Game.ui_font, at, s, sz, col, align, 3, Palette.NIGHT)

## A quiet line for an empty list or a hint ("Nothing here yet.").
func draw_hint(at: Vector2, s: String, align := 1) -> void:
	draw_label(at, s, Palette.MUTED, 12, align)

## A Dawnshard icon and an amount, with the text's baseline starting at `at`.
func draw_shards(at: Vector2, amount: int) -> void:
	draw_texture_rect(UiSkin.tex("icon_dawnshard"), Rect2(at + Vector2(0, -16), Vector2(22, 20)), false)
	DrawUtil.text(self, Game.num_font, at + Vector2(28, 0), str(amount), 15, Palette.SUN, 1, 4, Palette.NIGHT)

## Puts this window just left of the screen's centre at height `y` and opens the inventory
## just right of it (for windows you drag items into: trade, a player shop).
func place_beside_inventory(y: float) -> void:
	position = Vector2(TDWorld.VIEW.x / 2.0 - size.x - 10, y)
	var inv: TDWindow = hud.windows["inventory"]
	inv.visible = true
	inv.position = Vector2(TDWorld.VIEW.x / 2.0 + 10, y)

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
