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
## The dimmed layer over the game that holds the title card, character select, the
## character creator, the game menu and the settings screen. While it's showing, the game
## ignores play keys.
var title: Control
## The title card (log in or register on a server, Play solo, Host, Settings, Quit),
## hidden while any of the other screens on `title` is showing.
var title_card: Control
var character_select: TDCharacterSelect
var delete_confirm: TDDeleteConfirm
var creator: TDCreator
var game_menu: TDGameMenu
var settings_menu: TDSettingsMenu
## What the settings screen goes back to: the title card or the game menu.
var _settings_from: Control
var start_panel: Control
var address_field: LineEdit
var username_field: LineEdit
var password_field: LineEdit
## The second password box, shown while registering.
var confirm_field: LineEdit
var confirm_row: Control
var login_button: Button
var register_button: Button
## Shows why logging in didn't work.
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
	title_card = CenterContainer.new()
	title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(title_card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	title_card.add_child(col)

	var heading := Label.new()
	heading.text = "Tera Dawn"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", Game.num_font)
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", Palette.SUN)
	heading.add_theme_color_override("font_outline_color", Palette.PLUM)
	heading.add_theme_constant_override("outline_size", 18)
	heading.add_theme_color_override("font_shadow_color", Palette.EMBER)
	heading.add_theme_constant_override("shadow_offset_y", 6)
	heading.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(heading)

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

	# before playing: log in to (or register on) a server, or play solo, or host
	start_panel = VBoxContainer.new()
	start_panel.add_theme_constant_override("separation", 10)
	inner.add_child(start_panel)
	address_field = _field(Game.last_address, "Server address", 64)
	username_field = _field(Game.last_username, "Username", AccountStore.MAX_USERNAME)
	password_field = _field("", "Password", AccountStore.MAX_PASSWORD)
	password_field.secret = true
	confirm_field = _field("", "Password again", AccountStore.MAX_PASSWORD)
	confirm_field.secret = true
	start_panel.add_child(_row([_titled("Server", address_field), _titled("Username", username_field), _titled("Password", password_field)]))
	confirm_row = _row([_titled("Confirm password", confirm_field)])
	confirm_row.hide()
	start_panel.add_child(confirm_row)
	for f: LineEdit in [address_field, username_field, password_field]:
		f.text_submitted.connect(func(_t: String) -> void: _on_log_in())
	confirm_field.text_submitted.connect(func(_t: String) -> void: _on_register())
	login_button = _small_menu_button("Log in")
	login_button.pressed.connect(_on_log_in)
	register_button = _small_menu_button("Register")
	register_button.tooltip_text = "Make an account on this server"
	register_button.pressed.connect(_on_register)
	var play := _small_menu_button("Play solo")
	play.tooltip_text = "Play on your own, on this computer"
	play.pressed.connect(_on_play)
	var host := _small_menu_button("Host")
	host.tooltip_text = "Play and let friends register and join you (port %d)" % Net.DEFAULT_PORT
	host.pressed.connect(_on_host)
	start_panel.add_child(_row([login_button, register_button, play, host]))
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
	_focus_login.call_deferred()

	# while playing: the game menu (Esc)
	game_menu = TDGameMenu.new()
	game_menu.hide()
	title.add_child(game_menu)
	game_menu.resumed.connect(resume)
	game_menu.settings_requested.connect(func() -> void: open_settings())
	game_menu.to_characters.connect(_on_to_characters)
	game_menu.logged_out.connect(_on_log_out)
	game_menu.quit.connect(_quit)

	settings_menu = TDSettingsMenu.new()
	settings_menu.hide()
	title.add_child(settings_menu)
	settings_menu.closed.connect(func() -> void:
		_settings_from.show()
		if _settings_from == game_menu:
			game_menu.open()
		else:
			_focus_login())

	# after logging in: character select, the creator and the delete question
	character_select = TDCharacterSelect.new()
	character_select.hide()
	title.add_child(character_select)
	character_select.play_requested.connect(func(char_name: String) -> void: Net.play(char_name))
	character_select.create_requested.connect(func() -> void:
		character_select.hide()
		creator.open())
	character_select.delete_requested.connect(func(char_name: String) -> void: delete_confirm.open(char_name))
	character_select.logged_out.connect(_on_log_out)
	creator = TDCreator.new()
	creator.hide()
	title.add_child(creator)
	creator.created.connect(func(char_name: String, made: NewCharacter) -> void: Net.create_character(char_name, made))
	creator.cancelled.connect(func() -> void:
		creator.hide()
		character_select.show())
	delete_confirm = TDDeleteConfirm.new()
	delete_confirm.hide()
	title.add_child(delete_confirm)
	delete_confirm.confirmed.connect(func(char_name: String, typed: String) -> void: Net.delete_character(char_name, typed))

	Net.logged_in.connect(_on_logged_in)
	Net.characters_changed.connect(_on_characters_changed)
	Net.refused.connect(_on_refused)
	Net.joined.connect(_on_joined)
	Net.disconnected.connect(func() -> void:
		world.stop()
		show_title(false)
		_show_message("Lost the connection to the server."))

func _menu_button(text: String) -> Button:
	return UiSkin.menu_button(text)

func _small_menu_button(text: String) -> Button:
	return UiSkin.menu_button(text, Vector2(122, 42), 18)

func _field(text: String, hint: String, max_length: int) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	f.placeholder_text = hint
	f.max_length = max_length
	f.custom_minimum_size = Vector2(164, 36)
	return f

## A field with a small title over it.
func _titled(title_text: String, field: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = title_text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Palette.MUTED)
	col.add_child(l)
	col.add_child(field)
	return col

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

func _on_play() -> void:
	_show_message("")
	Net.play_single()

func _on_host() -> void:
	_show_message(Net.host())

## Log in: hides the register box, then connects with the username and password.
func _on_log_in() -> void:
	if confirm_row.visible:
		confirm_row.hide()
		confirm_field.text = ""
	_connect(false)

## Register: the first press asks for the password again, the second makes the account.
func _on_register() -> void:
	if not confirm_row.visible:
		confirm_row.show()
		confirm_field.grab_focus()
		_show_message("")
		return
	var why := AccountStore.username_problem(username_field.text.strip_edges())
	if why == "":
		why = AccountStore.password_problem(password_field.text)
	if why == "" and confirm_field.text != password_field.text:
		why = "The passwords don't match."
	if why != "":
		_show_message(why)
		return
	_connect(true)

func _connect(register: bool) -> void:
	var address := address_field.text.strip_edges()
	var user := username_field.text.strip_edges()
	if address == "" or user == "" or password_field.text == "":
		_show_message("Type the server, your username and your password.")
		return
	Game.last_address = address
	Game.last_username = user
	Game.save_settings()
	var problem := Net.log_in(address, user, password_field.text, register)
	password_field.text = ""
	confirm_field.text = ""
	_show_message(problem if problem != "" else "Connecting to %s…" % address)

func _focus_login() -> void:
	if username_field.text == "":
		username_field.grab_focus()
	else:
		password_field.grab_focus()

## Which server and account character select is for.
func _where() -> String:
	match Net.mode:
		Net.Mode.SINGLE:
			return "Playing solo on this computer"
		Net.Mode.HOST:
			return "Hosting on port %d" % Net.DEFAULT_PORT
	return "%s on %s" % [Net.username, Game.last_address]

func _on_logged_in() -> void:
	_show_message("")
	confirm_row.hide()
	title_card.hide()
	creator.hide()
	character_select.show_characters(Net.characters, "", _where())

func _on_characters_changed(selected: String) -> void:
	creator.hide()
	delete_confirm.hide()
	title_card.hide()
	title.show()
	character_select.show_characters(Net.characters, selected)

## The server said no: shown on whichever screen asked.
func _on_refused(reason: String) -> void:
	if Net.mode == Net.Mode.NONE or title_card.visible:
		_back_to_title()
		_show_message(reason)
	elif creator.visible:
		creator.show_message(reason)
	else:
		character_select.show_message(reason)

func _on_joined() -> void:
	_show_message("")
	creator.hide()
	character_select.hide()
	title.hide()
	world.start()

## Esc menu: back to character select, still logged in.
func _on_to_characters() -> void:
	world.stop(true)
	game_menu.hide()
	title_card.hide()
	title.show()
	Net.leave_character()

func _on_log_out() -> void:
	world.stop()
	show_title(false)

## Shows the title card alone.
func _back_to_title() -> void:
	character_select.hide()
	creator.hide()
	delete_confirm.hide()
	title_card.show()

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
	title.show()
	if paused:
		title_card.hide()
		game_menu.open()
	else:
		game_menu.hide()
		_back_to_title()
		_focus_login()

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
