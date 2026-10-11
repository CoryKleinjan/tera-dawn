class_name TDSkillWindow
extends TDWindow
## The skill book (K): a tab for each job the character has been (Beginner, then their
## job), listing that job's skills with their levels. Unspent Skill Points show at the top;
## "+" spends one (the server checks it). Click a skill to read what it does now and at its
## next level; drag a learned skill's icon onto a quickslot to use it with that key.

const LIST_Y := 74.0
const ROW_H := 46.0
const ICON := 36.0
const ROWS := 5

var tab := 0
var selected: StringName = &""

func _init() -> void:
	super("Skills", Vector2(300, LIST_Y + ROWS * ROW_H + 150))

## The jobs with a tab, oldest first.
func jobs() -> Array[StringName]:
	var line := Game.me.job_line()
	line.reverse()
	return line

## The skills in the open tab, sorted by name.
func listed() -> Array[SkillDef]:
	var out: Array[SkillDef] = []
	var line := jobs()
	var job: StringName = line[clampi(tab, 0, line.size() - 1)]
	for s in Content.skills.values():
		if s.job == job and not s.innate:
			out.append(s)
	out.sort_custom(func(a: SkillDef, b: SkillDef) -> bool: return a.display_name < b.display_name)
	return out

func row_rect(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + i * ROW_H, size.x - PAD * 2, ROW_H - 4)

func _icon_rect(i: int) -> Rect2:
	var r := row_rect(i)
	return Rect2(r.position + Vector2(3, 3), Vector2(ICON, ICON))

func _draw_body() -> void:
	var line := jobs()
	tab = clampi(tab, 0, line.size() - 1)
	draw_tabs(line.map(func(id: StringName) -> String:
		var j: JobDef = Content.jobs.get(id)
		return j.display_name if j else String(id)), tab)
	DrawUtil.text(self, Game.ui_font, Vector2(size.x - PAD - CLOSE_SIZE - 8, 20), "Skill Points: %d" % Game.me.sp, 13,
		Palette.SUN if Game.me.sp > 0 else Palette.MIST, -1, 3, Palette.NIGHT)
	var skills := listed()
	if selected == &"" or not skills.any(func(s: SkillDef) -> bool: return s.id == selected):
		selected = skills[0].id if not skills.is_empty() else &""
	for i in mini(skills.size(), ROWS):
		var s := skills[i]
		var r := row_rect(i)
		var lvl := Game.me.skill_level(s)
		var on := s.id == selected
		draw_row(r, on or r.has_point(_hover))
		var ir := _icon_rect(i)
		draw_texture_rect(UiSkin.tex("skill_slot"), ir, false)
		if s.icon:
			draw_texture_rect(s.icon, fit(s.icon, ir.grow(-3)), false, Color.WHITE if lvl > 0 else Color(0.55, 0.55, 0.6, 0.8))
		DrawUtil.text(self, Game.ui_font, Vector2(ir.end.x + 8, r.position.y + 17), s.display_name, 14, Palette.SUN if lvl > 0 else Palette.MIST, 1, 3, Palette.NIGHT)
		DrawUtil.text(self, Game.ui_font, Vector2(ir.end.x + 8, r.position.y + 34), "Lv. %d / %d  ·  %s" % [lvl, s.max_level, SkillDef.KIND_NAMES[s.kind]], 11, Palette.MUTED, 1, 3, Palette.NIGHT)
		if Game.me.learn_problem(s) == "":
			plus_button(Vector2(r.end.x - 26, r.position.y + 11), learn.bind(s))
	_draw_details(Content.skills.get(selected), Vector2(PAD, LIST_Y + ROWS * ROW_H + 4))

## What the selected skill does now and at its next level.
func _draw_details(s: SkillDef, at: Vector2) -> void:
	if s == null:
		return
	var box := Rect2(at, Vector2(size.x - PAD * 2, size.y - at.y - PAD))
	draw_row(box)
	var y := at.y + 18
	for l in DrawUtil.wrap_text(Game.ui_font, s.description, 12, box.size.x - 16):
		DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), l, 12, Palette.MIST, 1, 3, Palette.NIGHT)
		y += 16
	var lvl := Game.me.skill_level(s)
	var now := s.describe_level(lvl)
	var next := s.describe_level(lvl + 1) if lvl < s.max_level else PackedStringArray()
	y += 4
	if not now.is_empty():
		for l in DrawUtil.wrap_text(Game.ui_font, "Now: " + ", ".join(now), 11, box.size.x - 16):
			DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), l, 11, Palette.SUN, 1, 3, Palette.NIGHT)
			y += 15
	if not next.is_empty():
		for l in DrawUtil.wrap_text(Game.ui_font, "Next: " + ", ".join(next), 11, box.size.x - 16):
			DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), l, 11, Palette.GOOD, 1, 3, Palette.NIGHT)
			y += 15
	var problem := Game.me.learn_problem(s)
	if problem != "" and lvl < s.max_level and Game.me.sp > 0:
		DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), problem, 11, Palette.WARN, 1, 3, Palette.NIGHT)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var skills := listed()
	for i in mini(skills.size(), ROWS):
		if row_rect(i).has_point(at):
			selected = skills[i].id

func _tab_clicked(i: int) -> void:
	tab = i

## Spends a Skill Point on `skill`.
func learn(skill: SkillDef) -> void:
	selected = skill.id
	Net.ask(&"req_learn_skill", [skill.id])

func _get_drag_data(at: Vector2) -> Variant:
	var skills := listed()
	for i in mini(skills.size(), ROWS):
		var s := skills[i]
		if _icon_rect(i).has_point(at) and s.is_active() and Game.me.skill_level(s) > 0:
			set_drag_preview(drag_preview(s.icon, ICON - 6, 1.0, false))
			return DragPayload.skill(s.id)
	return null
