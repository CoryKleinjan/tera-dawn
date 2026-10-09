class_name TDSkillWindow
extends TDWindow
## The skill book (K): a tab for each job the character has been (Beginner, then their
## job), listing that job's skills with their levels. Unspent Skill Points show at the top;
## "+" spends one (the server checks it). Click a skill to read what it does now and at its
## next level; drag a learned skill's icon onto a quickslot to use it with that key.

const LIST_Y := 74.0
const ROW := 46.0
const ICON := 36.0
const ROWS := 5

var tab := 0
var selected: StringName = &""
## The "+" buttons, rebuilt each draw: skill id -> Rect2.
var _plus := {}

func _init() -> void:
	super("Skills", Vector2(300, LIST_Y + ROWS * ROW + 150))

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

func _tab_rect(i: int, n: int) -> Rect2:
	var w := minf(110.0, (size.x - PAD * 2) / n)
	return Rect2(PAD + i * w, 36, w + 4, 26)

func row_rect(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + i * ROW, size.x - PAD * 2, ROW - 4)

func _icon_rect(i: int) -> Rect2:
	var r := row_rect(i)
	return Rect2(r.position + Vector2(3, 3), Vector2(ICON, ICON))

func _draw_body() -> void:
	var line := jobs()
	tab = clampi(tab, 0, line.size() - 1)
	for i in line.size():
		var j: JobDef = Content.jobs.get(line[i])
		draw_tab(_tab_rect(i, line.size()), j.display_name if j else String(line[i]), i == tab)
	DrawUtil.text(self, Game.ui_font, Vector2(size.x - PAD - CLOSE_SIZE - 8, 20), "Skill Points: %d" % Game.me.sp, 13,
		Palette.SUN if Game.me.sp > 0 else Palette.MIST, -1, 3, Palette.NIGHT)
	_plus.clear()
	var skills := listed()
	if selected == &"" or not skills.any(func(s: SkillDef) -> bool: return s.id == selected):
		selected = skills[0].id if not skills.is_empty() else &""
	for i in mini(skills.size(), ROWS):
		var s := skills[i]
		var r := row_rect(i)
		var lvl := Game.me.skill_level(s)
		var on := s.id == selected
		DrawUtil.round_rect(self, r, 6, Color(1, 0.85, 0.45, 0.2) if on else Color(Palette.NIGHT, 0.35 if r.has_point(_hover) else 0.22))
		var ir := _icon_rect(i)
		draw_texture_rect(UiSkin.tex("skill_slot"), ir, false)
		if s.icon:
			draw_texture_rect(s.icon, fit(s.icon, ir.grow(-3)), false, Color.WHITE if lvl > 0 else Color(0.55, 0.55, 0.6, 0.8))
		DrawUtil.text(self, Game.ui_font, Vector2(ir.end.x + 8, r.position.y + 17), s.display_name, 14, Palette.SUN if lvl > 0 else Palette.MIST, 1, 3, Palette.NIGHT)
		DrawUtil.text(self, Game.ui_font, Vector2(ir.end.x + 8, r.position.y + 34), "Lv. %d / %d  ·  %s" % [lvl, s.max_level, SkillDef.KIND_NAMES[s.kind]], 11, Color("c9b8d9"), 1, 3, Palette.NIGHT)
		if Game.me.learn_problem(s) == "":
			var pr := Rect2(r.end.x - 26, r.position.y + 11, 20, 20)
			_plus[s.id] = pr
			draw_texture_rect(UiSkin.tex("stat_plus"), pr, false, Color(1.25, 1.2, 1.1) if pr.has_point(_hover) else Color.WHITE)
	_draw_details(Content.skills.get(selected), Vector2(PAD, LIST_Y + ROWS * ROW + 4))

## What the selected skill does now and at its next level.
func _draw_details(s: SkillDef, at: Vector2) -> void:
	if s == null:
		return
	var box := Rect2(at, Vector2(size.x - PAD * 2, size.y - at.y - PAD))
	DrawUtil.round_rect(self, box, 6, Color(Palette.NIGHT, 0.4))
	var y := at.y + 18
	for l in UiSkin.wrap_text(Game.ui_font, s.description, 12, box.size.x - 16):
		DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), l, 12, Palette.MIST, 1, 3, Palette.NIGHT)
		y += 16
	var lvl := Game.me.skill_level(s)
	var now := s.describe_level(lvl)
	var next := s.describe_level(lvl + 1) if lvl < s.max_level else PackedStringArray()
	y += 4
	if not now.is_empty():
		for l in UiSkin.wrap_text(Game.ui_font, "Now: " + ", ".join(now), 11, box.size.x - 16):
			DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), l, 11, Palette.SUN, 1, 3, Palette.NIGHT)
			y += 15
	if not next.is_empty():
		for l in UiSkin.wrap_text(Game.ui_font, "Next: " + ", ".join(next), 11, box.size.x - 16):
			DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), l, 11, Color("8cf0a6"), 1, 3, Palette.NIGHT)
			y += 15
	var problem := Game.me.learn_problem(s)
	if problem != "" and lvl < s.max_level and Game.me.sp > 0:
		DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), problem, 11, Color("ffb38a"), 1, 3, Palette.NIGHT)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var line := jobs()
	for i in line.size():
		if _tab_rect(i, line.size()).has_point(at):
			tab = i
			return
	for id in _plus:
		if _plus[id].has_point(at):
			learn(Content.skills[id])
			return
	var skills := listed()
	for i in mini(skills.size(), ROWS):
		if row_rect(i).has_point(at):
			selected = skills[i].id

## Spends a Skill Point on `skill`.
func learn(skill: SkillDef) -> void:
	selected = skill.id
	Net.ask(&"req_learn_skill", [skill.id])

func _get_drag_data(at: Vector2) -> Variant:
	var skills := listed()
	for i in mini(skills.size(), ROWS):
		var s := skills[i]
		if _icon_rect(i).has_point(at) and s.is_active() and Game.me.skill_level(s) > 0:
			var preview := TextureRect.new()
			preview.texture = s.icon
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.size = Vector2(ICON, ICON) - Vector2(6, 6)
			preview.position = -preview.size / 2.0
			var holder := Control.new()
			holder.add_child(preview)
			set_drag_preview(holder)
			return {"from": "skills", "id": s.id}
	return null
