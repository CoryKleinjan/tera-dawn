extends TestCase
## Character select: what playing solo shows, picking, playing, deleting with the name
## typed, the slot limit, and going back to it from the game menu.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.open_title()

func after_each() -> void:
	ui.stop()

func _solo() -> void:
	ui.hud.title._on_solo()
	await ui.ticks(2)

func _make(names: Array) -> void:
	for n: String in names:
		Net.create_character(n, NewCharacter.new())
	await ui.ticks(2)

func test_play_solo_shows_character_select_with_empty_slots() -> void:
	await _solo()
	var sel := ui.hud.title.character_select
	check(sel.visible and not ui.hud.title.title_card.visible, "character select shown")
	check_eq(sel.subheading.text, "Playing solo", "says where")
	check_eq(sel.slots.size(), CharacterStore.MAX_CHARACTERS, "a slot for each character allowed")
	check_eq(sel.slots[0].find_child("Title", true, false).text, "Empty slot", "empty")
	check(sel.play_button.disabled and sel.delete_button.disabled, "nothing to play or delete")
	check(not sel.create_button.disabled, "can create")
	check(await ui.redraw(sel.slots[0]), "a slot draws")

func test_characters_show_with_their_level_and_job_and_can_be_picked() -> void:
	await _solo()
	await _make(["Ann", "Bob"])
	var sel := ui.hud.title.character_select
	check_eq(sel.slots[0].find_child("Title", true, false).text, "Ann", "first")
	check_eq(sel.slots[1].find_child("Line", true, false).text, "Lv 1 Beginner", "level and job")
	check(await ui.redraw(sel.slots[1].find_child("Preview", true, false)._picture), "the hero draws")
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
	var sel := ui.hud.title.character_select
	sel.delete_button.pressed.emit()
	var ask := ui.hud.title.delete_confirm
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
	ui.hud.title.character_select.delete_button.pressed.emit()
	ui.hud.title.delete_confirm.cancel_button.pressed.emit()
	await ui.ticks(2)
	check_eq(Net.characters.size(), 1, "still there")

func test_create_is_off_when_every_slot_is_full() -> void:
	await _solo()
	var names := []
	for i in CharacterStore.MAX_CHARACTERS:
		names.append("Hero%d" % i)
	await _make(names)
	check(ui.hud.title.character_select.create_button.disabled, "no room")

func test_the_game_menu_goes_back_to_character_select() -> void:
	await _solo()
	await _make(["Ann"])
	Net.play("Ann")
	await ui.ticks(3)
	ui.hud.show_title(true)
	ui.hud.game_menu.characters_button.pressed.emit()
	await ui.ticks(3)
	check(not ui.world.started, "out of the world")
	check(ui.hud.title.character_select.visible and ui.hud.title.visible, "character select shown")
	check_eq(ui.hud.title.character_select.selected, "Ann", "Ann still picked")
	check_eq(Net.mode, Net.Mode.SINGLE, "still connected")
	check(Net.server.sessions.is_empty(), "nobody in the world")

func test_back_goes_back_to_the_title() -> void:
	await _solo()
	ui.hud.title.character_select.leave_button.pressed.emit()
	await ui.ticks(1)
	check(ui.hud.title.title_card.visible and not ui.hud.title.character_select.visible, "title card")
	check_eq(Net.mode, Net.Mode.NONE, "disconnected")

func test_a_refusal_is_shown_on_the_title_card() -> void:
	Net.refused.emit("Couldn't reach the host.")
	check(ui.hud.title.title_card.visible, "still on the title card")
	check_eq(ui.hud.title.message.text, "Couldn't reach the host.", "says why")

func test_joining_remembers_the_address() -> void:
	var path := Settings.path
	Settings.path = "user://test_settings_join.cfg"
	ui.hud.title.join_button.pressed.emit()
	ui.hud.title.address_field.text = "127.0.0.1:7399"
	ui.hud.title.connect_button.pressed.emit()
	check_eq(Net.mode, Net.Mode.CLIENT, "joining")
	check_eq(ui.hud.title.message.text, "Joining 127.0.0.1:7399…", "says so")
	Net.stop()
	var cfg := ConfigFile.new()
	cfg.load(Settings.path)
	check_eq(cfg.get_value("player", "address", ""), "127.0.0.1:7399", "address saved")
	DirAccess.remove_absolute(Settings.path)
	Settings.path = path

func test_join_needs_an_address() -> void:
	ui.hud.title.join_button.pressed.emit()
	ui.hud.title.address_field.text = "  "
	ui.hud.title.address_field.text_submitted.emit("  ")
	check_eq(Net.mode, Net.Mode.NONE, "not joining")
	check_eq(ui.hud.title.message.text, "Type the address your friend sees when they host.", "says what to type")

func test_escape_on_character_select_leaves_the_game() -> void:
	await _solo()
	await ui.press("pause")
	check(ui.hud.title.title_card.visible and not ui.hud.title.character_select.visible, "title card")
	check_eq(Net.mode, Net.Mode.NONE, "left the game")

