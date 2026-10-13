class_name TDHud
extends CanvasLayer
## The screen UI: the status bar (level, HP, MP, EXP, skills, Dawnshards), the in-game
## overlay, the game windows (inventory, equipment, character), the game menu (Esc) and the
## settings screen. It shows and hides the title screen (TDTitleScreen) and handles Esc.
## Art comes from UiSkin.

## Input actions that open and close a window, in the order the status bar shows them.
const WINDOW_ACTIONS: Array[String] = ["inventory", "equipment", "stats", "skills", "quests", "worldmap", "community", "collection"]

var world: TDWorld
var overlay: TDOverlay
var status: TDStatusBar
var quickslots: TDQuickslots
var tracker: TDQuestTracker
## The title screen: the dimmed layer over the game that holds the title card, character
## select, the character creator, the game menu and the settings screen. While it's showing,
## the game ignores play keys.
var title: TDTitleScreen
var game_menu: TDGameMenu
var settings_menu: TDSettingsMenu
## What the settings screen goes back to: the title card or the game menu.
var _settings_from: Control
## The HUD pieces over the scene's right side (the quickslots, the quest tracker) fade to
## SEE_THROUGH while the hero or an NPC within SEE_THROUGH_RANGE of them is behind one, at
## SEE_THROUGH_SPEED (alpha a second).
const SEE_THROUGH := 0.25
const SEE_THROUGH_SPEED := 4.0
const SEE_THROUGH_RANGE := 400.0
## The controls, which follow the player's keybinds, for a new character's first moments
## (the full list is in Settings > Controls): in town the keys for getting about, talking and
## the windows, and on their first field the keys for fighting. Each shows for
## FIRST_HINT_TIME seconds, counted only while no window is open over the game.
var keys_help: Label
## The two first-time hints: in a town, and on a hunting field.
enum Hint { TOWN, FIELD }
## How long each first-time hint stays up, and where it sits.
const FIRST_HINT_TIME := 40.0
const FIRST_HINT_Y := 138.0
## Hint -> its text, built from the player's keybinds (_update_keys_help).
var hint_texts := {}
## Hint -> how long it has shown so far.
var _hint_t := {Hint.TOWN: 0.0, Hint.FIELD: 0.0}
## The character the first-time hints are for: one that was level 1 when it came into the
## game ("" for none, so an old character never sees them).
var _hint_for := ""
var ui_theme: Theme
## Holds the windows so raising one never lifts it above the tooltip or the title menu.
var window_layer: Control
## action -> TDWindow
var windows := {}
var tooltip: TDItemTooltip
var chat: TDChat
var invites: TDInvites
var prompt: TDPrompt
## A yes-or-no question while playing ("Sell Iron Helm for 400 Dawnshards?").
var confirm: TDConfirm
## The invisible button over the minimap that opens the world map.
var minimap_button: Button
## Quest complete, job advance and achievement pop-ups.
var banners: TDBanners
## The game menu's button in the top left corner (shown while playing).
var menu_cog: TextureButton

func _ready() -> void:
	layer = 10
	ui_theme = Theme.new()
	ui_theme.default_font = Game.ui_font
	ui_theme.default_font_size = 14
	UiStyle.use_cursor()

	overlay = TDOverlay.new()
	overlay.world = world
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	tracker = TDQuestTracker.new()
	tracker.world = world
	add_child(tracker)
	status = TDStatusBar.new()
	status.world = world
	status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -TDStatusBar.HEIGHT
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(status)
	quickslots = TDQuickslots.new()
	quickslots.world = world
	quickslots.hud = self
	add_child(quickslots)
	chat = TDChat.new()
	chat.world = world
	add_child(chat)
	_build_windows()
	invites = TDInvites.new()
	add_child(invites)
	prompt = TDPrompt.new()
	add_child(prompt)
	confirm = TDConfirm.new()
	confirm.theme = ui_theme
	confirm.hide()
	add_child(confirm)
	banners = TDBanners.new()
	banners.world = world
	banners.set_anchors_preset(Control.PRESET_FULL_RECT)
	banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banners)
	# clicking the minimap opens the world map
	var minimap := Button.new()
	minimap_button = minimap
	minimap.flat = true
	minimap.focus_mode = Control.FOCUS_NONE
	minimap.position = TDOverlay.minimap_rect().position
	minimap.size = TDOverlay.minimap_rect().size
	minimap.tooltip_text = "World map (W)"
	minimap.pressed.connect(func() -> void:
		if world.started:
			toggle_window("worldmap"))
	add_child(minimap)
	move_child(minimap, window_layer.get_index())
	_build_menu_button()
	_build_title()

