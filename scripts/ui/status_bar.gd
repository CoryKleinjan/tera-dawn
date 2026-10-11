class_name TDStatusBar
extends Control
## The bar along the bottom of the screen: level badge, HP, MP and EXP, buttons for the
## game windows and the Dawnshard purse. The quickslots sit just above it (TDQuickslots). Drawn from
## the UI sheet's art.

const HEIGHT := 50.0
const WINDOW_BUTTON := 30.0
const WINDOW_BUTTON_GAP := 2.0
## The EXP bar is drawn a little smaller than its art so the window buttons fit beside it.
const EXP_SCALE := 0.85
## The bar art (art/source/ui_hud_bar.png): each end's brass sun cap and its dark rim, in
## texels. The art is drawn at one scale to fit HEIGHT, and the dawn-lit band between the caps
## repeats along the bar instead of stretching, so its gold trim stays sharp at any width.
const BAR_CAP := 38.0
## The level badge: its left edge (just inside the gold end cap) and its scale.
const BADGE_X := 28.0
const BADGE_SCALE := 0.68
## The HP and MP bars: where HP starts, their scale, and the space between bars.
const HP_X := 76.0
const BAR_SCALE := 0.95
const BAR_GAP := 6.0
## UI sheet art for each window's button. A window without art yet gets a round button
## with the first letter of its action.
const WINDOW_ICONS := {"inventory": "bag_button", "equipment": "gear_button", "stats": "stats_button",
	"quests": "hud/quests_button", "skills": "hud/skills_button", "worldmap": "hud/worldmap_button",
	"community": "hud/community_button", "collection": "hud/collection_button"}

## Lost HP/MP stays on the bar as a pale chunk for TRAIL_HOLD seconds, then drains away at
## TRAIL_DRAIN of the bar a second. EXP gained lights the EXP bar for EXP_FLASH seconds.
const TRAIL_HOLD := 0.35
const TRAIL_DRAIN := 0.9
const EXP_FLASH := 0.5
## Shown on the EXP bar (and the stats window) at Character.MAX_LEVEL.
const MAX_LEVEL_TEXT := "Max level"

var world: TDWorld
## The pale chunk's end for HP and MP: [fraction, seconds until it drains].
var _trails := {"hp": [0.0, 0.0], "mp": [0.0, 0.0]}
var _xp_seen := -1
var _flash := 0.0

func _process(delta: float) -> void:
	# the title screen shows no bar until there's a character to show
	visible = world != null and world.started
	if visible:
		_follow("hp", Game.me.health.fraction(), delta)
		_follow("mp", float(Game.me.mp) / Game.me.max_mp(), delta)
		var xp := Game.me.xp + Game.me.level * 1000000  # a level-up counts as a gain too
		if _xp_seen >= 0 and xp > _xp_seen:
			_flash = EXP_FLASH
		_xp_seen = xp
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()

## Moves a bar's pale chunk: up at once when the bar fills, down slowly after a pause when
## it empties.
func _follow(bar: String, now: float, delta: float) -> void:
	var t: Array = _trails[bar]
	if now >= t[0]:
		t[0] = now
		t[1] = TRAIL_HOLD
	elif t[1] > 0.0:
		t[1] -= delta
	else:
		t[0] = maxf(now, t[0] - TRAIL_DRAIN * delta)

## The pale chunk's end of `bar` ("hp" or "mp"), as a fraction of the bar.
func trail(bar: String) -> float:
	return _trails[bar][0]

