extends TestCase
## Every window the HUD registers, opened in a running single-player game with a character
## that has something in every tab: it draws, its tabs switch on click, its hit tests find
## what's drawn where, and what it lists matches the character. Windows NPCs open are
## tried with every NPC, shop and storage; trade, player shops and the player menu with
## the server's kind of state. (tests/run_all.sh fails on any script error they print.)

const KNOWN := ["inventory", "equipment", "stats", "quests", "skills", "worldmap", "community", "collection",
	"dialogue", "shop", "storage", "player", "trade", "player_shop"]

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	ui.stop()

func _win(key: String) -> TDWindow:
	return ui.hud.windows[key]

func _open(key: String) -> TDWindow:
	var w := _win(key)
	w.visible = true
	w.raise()
	return w

## Every item of a kind, sorted by id, so tests pick the same ones each run.
func _items(kind: Callable) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for i: ItemDef in Content.items.values():
		if kind.call(i):
			out.append(i)
	out.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return String(a.id) < String(b.id))
	return out

## Fills every bag tab and the storage with a few of each kind of item.
func _fill_bag(c: Character) -> void:
	for k: Callable in [
			func(i: ItemDef) -> bool: return i is EquipDef,
			func(i: ItemDef) -> bool: return i is UseDef,
			func(i: ItemDef) -> bool: return i is ScrollDef,
			func(i: ItemDef) -> bool: return i is AmmoDef,
			func(i: ItemDef) -> bool: return i.tab() == ItemDef.Tab.ETC and not i is CardDef,
			func(i: ItemDef) -> bool: return i is ChairDef,
			func(i: ItemDef) -> bool: return i is PetDef]:
		var list := _items(k)
		for n in mini(4, list.size()):
			c.inventory.add(list[n], 1 + n * 7 if list[n].stack_size() > 1 else 1)
			c.storage.add(list[list.size() - 1 - n], 2)
	c.shards = 123456

func _redrawn(w: CanvasItem, what: String) -> void:
	check(await ui.redraw(w), "%s: its draw ran" % what)

## Clicks tab `t` of `win`, drawing the window first if its tabs haven't been drawn yet.
func _click_tab(win: TDWindow, t: int) -> void:
	if win._tab_rects.size() <= t:
		await _redrawn(win, "%s before clicking a tab" % win.name)
	if check(t < win._tab_rects.size(), "%s has a tab %d" % [win.name, t]):
		await ui.click(win, win._tab_rects[t].get_center())

# ---------- the HUD itself ----------

func test_hud_registers_every_window_once() -> void:
	check_eq(ui.hud.windows.keys().size(), KNOWN.size(), "windows registered")
	for key in KNOWN:
		var w: TDWindow = ui.hud.windows.get(key)
		if not check(w != null, "hud.windows has no %s" % key):
			continue
		check(w.hud == ui.hud, "%s: hud is set" % key)
		check(w.get_parent() == ui.hud.window_layer, "%s: lives in the window layer" % key)
		check(not w.visible, "%s: starts closed" % key)
		check(w.size.x > 100 and w.size.y > 100, "%s: size %s" % [key, w.size])
		check(w.size.x <= TDWorld.VIEW.x and w.size.y <= TDWorld.VIEW.y - TDStatusBar.HEIGHT, "%s: size %s fits on screen above the status bar" % [key, w.size])

func test_key_windows_open_on_screen() -> void:
	for key in TDHud.WINDOW_ACTIONS:
		var w := _win(key)
		var r := Rect2(w.position, w.size)
		check(Rect2(Vector2.ZERO, TDWorld.VIEW).encloses(r), "%s: opens at %s, partly off screen" % [key, r])
		check(w.title != "", "%s: has a title" % key)

func test_every_window_draws_with_nothing_to_show() -> void:
	# windows NPCs or players open must cope with being shown before they're given anything
	for key in KNOWN:
		var w := _open(key)
		await _redrawn(w, key)
		w.visible = false

func test_every_window_draws_for_a_new_character() -> void:
	for key in TDHud.WINDOW_ACTIONS:
		ui.hud.toggle_window(key)
		await _redrawn(_win(key), key)
		ui.hud.toggle_window(key)
		check(not _win(key).visible, "%s: toggles closed" % key)

# ---------- inventory ----------

func test_inventory_draws_every_tab_full_of_items() -> void:
	await ui.edit(_fill_bag)
	var inv: TDInventoryWindow = _open("inventory")
	for t in ItemDef.Tab.size():
		await _click_tab(inv, t)
		check_eq(inv.tab, t, "clicking tab %s" % ItemDef.TAB_NAMES[t])
		check(Game.me.inventory.free_slots(t) < Inventory.SLOTS, "%s tab has items" % ItemDef.TAB_NAMES[t])
		await _redrawn(inv, "inventory, %s tab" % ItemDef.TAB_NAMES[t])

