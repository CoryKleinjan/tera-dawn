class_name TDTitleScreen
extends ColorRect
## The title screen: the dimmed layer over the game with the key art, the title card (the logo
## over a small menu of Play, Settings and Quit; Play opens Solo and Co-op, Co-op opens Host
## and Join, and Join asks for the host's address), character select, the character creator and their
## questions. It runs everything from the first button to playing. While it's showing, the
## game ignores play keys.
## TDHud owns it, puts the game menu and settings screen on it, and handles Esc and pausing.

## Settings was pressed on the main menu.
signal settings_requested
## Quit was pressed on the main menu.
signal quit_requested
## The game ended under the player (left, dropped, or turned away by the host): the HUD
## puts the title card back up (TDHud.show_title).
signal left_game

## How big the menus' buttons are, and the Join page's smaller ones.
const MAIN_BUTTON := Vector2(240, 46)
const SMALL_BUTTON := Vector2(122, 42)
const SMALL_BUTTON_FONT := 18

var world: TDWorld
## The title card: the logo over one of its pages. Hidden while any of the other screens on
## the title screen is showing.
var title_card: Control
## The title card's pages, one showing at a time: the main menu (Play, Settings, Quit), the
## Play menu (Solo, Co-op), the Co-op menu (Host, Join) and the Join page.
var main_menu: Control
var play_menu: Control
var coop_menu: Control
var join_page: Control
var menu_play_button: Button
var solo_button: Button
var coop_button: Button
var host_button: Button
var join_button: Button
## The key art behind the title screen and character select.
var title_backdrop: TextureRect
var character_select: TDCharacterSelect
var delete_confirm: TDDeleteConfirm
## Asks a host before leaving ends the game for the friends playing on it.
var confirm: TDConfirm
var creator: TDCreator
## The host's address on the Join page, and its Join button.
var address_field: LineEdit
var connect_button: Button
## Shows why starting or joining a game didn't work, under the menu.
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

	Net.welcomed.connect(_on_welcomed)
	Net.characters_changed.connect(_on_characters_changed)
	Net.refused.connect(_on_refused)
	Net.joined.connect(_on_joined)
	Net.disconnected.connect(func(why: String) -> void:
		world.stop()
		left_game.emit()
		show_message(why))

