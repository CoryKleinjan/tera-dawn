class_name TDQuestTracker
extends Control
## Quests in progress and how far along they are, on a panel under the minimap. It lists at
## most QUESTS (QuestLog.tracked picks which; the quest log has them all) and fades to
## see-through while the hero or an NPC near them is behind it (TDHud.fade_over_people).

## The panel's width, and how many quests it lists.
const W := 176.0
const QUESTS := 3
## Space from the top of the panel to the first line, and between lines.
const TOP := 26.0
const LINE_H := 15.0

var world: TDWorld
## What it shows this frame: [text, indent, colour, size] per line.
var lines := []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit_view()

## Under the minimap (called again when the window is resized).
func fit_view() -> void:
	position = Vector2(TDWorld.VIEW.x - W - 8, TDOverlay.minimap_rect().end.y + 2)

func _process(delta: float) -> void:
	visible = world != null and world.started
	if not visible:
		return
	lines = _lines()
	size = Vector2(W, TOP + lines.size() * LINE_H if not lines.is_empty() else 0.0)
	world.hud.fade_over_people(self, delta)
	queue_redraw()

## The quests it shows, in order (see QuestLog.tracked).
func quests() -> Array[QuestDef]:
	return Game.me.quests.tracked(Game.me, world.map, QUESTS)

func _lines() -> Array:
	var me := Game.me
	var out := []
	for q in quests():
		out.append([q.title, 0, Palette.SUN, 12])
		if me.quests.is_ready(q, me):
			out.append(["Ready to hand in", 8, Palette.GOOD, 11])
		else:
			for i in q.objectives.size():
				var o := q.objectives[i]
				var have := me.quests.progress(q, i, me)
				out.append(["%s %d/%d" % [o.describe(), have, o.count], 8, Palette.GOOD if have >= o.count else Palette.MIST, 11])
	return out

func _draw() -> void:
	if lines.is_empty():
		return
	UiSkin.draw_panel(self, UiSkin.TRACKER_PANEL, Rect2(Vector2.ZERO, size), 0.6)
	var y := TOP
	for l in lines:
		DrawUtil.text(self, Game.ui_font, Vector2(12 + l[1], y), l[0], l[3], l[2], 1, 4, Palette.NIGHT)
		y += LINE_H
