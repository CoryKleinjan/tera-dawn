class_name TDStatusBar
extends Control
## The bar along the bottom of the screen: level badge, HP, MP and EXP, buttons for the
## game windows and the Dawnshard purse. The quickslots sit just above it (TDQuickslots). Drawn from
## the UI sheet's art.

const HEIGHT := 50.0
## Every piece on the bar (level badge, HP, MP and EXP bars, window buttons, Dawnshards) is
## ITEM_H tall and centred on the band between the art's two gold trim lines.
const ITEM_H := 26.0
## The band between the gold trim lines, in art pixels of the bar art (top and bottom row).
const BAND_TOP := 10.0
const BAND_BOTTOM := 43.0
const WINDOW_BUTTON_GAP := 2.0
## The bar art (art/source/ui_hud_bar.png): each end's brass sun cap and its dark rim, in
## art pixels. The art is drawn at one scale to fit HEIGHT, and the dawn-lit band between the caps
## repeats along the bar instead of stretching, so its gold trim stays sharp at any width.
const BAR_CAP := 38.0
## The level badge's left edge, just inside the brass end cap.
const BADGE_X := 40.0
## How much wider than their art the HP and MP bars are drawn, in pixels.
const HP_MP_EXTRA := 24.0
## The space between the badge and the bars, and between bars.
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
## What was last drawn (_drawn_state), and a count bumped when the keys are rebound.
var _drawn := []
var _keys_shown := 0

func _ready() -> void:
	Settings.changed.connect(func(section: SettingsSection) -> void:
		if section is Keybinds:
			_keys_shown += 1)

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
	# drawn again only when something it shows changed
	var state := _drawn_state()
	if state != _drawn:
		_drawn = state
		queue_redraw()

## Everything _draw shows, to tell when it needs drawing again.
func _drawn_state() -> Array:
	if not visible:
		return []
	var me := Game.me
	var open := []
	for action in TDHud.WINDOW_ACTIONS:
		open.append(world.hud.windows[action].visible)
		if has_points_waiting(action):  # the button's glow pulses
			open.append(Time.get_ticks_msec())
	return [size, me.level, me.health.hp, me.health.max_hp, me.mp, me.max_mp(), me.xp, me.shards,
		_trails["hp"][0], _trails["mp"][0], _flash, open, _keys_shown]

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
	UiSkin.draw_box(self, _bar_box(), Rect2(0, 0, w, HEIGHT), HEIGHT / UiSkin.size_of("hud_bar").y)
	# level badge
	var badge := badge_rect()
	draw_texture_rect(UiSkin.tex("level_badge"), badge, false)
	var c := badge.get_center()
	DrawUtil.text(self, Game.ui_font, c + Vector2(0, -3), "Lv", 7, Palette.MIST)
	DrawUtil.text(self, Game.num_font, c + Vector2(0, 9), str(Game.me.level), 11, Palette.SUN, 0, 3, Palette.NIGHT)
	# HP, MP, EXP
	var hp := Game.me.health
	WorldSkin.draw_bar(self, "hp_frame", "fill_red", bar_rect("hp_frame").position, hp.fraction(), fit("hp_frame"), "%d / %d" % [hp.hp, hp.max_hp], trail("hp"), 0.0, HP_MP_EXTRA)
	WorldSkin.draw_bar(self, "mp_frame", "fill_blue", bar_rect("mp_frame").position, float(Game.me.mp) / Game.me.max_mp(), fit("mp_frame"), "%d / %d" % [Game.me.mp, Game.me.max_mp()], trail("mp"), 0.0, HP_MP_EXTRA)
	var exp_fill := 1.0 if Game.me.at_max_level() else float(Game.me.xp) / Game.me.xp_need()
	WorldSkin.draw_bar(self, "exp_frame", "fill_gold", exp_bar_rect().position, exp_fill, fit("exp_frame"), exp_text(), 0.0, _flash / EXP_FLASH)
	# window buttons
	for i in TDHud.WINDOW_ACTIONS.size():
		_window_button(TDHud.WINDOW_ACTIONS[i], _window_button_rect(i))
	# Dawnshards
	var icon := Rect2(w - 140, item_top(), 28, ITEM_H)
	UiSkin.draw_icon(self, "icon_dawnshard", icon)
	DrawUtil.text(self, Game.num_font, Vector2(icon.end.x + 4, band_center() + 5), str(Game.me.shards), 14, Palette.SUN, 1, 3, Palette.NIGHT)