## The logo, the main menu and the Join page.
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
	menu_play_button = UiStyle.menu_button("Play", MAIN_BUTTON)
	menu_play_button.pressed.connect(func() -> void: _show_page(play_menu))
	var settings := UiStyle.menu_button("Settings", MAIN_BUTTON)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	var quit := UiStyle.menu_button("Quit", MAIN_BUTTON)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	main_menu = _menu([menu_play_button, settings, quit])
	main_menu.show()
	col.add_child(main_menu)

	# Play: on your own, or with friends
	solo_button = UiStyle.menu_button("Solo", MAIN_BUTTON)
	solo_button.tooltip_text = "Play on your own"
	solo_button.pressed.connect(_on_solo)
	coop_button = UiStyle.menu_button("Co-op", MAIN_BUTTON)
	coop_button.tooltip_text = "Play with up to %d friends, each with their own character" % (Net.MAX_PLAYERS - 1)
	coop_button.pressed.connect(func() -> void: _show_page(coop_menu))
	play_menu = _menu([solo_button, coop_button, _back_button(main_menu)])
	col.add_child(play_menu)

	# Co-op: host a game here, or join a friend's
	host_button = UiStyle.menu_button("Host", MAIN_BUTTON)
	host_button.tooltip_text = "Play and let up to %d friends join you" % (Net.MAX_PLAYERS - 1)
	host_button.pressed.connect(_on_host)
	join_button = UiStyle.menu_button("Join", MAIN_BUTTON)
	join_button.tooltip_text = "Bring one of your characters into a friend's game"
	join_button.pressed.connect(func() -> void: _show_page(join_page))
	coop_menu = _menu([host_button, join_button, _back_button(play_menu)])
	col.add_child(coop_menu)

	# Join a friend: the host's address
	join_page = PanelContainer.new()
	join_page.add_theme_stylebox_override("panel", UiSkin.panel())
	join_page.hide()
	col.add_child(join_page)
	var page := UiBuild.column(6)
	join_page.add_child(page)
	var heading := UiBuild.small_title("Join a friend")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(heading)
	address_field = UiBuild.field(Game.last_address, "Host's address", 64)
	address_field.tooltip_text = "The address your friend sees when they host, with :port after it if it isn't %d" % Net.DEFAULT_PORT
	address_field.text_submitted.connect(func(_t: String) -> void: _on_join())
	page.add_child(UiBuild.centered_row([UiBuild.titled("Host's address", address_field)]))
	connect_button = _small_menu_button("Join")
	connect_button.pressed.connect(_on_join)
	var back := _small_menu_button("Back")
	back.pressed.connect(func() -> void: _show_page(coop_menu))
	page.add_child(UiBuild.centered_row([connect_button, back]))

	message = UiBuild.label("", 0, Palette.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	message.custom_minimum_size.x = 60
	message.hide()
	col.add_child(message)

## Character select, the creator and the delete and leave questions.
func _build_character_screens() -> void:
	character_select = TDCharacterSelect.new()
	character_select.hide()
	add_child(character_select)
	character_select.play_requested.connect(func(char_name: String) -> void: Net.play(char_name))
	character_select.create_requested.connect(func() -> void:
		character_select.hide()
		creator.open())
	character_select.delete_requested.connect(func(char_name: String) -> void: delete_confirm.open(char_name))
	character_select.left.connect(leave_game)
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

## A button on the title card's Join page.
func _small_menu_button(text: String) -> Button:
	return UiStyle.menu_button(text, SMALL_BUTTON, SMALL_BUTTON_FONT)

## One of the title card's menus: `buttons` in a column, hidden until it's shown.
func _menu(buttons: Array) -> Control:
	var menu := UiBuild.column(8)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	for b: Button in buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		menu.add_child(b)
	menu.hide()
	return menu

## Back to the menu `to`.
func _back_button(to: Control) -> Button:
	var b := UiStyle.menu_button("Back", MAIN_BUTTON)
	b.pressed.connect(func() -> void: _show_page(to))
	return b

func _on_solo() -> void:
	show_message("")
	Net.play_single()

func _on_host() -> void:
	show_message(Net.host())

## Join: connects to the host at the typed address; character select follows once it lets
## us in.
func _on_join() -> void:
	var address := address_field.text.strip_edges()
	if address == "":
		show_message("Type the address your friend sees when they host.")
		address_field.grab_focus()
		return
	var host := ServerAddress.parse(address)
	if host["error"] != "":
		show_message(host["error"])
		return
	Game.last_address = address
	Game.save_settings()
	var problem := Net.join(host["host"], host["port"])
	show_message(problem if problem != "" else "Joining %s…" % address)

## The title card's main menu.
func show_main_menu() -> void:
	_show_page(main_menu)

## Shows one of the title card's pages, with no message and the keyboard on its first button.
func _show_page(page: Control) -> void:
	for p: Control in _pages():
		p.visible = p == page
	show_message("")
	focus_login.call_deferred()

func _pages() -> Array[Control]:
	return [main_menu, play_menu, coop_menu, join_page]

## The page Back (or Esc) on `page` goes to, or null on the main menu.
func _page_before(page: Control) -> Control:
	match page:
		play_menu:
			return main_menu
		coop_menu:
			return play_menu
		join_page:
			return coop_menu
	return null

## The title card's page showing now.
func _page() -> Control:
	for p: Control in _pages():
		if p.visible:
			return p
	return main_menu

## Puts the keyboard focus on the title card's page: its first button, or on the Join page
## the address (or Join, when it's typed).
func focus_login() -> void:
	if not title_card.is_visible_in_tree():
		return
	var page := _page()
	if page == join_page:
		(address_field if address_field.text == "" else connect_button).grab_focus()
	else:
		(page.get_child(0) as Button).grab_focus()

## Which game character select is for.
func _where() -> String:
	match Net.mode:
		Net.Mode.SINGLE:
			return "Playing solo"
		Net.Mode.HOST:
			return "Hosting a game for up to %d players" % Net.MAX_PLAYERS
	return "Joining %s" % Game.last_address

func _on_welcomed() -> void:
	show_message("")
	title_card.hide()
	creator.hide()
	character_select.show_characters(Net.characters, "", _where())

func _on_characters_changed(selected: String) -> void:
	creator.hide()
	delete_confirm.hide()
	title_card.hide()
	show()
	character_select.show_characters(Net.characters, selected)

## Something asked for didn't happen: shown on whichever screen asked. If the game is over
## too (the host couldn't be reached, or its game is full), back to the title.
func _on_refused(reason: String) -> void:
	if Net.mode == Net.Mode.NONE:
		var joining := title_card.visible and join_page.visible
		world.stop()
		left_game.emit()
		if joining:
			_show_page(join_page)
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

## Character select again from the game menu, still in the game: the screen without the
## title card, over the key art.
func show_characters() -> void:
	title_card.hide()
	title_backdrop.show()
	show()

## Leave the game (game menu, or Back on character select). A host with friends playing is
## asked first, since it ends the game for them.
func leave_game() -> void:
	if Net.has_guests():
		confirm.open("Friends are playing in your game. Leave and end it for them?", "End game", _leave_game)
	else:
		_leave_game()

func _leave_game() -> void:
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
## select leaves the game and the title card's pages go back one. False if none of those was
## showing, so Esc is the game's.
func escape() -> bool:
	if confirm.visible:
		confirm.cancel()
	elif delete_confirm.visible:
		delete_confirm.cancel()
	elif creator.visible:
		creator.cancelled.emit()
	elif character_select.visible:
		leave_game()
	elif title_card.is_visible_in_tree() and _page_before(_page()) != null:
		_show_page(_page_before(_page()))
	else:
		return false
	return true

## Shows why starting or joining a game didn't work ("" hides it), under the menu or the
## Join page.
func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""
