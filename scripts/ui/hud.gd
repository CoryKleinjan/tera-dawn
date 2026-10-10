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
## The title card: the logo over a small menu (Play, Settings, Quit), and the Play page
## (Play solo, Host, or log in or register on a server). Hidden while any of the other
## screens on `title` is showing.
var title_card: Control
## The title card's two pages.
var main_menu: Control
var play_page: Control
var menu_play_button: Button
## Clouds drifting over the key art.
var title_clouds: TDTitleClouds
## The key art behind the title screen and character select.
var title_backdrop: TextureRect
var character_select: TDCharacterSelect
var delete_confirm: TDDeleteConfirm
## Asks a host before logging out ends the game for the friends playing on it.
var confirm: TDConfirm
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
## Play solo and Host, on their own row over the account boxes.
var play_button: Button
var host_button: Button
## Shows why logging in didn't work.
var message: Label
## The controls, which follow the player's keybinds: shown over the first map to a new
## character for their first FIRST_HINT_TIME seconds (the full list is in Settings > Controls).
var keys_help: Label
## How long the first-time hints stay up, and how big the title's main buttons are.
const FIRST_HINT_TIME := 40.0
const MAIN_BUTTON := Vector2(240, 54)
const FIRST_HINT_Y := 138.0
var _hint_t := 0.0
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

## The window changed shape (TDWorld.VIEW): move the pieces pinned to the right and bottom
## edges, and pull open windows back into view.
func fit_view() -> void:
	if quickslots == null:
		return
	quickslots.fit_view()
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

## The controls over the first map, for a brand-new character's first moments.
func _show_first_hints(delta: float) -> void:
	var playing := world != null and world.started and not title.visible
	if not playing:
		_hint_t = 0.0
	var first := playing and Game.me.level == 1 and world.map.id == Character.START_MAP and _hint_t < FIRST_HINT_TIME
	keys_help.visible = first
	if first:
		_hint_t += delta
		keys_help.modulate.a = clampf((FIRST_HINT_TIME - _hint_t) / 2.0, 0.0, 1.0) * clampf(_hint_t / 0.5, 0.0, 1.0)
		keys_help.reset_size()
		keys_help.position = Vector2((TDWorld.VIEW.x - keys_help.size.x) / 2.0, FIRST_HINT_Y)

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
	title_clouds = TDTitleClouds.new()
	title_backdrop.add_child(title_clouds)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	title_card.add_child(col)

	var logo := TextureRect.new()
	logo.texture = UiSkin.tex("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(520, 190)  # the logo is two lines (TERA'S over DAWN)
	col.add_child(logo)

	# first the small menu over the key art: Play, Settings, Quit
	main_menu = VBoxContainer.new()
	main_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	main_menu.add_theme_constant_override("separation", 8)
	col.add_child(main_menu)
	menu_play_button = UiSkin.menu_button("Play", MAIN_BUTTON)
	menu_play_button.pressed.connect(_open_play_page)
	var settings := UiSkin.menu_button("Settings", MAIN_BUTTON)
	settings.pressed.connect(func() -> void: open_settings())
	var quit := UiSkin.menu_button("Quit", MAIN_BUTTON)
	quit.pressed.connect(_quit)
	for b: Button in [menu_play_button, settings, quit]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		main_menu.add_child(b)

	# Play: on your own, hosting friends, or logging in to (or registering on) a server
	play_page = PanelContainer.new()
	play_page.add_theme_stylebox_override("panel", UiSkin.panel())
	play_page.hide()
	col.add_child(play_page)
	start_panel = VBoxContainer.new()
	start_panel.add_theme_constant_override("separation", 6)
	play_page.add_child(start_panel)
	play_button = _small_menu_button("Play solo")
	play_button.tooltip_text = "Play on your own, on this computer"
	play_button.pressed.connect(_on_play)
	host_button = _small_menu_button("Host")
	host_button.tooltip_text = "Play and let friends register and join you (port %d)" % Net.DEFAULT_PORT
	host_button.pressed.connect(_on_host)
	start_panel.add_child(_row([play_button, host_button]))
	var online := _small_title("Or play online")
	online.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_panel.add_child(online)
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
	# Enter logs in, or registers while the second password box is showing
	for f: LineEdit in [address_field, username_field, password_field]:
		f.text_submitted.connect(func(_t: String) -> void:
			if confirm_row.visible:
				_on_register()
			else:
				_on_log_in())
	confirm_field.text_submitted.connect(func(_t: String) -> void: _on_register())
	login_button = _small_menu_button("Log in")
	login_button.pressed.connect(_on_log_in)
	register_button = _small_menu_button("Register")
	register_button.tooltip_text = "Make an account on this server"
	register_button.pressed.connect(_on_register)
	start_panel.add_child(_row([login_button, register_button]))
	message = _label("")
	message.add_theme_color_override("font_color", Palette.BAD)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.hide()
	start_panel.add_child(message)
	start_panel.add_child(UiSkin.divider())
	var back := _small_menu_button("Back")
	back.pressed.connect(_show_main_menu)
	start_panel.add_child(_row([back]))

	# a new character's first steps: the controls, over the meadow (TDHud._process)
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
		character_select.show()
		character_select.focus_button())
	delete_confirm = TDDeleteConfirm.new()
	delete_confirm.hide()
	title.add_child(delete_confirm)
	delete_confirm.confirmed.connect(func(char_name: String, typed: String) -> void: Net.delete_character(char_name, typed))
	delete_confirm.cancelled.connect(character_select.focus_button)
	confirm = TDConfirm.new()
	confirm.hide()
	title.add_child(confirm)

	Net.logged_in.connect(_on_logged_in)
	Net.characters_changed.connect(_on_characters_changed)
	Net.refused.connect(_on_refused)
	Net.joined.connect(_on_joined)
	Net.disconnected.connect(func(why: String) -> void:
		world.stop()
		show_title(false)
		_show_message(why))

