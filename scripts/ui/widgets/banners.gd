class_name TDBanners
extends Control
## Fanfares over the game: a ribbon in the middle of the screen when you complete a quest or
## advance to a new job, and a toast near the top for an achievement. It notices quests and
## jobs from your character as the server refreshes it; TDWorld.show_achievement calls
## `achievement`. Everything takes turns, one at a time and never over the map-name banner:
## ribbons first, then toasts. Level ups have their own ribbon on the level up effect
## (EffectDef.caption_art).

## How long a ribbon and a toast stay up, in frames.
const RIBBON_TICKS := 150
const TOAST_TICKS := 240
## Where they show, and how wide.
const RIBBON_Y := 190.0
const RIBBON_W := {"dialogue/quest_complete_banner": 300.0, "dialogue/job_advance_banner": 380.0}
const TOAST_SIZE := Vector2(300, 54)
## The toast art's borders in texels (its star sits in the left one), and how it's scaled.
const TOAST_MARGINS := Vector4(64, 16, 18, 16)
const TOAST_SCALE := 0.8

var world: TDWorld
## Ribbons waiting their turn, the first one showing: [art, line under it].
var ribbons: Array = []
## Achievements waiting, the first one showing: their Achievements.LIST entry.
var toasts: Array = []
var _ribbon_t := 0
var _toast_t := 0
## What your character had last time it changed (quests done, job), to notice news.
var _who := ""
var _done := 0
var _job := &""

func _ready() -> void:
	Game.character_changed.connect(_on_character_changed)

func _on_character_changed() -> void:
	var me := Game.me
	var playing := world != null and world.started
	if playing and me.name == _who:
		if me.quests.done.size() > _done:
			ribbon("dialogue/quest_complete_banner")
		if me.job and me.job.id != _job:
			ribbon("dialogue/job_advance_banner", me.job.display_name)
	_who = me.name if playing else ""
	_done = me.quests.done.size()
	_job = me.job.id if me.job else &""

## Shows a ribbon (a texture name) with an optional line under it. A ribbon that's already
## waiting is updated rather than shown twice.
func ribbon(art: String, line := "") -> void:
	for i in range(1, ribbons.size()):
		if ribbons[i][0] == art:
			ribbons[i] = [art, line]
			return
	ribbons.append([art, line])

## Shows an achievement's toast (an entry of Achievements.LIST).
func achievement(a: Dictionary) -> void:
	toasts.append(a)

## Whether the map-name banner is up: everything here waits for it.
func _waiting() -> bool:
	return world.banner_t > 0

func _process(_delta: float) -> void:
	visible = world != null and world.started
	queue_redraw()
	if not visible or _waiting():
		return
	if not ribbons.is_empty():
		_ribbon_t += 1
		if _ribbon_t >= RIBBON_TICKS:
			ribbons.pop_front()
			_ribbon_t = 0
	elif not toasts.is_empty():
		_toast_t += 1
		# with more waiting, each one gets less time
		if _toast_t >= (TOAST_TICKS if toasts.size() == 1 else TOAST_TICKS / 2):
			toasts.pop_front()
			_toast_t = 0

## Where the achievement toast's top is: where the map-name banner shows (they take turns).
func toast_top() -> float:
	return world.hud.overlay.banner_y - TOAST_SIZE.y / 2.0

## Takes every ribbon and toast down at once.
func clear() -> void:
	ribbons.clear()
	toasts.clear()
	_ribbon_t = 0
	_toast_t = 0

func _draw() -> void:
	if _waiting():
		return
	if not ribbons.is_empty():
		_draw_ribbon(ribbons[0][0], ribbons[0][1], _ribbon_t)
	elif not toasts.is_empty():
		_draw_toast(toasts[0], _toast_t, TOAST_TICKS if toasts.size() == 1 else TOAST_TICKS / 2)

## How far in (0 to 1) something that pops in over `ins` frames and fades over `outs` is.
static func _fade(t: int, total: int, ins: int, outs: int) -> float:
	return clampf(minf(t / float(ins), (total - t) / float(outs)), 0.0, 1.0)

func _draw_ribbon(art: String, line: String, t: int) -> void:
	var a := _fade(t, RIBBON_TICKS, 10, 30)
	var tex := UiSkin.tex(art)
	var w: float = RIBBON_W.get(art, 300.0) * (0.85 + 0.15 * minf(1.0, t / 10.0))
	var size := tex.get_size() * w / tex.get_width()
	var c := Vector2(TDWorld.VIEW.x / 2.0, RIBBON_Y)
	draw_texture_rect(tex, Rect2(c - size / 2.0, size), false, Color(1, 1, 1, a))
	if line != "":
		DrawUtil.text(self, Game.num_font, c + Vector2(0, size.y / 2.0 + 22), line, 22, Color(Palette.SUN, a), 0, 6, Color(Palette.NIGHT, a))

func _draw_toast(ach: Dictionary, t: int, total: int) -> void:
	var a := _fade(t, total, 12, 30)
	var r := Rect2(Vector2((TDWorld.VIEW.x - TOAST_SIZE.x) / 2.0, toast_top() + (1.0 - a) * 20.0), TOAST_SIZE)
	var sb := UiSkin.box("book/achievement_toast", TOAST_MARGINS.z, TOAST_MARGINS.y).duplicate() as StyleBoxTexture
	sb.texture_margin_left = TOAST_MARGINS.x
	sb.modulate_color = Color(1, 1, 1, a)
	UiSkin.draw_box(self, sb, r, TOAST_SCALE)
	var x := r.position.x + TOAST_MARGINS.x * TOAST_SCALE + 4
	DrawUtil.text(self, Game.ui_font, Vector2(x, r.position.y + 22), "Achievement unlocked", 11, Color(Palette.MUTED, a), 1, 3, Color(Palette.NIGHT, a))
	DrawUtil.text(self, Game.num_font, Vector2(x, r.position.y + 40), ach.get("title", ""), 17, Color(Palette.SUN, a), 1, 4, Color(Palette.NIGHT, a))
