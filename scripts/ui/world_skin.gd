class_name WorldSkin
extends RefCounted
## Drawing helpers for what the overlay and the HUD draw every frame over the world, from
## the UI art (UiSkin): party, monster and boss HP bars, the plaques
## under name tags and hints, guild tags, quest markers, speech bubbles and the
## map-name banner. All sizes are in the 960x540 canvas.

## Where each bar frame's empty groove is, in art pixels: Rect2(x, y, w, h).
const GROOVES := {
	"social/party_hp_frame": Rect2(10, 8, 164, 11),
}
## The monster HP bar's frame without the emblem painted at its left end, in art pixels of
## monster_hp_1: its right end cap and a plain strip of its middle. The left end is the right
## cap mirrored, and the groove sits MONSTER_GROOVE_INSET into each cap.
const MONSTER_CAP := Rect2(123, 4, 12, 29)
const MONSTER_MID := Rect2(90, 4, 8, 29)
const MONSTER_GROOVE_INSET := Vector2(7, 5)
const MONSTER_GROOVE_H := 18.0
## The quest marker over an NPC for each QuestLog-like state TDNpc.quest_marker() returns.
const QUEST_MARKERS := {"!": "hud/quest_available", "?": "hud/quest_ready", "...": "hud/quest_in_progress"}
## The speech bubble's body and tail inside hud/speech_bubble, in art pixels.
const SPEECH_BODY := Rect2(0, 0, 144, 103)
const SPEECH_TAIL := Rect2(24, 98, 34, 28)
## Where the tail's tip is inside SPEECH_TAIL.
const SPEECH_TIP := Vector2(3, 27)
## The bubble's text size, line height and widest line, the room between the text and the
## inside of the outline, and the outline's thickness on screen (left, top, right, bottom).
const SPEECH_TEXT := 12
const SPEECH_LINE_H := 16.0
const SPEECH_MAX_W := 220.0
const SPEECH_PAD := Vector2(12, 7)
const SPEECH_EDGE := Vector4(2, 2, 2, 3)
## The plaque (name_tag) behind name tags and hints: its end caps and trim in art pixels (the
## caps' gold diamonds sit inside them), and the room left between the text and a cap.
const PLAQUE_MARGINS := Vector2(20, 9)
const PLAQUE_PAD := 2.0
## How tall name tags and hints are drawn.
const NAME_TAG_H := 19.0
const HINT_H := 22.0
## How tall the map-name banner is drawn, the middle row of its parchment band (the art's
## top half, in art pixels: the ribbon tails hang below it), and its text size.
const BANNER_H := 56.0
const BANNER_BAND_MID := 13.5
const BANNER_TEXT := 26
## Panels with an ornament in the middle of an edge, drawn with UiSkin.draw_panel:
## [texture, margins (left, top, right, bottom), middle kept (across, down)], in art pixels.
const GUILD_TAG := ["social/guild_tag", Vector4(46, 28, 46, 18), Vector2(56, 0)]

## A bar's fill pill across the left `fraction` of `groove`.
static func draw_bar_fill(ci: CanvasItem, fill: String, groove: Rect2, fraction: float, scale := 1.0) -> void:
	var w := groove.size.x * clampf(fraction, 0.0, 1.0)
	if w < 2.0:
		return
	if w < 20.0 * scale:  # too short for the rounded ends: squeeze the whole pill
		ci.draw_texture_rect(UiSkin.tex(fill), Rect2(groove.position, Vector2(w, groove.size.y)), false)
	else:
		UiSkin.box(fill, 10, 0).draw(ci.get_canvas_item(), Rect2(groove.position, Vector2(w, groove.size.y)))

## How wide a plaque `h` pixels tall must be to hold text `text_w` wide between its end caps.
static func plaque_width(text_w: float, h: float) -> float:
	return text_w + 2.0 * (PLAQUE_MARGINS.x * h / UiSkin.size_of("name_tag").y + PLAQUE_PAD)

## The small dark plaque with gold end caps (name tags, hints), scaled to the height of `r`
## so the caps keep their shape and only the middle stretches.
static func draw_plaque(ci: CanvasItem, r: Rect2) -> void:
	UiSkin.draw_box(ci, UiSkin.box("name_tag", PLAQUE_MARGINS.x, PLAQUE_MARGINS.y), r, r.size.y / UiSkin.size_of("name_tag").y)

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
	var w := maxf(DrawUtil.text_width(Game.ui_font, label, 11) + 34, UiSkin.ornate_min_size(GUILD_TAG[1], GUILD_TAG[2], 0.4).x)
	return Rect2(top_center.x - w / 2.0, top_center.y - 3, w, 24)