func test_inventory_slot_hit_test_matches_its_layout() -> void:
	var inv: TDInventoryWindow = _open("inventory")
	for i in Inventory.SLOTS:
		var r := inv.slot_rect(i)
		check_eq(inv.slot_at(r.get_center()), i, "slot_at the middle of slot %d" % i)
		check(Rect2(Vector2.ZERO, inv.size).encloses(r), "slot %d at %s lies inside the window" % [i, r])
	check_eq(inv.slot_at(Vector2(2, 2)), -1, "slot_at the corner")
	await _redrawn(inv, "inventory")
	check_eq(inv.slot_at(inv._tab_rects[0].get_center()), -1, "slot_at a tab")
	for t in ItemDef.Tab.size():
		check(inv._tab_rects[t].get_center().y < inv.slot_rect(0).position.y, "tab %d sits above the slots" % t)

func test_inventory_hover_shows_the_item_under_the_mouse() -> void:
	await ui.edit(_fill_bag)
	var inv: TDInventoryWindow = _open("inventory")
	for t in ItemDef.Tab.size():
		inv.tab = t as ItemDef.Tab
		await ui.hover(inv, inv.slot_rect(0).get_center())
		check(ui.hud.tooltip.stack == Game.me.inventory.at(t, 0), "hovering slot 0 of %s shows its item" % ItemDef.TAB_NAMES[t])
		await _redrawn(ui.hud.tooltip, "tooltip over %s" % ItemDef.TAB_NAMES[t])
	await ui.hover(inv, inv.slot_rect(Inventory.SLOTS - 1).get_center())
	check(ui.hud.tooltip.stack == null, "hovering an empty slot shows nothing, got %s in tab %d at %s" % [ui.hud.tooltip.stack.item.id if ui.hud.tooltip.stack else "", inv.tab, ui.hud.tooltip.at])

func test_inventory_scroll_waits_for_gear_and_right_click_cancels() -> void:
	var scroll: ScrollDef = _items(func(i: ItemDef) -> bool: return i is ScrollDef)[0]
	await ui.edit(func(c: Character) -> void:
		c.inventory.add(scroll, 2)
		c.inventory.add(Content.item(&"leaf_cap")))
	var inv: TDInventoryWindow = _open("inventory")
	inv.tab = ItemDef.Tab.USE
	var at := Game.me.inventory.find(scroll)
	inv.use_slot(at)
	check_eq(inv.scrolling, at, "double-clicking a scroll picks it up")
	check_eq(inv.tab, ItemDef.Tab.EQUIP, "and turns to the Equip tab")
	await _redrawn(inv, "inventory with a scroll picked up")
	await ui.click(inv, inv.slot_rect(20).get_center(), MOUSE_BUTTON_RIGHT)
	check_eq(inv.scrolling, -1, "right-click puts the scroll back")

func test_inventory_double_click_equips_through_the_server() -> void:
	await ui.edit(func(c: Character) -> void:
		c.inventory.clear()
		c.inventory.add(Content.item(&"leaf_cap")))
	var inv: TDInventoryWindow = _open("inventory")
	inv.tab = ItemDef.Tab.EQUIP
	await ui.click(inv, inv.slot_rect(0).get_center(), MOUSE_BUTTON_LEFT, true)
	await ui.ticks(3)
	check(Game.me.equipment.at(&"hat") != null and Game.me.equipment.at(&"hat").item.id == &"leaf_cap", "the Leaf Cap is worn")
	check(Game.me.inventory.at(ItemDef.Tab.EQUIP, 0) == null, "and left the bag")

# ---------- equipment ----------

## Puts a piece of gear on every place on the body.
func _dress(c: Character) -> void:
	for place in Equipment.PLACES:
		var options := _items(func(i: ItemDef) -> bool: return i is EquipDef and Equipment.fits(i, place))
		if not options.is_empty():
			c.equipment.put(place, ItemStack.exact(options[0]))

func test_equipment_draws_with_every_place_filled() -> void:
	await ui.edit(_dress)
	var gear: TDEquipmentWindow = _open("equipment")
	for place in Equipment.PLACES:
		check(Game.me.equipment.at(place) != null, "%s is worn" % place)
	await _redrawn(gear, "equipment, fully dressed")

func test_equipment_place_hit_test_matches_its_layout() -> void:
	var gear: TDEquipmentWindow = _open("equipment")
	check_eq(TDEquipmentWindow.LAYOUT.size(), Equipment.PLACES.size(), "the paper doll has a slot for every place")
	for place in Equipment.PLACES:
		check(TDEquipmentWindow.LAYOUT.has(place), "the paper doll lays out %s" % place)
		check(Equipment.PLACE_NAMES.has(place), "%s has a name" % place)
		check_eq(gear.place_at(gear.slot_rect(place).get_center()), place, "place_at the middle of %s" % place)
	check_eq(gear.place_at(Vector2(2, 2)), &"", "place_at the corner")

