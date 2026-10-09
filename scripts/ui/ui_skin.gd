class_name UiSkin
extends RefCounted
## The game's UI art (assets/sprites/ui/, cut from art/source/ui.png) as Godot styles,
## plus drawing helpers for things the overlay draws every frame (name tags, HP bars,
## speech bubbles). All sizes are in the 960x540 canvas.

const DIR := "res://assets/sprites/ui/"
## Where each bar frame's empty groove is, in texels: Rect2(x, y, w, h).
const GROOVES := {
	"hp_frame": Rect2(42, 10, 108, 18),
	"mp_frame": Rect2(37, 12, 116, 18),
	"exp_frame": Rect2(27, 7, 131, 13),
	"monster_hp_1": Rect2(38, 9, 83, 17),
}

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

static func panel() -> StyleBoxTexture:
	return box("menu_panel", 16, 16, 28, 24)

## The game windows' frame (inventory, equipment, character): gold trim and a title strip.
static func window_frame() -> StyleBoxTexture:
	var sb := box("window_frame", 22, 24)
	sb.texture_margin_bottom = 20
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

## A tab button (toggle_mode, in a ButtonGroup) lit like the game windows' tabs when chosen.
static func style_tab(b: Button) -> void:
	for state in ["normal", "hover"]:
		b.add_theme_stylebox_override(state, box("window_tab_off", 30, 14))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", box("window_tab_on", 30, 14))
	b.add_theme_stylebox_override("hover_pressed", box("window_tab_on", 30, 14))
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(state, Palette.MIST)
	b.add_theme_color_override("font_pressed_color", Palette.INK)
	b.add_theme_color_override("font_hover_pressed_color", Palette.INK)

## A small dark framed button, like a tooltip (the keys on the Controls tab).
static func style_slot_button(b: Button) -> void:
	var normal := box("tooltip_frame", 12, 12, 10, 4)
	var lit := normal.duplicate() as StyleBoxTexture
	lit.modulate_color = Color(1.3, 1.2, 1.0)
	b.add_theme_stylebox_override("normal", normal)
	for state in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(state, lit)
	for state in ["font_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Palette.MIST)
	b.add_theme_color_override("font_hover_color", Palette.SUN)

## A big gold menu button in the title font (title screen, game menu, settings).
static func menu_button(text: String, min_size := Vector2(150, 48), font_size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", font_size)
	style_button(b)
	return b

static func use_cursor() -> void:
	Input.set_custom_mouse_cursor(tex("cursor"), Input.CURSOR_ARROW, Vector2(14, 6))

## A bar: the frame texture with its fill drawn into the groove. `pos` is the frame's top left.
static func draw_bar(ci: CanvasItem, frame: String, fill: String, pos: Vector2, fraction: float, scale := 1.0, text := "") -> void:
	var ft := tex(frame)
	ci.draw_texture_rect(ft, Rect2(pos, ft.get_size() * scale), false)
	var g: Rect2 = GROOVES[frame]
	var groove := Rect2(pos + g.position * scale, g.size * scale)
	var w := groove.size.x * clampf(fraction, 0.0, 1.0)
	if w >= 2.0:
		var fill_box := box(fill, 10, 0)
		var r := Rect2(groove.position, Vector2(maxf(w, 20.0 * scale), groove.size.y))
		if w < 20.0 * scale:  # too short for the rounded ends: squeeze the whole pill
			ci.draw_texture_rect(tex(fill), Rect2(groove.position, Vector2(w, groove.size.y)), false)
		else:
			fill_box.draw(ci.get_canvas_item(), r)
	if text != "":
		DrawUtil.text(ci, Game.ui_font, groove.position + Vector2(groove.size.x / 2.0, groove.size.y - 4.0 * scale),
			text, int(12 * scale), Palette.MIST, 0, 4, Color(0.1, 0.05, 0.15, 0.9))

## The plaque under a character's feet with their name.
static func draw_name_tag(ci: CanvasItem, top_center: Vector2, label: String, col: Color, badge := Color.TRANSPARENT) -> void:
	var w := DrawUtil.text_width(Game.ui_font, label, 11) + 22
	var r := Rect2(top_center.x - w / 2.0, top_center.y, w, 19)
	box("name_tag", 12, 8).draw(ci.get_canvas_item(), r)
	DrawUtil.text(ci, Game.ui_font, top_center + Vector2(0, 14), label, 11, col)
	if badge.a > 0.0:
		DrawUtil.text(ci, Game.num_font, top_center + Vector2(0, 32), "BOSS", 12, badge, 0, 4, Palette.NIGHT)

## A monster HP bar centred above it.
static func draw_monster_hp(ci: CanvasItem, bottom_center: Vector2, width: float, fraction: float) -> void:
	var scale := width / 134.0
	var h := 38.0 * scale
	draw_bar(ci, "monster_hp_1", "monster_hp_2", bottom_center - Vector2(width / 2.0, h), fraction, scale)

## A speech bubble whose tail points down at `bottom_center`.
static func draw_speech(ci: CanvasItem, bottom_center: Vector2, text: String) -> void:
	var font := Game.ui_font
	var size := 12
	var max_w := 240.0
	var lines := wrap_text(font, text, size, max_w)
	var w := 0.0
	for l in lines:
		w = maxf(w, DrawUtil.text_width(font, l, size))
	var r := Rect2(bottom_center.x - w / 2.0 - 16, bottom_center.y - lines.size() * 16 - 28, w + 32, lines.size() * 16 + 20)
	panel().draw(ci.get_canvas_item(), r)
	ci.draw_colored_polygon(PackedVector2Array([bottom_center + Vector2(-7, -9), bottom_center + Vector2(7, -9), bottom_center]), Palette.GOLD_TRIM)
	for i in lines.size():
		DrawUtil.text(ci, font, Vector2(bottom_center.x, r.position.y + 24 + i * 16), lines[i], size, Palette.MIST)

## A small floating hint ("↑ Talk", "↑ to Ember Hollow").
static func draw_hint(ci: CanvasItem, bottom_center: Vector2, text: String) -> void:
	var w := DrawUtil.text_width(Game.ui_font, text, 13) + 26
	box("name_tag", 12, 8).draw(ci.get_canvas_item(), Rect2(bottom_center.x - w / 2.0, bottom_center.y - 22, w, 22))
	DrawUtil.text(ci, Game.ui_font, bottom_center + Vector2(0, -6), text, 13, Palette.MIST)

## The parchment banner with a map's name, faded by `alpha`.
static func draw_banner(ci: CanvasItem, center: Vector2, text: String, alpha: float) -> void:
	var w := DrawUtil.text_width(Game.num_font, text, 34) + 140
	ci.draw_set_transform(Vector2.ZERO)
	var sb := box("area_banner", 34, 18)
	sb.modulate_color = Color(1, 1, 1, alpha)
	sb.draw(ci.get_canvas_item(), Rect2(center.x - w / 2.0, center.y - 34, w, 68))
	DrawUtil.text(ci, Game.num_font, center + Vector2(0, 12), text, 34, Color("5a3414", alpha), 0, 0)

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
