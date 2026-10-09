extends TestCase
## The always-on HUD: the status bar, the quickslots, the chat box, invitation cards, the
## text prompt and the overlay (log, banner, party, quest tracker, buffs, fainting) all draw
## with something to show, and their hit tests and buttons work.

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	ui.stop()

func test_status_bar_draws_any_state() -> void:
	var bar := ui.hud.status
	check(bar.visible and bar.size.y == TDStatusBar.HEIGHT, "the status bar runs along the bottom")
	for state in [[1, 0], [30, 1], [99, 5]]:
		await ui.edit(func(c: Character) -> void:
			c.level = state[0]
			c.xp = c.xp_need() / 2
			c.mp = state[1]
			c.shards = 9999999)
		check(await ui.redraw(bar), "the status bar draws at level %d" % state[0])

func test_quickslots_hold_skills_and_items() -> void:
	var slots := ui.hud.quickslots
	await ui.frames(1)
	check(slots.visible, "quickslots show while playing")
	for i in Character.QUICKSLOTS:
		check_eq(slots.slot_at(slots.slot_rect(i).get_center()), i, "slot_at the middle of quickslot %d" % i)
	check_eq(slots.slot_at(Vector2(-5, -5)), -1, "slot_at outside")
	slots.assign(0, &"skill", Character.BASIC_ATTACK)
	slots.assign(1, &"item", &"red_potion")
	slots.assign(2, &"item", &"elixir")
	await ui.ticks(2)
	check(TDQuickslots.content(0) == Content.skill(Character.BASIC_ATTACK), "slot 1 holds the basic attack")
	check(TDQuickslots.content(1) == Content.item(&"red_potion"), "slot 2 holds Red Potions")
	check(TDQuickslots.content(3) == null, "slot 4 is empty")
	check(await ui.redraw(slots), "the quickslots draw")
	await ui.click(slots, slots.slot_rect(2).get_center(), MOUSE_BUTTON_RIGHT)
	await ui.ticks(2)
	check(TDQuickslots.content(2) == null, "right-click clears a slot")

func test_quickslot_skill_hover_clears_the_tooltip() -> void:
	var slots := ui.hud.quickslots
	slots.assign(0, &"skill", Character.BASIC_ATTACK)
	await ui.ticks(2)
	await ui.hover(slots, slots.slot_rect(0).get_center())
	check(ui.hud.tooltip.stack == null, "a skill shows no item tooltip")

func test_quickslot_item_hover_shows_the_item() -> void:
	var slots := ui.hud.quickslots
	slots.assign(1, &"item", &"red_potion")
	await ui.ticks(2)
	await ui.hover(slots, slots.slot_rect(1).get_center())
	check(ui.hud.tooltip.stack != null and ui.hud.tooltip.stack.item.id == &"red_potion", "hovering a potion shows it")

func test_chat_shows_every_channel() -> void:
	var chat := ui.hud.chat
	for kind in TDChat.COLORS:
		chat.add(kind, "Mossy", "Hello from the %s channel, with enough words to wrap onto a second line of the box." % kind)
	chat.add("unknown", "Mossy", "Still shown")
	check(chat.lines.size() > TDChat.COLORS.size(), "long lines wrap (%d lines)" % chat.lines.size())
	check_eq(chat.lines[-1]["text"], "Mossy: Still shown", "an unknown channel reads as plain chat")
	check(await ui.redraw(chat), "the chat box draws closed")
	chat.open("/w Mossy ")
	check(chat.field.visible and chat.field.text == "/w Mossy ", "open() starts the line with its text")
	check(await ui.redraw(chat), "the chat box draws open")
	chat.close()
	for i in 80:
		chat.add("all", "Spam", str(i))
	check(chat.lines.size() <= 60, "the chat keeps at most 60 lines (%d)" % chat.lines.size())

func test_invitation_cards_queue_up() -> void:
	var inv := ui.hud.invites
	inv.add(1, "party", "Mossy", "Mossy invites you to a party.")
	inv.add(2, "buddy", "Kestrel", "Kestrel wants to be buddies.")
	await ui.frames(1)
	check(inv.visible and inv.label.text == "Mossy invites you to a party.", "the oldest invitation shows first")
	check(Rect2(Vector2.ZERO, TDWorld.VIEW).encloses(Rect2(inv.position, inv.size)), "the card is on screen at %s" % inv.position)
	inv.pending.pop_front()
	inv._show()
	check_eq(inv.label.text, "Kestrel wants to be buddies.", "then the next")
	inv.clear()
	check(not inv.visible, "clearing hides the card")

