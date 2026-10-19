class_name TDStatusBar
extends Control
## The bar along the bottom of the screen: buttons for the game windows and the Dawnshard
## purse (hearts and Mana are top left, TDVitals). The quickslots sit just above it (TDQuickslots). Drawn from
## the UI sheet's art.

const HEIGHT := 50.0
## Every piece on the bar (window buttons, Dawnshards) is
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
## UI sheet art for each window's button. A window without art yet gets a round button
## with the first letter of its action.
const WINDOW_ICONS := {"inventory": "bag_button", "equipment": "gear_button", "stats": "stats_button",
	"quests": "hud/quests_button", "worldmap": "hud/worldmap_button",
	"community": "hud/community_button", "collection": "hud/collection_button"}

var world: TDWorld
## What was last drawn (_drawn_state), and a count bumped when the keys are rebound.
var _drawn := []
var _keys_shown := 0

func _ready() -> void:
	Settings.changed.connect(func(section: SettingsSection) -> void:
		if section is Keybinds:
			_keys_shown += 1)

func _process(_delta: float) -> void:
	# the title screen shows no bar until there's a character to show
	visible = world != null and world.started
	# drawn again only when something it shows changed
	var state := _drawn_state()
	if state != _drawn:
		_drawn = state
		queue_redraw()

## Everything _draw shows, to tell when it needs drawing again.
func _drawn_state() -> Array:
	if not visible:
		return []
	var open := []
	for action in TDHud.WINDOW_ACTIONS:
		open.append(world.hud.windows[action].visible)
	return [size, Game.me.shards, open, _keys_shown]

func _draw() -> void:
	var w := size.x
	UiSkin.draw_box(self, _bar_box(), Rect2(0, 0, w, HEIGHT), HEIGHT / UiSkin.size_of("hud_bar").y)
	# window buttons
	for i in TDHud.WINDOW_ACTIONS.size():
		_window_button(TDHud.WINDOW_ACTIONS[i], _window_button_rect(i))
	# Dawnshards
	var icon := Rect2(w - 140, item_top(), 28, ITEM_H)
	UiSkin.draw_icon(self, "icon_dawnshard", icon)
	DrawUtil.text(self, Game.num_font, Vector2(icon.end.x + 4, band_center() + 5), str(Game.me.shards), 14, Palette.SUN, 1, 3, Palette.NIGHT)

## The middle of the band between the bar art's gold trim lines, in pixels from the top.
static func band_center() -> float:
	return (BAND_TOP + BAND_BOTTOM) / 2.0 * HEIGHT / UiSkin.size_of("hud_bar").y

## The top of every ITEM_H-tall piece on the bar.
static func item_top() -> float:
	return band_center() - ITEM_H / 2.0

## The scale that draws a piece of UI art ITEM_H tall.
static func fit(art: String) -> float:
	return ITEM_H / UiSkin.size_of(art).y

func _window_button_rect(i: int) -> Rect2:
	var left := size.x - 150 - TDHud.WINDOW_ACTIONS.size() * (ITEM_H + WINDOW_BUTTON_GAP)
	return Rect2(left + i * (ITEM_H + WINDOW_BUTTON_GAP), item_top(), ITEM_H, ITEM_H)

func _window_button(action: String, r: Rect2) -> void:
	var open: bool = world != null and world.hud.windows[action].visible
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
