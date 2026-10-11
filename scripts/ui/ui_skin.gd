class_name UiSkin
extends RefCounted
## The game's UI art as Godot styles, plus drawing helpers for things the overlay and the
## windows draw every frame (name tags, HP bars, speech bubbles, rows, markers). All sizes
## are in the 960x540 canvas.
##
## The art is cut from the UI sheets in art/source/ into assets/sprites/ui/: ui.png and
## ui_windows.png straight into it, and one folder per newer sheet, named like the textures
## here ("hud/quests_button"): hud/ (HUD buttons, quest markers, minimap), menu/ (Esc menu
## and settings controls), dialogue/ (dialogue, shop, trade, quests, banners), social/
## (buddies, party, guild, chat, invitations), book/ (Monster Book and achievements).
## world_map.png is the painted world map.

const DIR := "res://assets/sprites/ui/"
## The smallest text draw_bar writes on a bar.
const BAR_TEXT_MIN := 9
## Where each bar frame's empty groove is, in texels: Rect2(x, y, w, h).
const GROOVES := {
	"hp_frame": Rect2(40, 10, 92, 21),
	"mp_frame": Rect2(42, 12, 92, 21),
	"exp_frame": Rect2(28, 9, 124, 12),
	"social/party_hp_frame": Rect2(10, 8, 164, 11),
}
## The monster HP bar's frame without the emblem painted at its left end, in texels of
## monster_hp_1: its right end cap and a plain strip of its middle. The left end is the right
## cap mirrored, and the groove sits MONSTER_GROOVE_INSET into each cap.
const MONSTER_CAP := Rect2(123, 4, 12, 29)
const MONSTER_MID := Rect2(90, 4, 8, 29)
const MONSTER_GROOVE_INSET := Vector2(7, 5)
const MONSTER_GROOVE_H := 18.0
## The quest marker over an NPC for each QuestLog-like state TDNpc.quest_marker() returns.
const QUEST_MARKERS := {"!": "hud/quest_available", "?": "hud/quest_ready", "...": "hud/quest_in_progress"}
## The speech bubble's body and tail inside hud/speech_bubble, in texels.
const SPEECH_BODY := Rect2(0, 0, 144, 103)
const SPEECH_TAIL := Rect2(24, 98, 34, 28)
## Where the tail's tip is inside SPEECH_TAIL.
const SPEECH_TIP := Vector2(3, 27)
## The plaque (name_tag) behind name tags and hints: its end caps and trim in texels (the
## caps' gold diamonds sit inside them), and the room left between the text and a cap.
const PLAQUE_MARGINS := Vector2(20, 9)
const PLAQUE_PAD := 2.0
## How tall name tags and hints are drawn.
const NAME_TAG_H := 19.0
const HINT_H := 22.0
## Spaces between the caret and a box's placeholder hint (see set_hint).
const HINT_ROOM := "  "
## The settings tabs' art: how far in from each side the lit tab's stud ends, and how far in
## the label and icon start.
const TAB_STUD := 28.0
const TAB_PAD := 32.0
## How tall the map-name banner is drawn, the middle row of its parchment band (the art's
## top half, in texels: the ribbon tails hang below it), and its text size.
const BANNER_H := 56.0
const BANNER_BAND_MID := 13.5
const BANNER_TEXT := 26
## Brighter and darker tints for hover and pressed states of art that has only one state.
const LIT := Color(1.25, 1.18, 1.05)
const PRESSED := Color(0.85, 0.8, 0.75)

static var _cache := {}

static func tex(name: String) -> Texture2D:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".png")
	return _cache[name]

## A nine-patch style from a UI texture: the corners keep their size, the rest stretches.
static func box(name: String, margin_x: float, margin_y: float, pad_x := 0.0, pad_y := 0.0) -> StyleBoxTexture:
	var key := "box:%s:%s:%s:%s:%s" % [name, margin_x, margin_y, pad_x, pad_y]
	if not _cache.has(key):
		var sb := StyleBoxTexture.new()
		sb.texture = tex(name)
		sb.texture_margin_left = margin_x
		sb.texture_margin_right = margin_x
		sb.texture_margin_top = margin_y
		sb.texture_margin_bottom = margin_y
		sb.content_margin_left = pad_x if pad_x > 0 else margin_x
		sb.content_margin_right = pad_x if pad_x > 0 else margin_x
		sb.content_margin_top = pad_y if pad_y > 0 else margin_y
		sb.content_margin_bottom = pad_y if pad_y > 0 else margin_y
		_cache[key] = sb
	return _cache[key]

