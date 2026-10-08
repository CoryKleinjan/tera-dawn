class_name TDStatusBar
extends Control
## The bar along the bottom of the screen: level badge, HP, MP and EXP, the skill slots
## with their cooldowns, and the Dawnshard purse. Drawn from the UI sheet's art.

const HEIGHT := 50.0

var world: TDWorld

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var w := size.x
	UiSkin.box("hud_bar", 22, 10).draw(get_canvas_item(), Rect2(0, 0, w, HEIGHT))
	# level badge
	var badge := UiSkin.tex("level_badge")
	var bs := 0.72
	var bpos := Vector2(14, (HEIGHT - badge.get_height() * bs) / 2.0)
	draw_texture_rect(badge, Rect2(bpos, badge.get_size() * bs), false)
	var c := bpos + badge.get_size() * bs / 2.0
	DrawUtil.text(self, Game.ui_font, c + Vector2(0, -5), "Lv", 9, Palette.MIST)
	DrawUtil.text(self, Game.num_font, c + Vector2(0, 11), str(Game.level), 17, Palette.SUN, 0, 4, Palette.NIGHT)
	# HP, MP, EXP
	var hp := Game.health
	var need := Game.xp_need()
	var x := 74.0
	UiSkin.draw_bar(self, "hp_frame", "fill_red", Vector2(x, 6), hp.fraction(), 0.95, "%d / %d" % [hp.hp, hp.max_hp])
	x += 165 * 0.95 + 6
	UiSkin.draw_bar(self, "mp_frame", "fill_blue", Vector2(x, 4), float(Game.mp) / Game.max_mp(), 0.95, "%d / %d" % [Game.mp, Game.max_mp()])
	x += 168 * 0.95 + 6
	UiSkin.draw_bar(self, "exp_frame", "fill_gold", Vector2(x, 10), float(Game.xp) / need, 1.0, "%.1f%%" % (100.0 * Game.xp / need))
	# skill slots
	x = w - 250
	for action in Game.SKILL_BINDINGS:
		_skill_slot(Content.skill(Game.SKILL_BINDINGS[action]), action, Vector2(x, 5))
		x += 48
	# Dawnshards
	var icon := UiSkin.tex("icon_dawnshard")
	draw_texture_rect(icon, Rect2(w - 140, 8, 36, 33), false)
	DrawUtil.text(self, Game.num_font, Vector2(w - 100, 32), str(Game.shards), 18, Palette.SUN, 1, 4, Palette.NIGHT)

func _skill_slot(skill: SkillDef, action: String, pos: Vector2) -> void:
	var s := 40.0
	var r := Rect2(pos, Vector2(s, s))
	draw_texture_rect(UiSkin.tex("skill_slot"), r, false)
	if skill and skill.icon:
		draw_texture_rect(skill.icon, r.grow(-3), false)
	var p := world.player if world else null
	if p and skill and p.cooldown > 0:
		var k := float(p.cooldown) / skill.cooldown
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(s - 6, (s - 6) * clampf(k, 0, 1))), Color(0.05, 0.02, 0.1, 0.6))
	if skill and Game.mp < skill.mp_cost:
		draw_rect(r.grow(-3), Color(0.05, 0.02, 0.15, 0.55))
	var key := _key_name(action)
	DrawUtil.text(self, Game.num_font, pos + Vector2(s - 4, s - 2), key, 12, Palette.MIST, -1, 4, Palette.NIGHT)

func _key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return ""
