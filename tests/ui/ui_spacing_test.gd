extends TestCase
## Nothing on screen sits on top of something else: every window's buttons keep apart and
## inside their window, labels fit the art they're drawn on (tabs, slots, chips), and the
## status bar, party rows, NPC speech and quest details leave room between their parts.

## The least space between two buttons, or a button and the frame.
const GAP := 2.0

var ui: UiHelpers

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()

func after_each() -> void:
	Game.social = {}
	ui.stop()

func _open(key: String) -> TDWindow:
	var w: TDWindow = ui.hud.windows[key]
	w.visible = true
	w.raise()
	check(await ui.redraw(w), "%s: its draw ran" % key)
	return w

## The buttons `w` drew last keep `GAP` apart and stay inside its frame, and its tab labels
## fit between their tabs' pointed ends.
func _check_layout(w: TDWindow, what: String) -> void:
	var inside := Rect2(Vector2.ZERO, w.size).grow(-GAP)
	for i in w._buttons.size():
		var a: Rect2 = w._buttons[i][0]
		check(inside.encloses(a), "%s: button at %s lies inside the window (%s)" % [what, a, w.size])
		for j in range(i + 1, w._buttons.size()):
			var b: Rect2 = w._buttons[j][0]
			check(not a.grow(GAP / 2.0).intersects(b.grow(GAP / 2.0)), "%s: buttons at %s and %s keep apart" % [what, a, b])
	for i in w._tab_rects.size():
		var label: String = w._tab_labels[i]
		var r: Rect2 = w._tab_rects[i]
		var width := DrawUtil.text_width(Game.ui_font, label, TDWindow.tab_font_size(r, label))
		check(width <= TDWindow.tab_text_width(r), "%s: the %s tab's label (%d px) fits its tab (%d px)" % [what, label, width, TDWindow.tab_text_width(r)])

func _spender(job: StringName, level: int) -> void:
	await ui.edit(func(c: Character) -> void:
		c.job = Content.job(job)
		c.level = level
		c.ap.points = 12
		c.skills.points = 5
		c.guild = "Dawnbreakers"
		c.fame = 12)

func test_stat_plus_buttons_and_auto_keep_apart() -> void:
	for pair in [[&"warrior", 30], [&"beginner", 9]]:
		await _spender(pair[0], pair[1])
		var stats: TDStatsWindow = await _open("stats")
		_check_layout(stats, "Character window, %s" % pair[0])
		var plus := stats._buttons.filter(func(b: Array) -> bool: return (b[0] as Rect2).size.x == (b[0] as Rect2).size.y)
		check_eq(plus.size(), StatBlock.BASE.size(), "%s: a + for every stat" % pair[0])
		check_eq(stats.auto_rect.size.x > 0, pair[0] != &"beginner", "%s: Auto once you have a job" % pair[0])
		check(stats.position.y + stats.size.y < TDWorld.VIEW.y - TDStatusBar.HEIGHT, "%s: the window ends above the status bar" % pair[0])
		check(stats.content_end <= stats.size.y - 16, "%s: the rows fit" % pair[0])

func test_every_window_opens_above_the_status_bar() -> void:
	await _spender(&"beginner", 9)  # a Beginner's Character window is its tallest
	for key in TDHud.WINDOW_ACTIONS:
		var w := await _open(key)
		check(TDWindow.room().encloses(w.get_rect()), "%s: the window (%s) stays on screen and above the status bar" % [key, w.get_rect()])
		w.visible = false

func test_every_window_keeps_its_buttons_apart() -> void:
	await _spender(&"warrior", 30)
	Game.social = {
		"buddies": [["Mossy", true, "Dawnrise Meadow"], ["Kestrel", false, ""]],
		"party": {"leader": Game.me.name, "members": [[Game.me.name, 1, 30, "warrior", 1.0, "meadow"], ["Kestrelwings", 7, 22, "archer", 0.4, "hollow"]]},
		"guild": {"name": "Dawnbreakers", "master": Game.me.name, "members": [[Game.me.name, true], ["Mossy", true]]},
	}
	for key in ["inventory", "equipment", "stats", "skills", "quests", "worldmap", "community", "collection"]:
		var w := await _open(key)
		var tabs := maxi(1, w._tab_rects.size())
		for t in tabs:
			if "tab" in w:
				w.tab = t
			elif "page" in w:
				w.page = t
			check(await ui.redraw(w), "%s: drawn on tab %d" % [key, t])
			_check_layout(w, "%s, tab %d" % [key, t])
		w.visible = false

