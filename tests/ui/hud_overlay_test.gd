extends TestCase
## The always-on HUD: the status bar, the quickslots, the chat box, invitation cards, the
## text prompt and the overlay (log, banner, party, quest tracker, buffs, fainting) all draw
## with something to show, and their hit tests and buttons work. Name tags fit their names,
## and the log, toasts and the map's sign keep clear of what's under them. The quickslots and
## quest tracker fade over the hero, the tracker lists three quests, and the first-time hint
## shows the fighting keys on the first field, never in town and never over a window.

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

func test_status_bar_says_max_level_at_the_cap() -> void:
	var bar := ui.hud.status
	await ui.edit(func(c: Character) -> void:
		c.level = 20
		c.xp = c.xp_need() / 4)
	check_eq(bar.exp_text(), "%.1f%%" % (100.0 * Game.me.xp / Game.me.xp_need()), "how far to the next level")
	await ui.edit(func(c: Character) -> void:
		c.level = Character.MAX_LEVEL
		c.xp = 0)
	check_eq(bar.exp_text(), "Max level", "at the cap")
	check(await ui.redraw(bar), "the status bar draws at the cap")

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
				c.skills.learned[s.id] = 1
				c.skills.buffs[s.id] = [1, 600]
		c.guild = "Dawnbreakers")
	Game.social = {"party": {"leader": "Mossy", "members": [["Mossy", 7, 22, "warrior", 0.5, "meadow"], [Game.me.name, 1, 20, "warrior", 1.0, "meadow"], ["Kestrel", 8, 18, "archer", 0.1, "hollow"]]}}
	for i in 8:
		ui.world.add_log("Log line %d" % i, Palette.MIST)
	ui.world.show_banner("A Banner")
	check_eq(ui.world.log_lines.size(), 6, "the log keeps the last 6 lines")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws")
	ui.world.log_lines.clear()
	ui.world.show_achievement("first_hunt")
	check(ui.hud.banners.toasts.any(func(t: AchievementDef) -> bool: return t.title == "First Hunt"), "an achievement shows a toast")
	check(ui.world.log_lines.is_empty(), "and no log line as well")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws the achievement")
	check(await ui.redraw(ui.hud.banners), "the toast draws")

func test_popups_take_turns_and_wait_for_the_map_banner() -> void:
	var banners := ui.hud.banners
	ui.world.started = true
	ui.world.show_banner("A Banner")
	ui.world.show_achievement("first_hunt")
	banners.ribbon("dialogue/job_advance_banner", "Warrior")
	banners._process(0.0)
	check_eq([banners._ribbon_t, banners._toast_t], [0, 0], "nothing counts down while the map banner shows")
	ui.world.banner_t = 0
	banners._process(0.0)
	check_eq([banners._ribbon_t, banners._toast_t], [1, 0], "then the ribbon shows first and the toast waits its turn")
	for i in TDBanners.RIBBON_TICKS:
		banners._process(0.0)
	check(banners.ribbons.is_empty() and banners._toast_t > 0, "the toast shows once the ribbon is done")
	check(await ui.redraw(banners), "the toast draws")
	banners.clear()
	check(banners.toasts.is_empty() and banners.ribbons.is_empty(), "clear() takes every toast and ribbon down")

func test_the_achievement_toast_sits_at_the_bottom_clear_of_the_hud() -> void:
	var r := ui.hud.banners.toast_rect()
	check(r.end.y <= TDWorld.VIEW.y - TDStatusBar.HEIGHT, "above the status bar: %s" % r)
	check(r.end.y >= TDWorld.VIEW.y - TDStatusBar.HEIGHT - 20, "just above it: %s" % r)
	check(not r.intersects(ui.hud.quickslots.get_global_rect()), "clear of the quickslots: %s" % r)
	check(not r.intersects(ui.hud.chat.get_global_rect()), "clear of the chat box: %s" % r)
	check(absf(r.get_center().x - TDWorld.VIEW.x / 2.0) < 120, "near the middle: %s" % r)
	for w: TDWindow in ui.hud.windows.values():
		check(r.position.y > w.position.y + 40, "below %s's title" % w.get_class())