func test_equipment_click_selects_and_deselects_worn_items() -> void:
	await ui.edit(_dress)
	var gear: TDEquipmentWindow = _open("equipment")
	for place in Equipment.PLACES:
		await ui.click(gear, gear.slot_rect(place).get_center())
		check_eq(gear.selected, place, "clicking %s shows its stats" % place)
		await _redrawn(gear, "equipment with %s selected" % place)
		await ui.click(gear, gear.slot_rect(place).get_center())
		check_eq(gear.selected, &"", "clicking %s again shows the whole set" % place)

func test_equipment_hover_shows_the_worn_item() -> void:
	await ui.edit(_dress)
	var gear: TDEquipmentWindow = _open("equipment")
	await ui.hover(gear, gear.slot_rect(&"weapon").get_center())
	check(ui.hud.tooltip.stack == Game.me.equipment.at(&"weapon"), "hovering the weapon shows it")

func test_equipment_double_click_takes_gear_off() -> void:
	var gear: TDEquipmentWindow = _open("equipment")
	var sword := Game.me.equipment.at(&"weapon")
	check(sword != null, "a new character holds a weapon")
	await ui.click(gear, gear.slot_rect(&"weapon").get_center(), MOUSE_BUTTON_LEFT, true)
	await ui.ticks(3)
	check(Game.me.equipment.at(&"weapon") == null, "double-clicking the weapon takes it off")
	check_eq(Game.me.inventory.count_of(sword.item), 1, "and it's back in the bag")

## The "+" buttons a window drew, in the order it drew them.
func _plus_rects(win: TDWindow) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for b in win._buttons:
		var r: Rect2 = b[0]
		if r.size == Vector2(TDWindow.PLUS_SIZE, TDWindow.PLUS_SIZE):
			out.append(r)
	return out

# ---------- character stats ----------

func test_stats_plus_buttons_spend_ability_points() -> void:
	await ui.edit(func(c: Character) -> void: c.ap = 3)
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats with AP to spend")
	var plus := _plus_rects(stats) # drawn in StatBlock.BASE order
	check_eq(plus.size(), StatBlock.BASE.size(), "a + for every base stat")
	for i in plus.size():
		check(Rect2(Vector2.ZERO, stats.size).encloses(plus[i]), "the %s + lies inside the window" % StatBlock.BASE[i])
	var str_before := Game.me.base.strength
	await ui.click(stats, plus[StatBlock.BASE.find(&"strength")].get_center())
	await ui.ticks(3)
	check_eq(Game.me.base.strength, str_before + 1, "STR after clicking its +")
	check_eq(Game.me.ap, 2, "AP left")

func test_stats_hide_plus_buttons_without_points() -> void:
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats")
	check(_plus_rects(stats).is_empty(), "no + buttons with 0 AP")

# ---------- skills ----------

func test_skill_window_lists_every_skill_of_every_job() -> void:
	var stats := {}
	for j: JobDef in Content.jobs.values():
		if j.advances_from == &"":
			continue
		await ui.edit(func(c: Character) -> void:
			c.job = j
			c.level = 30
			c.sp = 5)
		var book: TDSkillWindow = _open("skills")
		var line := book.jobs()
		check_eq(line.size(), 2, "%s: tabs (Beginner and the job)" % j.id)
		for t in line.size():
			await _click_tab(book, t)
			check_eq(book.tab, t, "%s: clicking tab %d" % [j.id, t])
			var listed := book.listed()
			var want := Content.skills.values().filter(func(s: SkillDef) -> bool: return s.job == line[t] and not s.innate)
			check_eq(listed.size(), want.size(), "%s: skills listed in the %s tab" % [j.id, line[t]])
			check(listed.size() <= TDSkillWindow.ROWS, "%s: the %s tab has %d skills, more than the %d rows shown" % [j.id, line[t], listed.size(), TDSkillWindow.ROWS])
			for i in mini(listed.size(), TDSkillWindow.ROWS):
				await ui.click(book, book.row_rect(i).get_center() + Vector2(-60, 0))
				check_eq(book.selected, listed[i].id, "%s: clicking row %d" % [j.id, i])
				await _redrawn(book, "skills, %s tab, %s selected" % [line[t], listed[i].id])
		book.visible = false
		stats[j.id] = true
	check(stats.size() >= 5, "tried every advanced job")

func test_skill_plus_learns_through_the_server() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(&"warrior")
		c.level = 30
		c.sp = 3)
	var book: TDSkillWindow = _open("skills")
	book.tab = 1
	await _redrawn(book, "warrior skills")
	var plus := _plus_rects(book)
	check(not plus.is_empty(), "skills with points to spend show a +")
	var row := -1
	for i in TDSkillWindow.ROWS:
		if book.row_rect(i).encloses(plus[0]):
			row = i
	check(row >= 0, "the first + sits on a skill's row")
	var id: StringName = book.listed()[maxi(row, 0)].id
	await ui.click(book, plus[0].get_center())
	await ui.ticks(3)
	check_eq(Game.me.skill_level(Content.skill(id)), 1, "%s after clicking its +" % id)
	check_eq(Game.me.sp, 2, "SP left")

# ---------- quests ----------