func test_escape_in_the_creator_goes_back() -> void:
	await _solo()
	ui.hud.title.character_select.create_button.pressed.emit()
	check(ui.hud.title.creator.visible, "creator open")
	await ui.press("pause")
	check(not ui.hud.title.creator.visible and ui.hud.title.character_select.visible, "back on character select")
	check(ui.hud.title.character_select.create_button.has_focus(), "Create has the focus")
	check_eq(Net.mode, Net.Mode.SINGLE, "still in the game")

func test_escape_cancels_deleting() -> void:
	await _solo()
	await _make(["Ann"])
	ui.hud.title.character_select.delete_button.pressed.emit()
	await ui.press("pause")
	check(not ui.hud.title.delete_confirm.visible and ui.hud.title.character_select.visible, "back on character select")
	check(ui.hud.title.character_select.play_button.has_focus(), "Play has the focus")
	check_eq(Net.characters.size(), 1, "not deleted")
	check_eq(Net.mode, Net.Mode.SINGLE, "still in the game")

func test_cancel_puts_the_focus_back_on_play() -> void:
	await _solo()
	await _make(["Ann"])
	ui.hud.title.character_select.delete_button.pressed.emit()
	ui.hud.title.delete_confirm.cancel_button.pressed.emit()
	check(ui.hud.title.character_select.play_button.has_focus(), "Play has the focus")

func test_a_second_create_before_the_answer_is_ignored() -> void:
	await _solo()
	ui.hud.title.character_select.create_button.pressed.emit()
	var creator := ui.hud.title.creator
	creator.name_field.text = "Ann"
	creator.name_field.text_submitted.emit("Ann")
	check(creator.create_button.disabled, "Create waits for the answer")
	creator.create_button.pressed.emit()
	await ui.ticks(2)
	check_eq(Net.characters.size(), 1, "made once")
	check(not creator.visible and ui.hud.title.character_select.visible, "back on character select")
	check_eq(ui.hud.title.character_select.message.text, "", "no 'Ann is taken'")
	ui.hud.title.character_select.create_button.pressed.emit()
	check(not creator.create_button.disabled, "a new character can be made again")

func test_a_refused_create_can_be_tried_again() -> void:
	await _solo()
	await _make(["Ann"])
	ui.hud.title.character_select.create_button.pressed.emit()
	var creator := ui.hud.title.creator
	creator.name_field.text = "Ann"
	creator.create_button.pressed.emit()
	await ui.ticks(2)
	check_eq(creator.message.text, "You already have a character called Ann.", "says why")
	check(not creator.create_button.disabled, "Create works again")

func test_leaving_the_world_clears_the_chat_and_closes_windows() -> void:
	await _solo()
	await _make(["Ann"])
	Net.play("Ann")
	await ui.ticks(3)
	ui.world.show_chat("all", "Ann", "hello", 1)
	ui.hud.windows["dialogue"].visible = true
	ui.hud.windows["inventory"].visible = true
	ui.hud.show_title(true)
	ui.hud.game_menu.characters_button.pressed.emit()
	await ui.ticks(3)
	check_eq(ui.hud.chat.lines, [], "chat history gone")
	for key: String in ui.hud.windows:
		check(not ui.hud.windows[key].visible, "%s window closed" % key)

func test_a_dialogue_left_open_doesnt_answer_number_keys_on_character_select() -> void:
	await _solo()
	await _make(["Ann"])
	Net.play("Ann")
	await ui.ticks(3)
	var ids := Content.npcs.keys()
	ids.sort()
	var talk: TDDialogueWindow = ui.hud.windows["dialogue"]
	ui.hud.open_dialogue(ui.npc_beside(Content.npcs[ids[0]]))
	check(talk.visible, "talking")
	ui.hud.show_title(true)
	ui.hud.game_menu.characters_button.pressed.emit()
	await ui.ticks(3)
	check(not talk.visible, "the dialogue closed")
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	get_viewport().push_input(key)
	await ui.frames(2)
	check(ui.hud.title.character_select.visible and not talk.visible, "1 does nothing there")

func test_being_dropped_while_playing_goes_back_to_the_title() -> void:
	await _solo()
	await _make(["Ann"])
	Net.play("Ann")
	await ui.ticks(3)
	Net.ev_refused("Dropped.", true)
	await ui.ticks(1)
	check(not ui.world.started, "out of the world")
	check(ui.hud.title.visible and ui.hud.title.title_card.visible, "on the title card")
	check_eq(ui.hud.title.message.text, "Dropped.", "says why")

func test_playing_saves_on_this_computer() -> void:
	await _solo()
	await _make(["Ann"])
	Net.play("Ann")
	await ui.ticks(3)
	ui.player().character.shards = 99
	ui.hud.show_title(true)
	ui.hud.game_menu.characters_button.pressed.emit()
	await ui.ticks(3)
	check_eq(CharacterStore.new(UiHelpers.SAVE_DIR).load_character("Ann").shards, 99, "saved")
