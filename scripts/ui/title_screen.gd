class_name TDTitleScreen
extends ColorRect
## The title screen: the dimmed layer over the game with the key art, the title card (the logo
## over a small menu of Play, Settings and Quit, and the Play page: Play solo, Host, or log in
## or register on a server), character select, the character creator and their questions.
## It runs the login flow from the first button to joining the game. While it's showing, the
## game ignores play keys.
## TDHud owns it, puts the game menu and settings screen on it, and handles Esc and pausing.

## Settings was pressed on the main menu.
signal settings_requested
## Quit was pressed on the main menu.
signal quit_requested
## The game ended under the player (logged out, dropped or refused by the server): the HUD
## puts the title card back up (TDHud.show_title).
signal left_game

## How big the main menu's buttons are, and the Play page's smaller ones.
const MAIN_BUTTON := Vector2(240, 54)
const SMALL_BUTTON := Vector2(122, 42)
const SMALL_BUTTON_FONT := 18

var world: TDWorld
## The title card: the logo over the main menu and the Play page. Hidden while any of the
## other screens on the title screen is showing.
var title_card: Control
## The title card's two pages.
var main_menu: Control
var play_page: Control
var menu_play_button: Button
## The key art behind the title screen and character select.
var title_backdrop: TextureRect
var character_select: TDCharacterSelect
var delete_confirm: TDDeleteConfirm
## Asks a host before logging out ends the game for the friends playing on it.
var confirm: TDConfirm
var creator: TDCreator
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

func _init() -> void:
	color = Color(Palette.NIGHT, 0.45)
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	# the key art behind the title screen and the creator (not behind the Esc menu)
	title_backdrop = TextureRect.new()
	title_backdrop.texture = UiSkin.tex("title_backdrop")
	title_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_backdrop)
	_build_title_card()
	focus_login.call_deferred()
	_build_character_screens()

	Net.logged_in.connect(_on_logged_in)
	Net.characters_changed.connect(_on_characters_changed)
	Net.refused.connect(_on_refused)
	Net.joined.connect(_on_joined)
	Net.disconnected.connect(func(why: String) -> void:
		world.stop()
		left_game.emit()
		show_message(why))