## The guild plaque under a member's name: cream with green trim, in dark ink.
static func draw_guild_tag(ci: CanvasItem, top_center: Vector2, label: String) -> void:
	UiSkin.draw_panel(ci, GUILD_TAG, guild_tag_rect(top_center, label), 0.4)
	DrawUtil.text(ci, Game.ui_font, top_center + Vector2(0, 13), label, 11, Palette.INK)

## The marker over an NPC: "!" a quest for you, "?" one to hand in, "..." one in progress.
## `height` is the "!"'s height; the others keep their size beside it, centred on the same spot.
static func draw_quest_marker(ci: CanvasItem, bottom_center: Vector2, kind: String, height := 34.0) -> void:
	var art: String = QUEST_MARKERS.get(kind, "")
	if art == "":
		return
	var t := UiSkin.tex(art)
	var s := UiSkin.size_of(art) * height / UiSkin.size_of(QUEST_MARKERS["!"]).y
	var center := bottom_center - Vector2(0, height / 2.0)
	ci.draw_texture_rect(t, Rect2(center - s / 2.0, s), false)

## A party member's slim HP bar, `width` pixels wide with its top left at `pos`. The art has
## a fill painted in, so the groove is emptied before the real fill goes on.
static func draw_party_hp(ci: CanvasItem, pos: Vector2, width: float, fraction: float) -> void:
	var frame := "social/party_hp_frame"
	var scale := width / UiSkin.size_of(frame).x
	var g: Rect2 = GROOVES[frame]
	ci.draw_texture_rect(UiSkin.tex(frame), Rect2(pos, UiSkin.size_of(frame) * scale), false)
	var groove := Rect2(pos + g.position * scale, g.size * scale)
	DrawUtil.round_rect(ci, groove.grow(0.5), groove.size.y / 2.0, Palette.NIGHT)
	draw_bar_fill(ci, "fill_red", groove, fraction)

## A monster HP bar `width` pixels wide centred above it.
static func draw_monster_hp(ci: CanvasItem, bottom_center: Vector2, width: float, fraction: float) -> void:
	var scale := width / 135.0
	draw_monster_bar(ci, bottom_center - Vector2(width / 2.0, (MONSTER_CAP.size.y + 5.0) * scale), width, fraction, scale)

## Where the monster bar's frame sits when drawn `width` pixels wide from `pos`, `scale`
## canvas pixels per art pixel.
static func monster_bar_rect(pos: Vector2, width: float, scale: float) -> Rect2:
	return Rect2(pos, Vector2(maxf(width, 2.0 * MONSTER_CAP.size.x * scale), MONSTER_CAP.size.y * scale))

## Where the monster bar's fill runs inside its frame `frame`.
static func monster_bar_groove(frame: Rect2, scale: float) -> Rect2:
	var inset := MONSTER_GROOVE_INSET * scale
	return Rect2(frame.position + inset, Vector2(frame.size.x - 2.0 * inset.x, MONSTER_GROOVE_H * scale))

## The monster bar with its top left at `pos`: two end caps and a stretched middle, so it
## can be any width and leaves out the emblem on the art's left end.
static func draw_monster_bar(ci: CanvasItem, pos: Vector2, width: float, fraction: float, scale: float) -> void:
	var art := UiSkin.tex("monster_hp_1")
	var r := monster_bar_rect(pos, width, scale)
	var cap := MONSTER_CAP.size * scale
	var mid := UiSkin.region("monster_hp_1", MONSTER_MID)
	var end := UiSkin.region("monster_hp_1", MONSTER_CAP)
	ci.draw_texture_rect_region(art, Rect2(r.position.x + cap.x, r.position.y, r.size.x - 2.0 * cap.x, cap.y), mid)
	ci.draw_texture_rect_region(art, Rect2(r.end.x - cap.x, r.position.y, cap.x, cap.y), end)
	ci.draw_set_transform(Vector2(r.position.x + cap.x, r.position.y), 0.0, Vector2(-1, 1))
	ci.draw_texture_rect_region(art, Rect2(Vector2.ZERO, cap), end)
	ci.draw_set_transform(Vector2.ZERO)
	draw_bar_fill(ci, "monster_hp_2", monster_bar_groove(r, scale), fraction, scale)