func test_prompt_answers_with_what_was_typed() -> void:
	var prompt := ui.hud.prompt
	var got := []
	prompt.ask("Name your guild", "Dawn", func(t: String) -> void: got.append(t))
	await ui.frames(1)
	check(prompt.visible and prompt.field.text == "Dawn" and prompt.field.max_length == 24, "the prompt opens with its starting text")
	check(ui.hud.typing(), "typing in the prompt blocks movement")
	prompt.field.text = "  Dawnbreakers  "
	prompt.answer(true)
	check_eq(got, ["Dawnbreakers"], "OK answers with the trimmed text")
	check(not prompt.visible, "and closes")
	prompt.ask("Price", "10", func(t: String) -> void: got.append(t), true)
	check_eq(prompt.field.max_length, 9, "number prompts are short")
	prompt.field.text = "   "
	prompt.answer(true)
	check_eq(got.size(), 1, "an empty answer isn't sent")
	prompt.ask("Price", "10", func(t: String) -> void: got.append(t), true)
	prompt.answer(false)
	check_eq(got.size(), 1, "Cancel sends nothing")

func test_overlay_draws_everything_it_can_show() -> void:
	await ui.edit(func(c: Character) -> void:
		c.level = 20
		c.job = Content.job(&"warrior")
		for q: QuestDef in Content.quests.values().slice(0, 5):
			c.quests.accept(q)
		for s: SkillDef in Content.skills.values():
			if s.kind == SkillDef.Kind.BUFF:
				c.skills[s.id] = 1
				c.buffs[s.id] = [1, 600]
		c.guild = "Dawnbreakers")
	Game.social = {"party": {"leader": "Mossy", "members": [["Mossy", 7, 22, "warrior", 0.5, "meadow"], [Game.me.name, 1, 20, "warrior", 1.0, "meadow"], ["Kestrel", 8, 18, "archer", 0.1, "hollow"]]}}
	for i in 8:
		ui.world.add_log("Log line %d" % i, Palette.MIST)
	ui.world.show_banner("A Banner")
	check_eq(ui.world.log_lines.size(), 6, "the log keeps the last 6 lines")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws")
	ui.world.show_achievement("first_hunt")
	check(ui.hud.banners.toasts.any(func(t: Dictionary) -> bool: return t["title"] == "First Hunt"), "an achievement shows a toast")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws the achievement")

func test_overlay_draws_the_faint_screen() -> void:
	ui.world.player.faint()
	check(ui.world.player.fainted(), "the player is fainted")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws the faint screen")

func test_title_screen_draws_and_hides() -> void:
	check(not ui.hud.title.visible, "playing hides the title screen")
	ui.hud.show_title(false)
	check(ui.hud.title.visible and ui.hud.start_panel.visible and not ui.hud.game_menu.visible, "the title shows the start panel")
	check(await ui.redraw(ui.hud.title), "the title screen draws")
	ui.hud.show_title(true)
	check(ui.hud.game_menu.visible and not ui.hud.title_card.visible, "the game menu shows Resume, Settings, Leave and Quit")
	ui.hud.game_menu.resume_button.pressed.emit()
	check(not ui.hud.title.visible, "Resume hides it")

# ---------- name tags ----------

func test_name_tags_nudge_apart_and_yours_stays_put() -> void:
	var tags := TDNameTags.new()
	tags.add_name(Vector2(100, 200), "Mossy", Palette.MIST)
	tags.add_name(Vector2(104, 202), "Kestrel", Palette.MIST, "Dawnbreakers")
	tags.add_name(Vector2(102, 201), Game.me.name, Palette.SUN, "", true)
	tags.add_name(Vector2(400, 200), "Far away", Palette.MIST)
	tags.arrange()
	var r := tags.rects()
	check_eq(r[2].position, Vector2(102, 201) - Vector2(r[2].size.x / 2.0, 0), "your own tag doesn't move")
	for i in r.size():
		for k in range(i + 1, r.size()):
			check(not r[i].intersects(r[k]), "tags %d and %d overlap: %s %s" % [i, k, r[i], r[k]])
	check_eq(tags.tags[3]["offset"], Vector2.ZERO, "a tag nothing overlaps stays put")
	check(r[0].position.y > r[2].position.y and r[1].position.y > r[0].position.y, "the others move down below yours, in order")
	var order := []
	var draw_order := TDNameTags.new()
	for i in 3:
		draw_order.add(Rect2(0, 0, 10, 10), func(_ci: CanvasItem, _o: Vector2) -> void: order.append(i), i == 1)
	draw_order.draw(ui.hud.overlay)
	check_eq(order, [0, 2, 1], "your tag draws last, on top")