## The window changed shape (TDWorld.VIEW): move the pieces pinned to the right and bottom
## edges, and pull open windows back into view.
func fit_view() -> void:
	if quickslots == null:
		return
	quickslots.fit_view()
	tracker.fit_view()
	chat.fit_view()
	minimap_button.position = TDOverlay.minimap_rect().position
	for w: TDWindow in windows.values():
		w.keep_on_screen()

## The cog in the top left corner: the game menu, for playing with the mouse (Esc does the same).
func _build_menu_button() -> void:
	var cog := TextureButton.new()
	cog.texture_normal = UiSkin.tex("hud/menu_button")
	cog.ignore_texture_size = true
	cog.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	cog.focus_mode = Control.FOCUS_NONE
	cog.position = TDOverlay.MENU_BUTTON.position
	cog.size = TDOverlay.MENU_BUTTON.size
	cog.tooltip_text = "Menu (Esc)"
	cog.mouse_entered.connect(func() -> void: cog.self_modulate = UiSkin.LIT)
	cog.mouse_exited.connect(func() -> void: cog.self_modulate = Color.WHITE)
	cog.pressed.connect(func() -> void:
		if world.started and not title.visible:
			show_title(true))
	add_child(cog)
	move_child(cog, window_layer.get_index())
	menu_cog = cog

func _process(delta: float) -> void:
	menu_cog.visible = world != null and world.started
	# the minimap (drawn by the overlay) only shows once there's a character
	minimap_button.visible = world != null and world.started
	_show_first_hints(delta)

## The first-time controls, for a brand-new character: the town hint while they're in a town,
## the field hint on their first field. Hidden (and its time paused) behind any window, so it
## never covers a dialogue.
func _show_first_hints(delta: float) -> void:
	if world == null or not world.started:
		_hint_for = ""
		keys_help.hide()
		return
	if _hint_for != Game.me.name:
		# a new character to hint for: start both hints again
		_hint_for = Game.me.name if Game.me.level == 1 else ""
		for kind in _hint_t:
			_hint_t[kind] = 0.0
	var kind := hint_kind()
	var t: float = _hint_t[kind]
	keys_help.visible = _hint_for != "" and t < FIRST_HINT_TIME and not title.visible and not any_window_open()
	if not keys_help.visible:
		return
	t += delta
	_hint_t[kind] = t
	keys_help.text = hint_texts[kind]
	keys_help.modulate.a = clampf((FIRST_HINT_TIME - t) / 2.0, 0.0, 1.0) * clampf(t / 0.5, 0.0, 1.0)
	keys_help.reset_size()
	keys_help.position = Vector2((TDWorld.VIEW.x - keys_help.size.x) / 2.0, FIRST_HINT_Y)

## Which first-time hint fits the map you're on.
func hint_kind() -> Hint:
	return Hint.TOWN if world.map.town else Hint.FIELD

## Fades a HUD piece toward see-through while it covers someone (covers_people), and back.
func fade_over_people(piece: Control, delta: float) -> void:
	var target := SEE_THROUGH if covers_people(piece.get_global_rect()) else 1.0
	piece.modulate.a = move_toward(piece.modulate.a, target, SEE_THROUGH_SPEED * delta)

## Whether screen rect `r` covers the hero or an NPC near them.
func covers_people(r: Rect2) -> bool:
	if world == null or not world.started or r.size == Vector2.ZERO:
		return false
	var p := world.player
	if r.intersects(screen_rect(world.drawn(p), Vector2(TDPlayer.WIDTH, TDPlayer.HEIGHT), TDPlayer.Z)):
		return true
	for n in world.npcs():
		if absf(n.position.x - p.position.x) <= SEE_THROUGH_RANGE and r.intersects(screen_rect(n.position, n.body_size(), TDStage.Z_NPC)):
			return true
	return false

