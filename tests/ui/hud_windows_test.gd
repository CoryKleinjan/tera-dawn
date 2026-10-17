extends TestCase
## Every window the HUD registers, opened in a running single-player game with a character
## that has something in every tab: it draws, its tabs switch on click, its hit tests find
## what's drawn where, and what it lists matches the character. Windows NPCs open are
## tried with every NPC, shop and storage; trade and the player menu with
## the server's kind of state. (tests/run_all.sh fails on any script error they print.)

const KNOWN := ["inventory", "equipment", "stats", "quests", "skills", "worldmap", "community", "collection",
	"dialogue", "shop", "storage", "player", "trade"]

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
			func(i: ItemDef) -> bool: return i.tab() == ItemDef.Tab.ETC and not i is CardDef,
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
		if r.size.x == r.size.y: # the "+" buttons are the only square ones
			out.append(r)
	return out

# ---------- character stats ----------

func test_stats_plus_buttons_buy_with_dawn_essence() -> void:
	# a fresh character: every stat's first point costs the same, and this pays for one
	await ui.edit(func(c: Character) -> void: c.essence = CharacterStats.stat_price(0))
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats with essence to spend")
	var plus := _plus_rects(stats) # drawn in StatBlock.BASE order
	check_eq(plus.size(), StatBlock.BASE.size(), "a + for every base stat")
	for i in plus.size():
		check(Rect2(Vector2.ZERO, stats.size).encloses(plus[i]), "the %s + lies inside the window" % StatBlock.BASE[i])
	var str_before := Game.me.base.strength
	var price := Game.me.ap.price(&"strength")
	check_eq(price, CharacterStats.stat_price(0), "the first STR point costs the base price")
	await ui.click(stats, plus[StatBlock.BASE.find(&"strength")].get_center())
	await ui.ticks(3)
	check_eq(Game.me.base.strength, str_before + 1, "STR after clicking its +")
	check_eq(Game.me.essence, 0, "the point's price was paid")
	check_eq(Game.me.ap.price(&"strength"), CharacterStats.stat_price(1), "the next STR point costs more")
	await _redrawn(stats, "stats with no essence left")
	check(_plus_rects(stats).is_empty(), "no + buttons once the essence is spent")

func test_stats_window_leaves_the_status_bar_visible() -> void:
	var stats: TDStatsWindow = _open("stats")
	check(stats.position.y + stats.size.y < TDWorld.VIEW.y - TDStatusBar.HEIGHT, "ends above the HP bar")

func test_stats_hide_plus_buttons_without_essence() -> void:
	await ui.edit(func(c: Character) -> void: c.essence = 0)
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats")
	check(_plus_rects(stats).is_empty(), "no + buttons with no Dawn Essence")
	check(not TDStatsWindow.can_buy_any(Game.me), "nothing to buy")

func test_stats_show_plus_only_where_the_essence_pays() -> void:
	# five STR points bought make the next one dearer than a first point anywhere else
	await ui.edit(func(c: Character) -> void:
		c.essence = 1000000
		c.ap.buy(&"strength", 5)
		c.essence = CharacterStats.stat_price(0))
	check(Game.me.ap.price(&"strength") > Game.me.essence, "STR costs more than the essence in hand")
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats with essence for some stats")
	check_eq(_plus_rects(stats).size(), StatBlock.BASE.size() - 1, "a + for every stat but STR")
	check(TDStatsWindow.can_buy_any(Game.me), "something to buy")

func test_stats_window_for_a_beginner() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(Character.START_JOB)
		c.essence = 1000000)
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats for a Beginner")
	check_eq(stats.size.y, TDStatsWindow.BASE_H, "no job paths, no extra room")
	check(stats.position.y + stats.size.y < TDWorld.VIEW.y - TDStatusBar.HEIGHT, "ends above the HP bar (%s)" % (stats.position.y + stats.size.y))
	check(stats.content_end <= stats.size.y - 16, "the rows fit")
	check_eq(stats.auto_rect, Rect2(), "no Auto button for a Beginner")
	check_eq(_plus_rects(stats).size(), StatBlock.BASE.size(), "a + for every stat")