## A nine-patch drawn `scale` screen pixels per texel, so chunky art fits a thin row
## (a row 26 pixels tall from art 60 texels tall) without squeezing its corners.
static func draw_box(ci: CanvasItem, sb: StyleBox, r: Rect2, scale := 1.0) -> void:
	if is_equal_approx(scale, 1.0):
		sb.draw(ci.get_canvas_item(), r)
		return
	ci.draw_set_transform(r.position, 0.0, Vector2(scale, scale))
	sb.draw(ci.get_canvas_item(), Rect2(Vector2.ZERO, r.size / scale))
	ci.draw_set_transform(Vector2.ZERO)

## A nine-patch whose middle `keep` texels (a sun on the top trim, diamonds halfway down the
## sides) keep their size: the art is cut into quarters and each quarter stretches only
## between its own corner and the middle. `margins` are the left, top, right and bottom
## borders in texels; `keep` is how much of the middle stays put across and down.
static func draw_ornate(ci: CanvasItem, name: String, r: Rect2, margins: Vector4, keep: Vector2, scale := 1.0) -> void:
	var half := r.size / 2.0
	for q in 4:
		var right := q % 2 == 1
		var bottom := q >= 2
		var at := r.position + Vector2(half.x if right else 0.0, half.y if bottom else 0.0)
		draw_box(ci, _quarter_box(name, right, bottom, margins, keep), Rect2(at, half), scale)

static func _quarter_box(name: String, right: bool, bottom: bool, margins: Vector4, keep: Vector2) -> StyleBoxTexture:
	var key := "quarter:%s:%s:%s:%s:%s" % [name, right, bottom, margins, keep]
	if not _cache.has(key):
		var t := tex(name)
		var half := t.get_size() / 2.0
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.region_rect = Rect2(half.x if right else 0.0, half.y if bottom else 0.0, half.x, half.y)
		sb.texture_margin_left = keep.x / 2.0 if right else margins.x
		sb.texture_margin_right = margins.z if right else keep.x / 2.0
		sb.texture_margin_top = keep.y / 2.0 if bottom else margins.y
		sb.texture_margin_bottom = margins.w if bottom else keep.y / 2.0
		_cache[key] = sb
	return _cache[key]

## The smallest size `draw_ornate` can draw at `scale` without squeezing the art.
static func ornate_min_size(margins: Vector4, keep: Vector2, scale := 1.0) -> Vector2:
	return Vector2(margins.x + margins.z + keep.x, margins.y + margins.w + keep.y) * scale

## A texture with its shape kept, centred in `r`.
static func draw_icon(ci: CanvasItem, name: String, r: Rect2, modulate := Color.WHITE) -> void:
	var t := tex(name)
	var k := minf(r.size.x / t.get_width(), r.size.y / t.get_height())
	var s := t.get_size() * k
	ci.draw_texture_rect(t, Rect2(r.get_center() - s / 2.0, s), false, modulate)

static func panel() -> StyleBoxTexture:
	return box("menu_panel", 16, 16, 28, 24)

## The thin gold line with a sun in the middle, as wide as its container (under a heading).
static func divider() -> Control:
	var line := Control.new()
	var scale := 0.6
	line.custom_minimum_size = Vector2(0, tex(DIVIDER[0]).get_height() * scale)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void: draw_panel(line, DIVIDER, Rect2(Vector2.ZERO, line.size), scale))
	return line

## A PanelContainer drawn with one of the ornate panels above, `pad` pixels inside it.
static func use_panel(card: PanelContainer, panel_art: Array, pad: Vector4, scale := 1.0) -> void:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	card.add_theme_stylebox_override("panel", sb)
	card.draw.connect(func() -> void: draw_panel(card, panel_art, Rect2(Vector2.ZERO, card.size), scale))

## A list row (dialogue options, quests); `lit` when hovered or chosen.
static func option_row(lit: bool) -> StyleBoxTexture:
	return box("dialogue/option_row_hover" if lit else "dialogue/option_row", 22, 14)

## A shop line: a square item niche on the left, then the name and price.
static func shop_row(lit: bool) -> StyleBoxTexture:
	var sb := box("dialogue/shop_row_hover" if lit else "dialogue/shop_row", 18, 16)
	sb.texture_margin_left = 64
	return sb

## A pill with a Dawnshard on its left and room for the amount after it.
static func shard_counter() -> StyleBoxTexture:
	var sb := box("dialogue/shard_counter", 20, 14)
	sb.texture_margin_left = 60
	return sb

