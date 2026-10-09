class_name TDHud
extends CanvasLayer
## The screen UI: the status bar (level, HP, MP, EXP, skills, Dawnshards), the in-game
## overlay, the game windows (inventory, equipment, character), the title screen, the
## game menu (Esc) and the settings screen.
## Art comes from UiSkin.

## Input actions that open and close a window, in the order the status bar shows them.
const WINDOW_ACTIONS: Array[String] = ["inventory", "equipment", "stats", "skills", "quests", "worldmap", "community", "collection"]

var world: TDWorld
var overlay: TDOverlay
var status: TDStatusBar
var quickslots: TDQuickslots
## The dimmed layer over the game that holds the title card, the game menu, the settings
## screen and the character creator. While it's showing, the game ignores play keys.
var title: Control
## The title card (name, Play, Host, Join, Settings, Quit), hidden while the character
## creator, the game menu or the settings screen is showing.
var title_card: Control
## The key art behind the title screen.
var title_backdrop: TextureRect
var creator: TDCreator
var game_menu: TDGameMenu
var settings_menu: TDSettingsMenu
## What the settings screen goes back to: the title card or the game menu.
var _settings_from: Control
var start_panel: Control
var name_field: LineEdit
var address_field: LineEdit
## Shows why joining didn't work.
var message: Label
## The key hints under the title card, which follow the player's keybinds.
var keys_help: Label
var ui_theme: Theme
## Holds the windows so raising one never lifts it above the tooltip or the title menu.
var window_layer: Control
## action -> TDWindow
var windows := {}
var tooltip: TDItemTooltip
var chat: TDChat
var invites: TDInvites
var prompt: TDPrompt
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
	UiSkin.use_cursor()

	overlay = TDOverlay.new()
	overlay.world = world
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
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

func _process(_delta: float) -> void:
	menu_cog.visible = world != null and world.started
	# the minimap (drawn by the overlay) only shows once there's a character
	minimap_button.visible = world != null and world.started

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
	stats.position = Vector2(16, 56)
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
	return chat.typing() or prompt.visible

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