func test_stats_window_for_a_warrior() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(&"warrior"))
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats for a Warrior")
	check_eq(stats.size.y, TDStatsWindow.BASE_H, "the same height as a Beginner's")
	check(stats.content_end <= stats.size.y - 16, "the rows fit")

func test_stats_auto_buys_damage_stats_through_the_server() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(&"thief")
		c.essence = 600)
	var stats: TDStatsWindow = _open("stats")
	await _redrawn(stats, "stats with an Auto button")
	check(stats.auto_rect.size.x > 0 and Rect2(Vector2.ZERO, stats.size).encloses(stats.auto_rect), "Auto lies inside the window")
	# what AbilityPoints.auto should buy: the cheaper damage stat each time, while the essence lasts
	var main := Game.me.job.damage_stats()
	var bought := {}
	for stat in main:
		bought[stat] = Game.me.ap.bought(stat)
	var left := Game.me.essence
	var want := {}
	while true:
		var next: StringName = main[0]
		for stat in main:
			if CharacterStats.stat_price(bought[stat]) < CharacterStats.stat_price(bought[next]):
				next = stat
		var price := CharacterStats.stat_price(bought[next])
		if left < price:
			break
		left -= price
		bought[next] += 1
		want[next] = int(want.get(next, 0)) + 1
	var before := Game.me.base.copy()
	await ui.click(stats, stats.auto_rect.get_center())
	await ui.ticks(3)
	check_eq(Game.me.essence, left, "Dawn Essence left once the next point costs too much")
	for stat in StatBlock.BASE:
		check_eq(Game.me.base.value(stat) - before.value(stat), int(want.get(stat, 0)), "%s as Auto buys it" % stat)
	check(int(want.get(&"luck", 0)) > 0, "the thief's LUK gets points")

func test_status_bar_glows_while_essence_waits() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(&"warrior")
		c.essence = 0)
	check(not TDStatusBar.has_points_waiting("stats") and not TDStatusBar.has_points_waiting("skills"), "nothing to spend, no glow")
	await ui.edit(func(c: Character) -> void: c.essence = 100000)
	check(TDStatusBar.has_points_waiting("stats"), "the Character button glows when the essence buys a stat")
	check(TDStatusBar.has_points_waiting("skills"), "the Skills button glows when it buys a skill level")
	check(not TDStatusBar.has_points_waiting("inventory"), "other buttons don't")
	check(await ui.redraw(ui.hud.status), "the status bar draws the glow")

# ---------- skills ----------

func test_skill_window_lists_every_skill_of_every_job() -> void:
	var stats := {}
	for j: JobDef in Content.jobs.values():
		if j.advances_from == &"":
			continue
		await ui.edit(func(c: Character) -> void:
			c.job = j
			c.essence = 100000)
		var book: TDSkillWindow = _open("skills")
		var line := book.jobs()
		if j.partner == &"":
			check_eq(line.size(), 2, "%s: tabs (Beginner and the job)" % j.id)
		else:
			check_eq(line, [Character.START_JOB, j.advances_from, j.partner, j.id] as Array[StringName], "%s: tabs (Beginner, both parents, the blend)" % j.id)
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
		c.essence = c.skills.price())
	var book: TDSkillWindow = _open("skills")
	book.tab = 1
	await _redrawn(book, "warrior skills")
	var plus := _plus_rects(book)
	check(not plus.is_empty(), "skills the essence pays for show a +")
	var row := -1
	for i in TDSkillWindow.ROWS:
		if book.row_rect(i).encloses(plus[0]):
			row = i
	check(row >= 0, "the first + sits on a skill's row")
	var id: StringName = book.listed()[maxi(row, 0)].id
	await ui.click(book, plus[0].get_center())
	await ui.ticks(3)
	check_eq(Game.me.skills.level(Content.skill(id)), 1, "%s after clicking its +" % id)
	check_eq(Game.me.essence, 0, "the level's price was paid")
	check_eq(Game.me.skills.price(), CharacterStats.skill_price(1), "the next skill level costs more")

# ---------- quests ----------