## A small pill for picking an amount (×1, ×10, ×100); `on` is the one picked.
static func amount_chip(on: bool) -> StyleBoxTexture:
	return box("dialogue/amount_chip_on" if on else "dialogue/amount_chip", 20, 14)

## A buddy or guild member: a round niche on the left (for their online dot), then text.
static func friend_row() -> StyleBoxTexture:
	var sb := box("social/friend_row", 18, 16)
	sb.texture_margin_left = 70
	return sb

## An achievement: a round badge niche on the left; the done one glows with a star in it.
static func achievement_row(done: bool) -> StyleBoxTexture:
	var sb := box("book/achievement_row_done" if done else "book/achievement_row", 20, 18)
	sb.texture_margin_left = 84
	return sb

## The open Monster Book (book/book_pages): drawn as two pages of any widths with the
## spine between them, see `draw_book`.
const BOOK := ["book/book_pages", Vector4(40, 44, 40, 48), Vector2(30, 0)]

## Panels with an ornament in the middle of an edge (draw them with draw_panel):
## [texture, margins (left, top, right, bottom), middle kept (across, down)], in texels.
## The arch panel's bottom border takes in the light trim under its dark middle, so content
## padded past it never sits on the trim.
const ARCH_PANEL := ["menu/menu_panel", Vector4(30, 56, 30, 44), Vector2(70, 34)]
const TRACKER_PANEL := ["dialogue/tracker_panel", Vector4(16, 32, 16, 12), Vector2(44, 0)]
const GUILD_TAG := ["social/guild_tag", Vector4(46, 28, 46, 18), Vector2(56, 0)]
const SHOP_SIGN := ["social/shop_sign", Vector4(40, 50, 40, 20), Vector2(50, 0)]
const DIVIDER := ["menu/divider", Vector4(12, 0, 12, 0), Vector2(40, 0)]
const CREATOR_FRAME := ["creator/frame", Vector4(22, 34, 22, 24), Vector2(70, 0)]
const DIALOGUE_FRAME := ["dialogue/dialogue_frame", Vector4(160, 52, 30, 34), Vector2(100, 50)]

## Draws one of the panels above.
static func draw_panel(ci: CanvasItem, panel_art: Array, r: Rect2, scale := 1.0) -> void:
	draw_ornate(ci, panel_art[0], r, panel_art[1], panel_art[2], scale)

## The open book with its left page `left_w` pixels wide; the right page takes the rest of `r`.
static func draw_book(ci: CanvasItem, r: Rect2, left_w: float, scale := 1.0) -> void:
	var name: String = BOOK[0]
	var spine := Vector2(BOOK[2].x, 0)
	draw_box(ci, _quarter_box(name, false, false, BOOK[1], spine), Rect2(r.position, Vector2(left_w, r.size.y / 2.0)), scale)
	draw_box(ci, _quarter_box(name, false, true, BOOK[1], spine), Rect2(r.position + Vector2(0, r.size.y / 2.0), Vector2(left_w, r.size.y / 2.0)), scale)
	var right := Rect2(r.position.x + left_w, r.position.y, r.size.x - left_w, r.size.y / 2.0)
	draw_box(ci, _quarter_box(name, true, false, BOOK[1], spine), right, scale)
	draw_box(ci, _quarter_box(name, true, true, BOOK[1], spine), Rect2(right.position + Vector2(0, right.size.y), right.size), scale)

## The game windows' frame (inventory, equipment, character): gold trim and a title strip.
static func window_frame() -> StyleBoxTexture:
	var sb := box("window_frame", 16, 30)
	sb.texture_margin_bottom = 14
	return sb

static func tooltip_frame() -> StyleBoxTexture:
	return box("tooltip_frame", 12, 12)

## Styles for a gold button in every state.
static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box("button_normal", 16, 14))
	b.add_theme_stylebox_override("hover", box("button_hover", 18, 16))
	b.add_theme_stylebox_override("focus", box("button_hover", 18, 16))
	b.add_theme_stylebox_override("pressed", box("button_pressed", 16, 14))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Palette.INK)
	add_motion(b)