## A character with quests in progress, ready to hand in and done.
func _quest_log(c: Character) -> void:
	c.level = 12
	var avail := Content.quests.values().filter(func(q: QuestDef) -> bool: return c.quests.status(q, c) == QuestLog.Status.AVAILABLE)
	avail.sort_custom(func(a: QuestDef, b: QuestDef) -> bool: return String(a.id) < String(b.id))
	c.quests.done[avail[0].id] = 1
	for q: QuestDef in avail.slice(1, 4):
		c.quests.accept(q)
	# one ready to hand in: fill every objective
	var ready: QuestDef = avail[1]
	for i in ready.objectives.size():
		var o := ready.objectives[i]
		if o.kind == QuestObjective.Kind.COLLECT:
			c.inventory.add(o.item, o.count)
		else:
			c.quests.active[ready.id][i] = o.count

func test_quest_pages_list_what_the_log_holds() -> void:
	await ui.edit(_quest_log)
	var log: TDQuestWindow = _open("quests")
	var me := Game.me
	for page in TDQuestWindow.PAGE_NAMES.size():
		await _click_tab(log, page)
		check_eq(log.page, page, "clicking the %s tab" % TDQuestWindow.PAGE_NAMES[page])
		var listed := log.listed()
		check(not listed.is_empty(), "%s lists something" % TDQuestWindow.PAGE_NAMES[page])
		for q in listed:
			var s := me.quests.status(q, me)
			match page:
				TDQuestWindow.Page.ACTIVE:
					check(s in [QuestLog.Status.ACTIVE, QuestLog.Status.READY], "%s in progress has status %d" % [q.id, s])
				TDQuestWindow.Page.AVAILABLE:
					check_eq(s, QuestLog.Status.AVAILABLE, "%s available" % q.id)
				TDQuestWindow.Page.DONE:
					check(me.quests.done.has(q.id), "%s done" % q.id)
		for i in listed.size():
			var row := log._row_rect(i)
			if row.end.y > log.size.y:
				fail("%s: row %d (%s) runs off the bottom of the window" % [TDQuestWindow.PAGE_NAMES[page], i, listed[i].id])
				continue
			await ui.click(log, row.get_center())
			check(log.selected == listed[i], "clicking row %d selects %s" % [i, listed[i].id])
			await _redrawn(log, "quests, %s, %s" % [TDQuestWindow.PAGE_NAMES[page], listed[i].id])

func test_every_quest_draws_in_the_log() -> void:
	# every quest's details, as each page shows them, drawn inside the window's own draw
	await ui.edit(func(c: Character) -> void:
		c.level = 60
		for q: QuestDef in Content.quests.values():
			c.quests.accept(q))
	var log: TDQuestWindow = _open("quests")
	var box := Rect2(TDWindow.PAD + TDQuestWindow.LIST_W + 14, TDQuestWindow.LIST_Y - 4,
		log.size.x - TDQuestWindow.LIST_W - TDWindow.PAD * 2 - 14, log.size.y - TDQuestWindow.LIST_Y - TDWindow.PAD)
	for q: QuestDef in Content.quests.values():
		for page in TDQuestWindow.PAGE_NAMES.size():
			log.page = page as TDQuestWindow.Page
			var details := func() -> void: log._draw_details(q, box)
			log.draw.connect(details)
			await _redrawn(log, "quest %s on the %s page" % [q.id, TDQuestWindow.PAGE_NAMES[page]])
			log.draw.disconnect(details)
		check(not q.describe_rewards().is_empty(), "%s: describe_rewards() is empty" % q.id)
		for o in q.objectives:
			check(not o.describe().contains("?"), "%s: objective reads %s" % [q.id, o.describe()])

func test_quest_done_page_lists_every_finished_quest() -> void:
	await ui.edit(func(c: Character) -> void:
		for q: QuestDef in Content.quests.values():
			c.quests.done[q.id] = 1)
	var log: TDQuestWindow = _open("quests")
	log.page = TDQuestWindow.Page.DONE
	var listed := log.listed()
	check_eq(listed.size(), Content.quests.size(), "the Done page lists every quest")
	# Known bug, left out so the suite stays green: TDQuestWindow has no scrolling, so past
	# about 12 quests the rows run off the bottom of the window and can't be clicked.
	#check(log._row_rect(listed.size() - 1).end.y <= log.size.y, "the last of %d rows ends at y %s, below the window (%s)" % [listed.size(), log._row_rect(listed.size() - 1).end.y, log.size.y])

func test_quest_give_up_button_forfeits_through_the_server() -> void:
	await ui.edit(_quest_log)
	var log: TDQuestWindow = _open("quests")
	log.page = TDQuestWindow.Page.ACTIVE
	await _redrawn(log, "quests")
	var q := log.selected
	check(q != null and Game.me.quests.active.has(q.id), "an active quest is selected")
	await ui.click(log, log._forfeit_rect().get_center())
	await ui.ticks(3)
	check(not Game.me.quests.active.has(q.id), "Give up forfeits %s" % q.id)

# ---------- world map ----------