## A character with quests in progress, ready to hand in and done.
func _quest_log(c: Character) -> void:
	# past the Job Tests (five of them, one per tutor; a Warrior may still take the other four)
	c.job = Content.job(&"warrior")
	for job in JobDef.paths_from(Character.START_JOB):
		c.quests.done[job.advance_quest.id] = 1
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
		# rows past the first screenful scroll into view (test_quest_done_page_lists_every_finished_quest)
		for i in mini(listed.size(), TDQuestWindow.ROWS):
			var row := log.row_rect(i)
			if row.end.y > log.size.y:
				fail("%s: row %d (%s) runs off the bottom of the window" % [TDQuestWindow.PAGE_NAMES[page], i, listed[i].id])
				continue
			await ui.click(log, row.get_center())
			check(log.selected == listed[i], "clicking row %d selects %s" % [i, listed[i].id])
			await _redrawn(log, "quests, %s, %s" % [TDQuestWindow.PAGE_NAMES[page], listed[i].id])

func test_every_quest_draws_in_the_log() -> void:
	# every quest's details, as each page shows them, drawn inside the window's own draw
	await ui.edit(func(c: Character) -> void:
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
	log.list.scroll = 0
	await _redrawn(log, "the Done page")
	check(listed.size() > TDQuestWindow.ROWS, "more quests than fit, so the list scrolls")
	for i in range(log.list.scroll, mini(log.list.scroll + TDQuestWindow.ROWS, listed.size())):
		check(log.row_rect(i).end.y <= log.size.y - TDWindow.PAD, "row %d ends at y %s, inside the window (%s)" % [i, log.row_rect(i).end.y, log.size.y])
	for n in listed.size():
		await ui.click(log, log.row_rect(log.list.scroll).get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check_eq(log.list.scroll, listed.size() - TDQuestWindow.ROWS, "the wheel scrolls to the last quest and stops")
	var last := listed.size() - 1
	check(log.row_rect(last).end.y <= log.size.y - TDWindow.PAD, "the last row is inside the window once scrolled")
	await ui.click(log, log.row_rect(last).get_center())
	check(log.selected == listed[last], "clicking the last row selects the last quest")
	await ui.click(log, log.row_rect(last - 1).get_center(), MOUSE_BUTTON_WHEEL_UP)
	check_eq(log.list.scroll, listed.size() - TDQuestWindow.ROWS - 1, "the wheel scrolls back up")
	await ui.click(log, log.row_rect(log.list.scroll).get_center())
	check(log.selected == listed[log.list.scroll], "clicking the top row selects the quest shown there")
	await _redrawn(log, "the scrolled Done page")

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

func test_world_map_shows_the_major_routes_between_cities() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	wm.open_zone(&"")
	check(WorldRoutes.routes().size() > 0, "the world has major routes")
	for r: RegionDef in Content.regions.values():
		var at := wm.to_screen(TDWorldMapWindow.capital_pos(r))
		check(wm._area().has_point(at), "%s: its city at %s lies inside the map area" % [r.id, at])
		wm._hovered(at)
		check_eq(wm.hovered_region, r.id, "hovering %s's city finds the region" % r.id)
		await _redrawn(wm, "world map hovering %s" % r.id)
	wm._hovered(Vector2(-50, -50))
	check_eq(wm.hovered_region, &"", "hovering outside the map finds nothing")

func test_world_map_opens_on_the_zone_you_are_in() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	var here: MapDef = Content.maps[wm._here()]
	check(Content.regions.has(here.region), "the start map %s is in a zone" % here.id)
	check_eq(wm.zone, here.region, "the map opens on %s, where you are" % here.region)
	await _redrawn(wm, "zone %s" % here.region)
	await ui.click(wm, wm.back_rect().get_center())
	check_eq(wm.zone, &"", "the back arrow still leads to the world view")
	wm.toggle()
	wm.toggle()
	check_eq(wm.zone, here.region, "opening it again goes back to %s" % here.region)

func test_world_map_click_opens_a_zone_and_the_arrow_goes_back() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	for r: RegionDef in Content.regions.values():
		wm.open_zone(&"")
		await _redrawn(wm, "world view")
		await ui.click(wm, wm.to_screen(TDWorldMapWindow.capital_pos(r)))
		check_eq(wm.zone, r.id, "clicking %s's city opens its zone" % r.id)
		await _redrawn(wm, "zone %s" % r.id)
		for m in TDWorldMapWindow.placed_in(r.id):
			var at := wm.spot(m)
			check(wm._area().grow(-6).has_point(at), "%s: %s's dot or room at %s lies inside the zone view" % [r.id, m.id, at])
			if wm.shows(m):
				wm._hovered(at)
				check_eq(wm.hovered, m.id, "%s: hovering %s's dot or room finds it" % [r.id, m.id])
		check(wm.zone_exits().size() > 0, "%s: the zone shows its ways out" % r.id)
		for exit in wm.zone_exits():
			check(wm._area().has_point(exit.label_at), "%s: the label %s lies inside the view" % [r.id, exit.label])
		await ui.click(wm, wm.back_rect().get_center())
		check_eq(wm.zone, &"", "%s: the back arrow returns to the world view" % r.id)

func test_world_map_zone_exits_open_the_next_zone() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	var r: RegionDef = Content.regions.values()[0]
	wm.open_zone(r.id)
	await _redrawn(wm, "zone %s" % r.id)
	var exit: Dictionary = wm.zone_exits()[0]
	await ui.click(wm, exit.label_at + Vector2(0, -4))
	check_eq(wm.zone, exit.region, "clicking %s opens that zone" % exit.label)
	wm.open_zone(&"")

func test_world_map_draws_shaped_zones_room_by_room() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	var shaped := Content.regions.values().filter(func(r: RegionDef) -> bool: return r.shaped_zone)
	check(not shaped.is_empty(), "some zone is drawn to shape")
	for r: RegionDef in shaped:
		wm.open_zone(r.id)
		var rooms := TDWorldMapWindow.placed_in(r.id)
		for m in rooms:
			check(wm._area().encloses(wm.room_rect(m)), "%s: %s's room lies inside the zone view" % [r.id, m.id])
		# only the rooms you've been to show, with the doors you've found
		Game.me.visited.clear()
		Game.me.visited.append(String(r.capital))
		await _redrawn(wm, "%s with only its city found" % r.id)
		for m in rooms:
			check_eq(wm.shows(m), m.town, "%s: %s shows only once visited" % [r.id, m.id])
		for door in wm.room_doors():
			check(door[0].town, "%s: only the city's doors show" % r.id)
		for m in rooms:
			Game.me.visited.append(String(m.id))
		await _redrawn(wm, "%s with every room found" % r.id)
		for m in rooms:
			wm._hovered(wm.spot(m))
			check_eq(wm.hovered, m.id, "%s: hovering %s's room finds it" % [r.id, m.id])
		for door in wm.room_doors():
			check(wm._area().has_point(door[1]), "%s: a door of %s lies inside the view" % [r.id, door[0].id])
	wm.open_zone(&"")

func test_world_map_painting_keeps_its_shape() -> void:
	# world_pos values are pixels of this painting: a repaint must place every dot again
	var art := UiSkin.size_of("world_map")
	check(art.distance_to(TDWorldMapWindow.WORLD) < 1.0, "the world-map units are the painting's art pixels (%s)" % art)
	var wm: TDWorldMapWindow = _open("worldmap")
	var a := wm._area()
	check(absf(a.size.aspect() - TDWorldMapWindow.WORLD.aspect()) < 0.01, "the painting is drawn unstretched (%s)" % a.size)
	for r: RegionDef in Content.regions.values():
		var v := TDWorldMapWindow.zone_view(r)
		check(absf(v.size.aspect() - TDWorldMapWindow.WORLD.aspect()) < 0.01, "%s: the zone view is unstretched (%s)" % [r.id, v])
		check(TDWorldMapWindow.INNER.grow(0.5).encloses(v), "%s: the zone view %s stays inside the painting's scroll" % [r.id, v])

func test_world_map_zone_dots_dont_overlap() -> void:
	# a zone drawn to shape has rooms, not dots: content_routes_test keeps them from overlapping
	var wm: TDWorldMapWindow = _open("worldmap")
	for r: RegionDef in Content.regions.values():
		if r.shaped_zone:
			continue
		wm.open_zone(r.id)
		var placed := TDWorldMapWindow.placed_in(r.id)
		for i in placed.size():
			for k in range(i + 1, placed.size()):
				var d := wm.to_screen(placed[i].world_pos).distance_to(wm.to_screen(placed[k].world_pos))
				check(d >= 24.0, "%s and %s sit %.1f px apart in the %s zone view" % [placed[i].id, placed[k].id, d, r.id])
	wm.open_zone(&"")

func test_world_map_cities_keep_off_region_names() -> void:
	var wm: TDWorldMapWindow = _open("worldmap")
	wm.open_zone(&"")
	for r: RegionDef in Content.regions.values():
		if r.label_pos == Vector2.ZERO:
			continue
		var label := wm.label_rect(r)
		check(wm._area().encloses(label), "%s: its name lies inside the map area" % r.id)
		for other: RegionDef in Content.regions.values():
			var dot := wm.to_screen(TDWorldMapWindow.capital_pos(other))
			var hit := Rect2(dot - Vector2(9, 9), Vector2(18, 18)).intersects(label)
			check(not hit, "%s's city at %s covers the name %s at %s" % [other.id, dot, r.display_name, label])
	await _redrawn(wm, "world map")

# ---------- community ----------

func _social() -> Dictionary:
	var me := Game.me.name
	return {
		"buddies": [["Mossy", true, "Dawnrise Meadow"], ["Kestrel", false, ""]],
		"fame": 3,
		"party": {"leader": me, "members": [[me, 1, "beginner", 1.0, "meadow"], ["Mossy", 7, "warrior", 0.4, "hollow"]]},
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
			for key in ["dialogue", "shop", "storage", "inventory"]:
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
			for key in ["dialogue", "shop", "storage", "inventory"]:
				_win(key).visible = false
		npc.free()

func test_choosing_a_path_lists_every_job() -> void:
	var q: QuestDef = Content.quests[&"q07_choosing_a_path"]
	check(q.lists_job_paths, "the quest lists the job paths")
	var npc := ui.npc_beside(Content.npcs[q.giver])
	ui.hud.open_dialogue(npc)
	var talk: TDDialogueWindow = _win("dialogue")
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	var at := labels.find("New quest: %s" % q.title)
	if not check(at >= 0, "Sorrel offers %s: %s" % [q.title, labels]):
		return
	talk.choose(at)
	check(talk.text.contains("The paths ahead:"), "the offer lists the paths")
	for j in JobDef.paths_from(Character.START_JOB):
		check(talk.text.contains("\n" + j.display_name), "the offer names %s" % j.display_name)
	check(not talk.text.contains("STR"), "and asks for no stats")
	await _redrawn(talk, "the Choosing a Path offer")
	check(talk.position.y + talk.size.y < TDWorld.VIEW.y - TDStatusBar.HEIGHT, "the window ends above the status bar")

## Opens `tutor`'s page for the job named `job_name` (through "Choose a job").
func _job_page(tutor: StringName, job_name: String) -> TDNpc:
	var npc := ui.npc_beside(Content.npcs[tutor])
	ui.hud.open_dialogue(npc)
	var talk: TDDialogueWindow = _win("dialogue")
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	check(labels.has("Choose a job"), "%s offers a job" % tutor)
	talk.choose(labels.find("Choose a job"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	check(labels.has(job_name), "%s is offered: %s" % [job_name, labels])
	talk.choose(labels.find(job_name))
	return npc

func test_a_job_page_shows_what_switching_costs() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(&"warrior")
		c.jobs_passed.assign(["warrior"])
		c.quests.done.erase(&"jtest_mage")
		c.skills.learned[&"power_strike"] = 2
		c.skills.paid[&"power_strike"] = 48)
	var npc := _job_page(&"lumewood_instructor", "Magician")
	var talk: TDDialogueWindow = _win("dialogue")
	check(talk.text.contains("You would forget Power Strike, and get back 48 Dawn Essence."), "what would go and what comes back: %s" % talk.text)
	check(talk.text.contains("Pass the Job Test first."), "the Job Test first")
	check(not talk.text.contains("You passed this path before"), "not passed yet")
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	check_eq(labels, ["Back"], "no Become button yet")
	await _redrawn(talk, "a Warrior's Magician page")
	talk.visible = false
	npc.free()

func test_a_job_page_for_a_job_passed_before() -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(&"warrior")
		c.jobs_passed.assign(["warrior", "mage"])
		c.quests.done.erase(&"jtest_mage"))
	var npc := _job_page(&"lumewood_instructor", "Magician")
	var talk: TDDialogueWindow = _win("dialogue")
	check(talk.text.contains("You passed this path before, so it's yours again for the asking."), "passed before")
	check(not talk.text.contains("You would forget"), "no skills to lose")
	check(not talk.text.contains("Pass the Job Test"), "no Job Test again")
	check_eq(talk.options[0][0], "Become a Magician", "free to switch back")
	talk.visible = false
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
	a.position.x += TDWindow.NPC_REACH + 50
	b.position.x += TDWindow.NPC_REACH + 50
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
			await ui.click(shop, shop.row_rect(shop.list.scroll).get_center(), MOUSE_BUTTON_WHEEL_DOWN)
		check_eq(shop.list.scroll, most, "%s: scrolling down stops at the last row" % s.id)
		await _redrawn(shop, "%s scrolled" % s.id)
		await ui.hover(shop, shop.row_rect(shop.list.scroll).get_center())
		check(ui.hud.tooltip.stack != null and ui.hud.tooltip.stack.item == s.items[shop.list.scroll].item, "%s: hovering a line shows its item" % s.id)
		for n in most + 2:
			await ui.click(shop, shop.row_rect(shop.list.scroll).get_center(), MOUSE_BUTTON_WHEEL_UP)
		check_eq(shop.list.scroll, 0, "%s: scrolling up stops at the first row" % s.id)
		shop.visible = false
		npc.free()

func test_shop_double_click_buys_through_the_server() -> void:
	var keeper: NpcDef = Content.npcs[&"shopkeeper"]
	await ui.edit(func(c: Character) -> void: c.shards = 100000)
	# Mira keeps her shop inside her house in the village
	Net.server.enter_map(ui.player(), &"meadow_store", 240)
	await ui.ticks(3)
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

# ---------- trade, the player menu ----------

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

func test_player_menu_lists_what_you_can_do() -> void:
	var a := TDAvatar.create(ui.world, 4242)
	a.char_name = "Mossy"
	a.job = &"warrior"
	var menu: TDPlayerMenuWindow = _win("player")
	Game.social = {}
	menu.open(a)
	check(menu.visible and menu.title == "Mossy", "clicking a player opens their menu")
	var labels: Array = menu.actions().map(func(x: Array) -> String: return x[0])
	check_eq(labels, ["Whisper", "Invite to party", "Add buddy", "Trade", "Fame +1", "Fame -1"], "actions for a stranger")
	await _redrawn(menu, "player menu")
	for i in labels.size():
		check(menu.row_rect(i).end.y <= menu.size.y, "action %d lies inside the window" % i)
	Game.social = _social() # a guild we're master of, with Mossy as a buddy
	labels = menu.actions().map(func(x: Array) -> String: return x[0])
	check_eq(labels, ["Whisper", "Invite to party", "Trade", "Invite to guild", "Fame +1", "Fame -1"], "actions for a guildless buddy")
	a.guild = "Elsewhere"
	menu.open(a)
	labels = menu.actions().map(func(x: Array) -> String: return x[0])
	check(not labels.has("Invite to guild"), "someone in another guild can't be invited")
	await ui.click(menu, menu.row_rect(0).get_center())
	check(not menu.visible and ui.hud.chat.field.visible and ui.hud.chat.field.text == "/w Mossy ", "Whisper closes the menu and starts a whisper")
	ui.hud.chat.close()
	a.free()