## What the EXP bar says: "42.5%" of the way to the next level, or "Max level" at the cap.
func exp_text() -> String:
	if Game.me.at_max_level():
		return MAX_LEVEL_TEXT
	return "%.1f%%" % (100.0 * Game.me.xp / Game.me.xp_need())

## The middle of the band between the bar art's gold trim lines, in pixels from the top.
static func band_center() -> float:
	return (BAND_TOP + BAND_BOTTOM) / 2.0 * HEIGHT / UiSkin.size_of("hud_bar").y

## The top of every ITEM_H-tall piece on the bar.
static func item_top() -> float:
	return band_center() - ITEM_H / 2.0

## The scale that draws a piece of UI art ITEM_H tall.
static func fit(art: String) -> float:
	return ITEM_H / UiSkin.size_of(art).y

func badge_rect() -> Rect2:
	return Rect2(Vector2(BADGE_X, item_top()), UiSkin.size_of("level_badge") * fit("level_badge"))

## Where a bar frame is drawn: HP after the badge, then MP, then EXP, BAR_GAP apart. HP and
## MP are HP_MP_EXTRA wider than their art.
func bar_rect(frame: String) -> Rect2:
	var x := badge_rect().end.x + BAR_GAP
	for f in ["hp_frame", "mp_frame", "exp_frame"]:
		var s := UiSkin.size_of(f) * fit(f)
		if f != "exp_frame":
			s.x += HP_MP_EXTRA
		if f == frame:
			return Rect2(Vector2(x, item_top()), s)
		x += s.x + BAR_GAP
	return Rect2()

## Where the EXP bar's frame is drawn.
func exp_bar_rect() -> Rect2:
	return bar_rect("exp_frame")

func _window_button_rect(i: int) -> Rect2:
	var left := size.x - 150 - TDHud.WINDOW_ACTIONS.size() * (ITEM_H + WINDOW_BUTTON_GAP)
	return Rect2(left + i * (ITEM_H + WINDOW_BUTTON_GAP), item_top(), ITEM_H, ITEM_H)

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
		DrawUtil.text(self, Game.num_font, r.get_center() + Vector2(0, 6), action.left(1).to_upper(), 16, Palette.SUN, 0, 4, Palette.NIGHT)
	DrawUtil.text(self, Game.num_font, r.end + Vector2(1, 0), _key_name(action), 9, Palette.MIST, -1, 3, Palette.NIGHT)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or not world.started:
		return
	for i in TDHud.WINDOW_ACTIONS.size():
		if _window_button_rect(i).has_point(mb.position):
			world.hud.toggle_window(TDHud.WINDOW_ACTIONS[i])
			accept_event()

## Whether a window's button should glow because there's essence to spend in it: Skills
## while it pays for a skill level.
static func has_points_waiting(action: String) -> bool:
	return action == "skills" and Game.me.skills.can_learn_any()

static func _key_name(action: String) -> String:
	if TDPad.using_pad and Keybinds.pad_text(action) != "":
		return Keybinds.pad_text(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return ""

## The bar art as a nine-patch whose middle repeats across rather than stretching.
static var _bar_sb: TDUiBox
static func _bar_box() -> TDUiBox:
	if _bar_sb == null:
		_bar_sb = UiSkin.box("hud_bar", BAR_CAP, 0).copy()
		_bar_sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return _bar_sb