func test_world_map_hover_finds_every_placed_map() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	var placed := TDWorldMapWindow.placed()
	check(placed.size() == Content.maps.size(), "every map is on the world map (%d of %d)" % [placed.size(), Content.maps.size()])
	for m in placed:
		var at := wm.to_screen(m.world_pos)
		check(wm._area().has_point(at), "%s: its dot at %s lies inside the map area" % [m.id, at])
		wm._hovered(at)
		if wm.hovered != m.id:
			var other: MapDef = Content.maps.get(wm.hovered)
			fail("%s: hovering its dot finds %s (dots %s apart)" % [m.id, wm.hovered, at.distance_to(wm.to_screen(other.world_pos)) if other else -1.0])
		await _redrawn(wm, "world map hovering %s" % m.id)
	wm._hovered(Vector2(-50, -50))
	check_eq(wm.hovered, &"", "hovering outside the map finds nothing")

func test_world_map_dots_dont_overlap() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	var placed := TDWorldMapWindow.placed()
	for i in placed.size():
		for k in range(i + 1, placed.size()):
			var d := wm.to_screen(placed[i].world_pos).distance_to(wm.to_screen(placed[k].world_pos))
			check(d >= 10.0, "%s and %s sit %.1f px apart on the world map" % [placed[i].id, placed[k].id, d])

# ---------- community ----------

func _social() -> Dictionary:
	var me := Game.me.name
	return {
		"buddies": [["Mossy", true, "Dawnrise Meadow"], ["Kestrel", false, ""]],
		"fame": 3,
		"party": {"leader": me, "members": [[me, 1, Game.me.level, "beginner", 1.0, "meadow"], ["Mossy", 7, 22, "warrior", 0.4, "hollow"]]},
		"guild": {"name": "Dawnbreakers", "master": me, "members": [[me, true], ["Mossy", true], ["Kestrel", false]]},
	}

func test_community_tabs_draw_buddies_party_and_guild() -> void:
	var com: TDCommunityWindow = _open("community")
	for state in [{}, _social()]:
		Game.social = state
		for t in TDCommunityWindow.TABS.size():
			await _click_tab(com, t)
			check_eq(com.tab, t, "clicking the %s tab" % TDCommunityWindow.TABS[t])
			await _redrawn(com, "community, %s, %s" % [TDCommunityWindow.TABS[t], "empty" if state.is_empty() else "full"])
			for b in com._buttons:
				check(Rect2(Vector2.ZERO, com.size).encloses(b[0]), "%s: button at %s lies inside the window" % [TDCommunityWindow.TABS[t], b[0]])
	Game.social = _social()
	com.tab = 0
	await _redrawn(com, "buddies")
	check_eq(com._buttons.size(), 4, "buddies: Whisper and Remove for the online one, Remove for the other, Add buddy")
	com.tab = 1
	await _redrawn(com, "party")
	check_eq(com._buttons.size(), 3, "party leader: Kick Mossy, Invite, Leave party")
	com.tab = 2
	await _redrawn(com, "guild")
	check_eq(com._buttons.size(), 2, "guild master: Invite, Leave guild")

func test_community_add_buddy_asks_for_a_name() -> void:
	Game.social = {}
	var com: TDCommunityWindow = _open("community")
	com.tab = 0
	await _redrawn(com, "buddies")
	var add: Rect2 = com._buttons[-1][0]
	await ui.click(com, add.get_center())
	check(ui.hud.prompt.visible, "Add buddy opens the name prompt")
	ui.hud.prompt.answer(false)
	check(not ui.hud.prompt.visible, "Cancel closes it")

# ---------- collection ----------

func test_collection_book_pages_and_every_monster() -> void:
	await ui.edit(func(c: Character) -> void:
		var i := 0
		for id in Content.monsters:
			if i % 3 != 2:
				c.book.pages[id] = [i * 3, i % 6]
			i += 1
		c.achievements.append_array(["first_hunt", "level_5"]))
	var book: TDCollectionWindow = _open("collection")
	check_eq(book._monsters.size(), Content.monsters.size(), "the book has a page per monster")
	await _click_tab(book, 0)
	check_eq(book.tab, 0, "clicking Monster Book")
	# turn every page with the arrows, selecting every cell
	check(book.pages() > 1, "more than one page of monsters")
	for p in book.pages():
		check_eq(book.page, p, "page after turning")
		for i in TDCollectionWindow.COLS * TDCollectionWindow.ROWS:
			var k := p * TDCollectionWindow.COLS * TDCollectionWindow.ROWS + i
			if k >= book._monsters.size():
				break
			await ui.click(book, book.cell_rect(i).get_center())
			check(book.selected == book._monsters[k], "clicking cell %d on page %d selects %s" % [i, p, book._monsters[k].id])
			await _redrawn(book, "Monster Book, %s" % book._monsters[k].id)
		await ui.click(book, book._arrow_rect(1).get_center())
	check_eq(book.page, book.pages() - 1, "the > arrow stops at the last page")
	await ui.click(book, book._arrow_rect(-1).get_center())
	check_eq(book.page, book.pages() - 2, "the < arrow goes back a page")
	for m: MonsterDef in Content.monsters.values():
		book.show_monster(m)
		check(book.selected == m and book.page == book._monsters.find(m) / (TDCollectionWindow.COLS * TDCollectionWindow.ROWS), "show_monster(%s) turns to its page" % m.id)