func _small_menu_button(text: String) -> Button:
	return UiSkin.menu_button(text, Vector2(122, 42), 18)

func _field(text: String, hint: String, max_length: int) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	UiSkin.set_hint(f, hint)
	f.max_length = max_length
	f.custom_minimum_size = Vector2(164, 36)
	return f

## A field with a small title over it.
func _titled(title_text: String, field: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(_small_title(title_text))
	col.add_child(field)
	return col

## A small muted label, like the titles over the title card's boxes.
func _small_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Palette.MUTED)
	return l

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

## The title card's main menu (Play, Settings, Quit).
func _show_main_menu() -> void:
	play_page.hide()
	main_menu.show()
	_show_message("")
	menu_play_button.grab_focus.call_deferred()

## The Play page: solo, host, or online.
func _open_play_page() -> void:
	main_menu.hide()
	play_page.show()
	_focus_login()

func _focus_login() -> void:
	if not play_page.visible:
		if menu_play_button.is_visible_in_tree():
			menu_play_button.grab_focus()
		return
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

## The server said no: shown on whichever screen asked. If it also dropped us (the
## account was logged in from somewhere else), back to the title.
func _on_refused(reason: String) -> void:
	if Net.mode == Net.Mode.NONE:
		world.stop()
		show_title(false)
		_show_message(reason)
	elif title_card.visible:
		_back_to_title()
		_show_message(reason)
	elif creator.visible:
		creator.refused(reason)
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
	title_backdrop.show()
	title.show()
	Net.leave_character()

## Log out (game menu or character select). A host with friends playing is asked first,
## since it ends the game for them.
func _on_log_out() -> void:
	if Net.has_guests():
		confirm.open("Friends are playing on your game. Log out and end it for them?", "Log out", _log_out)
	else:
		_log_out()

func _log_out() -> void:
	world.stop()
	show_title(false)

## Shows the title card alone.
func _back_to_title() -> void:
	character_select.hide()
	creator.hide()
	delete_confirm.hide()
	confirm.hide()
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
	if text != "" and not play_page.visible:
		# the message sits on the Play page, with the boxes it's about
		main_menu.hide()
		play_page.show()

## The title screen (not playing yet) or the game menu (playing).
func show_title(paused: bool) -> void:
	if settings_menu.visible:
		settings_menu.close()
	title_backdrop.visible = not paused
	title.show()
	if paused:
		title_card.hide()
		game_menu.open()
	else:
		game_menu.hide()
		_back_to_title()
		_show_main_menu()

## Back to the game from the game menu.
func resume() -> void:
	game_menu.hide()
	title.hide()

## Esc. While playing: closes the top window, or opens the game menu, or closes it again.
## Before that: a question is cancelled, the creator goes back, and character select logs out.
func escape() -> void:
	if confirm.visible:
		confirm.cancel()
	elif delete_confirm.visible:
		delete_confirm.cancel()
	elif creator.visible:
		creator.cancelled.emit()
	elif character_select.visible:
		_on_log_out()
	elif title_card.is_visible_in_tree() and play_page.visible:
		_show_main_menu()
	elif not world.started:
		return
	elif title.visible:
		if game_menu.visible:
			resume()
	elif not close_top_window():
		show_title(true)

## Opens the settings screen in place of the title card or the game menu.
func open_settings() -> void:
	_settings_from = game_menu if game_menu.visible else title_card
	_settings_from.hide()
	settings_menu.open()
