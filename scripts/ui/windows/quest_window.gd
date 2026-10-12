class_name TDQuestWindow
extends TDWindow
## The quest log (Q): quests in progress, quests you could take (and who gives them), and
## quests you've finished. Click one to see its objectives and rewards; quests in progress
## can be given up here. A long list scrolls with the mouse wheel.

enum Page { ACTIVE, AVAILABLE, DONE }
const PAGE_NAMES := ["In progress", "Available", "Done"]
const LIST_Y := 68.0
const ROW_H := 24.0
const LIST_W := 200.0
const ROWS := 11
## Pixels per art pixel of the row art.
const ROW_SCALE := (ROW_H - 2) / 39.0
## The marker shown on each quest's row, as over the NPC (WorldSkin.QUEST_MARKERS).
const ROW_MARKERS := {QuestLog.Status.AVAILABLE: "!", QuestLog.Status.ACTIVE: "...", QuestLog.Status.READY: "?"}

var list := ScrollList.new(Vector2(PAD, LIST_Y), LIST_W, ROW_H, 2, ROWS)

var page := Page.ACTIVE
var selected: QuestDef

func _init() -> void:
	super("Quests", Vector2(500, 360))

## The quests on the open page.
func listed() -> Array[QuestDef]:
	var me := Game.me
	var out: Array[QuestDef] = []
	for q: QuestDef in Content.quests.values():
		var s := me.quests.status(q, me)
		var on_page := (page == Page.ACTIVE and s in [QuestLog.Status.ACTIVE, QuestLog.Status.READY]) \
			or (page == Page.AVAILABLE and s == QuestLog.Status.AVAILABLE) \
			or (page == Page.DONE and me.quests.done.has(q.id))
		if on_page:
			out.append(q)
	return out

func row_rect(i: int) -> Rect2:
	return list.row_rect(i)

## The indices of the rows that fit in the list right now.
func _shown(count: int) -> Array:
	list.clamp_to(count)
	return list.shown(count)

func _forfeit_rect() -> Rect2:
	return Rect2(size.x - PAD - 110, size.y - PAD - 32, 110, 32)

func _draw_body() -> void:
	draw_tabs(PAGE_NAMES, page)
	var quests := listed()
	if not selected in quests:
		selected = quests[0] if not quests.is_empty() else null
	if quests.is_empty():
		draw_hint(Vector2(PAD + 4, LIST_Y + 16), "Nothing here yet.")
	var me := Game.me
	for i in _shown(quests.size()):
		var q := quests[i]
		var r := row_rect(i)
		var lit := q == selected or r.has_point(_hover)
		UiSkin.draw_box(self, UiSkin.option_row(lit), r, ROW_SCALE)
		var status := me.quests.status(q, me)
		var ready := status == QuestLog.Status.READY
		var col := Palette.INK if lit else (Palette.SUN if ready else Palette.MIST)
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + 12, r.end.y - 6), q.title, 12, col, 1, 0 if lit else 3, Palette.NIGHT)
		if ROW_MARKERS.has(status):
			WorldSkin.draw_quest_marker(self, Vector2(r.end.x - 14, r.end.y - 1), ROW_MARKERS[status], 20)
	list.draw_more(self, quests.size())
	if selected:
		_draw_details(selected, Rect2(PAD + LIST_W + 14, LIST_Y - 4, size.x - LIST_W - PAD * 2 - 14, size.y - LIST_Y - PAD))

func _draw_details(q: QuestDef, box: Rect2) -> void:
	draw_row(box)
	var x := box.position.x + 10
	var y := box.position.y + 22
	DrawUtil.text(self, Game.num_font, Vector2(x, y), q.title, 15, Palette.SUN, 1, 3, Palette.NIGHT)
	var bottom := (_forfeit_rect().position.y if page == Page.ACTIVE else box.end.y) - 8
	for l in detail_lines(q, box.size.x - 20, bottom - y):
		y += l[0]
		DrawUtil.text(self, Game.ui_font, Vector2(x, y), l[1], l[2], l[3], 1, l[4], Palette.NIGHT)
	if page == Page.ACTIVE:
		draw_button(_forfeit_rect(), "Give up")

## The lines under a quest's title, each [space above it, text, size, colour, outline], fitting
## in `room` pixels at most `w` wide: who gives it, the story, the objectives, the level and
## the reward. When it's too long the story is cut short ("…"), never the rest.
func detail_lines(q: QuestDef, w: float, room: float) -> Array:
	var me := Game.me
	var giver: NpcDef = Content.npcs.get(q.giver)
	var turn_in: NpcDef = Content.npcs.get(q.turn_in_npc())
	var who := "From %s" % (giver.display_name if giver else "?")
	if turn_in != giver and turn_in:
		who += " · hand in to %s" % turn_in.display_name
	var head := [[20.0, who, 11, Palette.MUTED, 0]]
	var story := []
	var text := q.offer_text if page == Page.AVAILABLE else q.progress_text
	for l in DrawUtil.wrap_text(Game.ui_font, text, 11, w):
		story.append([15.0 if story.size() > 0 else 23.0, l, 11, Color(Palette.MIST, 0.85), 0])
	var tail := []
	for i in q.objectives.size():
		var o := q.objectives[i]
		var have := me.quests.progress(q, i, me) if me.quests.active.has(q.id) else (o.count if page == Page.DONE else 0)
		var col := Palette.GOOD if have >= o.count else Palette.MIST
		tail.append([24.0 if i == 0 else 18.0, "• %s  %d/%d" % [o.describe(), have, o.count], 12, col, 3])
	var gap := 30.0 if tail.is_empty() else 24.0
	if q.min_level > 1:
		tail.append([gap, "Level %d+" % q.min_level, 11, Palette.MUTED, 0])
		gap = 16.0
	for l in DrawUtil.wrap_text(Game.ui_font, "Reward: %s" % q.describe_rewards(), 11, w):
		tail.append([gap, l, 11, Palette.SUN, 0])
		gap = 15.0
	var used := 0.0
	for l in head + tail:
		used += l[0]
	while not story.is_empty() and used + _height(story) > room:
		story.pop_back()
		if not story.is_empty():
			story[-1][1] = (story[-1][1] as String).trim_suffix(".") + "…"
	return head + story + tail

static func _height(lines: Array) -> float:
	var h := 0.0
	for l in lines:
		h += l[0]
	return h

func _click(at: Vector2, button: int, _double: bool) -> void:
	if list.wheel(button, listed().size()) or button != MOUSE_BUTTON_LEFT:
		return
	var quests := listed()
	list.clamp_to(quests.size())
	var row := list.row_at(at, quests.size())
	if row >= 0:
		selected = quests[row]
		return
	if page == Page.ACTIVE and selected and _forfeit_rect().has_point(at):
		Net.ask(&"req_quest_forfeit", [selected.id])

func _tab_clicked(i: int) -> void:
	page = i as Page
	selected = null
	list.scroll = 0
