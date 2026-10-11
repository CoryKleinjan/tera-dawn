class_name UiStyle
extends RefCounted
## Styles Godot controls with the UI art (UiSkin): gold buttons and menu buttons, the
## settings sheet's tabs, keycaps, fields, sliders, check boxes, dropdowns and scroll bars,
## and the swell and squash buttons give under the mouse.

## Spaces between the caret and a box's placeholder hint (see set_hint).
const HINT_ROOM := "  "
## The settings tabs' art: how far in from each side the lit tab's stud ends, and how far in
## the label and icon start.
const TAB_STUD := 28.0
const TAB_PAD := 32.0
## Buttons swell a little under the mouse and squash when pressed.
const HOVER_GROW := 1.03
const PRESS_SQUASH := Vector2(1.04, 0.92)
const MOTION_TIME := 0.08

## Styles for a gold button in every state.
static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UiSkin.box("button_normal", 16, 14))
	b.add_theme_stylebox_override("hover", UiSkin.box("button_hover", 18, 16))
	b.add_theme_stylebox_override("focus", UiSkin.box("button_hover", 18, 16))
	b.add_theme_stylebox_override("pressed", UiSkin.box("button_pressed", 16, 14))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Palette.INK)
	add_motion(b)

## A tab button (toggle_mode, in a ButtonGroup) from the settings sheet: muted purple, raised
## gold when chosen. `icon` (a texture name) shows left of the text.
## The lit tab's ends hold a brass stud (TAB_STUD texels in from each side), so both states
## keep their label TAB_PAD in, past it.
static func style_tab(b: Button, icon := "") -> void:
	var off := UiSkin.box("menu/tab_off", 22, 12, TAB_PAD, 4)
	var on := UiSkin.box("menu/tab_on", TAB_STUD, 12, TAB_PAD, 4)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", UiSkin.lit(off))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(state, Palette.MIST)
	b.add_theme_color_override("font_pressed_color", Palette.INK)
	b.add_theme_color_override("font_hover_pressed_color", Palette.INK)
	if icon != "":
		b.icon = UiSkin.tex(icon)
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
	var sb := UiSkin.box("menu/" + art, 14, 14, 10, 2)
	if art == "keycap_listening":  # its glow is cut away; this art is bigger, so keep the same insets
		sb = UiSkin.box("menu/" + art, 20, 20, 10, 2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", UiSkin.lit(sb))
	b.add_theme_stylebox_override("pressed", UiSkin.pressed(sb))
	b.add_theme_color_override("font_color", Palette.MIST if art == "keycap_empty" else Palette.INK)

## A text field drawn with a field art (the chat line); `margins` are its borders in texels
## (left, top, right, bottom), drawn `scale` pixels per texel.
static func style_field(f: LineEdit, art: String, margins: Vector4, scale := 1.0) -> void:
	var img := UiSkin.tex(art).get_image()
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
	var track := UiSkin.box("menu/slider_track", 10, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := UiSkin.box("menu/slider_fill", 10, 0)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", UiSkin.lit(fill))
	s.add_theme_icon_override("grabber", UiSkin.sized("menu/slider_knob", 24))
	s.add_theme_icon_override("grabber_highlight", UiSkin.sized("menu/slider_knob_hover", 26))
	s.add_theme_icon_override("grabber_disabled", UiSkin.sized("menu/slider_knob", 24))

## A check box with the settings sheet's box and gold tick; `icon` shows before the text.
static func style_check_box(c: CheckBox, icon := "") -> void:
	# the ticked box's art is drawn a little bigger (the tick pokes out of it)
	c.add_theme_icon_override("unchecked", UiSkin.sized("menu/checkbox_off", 20))
	c.add_theme_icon_override("checked", UiSkin.sized("menu/checkbox_on", 24))
	c.add_theme_icon_override("unchecked_disabled", UiSkin.sized("menu/checkbox_off", 20))
	c.add_theme_icon_override("checked_disabled", UiSkin.sized("menu/checkbox_on", 24))
	c.add_theme_constant_override("h_separation", 8)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		c.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if icon != "":
		c.icon = UiSkin.sized(icon, 20)

## A dropdown: the long field with the down arrow, and its list in the dark gold-edged panel.
static func style_option_button(o: OptionButton) -> void:
	var field := UiSkin.box("menu/dropdown", 14, 12, 14, 4)
	field.texture_margin_right = 30
	field.content_margin_right = 34
	o.add_theme_stylebox_override("normal", field)
	o.add_theme_stylebox_override("hover", UiSkin.lit(field))
	o.add_theme_stylebox_override("pressed", UiSkin.pressed(field))
	o.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	o.add_theme_stylebox_override("disabled", UiSkin.tinted(field, Color(0.7, 0.65, 0.75, 0.6)))
	o.add_theme_icon_override("arrow", ImageTexture.new())  # the art has its own arrow
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		o.add_theme_color_override(state, Palette.MIST)
	o.add_theme_color_override("font_disabled_color", Color(Palette.MIST, 0.45))
	var popup := o.get_popup()
	popup.add_theme_stylebox_override("panel", UiSkin.box("menu/dropdown_list", 14, 10, 10, 8))
	popup.add_theme_stylebox_override("hover", UiSkin.list_row_hover())
	popup.add_theme_color_override("font_color", Palette.MIST)
	popup.add_theme_color_override("font_hover_color", Palette.INK)
	popup.add_theme_font_override("font", Game.ui_font)
	popup.add_theme_font_size_override("font_size", 15)
	popup.add_theme_constant_override("v_separation", 8)
	for icon in ["radio_checked", "radio_unchecked", "checked", "unchecked"]:
		popup.add_theme_icon_override(icon, ImageTexture.new())

## A scroll container's vertical bar: a thin groove with a gold handle.
static func style_scroll(sc: ScrollContainer) -> void:
	var bar := sc.get_v_scroll_bar()
	var track := UiSkin.box("menu/scroll_track", 0, 8)
	track.content_margin_left = 6
	track.content_margin_right = 6
	var grab := UiSkin.box("menu/scroll_grabber", 0, 10)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", UiSkin.lit(grab))
	bar.add_theme_stylebox_override("grabber_pressed", UiSkin.pressed(grab))
	bar.custom_minimum_size.x = 14

## A big gold menu button in the title font (title screen, game menu, settings), from the
## settings sheet's wide button: it brightens on hover and darkens when pressed.
static func menu_button(text: String, min_size := Vector2(150, 48), font_size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", font_size)
	var normal := UiSkin.box("menu/wide_button", 20, 14, 18, 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", UiSkin.lit(normal))
	b.add_theme_stylebox_override("focus", UiSkin.lit(normal))
	b.add_theme_stylebox_override("pressed", UiSkin.pressed(normal))
	b.add_theme_stylebox_override("disabled", UiSkin.tinted(normal, Color(0.7, 0.65, 0.7, 0.7)))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Palette.INK)
	add_motion(b)
	return b

## Gives `b` the hover swell and press squash (drawn only: its layout size doesn't change).
static func add_motion(b: BaseButton) -> void:
	var to := func(target: Vector2) -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", target, MOTION_TIME).set_trans(Tween.TRANS_SINE)
	b.mouse_entered.connect(func() -> void: if not b.disabled: to.call(Vector2.ONE * HOVER_GROW))
	b.mouse_exited.connect(func() -> void: to.call(Vector2.ONE))
	b.button_down.connect(func() -> void: to.call(PRESS_SQUASH))
	b.button_up.connect(func() -> void: to.call(Vector2.ONE * (HOVER_GROW if b.is_hovered() else 1.0)))

## Uses the UI art's pointer as the mouse cursor.
static func use_cursor() -> void:
	Input.set_custom_mouse_cursor(UiSkin.tex("cursor"), Input.CURSOR_ARROW, Vector2(3, 3))