## Where someone standing at `feet` (game pixels), `body` big, appears on the screen.
func screen_rect(feet: Vector2, body: Vector2, z: float) -> Rect2:
	var top_left := world.stage.screen(feet + Vector2(-body.x / 2.0, -body.y), z)
	var bottom_right := world.stage.screen(feet + Vector2(body.x / 2.0, 0.0), z)
	return Rect2(top_left, bottom_right - top_left).abs()

## Whether any window (a game window, a dialogue, a shop...) is open over the game.
func any_window_open() -> bool:
	for w: TDWindow in windows.values():
		if w.visible:
			return true
	return false

func _build_windows() -> void:
	window_layer = Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window_layer)
	var view := TDWorld.VIEW
	var inventory := TDInventoryWindow.new()
	inventory.position = Vector2(view.x - inventory.size.x - 16, 70)
	var equipment := TDEquipmentWindow.new()
	equipment.position = Vector2(inventory.position.x - equipment.size.x - 10, 70)
	var stats := TDStatsWindow.new()
	stats.position = Vector2(16, 50)
	var quests := TDQuestWindow.new()
	quests.position = Vector2(16, 120)
	var worldmap := TDWorldMapWindow.new()
	worldmap.position = (view - worldmap.size) / 2.0 + Vector2(0, -20)
	var skills := TDSkillWindow.new()
	skills.position = Vector2(276, 56)
	# opened by talking to NPCs rather than by a key
	var dialogue := TDDialogueWindow.new()
	var shop := TDShopWindow.new()
	var storage := TDStorageWindow.new()
	var community := TDCommunityWindow.new()
	community.position = Vector2(300, 80)
	var collection := TDCollectionWindow.new()
	collection.position = Vector2(230, 60)
	# opened by other players
	var player := TDPlayerMenuWindow.new()
	var trade := TDTradeWindow.new()
	var player_shop := TDPlayerShopWindow.new()
	for pair in [["inventory", inventory], ["equipment", equipment], ["stats", stats], ["quests", quests], ["skills", skills], ["worldmap", worldmap],
			["community", community], ["collection", collection], ["dialogue", dialogue], ["shop", shop], ["storage", storage], ["player", player], ["trade", trade], ["player_shop", player_shop]]:
		var w: TDWindow = pair[1]
		w.hud = self
		windows[pair[0]] = w
		window_layer.add_child(w)
	tooltip = TDItemTooltip.new()
	tooltip.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip)

## Opens an NPC's dialogue window.
func open_dialogue(npc: TDNpc) -> void:
	windows["dialogue"].open(npc)

## Opens an NPC's shop, with the bag beside it.
func open_shop(npc: TDNpc) -> void:
	windows["shop"].open(npc)

## The server's latest on your trade ({} when it's over).
func show_trade(state: Dictionary) -> void:
	windows["trade"].show_state(state)

## A player shop you're looking at (or your own).
func show_player_shop(owner: int, owner_name: String, title_text: String, items: Array) -> void:
	windows["player_shop"].show_shop(owner, owner_name, title_text, items)

## Typing in the chat box or a text prompt: keys shouldn't move the player.
func typing() -> bool:
	return chat.typing() or prompt.visible or confirm.visible

## Minding your own shop: you stay put.
func selling() -> bool:
	return windows["player_shop"].selling()

func toggle_window(action: String) -> void:
	if windows.has(action):
		windows[action].toggle()

## Closes the window on top (Esc). False if none was open.
func close_top_window() -> bool:
	for i in range(window_layer.get_child_count() - 1, -1, -1):
		var w := window_layer.get_child(i) as TDWindow
		if w.visible:
			w.toggle()
			return true
	return false

## The open window under a screen point, or null.
func window_at(pos: Vector2) -> TDWindow:
	for i in range(window_layer.get_child_count() - 1, -1, -1):
		var w := window_layer.get_child(i) as TDWindow
		if w.visible and w.get_global_rect().has_point(pos):
			return w
	return null