## The bar fixed at the top of the screen while a boss is on the map: its name with a
## BOSS badge, and its HP.
static func draw_boss_bar(ci: CanvasItem, top_center: Vector2, label: String, fraction: float) -> void:
	var scale := 1.8
	var width := UiSkin.size_of("monster_hp_1").x * scale
	DrawUtil.text(ci, Game.num_font, top_center + Vector2(0, 14), "BOSS", 12, Palette.EMBER, 0, 4, Palette.NIGHT)
	DrawUtil.text(ci, Game.ui_font, top_center + Vector2(0, 30), label, 14, Palette.MIST, 0, 4, Palette.NIGHT)
	draw_monster_bar(ci, top_center + Vector2(-width / 2.0, 30.0 + MONSTER_CAP.position.y * scale), width, fraction, scale)

## A cream speech bubble whose tail points down at `bottom_center`, in dark ink. Its lines are
## balanced (as narrow as they can be without adding a line) and sit centred in the cream.
static func draw_speech(ci: CanvasItem, bottom_center: Vector2, text: String) -> void:
	var font := Game.ui_font
	var k := 0.5  # canvas pixels per art pixel of the bubble
	var lines := _balanced_lines(font, text, SPEECH_TEXT, SPEECH_MAX_W)
	var w := 0.0
	for l in lines:
		w = maxf(w, DrawUtil.text_width(font, l, SPEECH_TEXT))
	var tail := Rect2(bottom_center - SPEECH_TIP * k, SPEECH_TAIL.size * k)
	var bottom := tail.position.y + (SPEECH_BODY.end.y - SPEECH_TAIL.position.y) * k
	var text_h := (lines.size() - 1) * SPEECH_LINE_H + SPEECH_TEXT * DrawUtil.CAP_HEIGHT
	var h := text_h + SPEECH_PAD.y * 2.0 + SPEECH_EDGE.y + SPEECH_EDGE.w
	var r := Rect2(bottom_center.x - w / 2.0 - SPEECH_PAD.x, bottom - h, w + SPEECH_PAD.x * 2.0, h)
	var body := UiSkin.box("hud/speech_bubble", 20, 20)
	body.region_rect = SPEECH_BODY
	UiSkin.draw_box(ci, body, r, k)
	ci.draw_texture_rect_region(UiSkin.tex("hud/speech_bubble"), tail, UiSkin.region("hud/speech_bubble", SPEECH_TAIL))
	var y := r.position.y + SPEECH_EDGE.y + SPEECH_PAD.y + SPEECH_TEXT * DrawUtil.CAP_HEIGHT
	for i in lines.size():
		DrawUtil.text(ci, font, Vector2(bottom_center.x, y + i * SPEECH_LINE_H), lines[i], SPEECH_TEXT, Palette.INK)

## `text` wrapped to at most `max_w`, then as narrow as it goes without taking another line, so a
## last word doesn't hang alone.
static func _balanced_lines(font: Font, text: String, size: int, max_w: float) -> PackedStringArray:
	var lines := DrawUtil.wrap_text(font, text, size, max_w)
	if lines.size() < 2:
		return lines
	var w := max_w
	while w > 40.0:
		var tighter := DrawUtil.wrap_text(font, text, size, w - 4.0)
		if tighter.size() > lines.size():
			break
		lines = tighter
		w -= 4.0
	return lines

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
	var sb := UiSkin.box("area_banner", 34, 18)
	sb.modulate_color = Color(1, 1, 1, alpha)
	sb.draw(ci.get_canvas_item(), banner_rect(center, text))
	DrawUtil.text(ci, Game.num_font, Vector2(center.x, DrawUtil.cap_baseline(center.y, BANNER_TEXT)), text, BANNER_TEXT, Color("5a3414", alpha), 0, 0)

## Where the map-name banner's art is drawn for `text`, its parchment band centred on `center`
## (the band lies inside the art's top margin, so stretching never moves it).
static func banner_rect(center: Vector2, text: String) -> Rect2:
	var w := DrawUtil.text_width(Game.num_font, text, BANNER_TEXT) + 120
	return Rect2(center.x - w / 2.0, center.y - BANNER_BAND_MID, w, BANNER_H)
