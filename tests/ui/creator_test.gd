extends TestCase
## The character creator: Play with a new name opens it, its arrows change the preview,
## Back returns to the title, and Create starts the game as a Beginner with that look.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.open_title()

func after_each() -> void:
	ui.stop()

func _play(char_name: String) -> void:
	ui.hud.name_field.text = char_name
	ui.hud._on_play()
	await ui.ticks(2)

func test_a_new_name_opens_the_creator() -> void:
	await _play("Fresh")
	check(ui.hud.creator.visible, "creator shown")
	check(not ui.hud.title_card.visible, "title card hidden")
	check(not ui.world.started, "not playing yet")
	check_eq(ui.hud.creator.heading.text, "Create Fresh", "named")

func test_every_row_steps_through_its_options_and_the_preview_follows() -> void:
	await _play("Fresh")
	var c := ui.hud.creator
	for key: String in c.values:
		var before := c.value_text(key)
		var look_before := c.preview.look.duplicate(true)
		c.step(key, 1)
		check_ne(c.value_text(key), before, "%s changes" % key)
		check_ne(c.preview.look, look_before, "%s changes the preview" % key)
		c.step(key, -1)
		check_eq(c.value_text(key), before, "%s steps back" % key)

func test_the_arrow_buttons_work() -> void:
	await _play("Fresh")
	var c := ui.hud.creator
	var key := "look:%d" % LookDef.Kind.HAIR
	var row := (c.values[key] as Label).get_parent()
	var next := row.get_child(row.get_child_count() - 1) as Button
	next.pressed.emit()
	check_eq(c.value_text(key), Content.looks_of(LookDef.Kind.HAIR)[1].display_name, "next hairstyle")

func test_the_preview_draws_and_animates() -> void:
	await _play("Fresh")
	var view := ui.hud.creator.preview
	check(await ui.redraw(view._body), "the body draws")
	view.play(&"walk")
	view.time = 0.3
	check_eq(view.frame(), 2, "walking at 9 frames a second, frame 2 at 0.3s")

func test_back_returns_to_the_title() -> void:
	await _play("Fresh")
	ui.hud.creator.cancelled.emit()
	await ui.ticks(1)
	check(not ui.hud.creator.visible and ui.hud.title_card.visible, "title card back")
	check_eq(Net.mode, Net.Mode.NONE, "not connected")

func test_create_starts_the_game_with_the_choices() -> void:
	await _play("Fresh")
	var c := ui.hud.creator
	c.step("look:%d" % LookDef.Kind.SKIN, 2)
	c.step("outfit:%d" % EquipDef.Slot.SHOES, 1)
	var want := c.made.appearance.to_dict()
	var shoes: EquipDef = c.made.outfit[EquipDef.Slot.SHOES]
	c.create_button.pressed.emit()
	await ui.ticks(3)
	check(ui.world.started and not ui.hud.title.visible, "playing")
	check_eq(Game.me.appearance.to_dict(), want, "the look picked")
	check_eq(Game.me.equipment.at(&"shoes").item, shoes, "the shoes picked")
	check_eq(Game.me.job.id, Character.START_JOB, "a Beginner")

func test_a_name_that_exists_skips_the_creator() -> void:
	await _play("Fresh")
	ui.hud.creator.create_button.pressed.emit()
	await ui.ticks(3)
	ui.world.stop()
	Net.stop()
	ui.hud.show_title(false)
	await _play("Fresh")
	check(ui.world.started and not ui.hud.creator.visible, "straight into the game")

func test_the_equipment_window_shows_the_dressed_hero() -> void:
	await _play("Fresh")
	ui.hud.creator.create_button.pressed.emit()
	await ui.ticks(3)
	var w: TDEquipmentWindow = ui.hud.windows["equipment"]
	w.visible = true
	check(await ui.redraw(w), "draws")
	check_eq(w.doll.look, Game.me.look(), "dressed in what's worn")