## The title screen (TDTitleScreen), the first-time hints under it, and the game menu and
## settings screen on it.
func _build_title() -> void:
	title = TDTitleScreen.new()
	title.world = world
	title.theme = ui_theme
	add_child(title)
	title.settings_requested.connect(func() -> void: open_settings())
	title.quit_requested.connect(_quit)
	title.left_game.connect(func() -> void: show_title(false))

	# a new character's first steps: the controls (TDHud._show_first_hints)
	keys_help = Label.new()
	keys_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys_help.add_theme_font_size_override("font_size", 13)
	keys_help.add_theme_color_override("font_color", Palette.MIST)
	keys_help.add_theme_color_override("font_outline_color", Palette.NIGHT)
	keys_help.add_theme_constant_override("outline_size", 5)
	keys_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(Palette.NIGHT, 0.55)
	plate.set_corner_radius_all(10)
	plate.set_content_margin_all(10)
	keys_help.add_theme_stylebox_override("normal", plate)
	keys_help.hide()
	add_child(keys_help)
	move_child(keys_help, title.get_index())
	_update_keys_help()
	Settings.changed.connect(_on_settings_changed)

	# while playing: the game menu (Esc), on the title screen right over the title card, so
	# character select and its questions stay above it
	game_menu = TDGameMenu.new()
	game_menu.hide()
	title.add_child(game_menu)
	title.move_child(game_menu, title.title_card.get_index() + 1)
	game_menu.resumed.connect(resume)
	game_menu.settings_requested.connect(func() -> void: open_settings())
	game_menu.to_characters.connect(_on_to_characters)
	game_menu.logged_out.connect(title.log_out)
	game_menu.quit.connect(_quit)

	settings_menu = TDSettingsMenu.new()
	settings_menu.hide()
	title.add_child(settings_menu)
	title.move_child(settings_menu, game_menu.get_index() + 1)
	settings_menu.closed.connect(func() -> void:
		_settings_from.show()
		if _settings_from == game_menu:
			game_menu.open()
		else:
			title.focus_login())

## Esc menu: back to character select, still logged in.
func _on_to_characters() -> void:
	world.stop(true)
	game_menu.hide()
	title.show_characters()
	Net.leave_character()

func _quit() -> void:
	Net.stop()
	get_tree().quit()

func _on_settings_changed(section: SettingsSection) -> void:
	if section is Keybinds:
		_update_keys_help()

## The first-time hints, naming the player's own keys. The town hint: moving, jumping,
## talking, every window key and the menu. The field hint: fighting, picking up and the first
## quickslots (empty for a new character, so no skill is named).
func _update_keys_help() -> void:
	var k := func(action: String) -> String: return TDStatusBar._key_name(action)
	var slots := []
	for i in range(1, 5):
		slots.append(k.call("quick_%d" % i))
	var window_keys := []
	for action in WINDOW_ACTIONS:
		window_keys.append("%s %s" % [k.call(action), String(Keybinds.info(action)["label"]).to_lower()])
	hint_texts[Hint.TOWN] = "%s %s move and climb · %s jump · %s talks and enters portals\n%s\nEsc menu · %s fullscreen · Gamepads work too" % [
		k.call("move_left"), k.call("move_right"), k.call("jump"), k.call("move_up"), " · ".join(window_keys), k.call("toggle_fullscreen")]
	hint_texts[Hint.FIELD] = "%s attack · %s loot · %s… quickslots" % [k.call("attack"), k.call("loot"), ", ".join(slots)]
	keys_help.text = hint_texts[hint_kind() if world != null and world.map != null else Hint.TOWN]

## The title screen (not playing yet) or the game menu (playing).
func show_title(paused: bool) -> void:
	if settings_menu.visible:
		settings_menu.close()
	title.title_backdrop.visible = not paused
	title.show()
	if paused:
		title.title_card.hide()
		game_menu.open()
	else:
		game_menu.hide()
		title.show_title_card()

## Back to the game from the game menu.
func resume() -> void:
	game_menu.hide()
	title.hide()

## Esc. While playing: cancels a question, closes the top window, or opens the game menu, or closes it again.
## Before that, the title screen has it first (TDTitleScreen.escape): a question is cancelled,
## the creator goes back, and character select logs out.
func escape() -> void:
	if title.escape() or not world.started:
		return
	if confirm.visible:
		confirm.cancel()
		return
	if title.visible:
		if game_menu.visible:
			resume()
	elif not close_top_window():
		show_title(true)

## Opens the settings screen in place of the title card or the game menu.
func open_settings() -> void:
	_settings_from = game_menu if game_menu.visible else title.title_card
	_settings_from.hide()
	settings_menu.open()
