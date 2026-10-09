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

var scroll := 0

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

func _row_rect(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + (i - scroll) * ROW_H, LIST_W, ROW_H - 2)

## The indices of the rows that fit in the list right now.
func _shown(count: int) -> Array:
	scroll = clampi(scroll, 0, maxi(0, count - ROWS))
	return range(scroll, mini(scroll + ROWS, count))

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
		var r := _row_rect(i)
		draw_row(r, q == selected or r.has_point(_hover))
		var ready := me.quests.status(q, me) == QuestLog.Status.READY
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + 6, r.end.y - 6), q.title, 12, Palette.SUN if ready else Palette.MIST, 1, 3, Palette.NIGHT)
	if quests.size() > ROWS:
		DrawUtil.text(self, Game.ui_font, Vector2(PAD + LIST_W, LIST_Y + ROWS * ROW_H + 8), "scroll for more (%d/%d)" % [scroll + 1, quests.size() - ROWS + 1], 10, Color(Palette.MIST, 0.6), -1)
	if selected:
		_draw_details(selected, Rect2(PAD + LIST_W + 14, LIST_Y - 4, size.x - LIST_W - PAD * 2 - 14, size.y - LIST_Y - PAD))

func _draw_details(q: QuestDef, box: Rect2) -> void:
	draw_row(box)
	var me := Game.me
	var x := box.position.x + 10
	var w := box.size.x - 20
	var y := box.position.y + 22
	DrawUtil.text(self, Game.num_font, Vector2(x, y), q.title, 15, Palette.SUN, 1, 3, Palette.NIGHT)
	y += 20
	var giver: NpcDef = Content.npcs.get(q.giver)
	var turn_in: NpcDef = Content.npcs.get(q.turn_in_npc())
	var who := "From %s" % (giver.display_name if giver else "?")
	if turn_in != giver and turn_in:
		who += " · hand in to %s" % turn_in.display_name
	DrawUtil.text(self, Game.ui_font, Vector2(x, y), who, 11, Palette.MUTED, 1)
	y += 8
	var text := q.offer_text if page == Page.AVAILABLE else q.progress_text
	for l in UiSkin.wrap_text(Game.ui_font, text, 11, w):
		y += 15
		DrawUtil.text(self, Game.ui_font, Vector2(x, y), l, 11, Color(Palette.MIST, 0.85), 1)
	y += 24
	for i in q.objectives.size():
		var o := q.objectives[i]
		var have := me.quests.progress(q, i, me) if me.quests.active.has(q.id) else (o.count if page == Page.DONE else 0)
		var col := Palette.GOOD if have >= o.count else Palette.MIST
		DrawUtil.text(self, Game.ui_font, Vector2(x, y), "• %s  %d/%d" % [o.describe(), have, o.count], 12, col, 1, 3, Palette.NIGHT)
		y += 18
	y += 6
	if q.min_level > 1:
		DrawUtil.text(self, Game.ui_font, Vector2(x, y), "Level %d+" % q.min_level, 11, Palette.MUTED, 1)
		y += 16
	for l in UiSkin.wrap_text(Game.ui_font, "Reward: %s" % q.describe_rewards(), 11, w):
		DrawUtil.text(self, Game.ui_font, Vector2(x, y), l, 11, Palette.SUN, 1)
		y += 15
	if page == Page.ACTIVE:
		draw_button(_forfeit_rect(), "Give up")

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
		scroll = clampi(scroll + (1 if button == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(0, listed().size() - ROWS))
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	var t := tab_at(at)
	if t >= 0:
		page = t as Page
		selected = null
		scroll = 0
		return
	var quests := listed()
	for i in _shown(quests.size()):
		if _row_rect(i).has_point(at):
			selected = quests[i]
			return
	if page == Page.ACTIVE and selected and _forfeit_rect().has_point(at):
		Net.ask(&"req_quest_forfeit", [selected.id])