func test_quickslots_and_tracker_fade_over_the_hero() -> void:
	var hud := ui.hud
	await ui.edit(func(c: Character) -> void:
		for q: QuestDef in Content.quests.values().slice(0, 2):
			c.quests.accept(q))
	ui.teleport(Vector2(400, ui.world.map.ground_y))
	ui.world.snap_camera()
	await ui.frames(5)
	var hero := hud.screen_rect(ui.world.drawn(ui.world.player), Vector2(TDPlayer.WIDTH, TDPlayer.HEIGHT), TDPlayer.Z)
	check(hero.size.x > 20 and hero.size.y > 50, "the hero's screen rect is about his size: %s" % hero)
	check(hud.covers_people(hero) and not hud.covers_people(Rect2()), "a panel over the hero covers him; an empty one nobody")
	check_eq(hud.quickslots.modulate.a, 1.0, "the quickslots are solid while nobody is behind them")
	check(hud.tracker.visible and hud.tracker.size.y > 0, "the tracker shows the quests")
	# the hero walks behind the panels (moved over him here, since where he ends up under
	# them depends on the window's shape)
	for piece: Control in [hud.quickslots, hud.tracker]:
		piece.position = hero.get_center() - piece.size / 2.0
	await _wait_until(func() -> bool: return hud.quickslots.modulate.a <= TDHud.SEE_THROUGH and hud.tracker.modulate.a <= TDHud.SEE_THROUGH)
	check_near(hud.quickslots.modulate.a, TDHud.SEE_THROUGH, "the quickslots fade to see-through", 0.05)
	check_near(hud.tracker.modulate.a, TDHud.SEE_THROUGH, "so does the tracker", 0.05)
	hud.quickslots.fit_view()
	hud.tracker.fit_view()
	await _wait_until(func() -> bool: return hud.quickslots.modulate.a >= 1.0 and hud.tracker.modulate.a >= 1.0)
	check_eq([hud.quickslots.modulate.a, hud.tracker.modulate.a], [1.0, 1.0], "and come back once he's out from under them")
	var npc := ui.npc_beside(Content.npcs.values()[0])
	await ui.frames(2)
	check(hud.covers_people(hud.screen_rect(npc.position, npc.body_size(), TDStage.Z_NPC)), "an NPC nearby counts too")

## Waits frames until `done` is true, up to two seconds.
func _wait_until(done: Callable) -> void:
	var until := Time.get_ticks_msec() + 2000
	while not done.call() and Time.get_ticks_msec() < until:
		await ui.frames(1)

func test_the_tracker_lists_at_most_three_quests() -> void:
	await ui.edit(func(c: Character) -> void:
		for q: QuestDef in Content.quests.values().slice(0, 6):
			c.quests.accept(q))
	await ui.frames(3)
	var tracker := ui.hud.tracker
	check_eq(tracker.quests().size(), TDQuestTracker.QUESTS, "three quests on the tracker")
	check_eq(TDQuestTracker.QUESTS, 3, "three at most")
	check_eq(Game.me.quests.active.size(), 6, "all six in the quest log")
	check(await ui.redraw(tracker), "the tracker draws")

func test_overlay_draws_the_faint_screen() -> void:
	ui.world.player.faint()
	check(ui.world.player.fainted(), "the player is fainted")
	check(await ui.redraw(ui.hud.overlay), "the overlay draws the faint screen")

func test_title_screen_draws_and_hides() -> void:
	check(not ui.hud.title.visible, "playing hides the title screen")
	ui.hud.show_title(false)
	check(ui.hud.title.visible and ui.hud.title.main_menu.visible and not ui.hud.game_menu.visible, "the title shows the main menu")
	check(await ui.redraw(ui.hud.title), "the title screen draws")
	ui.hud.show_title(true)
	check(ui.hud.game_menu.visible and not ui.hud.title.title_card.visible, "the game menu shows Resume, Settings, Leave and Quit")
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
	await ui.enter_map(&"meadow", 200)
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