## The logo, the main menu and the Play page.
func _build_title_card() -> void:
	title_card = CenterContainer.new()
	title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title_card)
	var col := UiBuild.column(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	title_card.add_child(col)

	var logo := TextureRect.new()
	logo.texture = UiSkin.tex("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(520, 190)  # the logo is two lines (TERA'S over DAWN)
	col.add_child(logo)

	# first the small menu over the key art: Play, Settings, Quit
	var menu := UiBuild.column(8)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	main_menu = menu
	col.add_child(main_menu)
	menu_play_button = UiStyle.menu_button("Play", MAIN_BUTTON)
	menu_play_button.pressed.connect(_open_play_page)
	var settings := UiStyle.menu_button("Settings", MAIN_BUTTON)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	var quit := UiStyle.menu_button("Quit", MAIN_BUTTON)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	for b: Button in [menu_play_button, settings, quit]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		main_menu.add_child(b)

	# Play: on your own, hosting friends, or logging in to (or registering on) a server
	play_page = PanelContainer.new()
	play_page.add_theme_stylebox_override("panel", UiSkin.panel())
	play_page.hide()
	col.add_child(play_page)
	start_panel = UiBuild.column(6)
	play_page.add_child(start_panel)
	_build_play_page()

## The Play page: Play solo and Host, then the server, account and password boxes.
func _build_play_page() -> void:
	play_button = _small_menu_button("Play solo")
	play_button.tooltip_text = "Play on your own, on this computer"
	play_button.pressed.connect(_on_play)
	host_button = _small_menu_button("Host")
	host_button.tooltip_text = "Play and let friends register and join you (port %d)" % Net.DEFAULT_PORT
	host_button.pressed.connect(_on_host)
	start_panel.add_child(UiBuild.centered_row([play_button, host_button]))
	var online := UiBuild.small_title("Or play online")
	online.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_panel.add_child(online)
	address_field = UiBuild.field(Game.last_address, "Server address", 64)
	username_field = UiBuild.field(Game.last_username, "Username", AccountStore.MAX_USERNAME)
	password_field = UiBuild.field("", "Password", AccountStore.MAX_PASSWORD)
	password_field.secret = true
	confirm_field = UiBuild.field("", "Password again", AccountStore.MAX_PASSWORD)
	confirm_field.secret = true
	start_panel.add_child(UiBuild.centered_row([UiBuild.titled("Server", address_field), UiBuild.titled("Username", username_field), UiBuild.titled("Password", password_field)]))
	confirm_row = UiBuild.centered_row([UiBuild.titled("Confirm password", confirm_field)])
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
	start_panel.add_child(UiBuild.centered_row([login_button, register_button]))
	message = UiBuild.label("", 0, Palette.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	message.custom_minimum_size.x = 60
	message.hide()
	start_panel.add_child(message)
	start_panel.add_child(UiSkin.divider())
	var back := _small_menu_button("Back")
	back.pressed.connect(show_main_menu)
	start_panel.add_child(UiBuild.centered_row([back]))

## After logging in: character select, the creator and the delete and log out questions.
func _build_character_screens() -> void:
	character_select = TDCharacterSelect.new()
	character_select.hide()
	add_child(character_select)
	character_select.play_requested.connect(func(char_name: String) -> void: Net.play(char_name))
	character_select.create_requested.connect(func() -> void:
		character_select.hide()
		creator.open())
	character_select.delete_requested.connect(func(char_name: String) -> void: delete_confirm.open(char_name))
	character_select.logged_out.connect(log_out)
	creator = TDCreator.new()
	creator.hide()
	add_child(creator)
	creator.created.connect(func(char_name: String, made: NewCharacter) -> void: Net.create_character(char_name, made))
	creator.cancelled.connect(func() -> void:
		creator.hide()
		character_select.show()
		character_select.focus_button())
	delete_confirm = TDDeleteConfirm.new()
	delete_confirm.hide()
	add_child(delete_confirm)
	delete_confirm.confirmed.connect(func(char_name: String, typed: String) -> void: Net.delete_character(char_name, typed))
	delete_confirm.cancelled.connect(character_select.focus_button)
	confirm = TDConfirm.new()
	confirm.hide()
	add_child(confirm)

## A button on the title card's Play page.
func _small_menu_button(text: String) -> Button:
	return UiStyle.menu_button(text, SMALL_BUTTON, SMALL_BUTTON_FONT)

func _on_play() -> void:
	show_message("")
	Net.play_single()

func _on_host() -> void:
	show_message(Net.host())

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
		show_message("")
		return
	var why := AccountStore.username_problem(username_field.text.strip_edges())
	if why == "":
		why = AccountStore.password_problem(password_field.text)
	if why == "" and confirm_field.text != password_field.text:
		why = "The passwords don't match."
	if why != "":
		show_message(why)
		return
	_connect(true)

func _connect(register: bool) -> void:
	var address := address_field.text.strip_edges()
	var user := username_field.text.strip_edges()
	if address == "" or user == "" or password_field.text == "":
		show_message("Type the server, your username and your password.")
		return
	Game.last_address = address
	Game.last_username = user
	Game.save_settings()
	var problem := Net.log_in(address, user, password_field.text, register)
	password_field.text = ""
	confirm_field.text = ""
	show_message(problem if problem != "" else "Connecting to %s…" % address)

## The title card's main menu (Play, Settings, Quit).
func show_main_menu() -> void:
	play_page.hide()
	main_menu.show()
	show_message("")
	menu_play_button.grab_focus.call_deferred()

## The Play page: solo, host, or online.
func _open_play_page() -> void:
	main_menu.hide()
	play_page.show()
	focus_login()

## Puts the keyboard focus on the title card: Play on the main menu, or the first empty
## account box on the Play page.
func focus_login() -> void:
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
	show_message("")
	confirm_row.hide()
	title_card.hide()
	creator.hide()
	character_select.show_characters(Net.characters, "", _where())

func _on_characters_changed(selected: String) -> void:
	creator.hide()
	delete_confirm.hide()
	title_card.hide()
	show()
	character_select.show_characters(Net.characters, selected)

## The server said no: shown on whichever screen asked. If it also dropped us (the
## account was logged in from somewhere else), back to the title.
func _on_refused(reason: String) -> void:
	if Net.mode == Net.Mode.NONE:
		world.stop()
		left_game.emit()
		show_message(reason)
	elif title_card.visible:
		_back_to_title()
		show_message(reason)
	elif creator.visible:
		creator.refused(reason)
	else:
		character_select.show_message(reason)

func _on_joined() -> void:
	show_message("")
	creator.hide()
	character_select.hide()
	hide()
	world.start()

## Character select again from the game menu, still logged in: the screen without the
## title card, over the key art.
func show_characters() -> void:
	title_card.hide()
	title_backdrop.show()
	show()

## Log out (game menu or character select). A host with friends playing is asked first,
## since it ends the game for them.
func log_out() -> void:
	if Net.has_guests():
		confirm.open("Friends are playing on your game. Log out and end it for them?", "Log out", _log_out)
	else:
		_log_out()

func _log_out() -> void:
	world.stop()
	left_game.emit()

## Shows the title card alone.
func _back_to_title() -> void:
	character_select.hide()
	creator.hide()
	delete_confirm.hide()
	confirm.hide()
	title_card.show()

## The title card alone, on its main menu (the title screen, not playing yet).
func show_title_card() -> void:
	_back_to_title()
	show_main_menu()

## The title screen's part of Esc: a question is cancelled, the creator goes back, character
## select logs out and the Play page goes back to the main menu. False if none of those was
## showing, so Esc is the game's.
func escape() -> bool:
	if confirm.visible:
		confirm.cancel()
	elif delete_confirm.visible:
		delete_confirm.cancel()
	elif creator.visible:
		creator.cancelled.emit()
	elif character_select.visible:
		log_out()
	elif title_card.is_visible_in_tree() and play_page.visible:
		show_main_menu()
	else:
		return false
	return true

## Shows why logging in didn't work ("" hides it).
func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""
	if text != "" and not play_page.visible:
		# the message sits on the Play page, with the boxes it's about
		main_menu.hide()
		play_page.show()
