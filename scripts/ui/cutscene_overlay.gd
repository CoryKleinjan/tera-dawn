class_name TDCutsceneOverlay
extends Control
## What a cutscene draws over the world (TDCutscenePlayer): the fade to black, the black
## bars at the top and bottom, the speech box with the speaker's portrait and name (the
## same frame as TDDialogueWindow), and how to skip. While a cutscene plays it covers the
## screen, so clicks press on instead of reaching the game.

## The black bars' height at full (`bars` 1), as a share of the screen's height.
const BAR_SHARE := 0.11
## The speech box: widest it gets, its gap above the bottom bar, and how big the dialogue
## frame art is drawn (TDDialogueWindow uses the same art and layout numbers).
const SPEECH_W := 660.0
const SPEECH_GAP := 14.0
const FRAME_SCALE := TDDialogueWindow.FRAME_SCALE
const TEXT_SIZE := 15
## The skip hint in the top right corner.
const SKIP_SIZE := 12
const SKIP_BAR := Vector2(70, 4)

var scenes: TDCutscenePlayer
## 0 (clear) to 1 (black).
var fade := 0.0
## 0 (no bars) to 1 (full bars).
var bars := 0.0
## The line being said, who says it and their portrait (null for none).
var speaker := ""
var portrait: Texture2D
var text := ""
## How many characters of `text` show so far (they appear like TDDialogueWindow's).
var _shown := 0.0

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func begin() -> void:
	fade = 0.0
	bars = 0.0
	hide_speech()
	visible = true

func end() -> void:
	visible = false
	fade = 0.0
	bars = 0.0
	hide_speech()

func say(who: String, picture: Texture2D, line: String) -> void:
	speaker = who
	portrait = picture
	text = line
	_shown = 0.0

func hide_speech() -> void:
	text = ""
	speaker = ""
	portrait = null

func speaking() -> bool:
	return text != ""

func typing() -> bool:
	return _shown < text.length()

func finish_typing() -> void:
	_shown = text.length()

func _process(delta: float) -> void:
	if not visible:
		return
	if typing():
		_shown = minf(_shown + TDDialogueWindow.TYPE_SPEED * delta, text.length())
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		scenes.advance()
		accept_event()

func bar_height() -> float:
	return size.y * BAR_SHARE * bars

func _draw() -> void:
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))
	var bar_h := bar_height()
	if bar_h > 0.5:
		draw_rect(Rect2(0, 0, size.x, bar_h), Color.BLACK)
		draw_rect(Rect2(0, size.y - bar_h, size.x, bar_h), Color.BLACK)
	if speaking():
		_draw_speech(bar_h)
	if scenes and scenes.def and scenes.def.skippable:
		_draw_skip_hint(bar_h)

## The lines of `text` wrapped to the frame.
func _lines(frame_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var w := frame_w - (TDDialogueWindow.TEXT_LEFT + TDDialogueWindow.TEXT_RIGHT) * FRAME_SCALE
	for paragraph in text.split("\n"):
		out.append_array(DrawUtil.wrap_text(Game.ui_font, paragraph, TEXT_SIZE, w))
	return out

func speech_rect() -> Rect2:
	var w := minf(SPEECH_W, size.x - 32.0)
	var natural := UiSkin.size_of(UiSkin.DIALOGUE_FRAME[0]).y * FRAME_SCALE
	var lines := _lines(w).size()
	var h := maxf(natural, TDDialogueWindow.NAME_H + lines * (TDDialogueWindow.LINE_H + 2) \
			+ (TDDialogueWindow.TEXT_TOP + TDDialogueWindow.TEXT_BOTTOM) * FRAME_SCALE)
	var bottom := size.y - maxf(bar_height(), 0.0) - SPEECH_GAP
	return Rect2((size.x - w) / 2.0, bottom - h, w, h)

func _draw_speech(_bar_h: float) -> void:
	var frame := speech_rect()
	UiSkin.draw_panel(self, UiSkin.DIALOGUE_FRAME, frame, FRAME_SCALE)
	var niche_box := TDDialogueWindow.NICHE
	var niche := Rect2(frame.position + Vector2(niche_box.x, niche_box.y) * FRAME_SCALE, Vector2.ZERO)
	niche.end = Vector2(frame.position.x + niche_box.z * FRAME_SCALE, frame.end.y - niche_box.w * FRAME_SCALE)
	if portrait:
		var bust := TDWindow.fit(portrait, niche.grow(-4))
		var big := bust.size * TDDialogueWindow.BUST_SCALE
		bust = Rect2(Vector2(bust.get_center().x - big.x / 2.0, bust.end.y - big.y), big)
		draw_texture_rect(portrait, bust, false)
	var left := frame.position.x + TDDialogueWindow.TEXT_LEFT * FRAME_SCALE
	var y := frame.position.y + TDDialogueWindow.TEXT_TOP * FRAME_SCALE
	if speaker != "":
		DrawUtil.text(self, Game.num_font, Vector2(left, y), speaker, TDDialogueWindow.NAME_SIZE, Palette.SUN, 1, 4, Palette.NIGHT)
		var name_w := DrawUtil.text_width(Game.num_font, speaker, TDDialogueWindow.NAME_SIZE)
		draw_line(Vector2(left, y + 7), Vector2(left + name_w + 24, y + 7), Color(Palette.GOLD_TRIM, 0.6), 1.5)
	y += TDDialogueWindow.NAME_H
	var left_to_show := int(_shown)
	for l in _lines(frame.size.x):
		if left_to_show > 0:
			DrawUtil.text(self, Game.ui_font, Vector2(left, y), l.left(left_to_show), TEXT_SIZE, Palette.MIST, 1, 3, Palette.NIGHT)
		left_to_show -= l.length() + 1
		y += TDDialogueWindow.LINE_H + 2
	if not typing():
		# a small bobbing arrow: press on
		var bob := sin(Time.get_ticks_msec() / 180.0) * 2.0
		var tip := Vector2(frame.end.x - TDDialogueWindow.TEXT_RIGHT * FRAME_SCALE, frame.end.y - TDDialogueWindow.TEXT_BOTTOM * FRAME_SCALE + bob)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, -9), tip + Vector2(7, -9), tip]), Palette.SUN)

func _draw_skip_hint(bar_h: float) -> void:
	var label := "Hold %s to skip" % TDStatusBar._key_name("pause")
	var y := maxf(bar_h / 2.0 + 4.0, 20.0)
	var right := size.x - 18.0
	DrawUtil.text(self, Game.ui_font, Vector2(right, y), label, SKIP_SIZE, Color(Palette.MIST, 0.75), -1, 3, Palette.NIGHT)
	var held := float(scenes.skip_t) / TDCutscenePlayer.SKIP_HOLD
	if held > 0.0:
		var bar := Rect2(Vector2(right - SKIP_BAR.x, y + 6), SKIP_BAR)
		draw_rect(bar, Color(Palette.NIGHT, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * held, bar.size.y)), Palette.SUN)
