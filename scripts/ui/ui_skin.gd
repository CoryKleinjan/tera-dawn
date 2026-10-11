class_name UiSkin
extends RefCounted
## The game's UI art: its textures, nine-patch styles cut from them, and the ornate panels
## and list rows the menus and windows are drawn with. Styling whole controls (buttons, tabs,
## fields) is UiStyle's job, and what's drawn over the world (HP bars, name tags, bubbles)
## is WorldSkin's. All sizes are in the 960x540 canvas.
##
## The art is cut from the UI sheets in art/source/ into assets/sprites/ui/: ui.png and
## ui_windows.png straight into it, and one folder per newer sheet, named like the textures
## here ("hud/quests_button"): hud/ (HUD buttons, quest markers, minimap), menu/ (Esc menu
## and settings controls), dialogue/ (dialogue, shop, trade, quests, banners), social/
## (buddies, party, guild, chat, invitations), book/ (Monster Book and achievements).
## world_map.png is the painted world map.

const DIR := "res://assets/sprites/ui/"
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

## Panels with an ornament in the middle of an edge (draw them with draw_panel; WorldSkin
## has the guild tag and shop sign):
## [texture, margins (left, top, right, bottom), middle kept (across, down)], in texels.
## The arch panel's bottom border takes in the light trim under its dark middle, so content
## padded past it never sits on the trim.
const ARCH_PANEL := ["menu/menu_panel", Vector4(30, 56, 30, 44), Vector2(70, 34)]
const TRACKER_PANEL := ["dialogue/tracker_panel", Vector4(16, 32, 16, 12), Vector2(44, 0)]
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

## A hovered row in a list (a dropdown's choices): cream and gold with the sun on its left,
## which keeps its size while the row stretches.
static func list_row_hover() -> StyleBoxTexture:
	if not _cache.has("list_row_hover"):
		var sb := box("menu/list_row_hover", 8, 8).duplicate() as StyleBoxTexture
		sb.texture_margin_left = 26
		sb.content_margin_left = 28
		_cache["list_row_hover"] = sb
	return _cache["list_row_hover"]

## A UI texture shrunk to `height` pixels tall (for button and theme icons, which draw at their own size).
static func sized(name: String, height: int) -> Texture2D:
	var key := "scaled:%s:%d" % [name, height]
	if not _cache.has(key):
		var img := tex(name).get_image()
		img.resize(maxi(1, roundi(img.get_width() * float(height) / img.get_height())), height, Image.INTERPOLATE_LANCZOS)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

## A style brightened, for hover and focus.
static func lit(sb: StyleBoxTexture) -> StyleBoxTexture:
	return tinted(sb, LIT)

## A style darkened, for a pressed button.
static func pressed(sb: StyleBoxTexture) -> StyleBoxTexture:
	return tinted(sb, PRESSED)

## A copy of a style drawn in another tint.
static func tinted(sb: StyleBoxTexture, tint: Color) -> StyleBoxTexture:
	var out := sb.duplicate() as StyleBoxTexture
	out.modulate_color = tint
	return out