func _draw() -> void:
	var w := size.x
	var art := UiSkin.tex("hud_bar")
	UiSkin.draw_box(self, _bar_box(), Rect2(0, 0, w, HEIGHT), HEIGHT / art.get_height())
	# level badge
	var badge := UiSkin.tex("level_badge")
	var bs := BADGE_SCALE
	var bpos := Vector2(BADGE_X, (HEIGHT - badge.get_height() * bs) / 2.0)
	draw_texture_rect(badge, Rect2(bpos, badge.get_size() * bs), false)
	var c := bpos + badge.get_size() * bs / 2.0
	DrawUtil.text(self, Game.ui_font, c + Vector2(0, -5), "Lv", 9, Palette.MIST)
	DrawUtil.text(self, Game.num_font, c + Vector2(0, 11), str(Game.me.level), 17, Palette.SUN, 0, 4, Palette.NIGHT)
	# HP, MP, EXP
	var hp := Game.me.health
	UiSkin.draw_bar(self, "hp_frame", "fill_red", Vector2(HP_X, 6), hp.fraction(), BAR_SCALE, "%d / %d" % [hp.hp, hp.max_hp], trail("hp"))
	UiSkin.draw_bar(self, "mp_frame", "fill_blue", Vector2(_mp_x(), 4), float(Game.me.mp) / Game.me.max_mp(), BAR_SCALE, "%d / %d" % [Game.me.mp, Game.me.max_mp()], trail("mp"))
	var exp_r := exp_bar_rect()
	var exp_fill := 1.0 if Game.me.at_max_level() else float(Game.me.xp) / Game.me.xp_need()
	UiSkin.draw_bar(self, "exp_frame", "fill_gold", exp_r.position, exp_fill, EXP_SCALE, exp_text(), 0.0, _flash / EXP_FLASH)
	# window buttons
	for i in TDHud.WINDOW_ACTIONS.size():
		_window_button(TDHud.WINDOW_ACTIONS[i], _window_button_rect(i))
	# Dawnshards
	var icon := UiSkin.tex("icon_dawnshard")
	draw_texture_rect(icon, Rect2(w - 140, 8, 36, 33), false)
	DrawUtil.text(self, Game.num_font, Vector2(w - 100, 32), str(Game.me.shards), 18, Palette.SUN, 1, 4, Palette.NIGHT)

## What the EXP bar says: "42.5%" of the way to the next level, or "Max level" at the cap.
func exp_text() -> String:
	if Game.me.at_max_level():
		return MAX_LEVEL_TEXT
	return "%.1f%%" % (100.0 * Game.me.xp / Game.me.xp_need())

func _mp_x() -> float:
	return HP_X + UiSkin.tex("hp_frame").get_width() * BAR_SCALE + BAR_GAP

## Where the EXP bar's frame is drawn, vertically centred in the bar.
func exp_bar_rect() -> Rect2:
	var s := UiSkin.tex("exp_frame").get_size() * EXP_SCALE
	var x := _mp_x() + UiSkin.tex("mp_frame").get_width() * BAR_SCALE + BAR_GAP
	return Rect2(Vector2(x, (HEIGHT - s.y) / 2.0), s)

func _window_button_rect(i: int) -> Rect2:
	var left := size.x - 150 - TDHud.WINDOW_ACTIONS.size() * (WINDOW_BUTTON + WINDOW_BUTTON_GAP)
	return Rect2(left + i * (WINDOW_BUTTON + WINDOW_BUTTON_GAP), (HEIGHT - WINDOW_BUTTON) / 2.0, WINDOW_BUTTON, WINDOW_BUTTON)

func _window_button(action: String, r: Rect2) -> void:
	var open: bool = world != null and world.hud.windows[action].visible
	if has_points_waiting(action):
		var glow := 0.4 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
		DrawUtil.ellipse(self, r.get_center(), r.size.x / 2.0 + 6, r.size.y / 2.0 + 6, Color(Palette.SUN, glow * 0.5))
		DrawUtil.ellipse(self, r.get_center(), r.size.x / 2.0 + 3, r.size.y / 2.0 + 3, Color(Palette.SUN, glow))
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

## Whether a window's button should glow because there are points to spend in it: the
## Character window while you have Ability Points, Skills while you have Skill Points.
static func has_points_waiting(action: String) -> bool:
	match action:
		"stats":
			return Game.me.ap > 0
		"skills":
			return Game.me.sp > 0
	return false

static func _key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return ""

## The bar art as a nine-patch whose middle repeats across rather than stretching.
static var _bar_sb: StyleBoxTexture
static func _bar_box() -> StyleBoxTexture:
	if _bar_sb == null:
		_bar_sb = UiSkin.box("hud_bar", BAR_CAP, 0).duplicate()
		_bar_sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return _bar_sb