func test_monster_tags_show_only_when_hurt_or_a_boss() -> void:
	var mobs := ui.world.mobs()
	if not check(not mobs.is_empty(), "the meadow has monsters"):
		return
	var m := mobs[0]
	m.apply([m.position.x, m.position.y, 1, 1000, 0])
	check(not m.shows_tag(), "an unhurt monster has no tag")
	m.apply([m.position.x, m.position.y, 1, 600, SnapshotFlags.MOB_SHOW_HP])
	check(m.shows_tag(), "a hurt one shows it")
	m.apply([m.position.x, m.position.y, 1, 1000, 0])
	var boss: MonsterDef = Content.monsters.values().filter(func(d: MonsterDef) -> bool: return d.boss)[0]
	var was := m.def
	m.def = boss
	check(m.shows_tag(), "a boss always shows it")
	m.def = was
	check(await ui.redraw(ui.hud.overlay), "the overlay draws the tags")
	check(ui.hud.overlay.last_tags != null and not ui.hud.overlay.last_tags.tags.is_empty(), "your own tag at least was gathered")

# ---------- message log and gains ----------

func test_pickups_of_the_same_item_merge() -> void:
	var tuft: ItemDef = Content.items.values().filter(func(i: ItemDef) -> bool: return not i.is_currency and i.stack_size() > 1)[0]
	var other: ItemDef = Content.items.values().filter(func(i: ItemDef) -> bool: return not i.is_currency and i != tuft)[0]
	ui.world.log_lines.clear()
	ui.world.show_pickup(tuft, 1)
	ui.world.show_pickup(other, 1)
	ui.world.show_pickup(tuft, 2)
	check_eq(ui.world.log_lines.size(), 2, "one line per item")
	check_eq(ui.world.log_lines[-1]["text"], "Picked up 3 %s" % tuft.display_name, "the counts add up, on the newest line")
	await ui.ticks(TDWorld.PICKUP_MERGE_TICKS + 5)
	ui.world.show_pickup(tuft, 1)
	check_eq(ui.world.log_lines[-1]["text"], "Picked up %s" % tuft.display_name, "later pickups start a new line")

func test_exp_and_dawnshards_float_over_you() -> void:
	ui.world.log_lines.clear()
	ui.world.show_gain(&"exp", 9)
	ui.world.show_gain(&"shards", 8)
	var gains: Array = ui.world.fx_layer.get_children().filter(func(f: Node) -> bool: return f is TDFloatText and f.is_gain())
	check_eq(gains.size(), 2, "two rising numbers")
	check(ui.world.log_lines.is_empty(), "nothing in the log")
	check_eq((gains[0] as TDFloatText).gain_text(), "+9 EXP", "EXP")
	check_eq((gains[1] as TDFloatText).gain_text(), "+8 Dawnshards", "Dawnshards")
	check(gains[1].position.y < gains[0].position.y, "the second stacks above the first")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws them")

func test_killing_shows_exp_over_you_not_in_the_log() -> void:
	ui.world.log_lines.clear()
	ui.player().map.server.give_xp(ui.player(), 3)
	await ui.ticks(2)
	check(ui.world.log_lines.all(func(l: Dictionary) -> bool: return not l["text"].contains("EXP")), "no EXP line in the log")
	check(ui.world.fx_layer.get_children().any(func(f: Node) -> bool: return f is TDFloatText and f.is_gain()), "a rising +3 EXP")

# ---------- title screen ----------

func test_title_screen_hides_the_status_bar_and_minimap() -> void:
	ui.world.stop()
	ui.hud.show_title(false)
	await ui.frames(2)
	check(not ui.hud.status.visible, "no status bar before there's a character")
	check(not ui.hud.minimap_button.visible, "no minimap button either")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws without the minimap")

func test_title_hints_name_the_real_keys() -> void:
	var text := ui.hud.keys_help.text
	check(not text.contains("Dawn Slash"), "no skill a new character doesn't have")
	check(text.contains("A, D, F, G… quickslots"), "the quickslot keys: %s" % text)
	for pair in [["K", "skills"], ["Q", "quests"], ["W", "world map"], ["O", "community"], ["L", "collection"], ["S", "character"], ["I", "inventory"]]:
		check(text.contains("%s %s" % pair), "names %s %s" % pair)