func test_name_tags_fit_their_names_between_the_end_caps() -> void:
	var tex_h := UiSkin.tex("name_tag").get_height()
	var cap := WorldSkin.PLAQUE_MARGINS.x * WorldSkin.NAME_TAG_H / tex_h
	for label in ["Elder Rowan", "Guide Sorrel", "Fletcher Wynn", "Al"]:
		var r := WorldSkin.name_tag_rect(Vector2(100, 50), label)
		var text_w := DrawUtil.text_width(Game.ui_font, label, 11)
		check(r.size.x >= text_w + 2.0 * cap, "%s: tag %s wide holds text %s plus two caps of %s" % [label, r.size.x, text_w, cap])
		check_near(r.get_center().x, 100.0, "%s: centred" % label)
	var hint := "↑ to Fern Hollow"
	check(WorldSkin.hint_width(hint) >= DrawUtil.text_width(Game.ui_font, hint, 13) + 2.0 * WorldSkin.PLAQUE_MARGINS.x * WorldSkin.HINT_H / tex_h, "hints fit too")

func test_no_text_floats_in_the_3d_stage() -> void:
	var labels := ui.world.stage.find_children("*", "Label3D", true, false)
	check(labels.is_empty(), "no text in the 3D stage, where depth of field would blur it")

# ---------- message log and gains ----------

func test_log_sits_above_the_name_tags_on_the_floor() -> void:
	ui.teleport(Vector2(400, ui.world.map.ground_y))
	await ui.ticks(30)
	var st := ui.world.stage
	var feet := st.screen(Vector2(400, ui.world.map.ground_y), TDStage.Z_NPC)
	var tag_top := WorldSkin.name_tag_rect(feet + Vector2(0, 4), "Elder Rowan").position.y
	check(ui.hud.overlay.log_bottom() < tag_top, "the log's newest line (%s) is above the floor's name tags (%s)" % [ui.hud.overlay.log_bottom(), tag_top])
	check(ui.hud.overlay.log_bottom() <= TDWorld.VIEW.y - TDStatusBar.HEIGHT, "and above the status bar")
	for i in 3:
		ui.world.add_log("Line %d" % i, Palette.MIST)
	ui.hud.chat.add("all", "Mossy", "Hello")
	check(await ui.redraw(ui.hud.overlay), "the log draws on its backdrop")
	check(await ui.redraw(ui.hud.chat), "the chat draws on its backdrop")

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

func test_play_leads_to_solo_and_co_op_and_co_op_to_host_and_join() -> void:
	ui.hud.show_title(false)
	var title := ui.hud.title
	var texts := func(menu: Control) -> Array: return menu.get_children().map(func(b: Button) -> String: return b.text)
	check_eq(texts.call(title.main_menu), ["Play", "Settings", "Quit"], "the main menu")
	check_eq(texts.call(title.play_menu), ["Solo", "Co-op", "Back"], "Play's menu")
	check_eq(texts.call(title.coop_menu), ["Host", "Join", "Back"], "Co-op's menu")
	check(not title.play_menu.visible and not title.coop_menu.visible and not title.join_page.visible, "only the main menu at first")
	title.menu_play_button.pressed.emit()
	check(title.play_menu.visible and not title.main_menu.visible, "Play shows Solo and Co-op")
	title.coop_button.pressed.emit()
	check(title.coop_menu.visible and not title.play_menu.visible, "Co-op shows Host and Join")
	title.join_button.pressed.emit()
	check(title.join_page.visible and not title.coop_menu.visible, "Join asks for the address")
	await ui.press("pause")
	check(title.coop_menu.visible, "Esc goes back to Co-op")
	(title.coop_menu.get_child(2) as Button).pressed.emit()
	check(title.play_menu.visible, "Back goes to Play")
	await ui.press("pause")
	check(title.main_menu.visible and not title.play_menu.visible, "Esc goes back to the main menu")
	Net.refused.emit("Couldn't reach the host.")
	check(title.main_menu.visible and title.message.visible, "a refusal shows under the menu")

func test_title_boxes_keep_their_hints_clear_of_the_caret() -> void:
	var f := ui.hud.title.address_field
	check(f.placeholder_text.begins_with(UiStyle.HINT_ROOM), "room between the caret and the hint")
	check_eq(f.alignment, HORIZONTAL_ALIGNMENT_LEFT, "left-aligned, so an empty box's caret starts before the hint")

func test_no_controls_box_for_a_new_character() -> void:
	# the tutorial teaches the keys; the game shows no controls box of its own
	var hud := ui.hud
	check(ui.world.map.town, "a new character starts in a town")
	await ui.frames(3)
	check(not hud.keys_help.visible, "no controls box in town")
	await ui.enter_map(&"meadow", 300)
	await ui.frames(3)
	check(not hud.keys_help.visible, "nor on their first field")
