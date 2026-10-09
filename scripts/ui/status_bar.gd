class_name TDStatusBar
extends Control
## The bar along the bottom of the screen: level badge, HP, MP and EXP, buttons for the
## game windows and the Dawnshard purse. The quickslots sit just above it (TDQuickslots). Drawn from
## the UI sheet's art.

const HEIGHT := 50.0
const WINDOW_BUTTON := 32.0
## UI sheet art for each window's button. A window without art yet gets a round button
## with the first letter of its action.
const WINDOW_ICONS := {"inventory": "bag_button", "equipment": "gear_button", "stats": "stats_button",
	"quests": "hud/quests_button", "skills": "hud/skills_button", "worldmap": "hud/worldmap_button",
	"community": "hud/community_button", "collection": "hud/collection_button"}

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
	DrawUtil.text(self, Game.num_font, c + Vector2(0, 11), str(Game.me.level), 17, Palette.SUN, 0, 4, Palette.NIGHT)
	# HP, MP, EXP
	var hp := Game.me.health
	var need := Game.me.xp_need()
	var x := 74.0
	UiSkin.draw_bar(self, "hp_frame", "fill_red", Vector2(x, 6), hp.fraction(), 0.95, "%d / %d" % [hp.hp, hp.max_hp])
	x += 165 * 0.95 + 6
	UiSkin.draw_bar(self, "mp_frame", "fill_blue", Vector2(x, 4), float(Game.me.mp) / Game.me.max_mp(), 0.95, "%d / %d" % [Game.me.mp, Game.me.max_mp()])
	x += 168 * 0.95 + 6
	UiSkin.draw_bar(self, "exp_frame", "fill_gold", Vector2(x, 10), float(Game.me.xp) / need, 1.0, "%.1f%%" % (100.0 * Game.me.xp / need))
	# window buttons
	for i in TDHud.WINDOW_ACTIONS.size():
		_window_button(TDHud.WINDOW_ACTIONS[i], _window_button_rect(i))
	# Dawnshards
	var icon := UiSkin.tex("icon_dawnshard")
	draw_texture_rect(icon, Rect2(w - 140, 8, 36, 33), false)
	DrawUtil.text(self, Game.num_font, Vector2(w - 100, 32), str(Game.me.shards), 18, Palette.SUN, 1, 4, Palette.NIGHT)

func _window_button_rect(i: int) -> Rect2:
	var left := size.x - 150 - TDHud.WINDOW_ACTIONS.size() * (WINDOW_BUTTON + 2)
	return Rect2(left + i * (WINDOW_BUTTON + 2), (HEIGHT - WINDOW_BUTTON) / 2.0, WINDOW_BUTTON, WINDOW_BUTTON)

func _window_button(action: String, r: Rect2) -> void:
	var open: bool = world != null and world.hud.windows[action].visible
	if open:
		DrawUtil.ellipse(self, r.get_center(), r.size.x / 2.0 + 2, r.size.y / 2.0 + 2, Color(Palette.SUN, 0.45))
	if WINDOW_ICONS.has(action):
		UiSkin.draw_icon(self, WINDOW_ICONS[action], r, Color(1.2, 1.15, 1.05) if open else Color.WHITE)
	else:
		DrawUtil.ellipse(self, r.get_center(), r.size.x / 2.0 - 2, r.size.y / 2.0 - 2, Palette.GOLD_TRIM)
		DrawUtil.ellipse(self, r.get_center(), r.size.x / 2.0 - 5, r.size.y / 2.0 - 5, Palette.PLUM)
		DrawUtil.text(self, Game.num_font, r.get_center() + Vector2(0, 7), action.left(1).to_upper(), 19, Palette.SUN, 0, 4, Palette.NIGHT)
	DrawUtil.text(self, Game.num_font, r.end + Vector2(0, -1), _key_name(action), 11, Palette.MIST, -1, 4, Palette.NIGHT)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or not world.started:
		return
	for i in TDHud.WINDOW_ACTIONS.size():
		if _window_button_rect(i).has_point(mb.position):
			world.hud.toggle_window(TDHud.WINDOW_ACTIONS[i])
			accept_event()

static func _key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return ""