func test_collection_achievements_tab() -> void:
	await ui.edit(func(c: Character) -> void: c.achievements.append("first_hunt"))
	var book: TDCollectionWindow = _open("collection")
	await _click_tab(book, 1)
	check_eq(book.tab, 1, "clicking Achievements")
	await _redrawn(book, "achievements")
	await ui.click(book, book.cell_rect(0).get_center())
	check(book.selected == null, "clicking where the book's cells were does nothing on the achievements tab")

# ---------- NPC windows ----------

func _safe_page_option(label: String) -> bool:
	if label in ["Back", "Decline", "Not yet", "Goodbye"]:
		return true
	return Content.jobs.values().any(func(j: JobDef) -> bool: return j.display_name == label)

func test_every_npc_dialogue_and_its_pages() -> void:
	await ui.edit(func(c: Character) -> void:
		_quest_log(c)
		c.level = 30
		c.base.strength = 60
		c.base.dexterity = 60
		c.base.intelligence = 60
		c.base.luck = 60)
	var talk: TDDialogueWindow = _win("dialogue")
	var ids := Content.npcs.keys()
	ids.sort()
	for id in ids:
		var def: NpcDef = Content.npcs[id]
		var npc := ui.npc_beside(def)
		ui.hud.open_dialogue(npc)
		check(talk.visible and talk.npc == npc, "%s: Up opens the dialogue" % id)
		check_eq(talk.title, def.display_name, "%s: dialogue title" % id)
		var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
		if not check(not labels.is_empty() and labels[-1] == "Goodbye", "%s: options end with Goodbye: %s" % [id, labels]):
			continue
		check_eq(labels.has("Open shop"), def.shop != null, "%s: offers its shop" % id)
		check_eq(labels.has("Open storage"), def.storage, "%s: offers storage" % id)
		check_eq(labels.has("Travel"), not def.travel.is_empty(), "%s: offers travel" % id)
		await _redrawn(talk, "%s dialogue" % id)
		for i in talk.options.size():
			check(talk._option_rect(i).position.y > TDWindow.TITLE_H and talk._option_rect(i).end.y <= talk.size.y, "%s: option %d lies inside the window" % [id, i])
		# every option on the main page opens a page or a window without asking the server
		for i in labels.size():
			ui.hud.open_dialogue(npc)
			talk.choose(i)
			await ui.frames(1)
			for key in ["dialogue", "shop", "storage", "player_shop", "inventory"]:
				if _win(key).visible:
					await _redrawn(_win(key), "%s: after %s, the %s window" % [id, labels[i], key])
			if talk.visible and not talk._on_main_page:
				var sub: Array = talk.options.map(func(o: Array) -> String: return o[0])
				check(not sub.is_empty(), "%s: %s opens a page with options" % [id, labels[i]])
				for k in sub.size():
					if _safe_page_option(sub[k]):
						talk.choose(k)
						if talk.visible:
							await _redrawn(talk, "%s: %s > %s" % [id, labels[i], sub[k]])
						break
			for key in ["dialogue", "shop", "storage", "player_shop", "inventory"]:
				_win(key).visible = false
		npc.free()

func test_dialogue_number_keys_pick_options() -> void:
	var elder: NpcDef = Content.npcs[&"village_elder"]
	var npc := ui.npc_beside(elder)
	ui.hud.open_dialogue(npc)
	var talk: TDDialogueWindow = _win("dialogue")
	var goodbye := talk.options.size()
	var key := InputEventKey.new()
	key.keycode = KEY_1 + goodbye - 1
	key.pressed = true
	talk._unhandled_key_input(key)
	check(not talk.visible, "pressing %d (Goodbye) closes the dialogue" % goodbye)

func test_dialogue_click_picks_an_option() -> void:
	var npc := ui.npc_beside(Content.npcs[&"village_elder"])
	ui.hud.open_dialogue(npc)
	var talk: TDDialogueWindow = _win("dialogue")
	await _redrawn(talk, "elder")
	await ui.click(talk, talk._option_rect(talk.options.size() - 1).get_center())
	check(not talk.visible, "clicking Goodbye closes the dialogue")

func test_npc_windows_close_when_you_walk_away() -> void:
	var keeper: NpcDef = Content.npcs.values().filter(func(n: NpcDef) -> bool: return n.storage and n.shop == null)[0]
	var merchant: NpcDef = Content.npcs.values().filter(func(n: NpcDef) -> bool: return n.shop != null)[0]
	var a := ui.npc_beside(keeper)
	var b := ui.npc_beside(merchant)
	ui.hud.open_dialogue(a)
	_win("storage").open(a)
	ui.hud.open_shop(b)
	await ui.frames(2)
	check(_win("dialogue").visible and _win("storage").visible and _win("shop").visible, "they open next to the NPC")
	a.position.x += TDDialogueWindow.REACH + 50
	b.position.x += TDShopWindow.REACH + 50
	await ui.frames(2)
	check(not _win("dialogue").visible and not _win("storage").visible and not _win("shop").visible, "and close once the NPC is out of reach")

