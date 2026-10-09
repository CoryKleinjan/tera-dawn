extends TestCase
## Character select: what logging in (or playing solo) shows, picking, playing, deleting
## with the name typed, the slot limit, and going back to it from the game menu.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.open_title()

func after_each() -> void:
	ui.stop()

func _solo() -> void:
	ui.hud._on_play()
	await ui.ticks(2)

func _make(names: Array) -> void:
	for n: String in names:
		Net.create_character(n, NewCharacter.new())
	await ui.ticks(2)

func test_play_solo_shows_character_select_with_empty_slots() -> void:
	await _solo()
	var sel := ui.hud.character_select
	check(sel.visible and not ui.hud.title_card.visible, "character select shown")
	check_eq(sel.subheading.text, "Playing solo on this computer", "says where")
	check_eq(sel.slots.size(), TDLobby.MAX_CHARACTERS, "a slot for each character allowed")
	check_eq(sel.slots[0].find_child("Title", true, false).text, "Empty slot", "empty")
	check(sel.play_button.disabled and sel.delete_button.disabled, "nothing to play or delete")
	check(not sel.create_button.disabled, "can create")
	check(await ui.redraw(sel.slots[0]), "a slot draws")

func test_characters_show_with_their_level_and_job_and_can_be_picked() -> void:
	await _solo()
	await _make(["Ann", "Bob"])
	var sel := ui.hud.character_select
	check_eq(sel.slots[0].find_child("Title", true, false).text, "Ann", "first")
	check_eq(sel.slots[1].find_child("Line", true, false).text, "Lv 1 Beginner", "level and job")
	check(await ui.redraw(sel.slots[1].find_child("Preview", true, false)._body), "the hero draws")
	sel.slots[0].pressed.emit()
	check_eq(sel.selected, "Ann", "picked by clicking")
	check(sel.slots[0].button_pressed and not sel.slots[1].button_pressed, "shown picked")
	sel.play_button.pressed.emit()
	await ui.ticks(3)
	check(ui.world.started and not ui.hud.title.visible, "playing")
	check_eq(Game.me.name, "Ann", "as Ann")

func test_delete_needs_the_name_typed() -> void:
	await _solo()
	await _make(["Ann"])
	var sel := ui.hud.character_select
	sel.delete_button.pressed.emit()
	var ask := ui.hud.delete_confirm
	check(ask.visible, "asks first")
	check(ask.delete_button.disabled, "Delete waits for the name")
	ask.field.text = "An"
	ask.field.text_changed.emit(ask.field.text)
	check(ask.delete_button.disabled, "not yet")
	ask.field.text = "ann"
	ask.field.text_changed.emit(ask.field.text)
	check(not ask.delete_button.disabled, "matches in any case")
	ask.delete_button.pressed.emit()
	await ui.ticks(2)
	check(not ask.visible, "closed")
	check_eq(Net.characters, [], "gone")
	check_eq(sel.slots[0].find_child("Title", true, false).text, "Empty slot", "slot empty again")

func test_cancel_keeps_the_character() -> void:
	await _solo()
	await _make(["Ann"])
	ui.hud.character_select.delete_button.pressed.emit()
	ui.hud.delete_confirm.cancel_button.pressed.emit()
	await ui.ticks(2)
	check_eq(Net.characters.size(), 1, "still there")

func test_create_is_off_when_every_slot_is_full() -> void:
	await _solo()
	var names := []
	for i in TDLobby.MAX_CHARACTERS:
		names.append("Hero%d" % i)
	await _make(names)
	check(ui.hud.character_select.create_button.disabled, "no room")

func test_the_game_menu_goes_back_to_character_select() -> void:
	await _solo()
	await _make(["Ann"])
	Net.play("Ann")
	await ui.ticks(3)
	ui.hud.show_title(true)
	ui.hud.game_menu.characters_button.pressed.emit()
	await ui.ticks(3)
	check(not ui.world.started, "out of the world")
	check(ui.hud.character_select.visible and ui.hud.title.visible, "character select shown")
	check_eq(ui.hud.character_select.selected, "Ann", "Ann still picked")
	check_eq(Net.mode, Net.Mode.SINGLE, "still connected")
	check(Net.server.sessions.is_empty(), "nobody in the world")

func test_log_out_goes_back_to_the_title() -> void:
	await _solo()
	ui.hud.character_select.logout_button.pressed.emit()
	await ui.ticks(1)
	check(ui.hud.title_card.visible and not ui.hud.character_select.visible, "title card")
	check_eq(Net.mode, Net.Mode.NONE, "disconnected")

func test_register_asks_for_the_password_twice() -> void:
	ui.hud.username_field.text = "rowan"
	ui.hud.password_field.text = "longenough"
	ui.hud.register_button.pressed.emit()
	check(ui.hud.confirm_row.visible, "second box shown")
	ui.hud.confirm_field.text = "different!"
	ui.hud.register_button.pressed.emit()
	check_eq(ui.hud.message.text, "The passwords don't match.", "checked before sending")
	check_eq(Net.mode, Net.Mode.NONE, "not connecting")
	ui.hud.password_field.text = "short"
	ui.hud.confirm_field.text = "short"
	ui.hud.register_button.pressed.emit()
	check_eq(ui.hud.message.text, "Passwords need at least 8 characters.", "too short")

func test_a_refused_login_is_shown_on_the_title_card() -> void:
	Net.refused.emit(TDLobby.WRONG_LOGIN)
	check(ui.hud.title_card.visible, "still on the title card")
	check_eq(ui.hud.message.text, TDLobby.WRONG_LOGIN, "says why")

func test_logging_in_remembers_the_username_and_server_but_not_the_password() -> void:
	var path := Settings.path
	Settings.path = "user://test_settings_login.cfg"
	ui.hud.address_field.text = "127.0.0.1"
	ui.hud.username_field.text = "rowan"
	ui.hud.password_field.text = "dawn breaks over"
	ui.hud._on_log_in()
	Net.stop()
	var cfg := ConfigFile.new()
	cfg.load(Settings.path)
	check_eq(cfg.get_value("player", "username", ""), "rowan", "username saved")
	check_eq(cfg.get_value("player", "address", ""), "127.0.0.1", "server saved")
	var text := FileAccess.get_file_as_string(Settings.path)
	check(not text.contains("dawn breaks over"), "no password in the file")
	check_eq(ui.hud.password_field.text, "", "the box is cleared once sent")
	DirAccess.remove_absolute(Settings.path)
	Settings.path = path