## A tab button (toggle_mode, in a ButtonGroup) from the settings sheet: muted purple, raised
## gold when chosen. `icon` (a texture name) shows left of the text.
## The lit tab's ends hold a brass stud (TAB_STUD texels in from each side), so both states
## keep their label TAB_PAD in, past it.
static func style_tab(b: Button, icon := "") -> void:
	var off := box("menu/tab_off", 22, 12, TAB_PAD, 4)
	var on := box("menu/tab_on", TAB_STUD, 12, TAB_PAD, 4)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", _tinted(off, LIT))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(state, Palette.MIST)
	b.add_theme_color_override("font_pressed_color", Palette.INK)
	b.add_theme_color_override("font_hover_pressed_color", Palette.INK)
	if icon != "":
		b.icon = tex(icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 22)

## A key on the Controls tab: a keycap, glowing gold while it waits for a key, dim and
## dashed when nothing is bound (see `set_keycap`).
static func style_key_button(b: Button) -> void:
	for state in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_color"]:
		b.add_theme_color_override(state, Palette.INK)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	set_keycap(b, "keycap")

## Shows a key button as "keycap", "keycap_listening" or "keycap_empty".
static func set_keycap(b: Button, art: String) -> void:
	var sb := box("menu/" + art, 14, 14, 10, 2)
	if art == "keycap_listening":  # its glow is cut away; this art is bigger, so keep the same insets
		sb = box("menu/" + art, 20, 20, 10, 2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", _tinted(sb, LIT))
	b.add_theme_stylebox_override("pressed", _tinted(sb, PRESSED))
	b.add_theme_color_override("font_color", Palette.MIST if art == "keycap_empty" else Palette.INK)

## A text field drawn with a field art (the chat line); `margins` are its borders in texels
## (left, top, right, bottom), drawn `scale` pixels per texel.
static func style_field(f: LineEdit, art: String, margins: Vector4, scale := 1.0) -> void:
	var img := tex(art).get_image()
	img.resize(roundi(img.get_width() * scale), roundi(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = margins.x * scale
	sb.texture_margin_top = margins.y * scale
	sb.texture_margin_right = margins.z * scale
	sb.texture_margin_bottom = margins.w * scale
	sb.content_margin_left = margins.x * scale + 2
	sb.content_margin_right = margins.z * scale
	f.add_theme_stylebox_override("normal", sb)
	f.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	f.add_theme_color_override("font_color", Palette.MIST)
	f.add_theme_color_override("font_placeholder_color", Color(Palette.MUTED, 0.8))
	f.add_theme_color_override("caret_color", Palette.SUN)

## Sets a box's placeholder hint with a little room before it, so the caret (where the first
## letter would go, which is where the hint starts) doesn't blink over it. Keep a box with a
## hint left-aligned: an empty centred box puts its caret in the middle, on the hint.
static func set_hint(f: LineEdit, hint: String) -> void:
	f.placeholder_text = HINT_ROOM + hint

## A slider: a dark groove, a glowing gold fill and the sun knob.
static func style_slider(s: HSlider) -> void:
	var track := box("menu/slider_track", 10, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := box("menu/slider_fill", 10, 0)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", _tinted(fill, LIT))
	s.add_theme_icon_override("grabber", sized("menu/slider_knob", 24))
	s.add_theme_icon_override("grabber_highlight", sized("menu/slider_knob_hover", 26))
	s.add_theme_icon_override("grabber_disabled", sized("menu/slider_knob", 24))

## A check box with the settings sheet's box and gold tick; `icon` shows before the text.
static func style_check_box(c: CheckBox, icon := "") -> void:
	# the ticked box's art is drawn a little bigger (the tick pokes out of it)
	c.add_theme_icon_override("unchecked", sized("menu/checkbox_off", 20))
	c.add_theme_icon_override("checked", sized("menu/checkbox_on", 24))
	c.add_theme_icon_override("unchecked_disabled", sized("menu/checkbox_off", 20))
	c.add_theme_icon_override("checked_disabled", sized("menu/checkbox_on", 24))
	c.add_theme_constant_override("h_separation", 8)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		c.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if icon != "":
		c.icon = sized(icon, 20)

## A dropdown: the long field with the down arrow, and its list in the dark gold-edged panel.
static func style_option_button(o: OptionButton) -> void:
	var field := box("menu/dropdown", 14, 12, 14, 4)
	field.texture_margin_right = 30
	field.content_margin_right = 34
	o.add_theme_stylebox_override("normal", field)
	o.add_theme_stylebox_override("hover", _tinted(field, LIT))
	o.add_theme_stylebox_override("pressed", _tinted(field, PRESSED))
	o.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	o.add_theme_stylebox_override("disabled", _tinted(field, Color(0.7, 0.65, 0.75, 0.6)))
	o.add_theme_icon_override("arrow", ImageTexture.new())  # the art has its own arrow
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		o.add_theme_color_override(state, Palette.MIST)
	o.add_theme_color_override("font_disabled_color", Color(Palette.MIST, 0.45))
	var popup := o.get_popup()
	popup.add_theme_stylebox_override("panel", box("menu/dropdown_list", 14, 10, 10, 8))
	popup.add_theme_stylebox_override("hover", list_row_hover())
	popup.add_theme_color_override("font_color", Palette.MIST)
	popup.add_theme_color_override("font_hover_color", Palette.INK)
	popup.add_theme_font_override("font", Game.ui_font)
	popup.add_theme_font_size_override("font_size", 15)
	popup.add_theme_constant_override("v_separation", 8)
	for icon in ["radio_checked", "radio_unchecked", "checked", "unchecked"]:
		popup.add_theme_icon_override(icon, ImageTexture.new())

## A hovered row in a list (a dropdown's choices): cream and gold with the sun on its left,
## which keeps its size while the row stretches.
static func list_row_hover() -> StyleBoxTexture:
	if not _cache.has("list_row_hover"):
		var sb := box("menu/list_row_hover", 8, 8).duplicate() as StyleBoxTexture
		sb.texture_margin_left = 26
		sb.content_margin_left = 28
		_cache["list_row_hover"] = sb
	return _cache["list_row_hover"]

## A scroll container's vertical bar: a thin groove with a gold handle.
static func style_scroll(sc: ScrollContainer) -> void:
	var bar := sc.get_v_scroll_bar()
	var track := box("menu/scroll_track", 0, 8)
	track.content_margin_left = 6
	track.content_margin_right = 6
	var grab := box("menu/scroll_grabber", 0, 10)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", _tinted(grab, LIT))
	bar.add_theme_stylebox_override("grabber_pressed", _tinted(grab, PRESSED))
	bar.custom_minimum_size.x = 14

## A UI texture shrunk to `height` pixels tall (for button and theme icons, which draw at their own size).
static func sized(name: String, height: int) -> Texture2D:
	var key := "scaled:%s:%d" % [name, height]
	if not _cache.has(key):
		var img := tex(name).get_image()
		img.resize(maxi(1, roundi(img.get_width() * float(height) / img.get_height())), height, Image.INTERPOLATE_LANCZOS)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

## A big gold menu button in the title font (title screen, game menu, settings), from the
## settings sheet's wide button: it brightens on hover and darkens when pressed.
static func menu_button(text: String, min_size := Vector2(150, 48), font_size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", font_size)
	var normal := box("menu/wide_button", 20, 14, 18, 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", _tinted(normal, LIT))
	b.add_theme_stylebox_override("focus", _tinted(normal, LIT))
	b.add_theme_stylebox_override("pressed", _tinted(normal, PRESSED))
	b.add_theme_stylebox_override("disabled", _tinted(normal, Color(0.7, 0.65, 0.7, 0.7)))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Palette.INK)
	add_motion(b)
	return b

## Buttons swell a little under the mouse and squash when pressed.
const HOVER_GROW := 1.03
const PRESS_SQUASH := Vector2(1.04, 0.92)
const MOTION_TIME := 0.08

## Gives `b` the hover swell and press squash (drawn only: its layout size doesn't change).
static func add_motion(b: BaseButton) -> void:
	var to := func(target: Vector2) -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", target, MOTION_TIME).set_trans(Tween.TRANS_SINE)
	b.mouse_entered.connect(func() -> void: if not b.disabled: to.call(Vector2.ONE * HOVER_GROW))
	b.mouse_exited.connect(func() -> void: to.call(Vector2.ONE))
	b.button_down.connect(func() -> void: to.call(PRESS_SQUASH))
	b.button_up.connect(func() -> void: to.call(Vector2.ONE * (HOVER_GROW if b.is_hovered() else 1.0)))

## A style brightened, for hover and focus.
static func lit(sb: StyleBoxTexture) -> StyleBoxTexture:
	return _tinted(sb, LIT)

## A style darkened, for a pressed button.
static func pressed(sb: StyleBoxTexture) -> StyleBoxTexture:
	return _tinted(sb, PRESSED)

## A copy of a style drawn in another tint.
static func _tinted(sb: StyleBoxTexture, tint: Color) -> StyleBoxTexture:
	var out := sb.duplicate() as StyleBoxTexture
	out.modulate_color = tint
	return out

static func use_cursor() -> void:
	Input.set_custom_mouse_cursor(tex("cursor"), Input.CURSOR_ARROW, Vector2(3, 3))

## A bar: the frame texture with its fill drawn into the groove. `pos` is the frame's top left.
## `trail` (above `fraction`) shows a pale chunk of what was just lost, and `flash` (0-1)
## lights the fill up, for bars that animate (TDStatusBar).
static func draw_bar(ci: CanvasItem, frame: String, fill: String, pos: Vector2, fraction: float, scale := 1.0, text := "", trail := 0.0, flash := 0.0) -> void:
	var ft := tex(frame)
	ci.draw_texture_rect(ft, Rect2(pos, ft.get_size() * scale), false)
	var g: Rect2 = GROOVES[frame]
	var groove := Rect2(pos + g.position * scale, g.size * scale)
	if trail > fraction:
		var from := groove.size.x * clampf(fraction, 0.0, 1.0)
		var to := groove.size.x * clampf(trail, 0.0, 1.0)
		DrawUtil.round_rect(ci, Rect2(groove.position.x + maxf(0.0, from - 4.0), groove.position.y + 1.0, to - from + 4.0, groove.size.y - 2.0),
			groove.size.y / 2.0 - 1.0, Color(Palette.MUTED, 0.85))
	draw_bar_fill(ci, fill, groove, fraction, scale)
	if flash > 0.0 and fraction > 0.0:
		DrawUtil.round_rect(ci, Rect2(groove.position, Vector2(groove.size.x * clampf(fraction, 0.0, 1.0), groove.size.y)),
			groove.size.y / 2.0, Color(1.0, 0.95, 0.75, 0.6 * flash))
	if text != "":
		# never smaller than BAR_TEXT_MIN, so a bar drawn small stays readable
		var ts := maxi(int(12 * scale), BAR_TEXT_MIN)
		DrawUtil.text(ci, Game.ui_font, Vector2(groove.get_center().x, groove.get_center().y + ts * 0.36),
			text, ts, Palette.MIST, 0, 4, Color(0.1, 0.05, 0.15, 0.9))

## A bar's fill pill across the left `fraction` of `groove`.
static func draw_bar_fill(ci: CanvasItem, fill: String, groove: Rect2, fraction: float, scale := 1.0) -> void:
	var w := groove.size.x * clampf(fraction, 0.0, 1.0)
	if w < 2.0:
		return
	if w < 20.0 * scale:  # too short for the rounded ends: squeeze the whole pill
		ci.draw_texture_rect(tex(fill), Rect2(groove.position, Vector2(w, groove.size.y)), false)
	else:
		box(fill, 10, 0).draw(ci.get_canvas_item(), Rect2(groove.position, Vector2(w, groove.size.y)))

## How wide a plaque `h` pixels tall must be to hold text `text_w` wide between its end caps.
static func plaque_width(text_w: float, h: float) -> float:
	return text_w + 2.0 * (PLAQUE_MARGINS.x * h / tex("name_tag").get_height() + PLAQUE_PAD)

## The small dark plaque with gold end caps (name tags, hints), scaled to the height of `r`
## so the caps keep their shape and only the middle stretches.
static func draw_plaque(ci: CanvasItem, r: Rect2) -> void:
	draw_box(ci, box("name_tag", PLAQUE_MARGINS.x, PLAQUE_MARGINS.y), r, r.size.y / tex("name_tag").get_height())

## Where a name tag with its top centre at `top_center` sits on screen.
static func name_tag_rect(top_center: Vector2, label: String) -> Rect2:
	var w := plaque_width(DrawUtil.text_width(Game.ui_font, label, 11), NAME_TAG_H)
	return Rect2(top_center.x - w / 2.0, top_center.y, w, NAME_TAG_H)

## The plaque under a character's feet with their name.
static func draw_name_tag(ci: CanvasItem, top_center: Vector2, label: String, col: Color, badge := Color.TRANSPARENT) -> void:
	draw_plaque(ci, name_tag_rect(top_center, label))
	DrawUtil.text(ci, Game.ui_font, top_center + Vector2(0, 14), label, 11, col)
	if badge.a > 0.0:
		DrawUtil.text(ci, Game.num_font, top_center + Vector2(0, 32), "BOSS", 12, badge, 0, 4, Palette.NIGHT)

## Where a guild plaque with its top centre at `top_center` sits on screen.
static func guild_tag_rect(top_center: Vector2, label: String) -> Rect2:
	var w := maxf(DrawUtil.text_width(Game.ui_font, label, 11) + 34, ornate_min_size(GUILD_TAG[1], GUILD_TAG[2], 0.4).x)
	return Rect2(top_center.x - w / 2.0, top_center.y - 3, w, 24)

## The guild plaque under a member's name: cream with green trim, in dark ink.
static func draw_guild_tag(ci: CanvasItem, top_center: Vector2, label: String) -> void:
	draw_panel(ci, GUILD_TAG, guild_tag_rect(top_center, label), 0.4)
	DrawUtil.text(ci, Game.ui_font, top_center + Vector2(0, 13), label, 11, Palette.INK)

## A wooden sign hanging over a player who keeps a shop, with the shop's name on it.
static func draw_shop_sign(ci: CanvasItem, bottom_center: Vector2, label: String) -> void:
	var scale := 0.4
	var size := Vector2(DrawUtil.text_width(Game.ui_font, label, 12) + 44, tex(SHOP_SIGN[0]).get_height() * scale)
	size.x = maxf(size.x, ornate_min_size(SHOP_SIGN[1], SHOP_SIGN[2], scale).x)
	draw_panel(ci, SHOP_SIGN, Rect2(bottom_center - Vector2(size.x / 2.0, size.y), size), scale)
	DrawUtil.text(ci, Game.ui_font, bottom_center + Vector2(0, -size.y * 0.3), label, 12, Palette.SUN, 0, 4, Palette.NIGHT)

## The marker over an NPC: "!" a quest for you, "?" one to hand in, "..." one in progress.
static func draw_quest_marker(ci: CanvasItem, bottom_center: Vector2, kind: String, height := 34.0) -> void:
	var art: String = QUEST_MARKERS.get(kind, "")
	if art == "":
		return
	var t := tex(art)
	var s := t.get_size() * height / t.get_height()
	ci.draw_texture_rect(t, Rect2(bottom_center - Vector2(s.x / 2.0, s.y), s), false)

## A party member's slim HP bar, `width` pixels wide with its top left at `pos`. The art has
## a fill painted in, so the groove is emptied before the real fill goes on.
static func draw_party_hp(ci: CanvasItem, pos: Vector2, width: float, fraction: float) -> void:
	var frame := "social/party_hp_frame"
	var scale := width / tex(frame).get_width()
	var g: Rect2 = GROOVES[frame]
	ci.draw_texture_rect(tex(frame), Rect2(pos, tex(frame).get_size() * scale), false)
	var groove := Rect2(pos + g.position * scale, g.size * scale)
	DrawUtil.round_rect(ci, groove.grow(0.5), groove.size.y / 2.0, Palette.NIGHT)
	draw_bar_fill(ci, "fill_red", groove, fraction)

## A monster HP bar `width` pixels wide centred above it.
static func draw_monster_hp(ci: CanvasItem, bottom_center: Vector2, width: float, fraction: float) -> void:
	var scale := width / 135.0
	draw_monster_bar(ci, bottom_center - Vector2(width / 2.0, (MONSTER_CAP.size.y + 5.0) * scale), width, fraction, scale)

## Where the monster bar's frame sits when drawn `width` pixels wide from `pos`, `scale`
## screen pixels per texel.
static func monster_bar_rect(pos: Vector2, width: float, scale: float) -> Rect2:
	return Rect2(pos, Vector2(maxf(width, 2.0 * MONSTER_CAP.size.x * scale), MONSTER_CAP.size.y * scale))

## Where the monster bar's fill runs inside its frame `frame`.
static func monster_bar_groove(frame: Rect2, scale: float) -> Rect2:
	var inset := MONSTER_GROOVE_INSET * scale
	return Rect2(frame.position + inset, Vector2(frame.size.x - 2.0 * inset.x, MONSTER_GROOVE_H * scale))

## The monster bar with its top left at `pos`: two end caps and a stretched middle, so it
## can be any width and leaves out the emblem on the art's left end.
static func draw_monster_bar(ci: CanvasItem, pos: Vector2, width: float, fraction: float, scale: float) -> void:
	var art := tex("monster_hp_1")
	var r := monster_bar_rect(pos, width, scale)
	var cap := MONSTER_CAP.size * scale
	ci.draw_texture_rect_region(art, Rect2(r.position.x + cap.x, r.position.y, r.size.x - 2.0 * cap.x, cap.y), MONSTER_MID)
	ci.draw_texture_rect_region(art, Rect2(r.end.x - cap.x, r.position.y, cap.x, cap.y), MONSTER_CAP)
	ci.draw_set_transform(Vector2(r.position.x + cap.x, r.position.y), 0.0, Vector2(-1, 1))
	ci.draw_texture_rect_region(art, Rect2(Vector2.ZERO, cap), MONSTER_CAP)
	ci.draw_set_transform(Vector2.ZERO)
	draw_bar_fill(ci, "monster_hp_2", monster_bar_groove(r, scale), fraction, scale)

## The bar fixed at the top of the screen while a boss is on the map: its name with a
## BOSS badge, and its HP.
static func draw_boss_bar(ci: CanvasItem, top_center: Vector2, label: String, fraction: float) -> void:
	var scale := 1.8
	var width := tex("monster_hp_1").get_width() * scale
	DrawUtil.text(ci, Game.num_font, top_center + Vector2(0, 14), "BOSS", 12, Palette.EMBER, 0, 4, Palette.NIGHT)
	DrawUtil.text(ci, Game.ui_font, top_center + Vector2(0, 30), label, 14, Palette.MIST, 0, 4, Palette.NIGHT)
	draw_monster_bar(ci, top_center + Vector2(-width / 2.0, 30.0 + MONSTER_CAP.position.y * scale), width, fraction, scale)

## A cream speech bubble whose tail points down at `bottom_center`, in dark ink.
static func draw_speech(ci: CanvasItem, bottom_center: Vector2, text: String) -> void:
	var font := Game.ui_font
	var size := 12
	var max_w := 240.0
	var k := 0.5  # screen pixels per texel of the bubble art
	var lines := wrap_text(font, text, size, max_w)
	var w := 0.0
	for l in lines:
		w = maxf(w, DrawUtil.text_width(font, l, size))
	var tail := Rect2(bottom_center - SPEECH_TIP * k, SPEECH_TAIL.size * k)
	var bottom := tail.position.y + (SPEECH_BODY.end.y - SPEECH_TAIL.position.y) * k
	var h := lines.size() * 16 + 14
	# the tail sits a little left of centre in the art; keep the bubble centred on the speaker
	var r := Rect2(bottom_center.x - w / 2.0 - 12, bottom - h, w + 24, h)
	var body := box("hud/speech_bubble", 20, 20)
	body.region_rect = SPEECH_BODY
	draw_box(ci, body, r, k)
	ci.draw_texture_rect_region(tex("hud/speech_bubble"), tail, SPEECH_TAIL)
	for i in lines.size():
		DrawUtil.text(ci, font, Vector2(bottom_center.x, r.position.y + 19 + i * 16), lines[i], size, Palette.INK)

## How wide `draw_hint` draws a hint with this text.
static func hint_width(text: String) -> float:
	return plaque_width(DrawUtil.text_width(Game.ui_font, text, 13), HINT_H)

## A small floating hint ("↑ Talk", "↑ to Fern Hollow").
static func draw_hint(ci: CanvasItem, bottom_center: Vector2, text: String) -> void:
	var w := hint_width(text)
	draw_plaque(ci, Rect2(bottom_center.x - w / 2.0, bottom_center.y - HINT_H, w, HINT_H))
	DrawUtil.text(ci, Game.ui_font, bottom_center + Vector2(0, -6), text, 13, Palette.MIST)

## The parchment banner with a map's name, faded by `alpha`: the name sits in the middle of
## the parchment band, which is centred on `center`.
static func draw_banner(ci: CanvasItem, center: Vector2, text: String, alpha: float) -> void:
	ci.draw_set_transform(Vector2.ZERO)
	var sb := box("area_banner", 34, 18)
	sb.modulate_color = Color(1, 1, 1, alpha)
	sb.draw(ci.get_canvas_item(), banner_rect(center, text))
	DrawUtil.text(ci, Game.num_font, Vector2(center.x, DrawUtil.cap_baseline(center.y, BANNER_TEXT)), text, BANNER_TEXT, Color("5a3414", alpha), 0, 0)

## Where the map-name banner's art is drawn for `text`, its parchment band centred on `center`
## (the band lies inside the art's top margin, so stretching never moves it).
static func banner_rect(center: Vector2, text: String) -> Rect2:
	var w := DrawUtil.text_width(Game.num_font, text, BANNER_TEXT) + 120
	return Rect2(center.x - w / 2.0, center.y - BANNER_BAND_MID, w, BANNER_H)

static func wrap_text(font: Font, text: String, size: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var next := word if line == "" else line + " " + word
		if line != "" and DrawUtil.text_width(font, next, size) > max_w:
			out.append(line)
			line = word
		else:
			line = next
	if line != "":
		out.append(line)
	return out