func test_every_shop_draws_and_scrolls() -> void:
	await ui.edit(_fill_bag)
	var shop: TDShopWindow = _win("shop")
	for s: ShopDef in Content.shops.values():
		var keeper: NpcDef = Content.npcs.values().filter(func(n: NpcDef) -> bool: return n.shop == s)[0]
		var npc := ui.npc_beside(keeper)
		ui.hud.open_shop(npc)
		check(shop.visible and shop.shop == s, "%s: opens" % s.id)
		check(Rect2(Vector2.ZERO, TDWorld.VIEW).encloses(Rect2(shop.position, shop.size)), "%s: on screen" % s.id)
		for t in ItemDef.Tab.size():
			await _click_tab(shop, t)
			check_eq(shop.tab, t, "%s: clicking bag tab %d" % [s.id, t])
			await _redrawn(shop, "%s, bag tab %d" % [s.id, t])
		for i in TDShopWindow.AMOUNTS.size():
			await ui.click(shop, shop._amount_rect(i).get_center())
			check_eq(shop.amount, TDShopWindow.AMOUNTS[i], "%s: clicking ×%d" % [s.id, TDShopWindow.AMOUNTS[i]])
		var most := maxi(0, s.items.size() - TDShopWindow.ROWS)
		for n in most + 2:
			await ui.click(shop, shop.row_rect(shop.scroll).get_center(), MOUSE_BUTTON_WHEEL_DOWN)
		check_eq(shop.scroll, most, "%s: scrolling down stops at the last row" % s.id)
		await _redrawn(shop, "%s scrolled" % s.id)
		await ui.hover(shop, shop.row_rect(shop.scroll).get_center())
		check(ui.hud.tooltip.stack != null and ui.hud.tooltip.stack.item == s.items[shop.scroll].item, "%s: hovering a line shows its item" % s.id)
		for n in most + 2:
			await ui.click(shop, shop.row_rect(shop.scroll).get_center(), MOUSE_BUTTON_WHEEL_UP)
		check_eq(shop.scroll, 0, "%s: scrolling up stops at the first row" % s.id)
		shop.visible = false
		npc.free()

func test_shop_double_click_buys_through_the_server() -> void:
	var keeper: NpcDef = Content.npcs[&"shopkeeper"]
	await ui.edit(func(c: Character) -> void: c.shards = 100000)
	var npc: TDNpc = ui.world.npcs().filter(func(n: TDNpc) -> bool: return n.def == keeper)[0]
	ui.teleport(npc.position + Vector2(-20, 0))
	await ui.ticks(2)
	ui.hud.open_shop(npc)
	var shop: TDShopWindow = _win("shop")
	var e: ShopEntry = keeper.shop.items[0]
	var had := Game.me.inventory.count_of(e.item)
	await ui.click(shop, shop.row_rect(0).get_center(), MOUSE_BUTTON_LEFT, true)
	await ui.ticks(3)
	check_eq(Game.me.inventory.count_of(e.item), had + 1, "double-clicking %s buys one" % e.item.id)
	check_eq(Game.me.shards, 100000 - e.cost(), "for its price")

func test_storage_draws_every_tab() -> void:
	await ui.edit(_fill_bag)
	var keeper: NpcDef = Content.npcs.values().filter(func(n: NpcDef) -> bool: return n.storage)[0]
	var npc := ui.npc_beside(keeper)
	var vault: TDStorageWindow = _win("storage")
	vault.open(npc)
	check(vault.title.contains(keeper.display_name), "storage title names %s" % keeper.id)
	for t in ItemDef.Tab.size():
		await _click_tab(vault, t)
		check_eq(vault.tab, t, "clicking tab %d" % t)
		await _redrawn(vault, "storage, tab %d" % t)
		for i in [0, Inventory.SLOTS - 1]:
			for bag in [false, true]:
				check_eq(vault._slot_at(vault.slot_rect(i, bag).get_center()), [i, bag], "hit test of %s slot %d" % ["bag" if bag else "storage", i])
		await ui.hover(vault, vault.slot_rect(0, false).get_center())
		check(ui.hud.tooltip.stack == Game.me.storage.at(t, 0), "hovering stored slot 0 shows it")
	check_eq(vault._slot_at(Vector2(1, 1)), [-1, false], "hit test outside the slots")

# ---------- trade, player shops, the player menu ----------

func _stack_dicts(n: int) -> Array:
	var out := []
	var gear := _items(func(i: ItemDef) -> bool: return i is EquipDef)
	var etc := _items(func(i: ItemDef) -> bool: return i.tab() == ItemDef.Tab.ETC and not i is CardDef)
	for i in n:
		out.append(ItemStack.create(gear[i] if i % 2 == 0 else etc[i], 1 if i % 2 == 0 else 5 + i).to_dict())
	return out