func _build_title() -> void:
	title = ColorRect.new()
	(title as ColorRect).color = Color(Palette.NIGHT, 0.45)
	title.theme = ui_theme
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title)
	# the key art behind the title screen and the creator (not behind the Esc menu)
	title_backdrop = TextureRect.new()
	title_backdrop.texture = UiSkin.tex("title_backdrop")
	title_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(title_backdrop)
	title_card = CenterContainer.new()
	title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(title_card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	title_card.add_child(col)

	var logo := TextureRect.new()
	logo.texture = UiSkin.tex("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(420, 124)
	col.add_child(logo)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	col.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	var blurb := Label.new()
	blurb.text = "The sun is rising over Dawnrise Meadow. Clear out the Dewlings, climb the ropes, and follow the portal east to Ember Hollow."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 500
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_color_override("font_color", Palette.MIST)
	blurb.add_theme_font_size_override("font_size", 16)
	inner.add_child(blurb)

	# before playing: a name, then single player, host, or join an address
	start_panel = VBoxContainer.new()
	start_panel.add_theme_constant_override("separation", 10)
	inner.add_child(start_panel)
	name_field = _field(Game.player_name, "Your character's name", CharacterStore.MAX_NAME)
	start_panel.add_child(_row([_label("Name"), name_field]))
	var play := _menu_button("Play")
	play.pressed.connect(_on_play)
	var host := _menu_button("Host")
	host.tooltip_text = "Play and let friends join you (port %d)" % Net.DEFAULT_PORT
	host.pressed.connect(_on_host)
	start_panel.add_child(_row([play, host]))
	address_field = _field(Game.last_address, "Server address", 64)
	var join := _menu_button("Join")
	join.pressed.connect(_on_join)
	start_panel.add_child(_row([_label("Server"), address_field, join]))
	message = _label("")
	message.add_theme_color_override("font_color", Palette.BAD)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.hide()
	start_panel.add_child(message)

	var settings := _menu_button("Settings")
	settings.pressed.connect(func() -> void: open_settings())
	var quit := _menu_button("Quit")
	quit.pressed.connect(_quit)
	inner.add_child(_row([settings, quit]))

	keys_help = Label.new()
	keys_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys_help.add_theme_font_size_override("font_size", 12)
	keys_help.add_theme_color_override("font_color", Palette.MUTED)
	inner.add_child(keys_help)
	_update_keys_help()
	Settings.changed.connect(_on_settings_changed)
	name_field.call_deferred("grab_focus")

	# while playing: the game menu (Esc)
	game_menu = TDGameMenu.new()
	game_menu.hide()
	title.add_child(game_menu)
	game_menu.resumed.connect(resume)
	game_menu.settings_requested.connect(func() -> void: open_settings())
	game_menu.left.connect(_on_leave)
	game_menu.quit.connect(_quit)

	settings_menu = TDSettingsMenu.new()
	settings_menu.hide()
	title.add_child(settings_menu)
	settings_menu.closed.connect(func() -> void:
		_settings_from.show()
		if _settings_from == game_menu:
			game_menu.open()
		else:
			name_field.grab_focus())

	# a name with no character yet: the creator takes the title card's place
	creator = TDCreator.new()
	creator.hide()
	title.add_child(creator)
	Net.new_character.connect(func(char_name: String) -> void:
		title_card.hide()
		creator.open(char_name))
	creator.created.connect(func(made: NewCharacter) -> void: Net.create(made))
	creator.cancelled.connect(func() -> void:
		Net.stop()
		_close_creator())

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(func(reason: String) -> void:
		_close_creator()
		_show_message(reason))
	Net.disconnected.connect(func() -> void:
		world.stop()
		show_title(false)
		_show_message("Lost the connection to the server."))

func _menu_button(text: String) -> Button:
	return UiSkin.menu_button(text)

func _field(text: String, hint: String, max_length: int) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	f.placeholder_text = hint
	f.max_length = max_length
	f.custom_minimum_size = Vector2(220, 40)
	return f

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 60
	l.add_theme_color_override("font_color", Palette.MIST)
	return l

func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for c in children:
		row.add_child(c)
	return row

## The name typed in, remembered for next time. "" (with a message) if it's no good.
func _chosen_name() -> String:
	var n := CharacterStore.clean_name(name_field.text)
	if n == "":
		_show_message("Please pick a name.")
		return ""
	Game.player_name = n
	Game.save_settings()
	return n

func _on_play() -> void:
	var n := _chosen_name()
	if n != "":
		Net.play_single(n)

func _on_host() -> void:
	var n := _chosen_name()
	if n != "":
		_show_message(Net.host(n))

func _on_join() -> void:
	var n := _chosen_name()
	var address := address_field.text.strip_edges()
	if n == "" or address == "":
		return
	Game.last_address = address
	Game.save_settings()
	var problem := Net.join(n, address)
	_show_message(problem if problem != "" else "Connecting to %s…" % address)

func _on_joined() -> void:
	_show_message("")
	_close_creator()
	title.hide()
	world.start()

func _close_creator() -> void:
	creator.hide()
	title_card.show()

func _on_leave() -> void:
	world.stop()
	show_title(false)

func _quit() -> void:
	Net.stop()
	get_tree().quit()

func _on_settings_changed(section: SettingsSection) -> void:
	if section is Keybinds:
		_update_keys_help()

## The hints under the title card, naming the player's own keys: moving and fighting, the
## first quickslots (empty for a new character, so no skill is named), then every window key.
func _update_keys_help() -> void:
	var k := func(action: String) -> String: return TDStatusBar._key_name(action)
	var slots := []
	for i in range(1, 5):
		slots.append(k.call("quick_%d" % i))
	var window_keys := []
	for action in WINDOW_ACTIONS:
		window_keys.append("%s %s" % [k.call(action), String(Keybinds.info(action)["label"]).to_lower()])
	keys_help.text = "%s %s move and climb · %s jump · %s attack · %s loot · %s talks and enters portals · %s… quickslots\n%s\nEsc menu · %s fullscreen · Gamepads work too" % [
		k.call("move_left"), k.call("move_right"), k.call("jump"), k.call("attack"), k.call("loot"), k.call("move_up"), ", ".join(slots),
		" · ".join(window_keys), k.call("toggle_fullscreen")]

func _show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""

## The title screen (not playing yet) or the game menu (playing).
func show_title(paused: bool) -> void:
	if settings_menu.visible:
		settings_menu.close()
	title_card.visible = not paused
	title_backdrop.visible = not paused
	title.show()
	if paused:
		game_menu.open()
	else:
		game_menu.hide()
		name_field.grab_focus()

## Back to the game from the game menu.
func resume() -> void:
	game_menu.hide()
	title.hide()

## Esc while playing: closes the top window, or opens the game menu, or closes it again.
func escape() -> void:
	if title.visible:
		if game_menu.visible:
			resume()
	elif not close_top_window():
		show_title(true)

## Opens the settings screen in place of the title card or the game menu.
func open_settings() -> void:
	_settings_from = game_menu if game_menu.visible else title_card
	_settings_from.hide()
	settings_menu.open()
