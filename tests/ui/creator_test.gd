extends TestCase
## The character creator: Create on character select opens it, its arrows step the outfit,
## Back returns to character select, and Create makes a Beginner with that outfit.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.open_title()

func after_each() -> void:
	ui.stop()

## Plays solo and opens the creator from character select, with `char_name` typed in.
func _play(char_name: String) -> void:
	ui.hud.title._on_solo()
	await ui.ticks(2)
	ui.hud.title.character_select.create_button.pressed.emit()
	ui.hud.title.creator.name_field.text = char_name

## Presses Create, then Play on character select.
func _create_and_play() -> void:
	ui.hud.title.creator.create_button.pressed.emit()
	await ui.ticks(2)
	ui.hud.title.character_select.play_button.pressed.emit()
	await ui.ticks(3)

func test_create_on_character_select_opens_the_creator() -> void:
	await _play("Fresh")
	check(ui.hud.title.creator.visible, "creator shown")
	check(not ui.hud.title.title_card.visible and not ui.hud.title.character_select.visible, "the rest hidden")
	check(not ui.world.started, "not playing yet")
	check_eq(ui.hud.title.creator.heading.text, "New character", "heading")

func test_name_box_keeps_its_hint_clear_of_the_caret() -> void:
	await _play("")
	var f := ui.hud.title.creator.name_field
	check(f.placeholder_text.begins_with(UiStyle.HINT_ROOM), "room between the caret and the hint")
	check_eq(f.alignment, HORIZONTAL_ALIGNMENT_LEFT, "left-aligned: an empty centred box puts its caret on the hint")

func test_every_row_steps_through_its_options() -> void:
	await _play("Fresh")
	var c := ui.hud.title.creator
	check(not c.values.is_empty(), "outfit rows")
	for key: String in c.values:
		var before := c.value_text(key)
		c.step(key, 1)
		check_ne(c.value_text(key), before, "%s changes" % key)
		c.step(key, -1)
		check_eq(c.value_text(key), before, "%s steps back" % key)

func test_the_arrow_buttons_work() -> void:
	await _play("Fresh")
	var c := ui.hud.title.creator
	var key := "outfit:%d" % EquipDef.Slot.ARMOR
	var row := (c.values[key] as Label).get_parent()
	var next := row.get_child(row.get_child_count() - 1) as Button
	next.pressed.emit()
	var options := NewCharacter.outfit_options(c.job, EquipDef.Slot.ARMOR)
	var was := options.find(NewCharacter.new(c.job.id).outfit[EquipDef.Slot.ARMOR])
	check_eq(c.value_text(key), options[(was + 1) % options.size()].display_name, "next shoes")

func test_back_returns_to_character_select() -> void:
	await _play("Fresh")
	ui.hud.title.creator.cancelled.emit()
	await ui.ticks(1)
	check(not ui.hud.title.creator.visible and ui.hud.title.character_select.visible, "character select back")
	check_eq(Net.characters, [], "nothing made")

func test_create_needs_a_name() -> void:
	await _play("  ")
	ui.hud.title.creator.create_button.pressed.emit()
	await ui.ticks(2)
	check(ui.hud.title.creator.visible, "still in the creator")
	check_eq(ui.hud.title.creator.message.text, "Please pick a name.", "asks for one")

func test_a_name_that_is_taken_is_shown_in_the_creator() -> void:
	await _play("Fresh")
	ui.hud.title.creator.create_button.pressed.emit()
	await ui.ticks(2)
	ui.hud.title.character_select.create_button.pressed.emit()
	ui.hud.title.creator.name_field.text = "fresh"
	ui.hud.title.creator.create_button.pressed.emit()
	await ui.ticks(2)
	check(ui.hud.title.creator.visible, "still in the creator")
	check_eq(ui.hud.title.creator.message.text, "You already have a character called Fresh.", "why")

func test_create_goes_back_to_character_select_with_it_picked() -> void:
	await _play("Fresh")
	ui.hud.title.creator.create_button.pressed.emit()
	await ui.ticks(2)
	var sel := ui.hud.title.character_select
	check(sel.visible and not ui.hud.title.creator.visible, "back on character select")
	check_eq(sel.selected, "Fresh", "picked")
	check_eq(sel.slots[0].find_child("Title", true, false).text, "Fresh", "in the first slot")
	check(not ui.world.started, "not playing yet")

func test_create_starts_the_game_with_the_choices() -> void:
	await _play("Fresh")
	var c := ui.hud.title.creator
	c.step("outfit:%d" % EquipDef.Slot.ARMOR, 1)
	var shoes: EquipDef = c.made.outfit[EquipDef.Slot.ARMOR]
	await _create_and_play()
	check(ui.world.started and not ui.hud.title.visible, "playing")
	check_eq(Game.me.equipment.at(&"armor").item, shoes, "the shoes picked")
	check_eq(Game.me.job.id, Character.START_JOB, "a Beginner")

func test_the_look_row_shows_and_makes_the_look_picked() -> void:
	await _play("Fresh")
	var c := ui.hud.title.creator
	var looks := HeroLookDef.all()
	check_eq(c.value_text("look"), looks[0].display_name, "the first look to start")
	check(c.preview.texture == looks[0].frames.get_frame_texture(&"idle", 0), "shown standing")
	c.step("look", 1)
	check_eq(c.value_text("look"), looks[1].display_name, "the next look")
	check(c.preview.texture == looks[1].frames.get_frame_texture(&"idle", 0), "and its picture")
	await _create_and_play()
	check_eq(Game.me.look, looks[1].id, "the new character has it")

func test_the_equipment_window_shows_what_is_worn() -> void:
	await _play("Fresh")
	await _create_and_play()
	# a new character wakes in the tutorial's opening cutscene, which hides the HUD
	ui.world.scenes.skip()
	await ui.ticks(2)
	var w: TDEquipmentWindow = ui.hud.windows["equipment"]
	w.visible = true
	check(await ui.redraw(w), "draws")
	check(Game.me.equipment.at(&"armor") != null, "the shoes worn sit in their slot")