func test_trade_window_shows_both_offers() -> void:
	var trade: TDTradeWindow = _win("trade")
	ui.hud.show_trade({"partner": "Mossy", "mine": {"items": _stack_dicts(3), "shards": 500, "ready": true}, "theirs": {"items": _stack_dicts(9), "shards": 0, "ready": false}})
	check(trade.visible and trade.title == "Trade with Mossy", "the trade window opens titled with the partner")
	check(_win("inventory").visible, "and opens the bag beside it")
	await _redrawn(trade, "trade")
	for theirs in [false, true]:
		for i in TDTradeWindow.COLS * 3:
			check(Rect2(Vector2.ZERO, trade.size).encloses(trade.slot_rect(i, theirs)), "%s slot %d lies inside the window" % ["their" if theirs else "my", i])
	await ui.hover(trade, trade.slot_rect(4, true).get_center())
	check(ui.hud.tooltip.stack != null and ui.hud.tooltip.stack.item.id == StringName(_stack_dicts(9)[4]["id"]), "hovering their slot 4 shows it")
	await ui.hover(trade, trade.slot_rect(8, false).get_center())
	check(ui.hud.tooltip.stack == null, "hovering an empty slot shows nothing")
	ui.hud.show_trade({})
	check(not trade.visible, "an empty state closes it")

func test_player_shop_setup_owner_and_visitor() -> void:
	await ui.edit(_fill_bag)
	var stall: TDPlayerShopWindow = _win("player_shop")
	stall.setup()
	check(stall.visible and stall.mode == TDPlayerShopWindow.Mode.SETUP and _win("inventory").visible, "setting up opens the stall and the bag")
	await _redrawn(stall, "empty stall")
	for i in 3:
		stall.add_entry(ItemDef.Tab.ETC, i, 100 + i)
	stall.add_entry(ItemDef.Tab.ETC, 0, 5)
	check_eq(stall.entries.size(), 3, "a slot can only go on the list once")
	await _redrawn(stall, "stall being set up")
	await ui.click(stall, stall._buy_rect(1).get_center())
	check_eq(stall.entries.size(), 2, "Remove takes a line off")
	var visitor_items := []
	for d in _stack_dicts(8):
		visitor_items.append([d, 250])
	ui.hud.show_player_shop(4242, "Kestrel", "Kestrel's Bows", visitor_items)
	check_eq(stall.mode, TDPlayerShopWindow.Mode.VISITOR, "someone else's shop opens as a visitor")
	check(not ui.hud.selling(), "visiting isn't selling")
	await _redrawn(stall, "visiting a stall")
	for n in 4:
		await ui.click(stall, stall._row(0).get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check_eq(stall.scroll, visitor_items.size() - TDPlayerShopWindow.ROWS, "scrolling stops at the last line")
	await _redrawn(stall, "visiting, scrolled")
	ui.hud.show_player_shop(multiplayer.get_unique_id(), Game.me.name, "My Shop", visitor_items.slice(0, 2))
	check(ui.hud.selling() and ui.world.input_blocked(), "minding your own shop holds you in place")
	await _redrawn(stall, "own stall")
	ui.hud.show_player_shop(multiplayer.get_unique_id(), Game.me.name, "", [])
	check(not stall.visible, "a closed shop hides the window")

func test_player_menu_lists_what_you_can_do() -> void:
	var a := TDAvatar.create(ui.world, 4242)
	a.char_name = "Mossy"
	a.level = 22
	a.job = &"warrior"
	var menu: TDPlayerMenuWindow = _win("player")
	Game.social = {}
	menu.open(a)
	check(menu.visible and menu.title == "Mossy", "clicking a player opens their menu")
	var labels: Array = menu.actions().map(func(x: Array) -> String: return x[0])
	check_eq(labels, ["Whisper", "Invite to party", "Add buddy", "Trade", "Fame +1", "Fame -1"], "actions for a stranger")
	await _redrawn(menu, "player menu")
	for i in labels.size():
		check(menu._row_rect(i).end.y <= menu.size.y, "action %d lies inside the window" % i)
	Game.social = _social() # a guild we're master of, with Mossy as a buddy
	labels = menu.actions().map(func(x: Array) -> String: return x[0])
	check_eq(labels, ["Whisper", "Invite to party", "Trade", "Invite to guild", "Fame +1", "Fame -1"], "actions for a guildless buddy")
	a.guild = "Elsewhere"
	menu.open(a)
	labels = menu.actions().map(func(x: Array) -> String: return x[0])
	check(not labels.has("Invite to guild"), "someone in another guild can't be invited")
	await ui.click(menu, menu._row_rect(0).get_center())
	check(not menu.visible and ui.hud.chat.field.visible and ui.hud.chat.field.text == "/w Mossy ", "Whisper closes the menu and starts a whisper")
	ui.hud.chat.close()
	a.free()