func test_shop_tabs_and_amount_chips_fit() -> void:
	var def: NpcDef = null
	for n: NpcDef in Content.npcs.values():
		if n.shop and (def == null or String(n.id) < String(def.id)):
			def = n
	ui.hud.open_shop(ui.npc_beside(def))
	var shop: TDShopWindow = ui.hud.windows["shop"]
	check(await ui.redraw(shop), "the shop drew")
	_check_layout(shop, "shop")
	var chips: Array[Rect2] = []
	for i in TDShopWindow.AMOUNTS.size():
		var r := shop._amount_rect(i)
		var label := "×%d" % TDShopWindow.AMOUNTS[i]
		var w := DrawUtil.text_width(Game.num_font, label, DrawUtil.fit_size(Game.num_font, label, 13, TDShopWindow.CHIP_W - TDShopWindow.CHIP_CAPS))
		check(w <= r.size.x - TDShopWindow.CHIP_CAPS, "%s fits its chip (%d px)" % [label, w])
		for c in chips:
			check(not c.intersects(r), "amount chips keep apart")
		chips.append(r)
	check(chips[-1].end.x + GAP <= shop._sell_etc_rect().position.x, "the chips end before Sell all Etc")
	check(TDWindow.PAD + DrawUtil.text_width(Game.ui_font, "Amount", 12) + GAP <= chips[0].position.x, "the Amount label ends before the chips")

func test_status_bar_exp_and_window_buttons_keep_apart() -> void:
	var bar := ui.hud.status
	check(bar.exp_bar_rect().end.x + GAP <= bar._window_button_rect(0).position.x,
		"the EXP bar (ends %d) stops before the first window button (%d)" % [bar.exp_bar_rect().end.x, bar._window_button_rect(0).position.x])
	var last := bar._window_button_rect(TDHud.WINDOW_ACTIONS.size() - 1)
	check(last.end.x + GAP <= bar.size.x - 140, "the window buttons stop before the Dawnshards")
	check(bar.exp_bar_rect().position.y >= 0 and bar.exp_bar_rect().end.y <= TDStatusBar.HEIGHT, "the EXP bar sits inside the bar")

func test_equipment_slot_labels_fit() -> void:
	for p in TDEquipmentWindow.LAYOUT:
		var label: String = Equipment.PLACE_NAMES[p]
		var w := DrawUtil.text_width(Game.ui_font, label, DrawUtil.fit_size(Game.ui_font, label, 9, TDWindow.SLOT - 8, 7))
		check(w <= TDWindow.SLOT - 8, "%s fits its slot (%d px)" % [label, w])

func test_party_hp_bar_stops_before_kick() -> void:
	var com: TDCommunityWindow = ui.hud.windows["community"]
	var row := com._row(1)
	check(com.party_hp_rect(row).end.x + GAP <= com.kick_rect(row).position.x, "the HP bar ends before Kick")
	check(com.party_hp_rect(row).position.x >= row.position.x + 150, "and leaves the name room on its left")

func test_npc_speech_starts_below_the_frame_top() -> void:
	var border := UiSkin.DIALOGUE_FRAME[1] as Vector4 # left, top, right, bottom margins in texels
	var ascent := 13 * 0.8 # how far the tallest letters reach above the baseline (the font's own ascent counts its padding)
	check((TDDialogueWindow.TEXT_TOP - border.y) * TDDialogueWindow.FRAME_SCALE >= ascent,
		"the first line's top (%.1f px under the border) clears the frame's top border" % ((TDDialogueWindow.TEXT_TOP - border.y) * TDDialogueWindow.FRAME_SCALE - ascent))
	check(TDDialogueWindow.TEXT_RIGHT > border.z, "the lines end inside the frame's right border")

func test_quest_details_end_above_give_up() -> void:
	var log: TDQuestWindow = ui.hud.windows["quests"]
	log.page = TDQuestWindow.Page.ACTIVE
	var box := Rect2(TDWindow.PAD + TDQuestWindow.LIST_W + 14, TDQuestWindow.LIST_Y - 4,
		log.size.x - TDQuestWindow.LIST_W - TDWindow.PAD * 2 - 14, log.size.y - TDQuestWindow.LIST_Y - TDWindow.PAD)
	var room := log._forfeit_rect().position.y - 8 - (box.position.y + 22)
	var cut := 0
	for q: QuestDef in Content.quests.values():
		var lines := log.detail_lines(q, box.size.x - 20, room)
		var h := 0.0
		for l in lines:
			h += l[0]
		check(h <= room, "%s: the details (%d px) fit above Give up (%d px)" % [q.id, h, room])
		check(lines.any(func(l: Array) -> bool: return (l[1] as String).begins_with("Reward:")), "%s: the reward is always shown" % q.id)
		if lines.any(func(l: Array) -> bool: return (l[1] as String).ends_with("…")):
			cut += 1
	check(cut < Content.quests.size() / 4, "most quests show their whole story (%d cut)" % cut)
