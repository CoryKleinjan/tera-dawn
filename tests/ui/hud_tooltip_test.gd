extends TestCase
## The item tooltip for every item in the game: it starts with the item's name, says what
## kind of item it is, shows what that kind needs (requirements in red when not met, what a
## potion restores, a scroll's success rate, a card's count...), compares gear with what's
## worn, ends with the hint, and draws over its window.

const RED := Color("ff6b7d")

var ui: UiHelpers
var tip: TDItemTooltip
var inv: TDInventoryWindow

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	tip = ui.hud.tooltip
	inv = ui.hud.windows["inventory"]
	inv.visible = true

func after_each() -> void:
	ui.stop()

func _texts(lines: Array) -> Array:
	return lines.map(func(l: Array) -> String: return l[0])

## The tooltip's lines for `stack`, checked for shape. [] if they're broken.
func _lines_for(stack: ItemStack, hint := "", compare := false) -> Array:
	tip.show_item(inv, stack, Vector2(400, 200), hint, compare)
	var lines: Variant = tip._lines()
	var id := stack.item.id
	if not check(lines is Array and not (lines as Array).is_empty(), "%s: the tooltip has lines" % id):
		return []
	for l in lines:
		if not check(l is Array and l.size() == 3 and l[0] is String and l[1] is Color and (l[2] is int or l[2] is float), "%s: tooltip line %s is [text, colour, size]" % [id, l]):
			return []
		check(String(l[0]).strip_edges() != "" or l[0] == "", "%s: a tooltip line is only spaces" % id)
	check_eq(lines[0][0], stack.display_name(), "%s: the first line" % id)
	return lines

func _kind_line(item: ItemDef) -> String:
	if item is EquipDef:
		return "Equip · "
	if item is UseDef:
		return "Use"
	if item is ChairDef:
		return "Setup · Chair"
	if item is PetDef:
		return "Setup · Pet"
	if item is CardDef:
		return "Monster Book card · "
	if item is ScrollDef:
		return "Upgrade scroll · "
	if item is AmmoDef:
		return "Ammo · "
	return "Etc"

func test_every_item_has_a_tooltip_naming_its_kind() -> void:
	var kinds := {}
	for item: ItemDef in Content.items.values():
		var lines := _lines_for(ItemStack.create(item, mini(3, item.stack_size())), "Double-click")
		if lines.size() < 2:
			continue
		check(String(lines[1][0]).begins_with(_kind_line(item)), "%s: second line %s, want it to start %s" % [item.id, lines[1][0], _kind_line(item)])
		check_eq(lines[-1][0], "Double-click", "%s: the hint is the last line" % item.id)
		if item.description != "":
			var text := " ".join(_texts(lines))
			check(text.contains(item.description.split(" ")[0]), "%s: the description is shown" % item.id)
		kinds[_kind_line(item)] = true
	check_eq(kinds.size(), 8, "item kinds seen (gear, use, chair, pet, card, scroll, ammo, etc)")

func test_every_item_tooltip_draws() -> void:
	for item: ItemDef in Content.items.values():
		tip.show_item(inv, ItemStack.create(item), Vector2(TDWorld.VIEW.x - 10, TDWorld.VIEW.y - 10), "hint", item is EquipDef)
		check(await ui.redraw(tip), "%s: the tooltip draws" % item.id)

func test_gear_tooltips_show_requirements_stats_and_upgrades() -> void:
	for item: ItemDef in Content.items.values():
		var e := item as EquipDef
		if e == null:
			continue
		var stack := ItemStack.exact(e)
		var lines := _lines_for(stack)
		var texts := _texts(lines)
		check(texts[1].contains(e.slot_name()), "%s: names its slot %s" % [e.id, e.slot_name()])
		for f in stack.stats.nonzero():
			check(texts.has("%s: %s" % [StatBlock.LABELS[f], StatBlock.format(f, stack.stats.value(f))]), "%s: lists %s" % [e.id, f])
		check(texts.has("Upgrades available: %d" % e.upgrade_slots), "%s: lists its upgrade slots" % e.id)
		var reqs := e.requirements()
		for key in reqs:
			var label: String = "Level" if key == &"level" else StatBlock.LABELS[key]
			var i := texts.find("Requires %s %d" % [label, reqs[key]])
			if check(i >= 0, "%s: lists Requires %s %d" % [e.id, label, reqs[key]]):
				var have := Game.me.level if key == &"level" else Game.me.stats.value(key)
				check_eq(lines[i][1] == RED, have < reqs[key], "%s: Requires %s is red exactly when not met" % [e.id, label])
		if not e.jobs.is_empty():
			var line := "%s only" % EquipDef.families_text(e.jobs)
			var i := texts.find(line)
			if check(i >= 0, "%s: says %s" % [e.id, line]):
				check_eq(lines[i][1] == RED, not Game.me.can_use(e.jobs), "%s: the job line is red exactly when a Beginner can't use it" % e.id)

func test_rolled_gear_colours_stats_against_the_base() -> void:
	var e: EquipDef = Content.item(&"dawn_blade")
	var stack := ItemStack.exact(e)
	stack.stats.attack = e.stats.attack + 2
	var lines := _lines_for(stack)
	var line := "%s: %s" % [StatBlock.LABELS[&"attack"], StatBlock.format(&"attack", stack.stats.attack)]
	var i := _texts(lines).find(line)
	if check(i >= 0, "the rolled attack is listed"):
		check_eq(lines[i][1], Color("8cf0a6"), "a better-than-base stat is green")
	stack.stats.attack = e.stats.attack - 1
	lines = _lines_for(stack)
	i = _texts(lines).find("%s: %s" % [StatBlock.LABELS[&"attack"], StatBlock.format(&"attack", stack.stats.attack)])
	if check(i >= 0, "the lower attack is listed"):
		check_eq(lines[i][1], Color("ffb38a"), "a worse-than-base stat is orange")

func test_upgraded_gear_shows_its_plus() -> void:
	var stack := ItemStack.exact(Content.item(&"dawn_blade"))
	stack.slots_used = 3
	stack.upgrades = 2
	var lines := _lines_for(stack)
	check_eq(lines[0][0], "Dawn Blade +2", "the name carries the upgrades")
	check(_texts(lines).has("Upgrades available: %d" % (stack.equip_def().upgrade_slots - 3)), "upgrade slots left")

func test_gear_compares_with_what_is_worn() -> void:
	var sword := Game.me.equipment.at(&"weapon")
	check(sword != null, "a new character holds a weapon")
	var other: EquipDef = Content.item(&"dawn_blade")
	var lines := _texts(_lines_for(ItemStack.exact(other), "", true))
	var at := lines.find("vs. worn %s:" % sword.item.display_name)
	if check(at >= 0, "the comparison names the worn %s: %s" % [sword.item.id, lines]):
		var diff: int = other.stats.attack - sword.stats.attack
		check(lines.has("  %s %s" % [StatBlock.format(&"attack", diff), StatBlock.LABELS[&"attack"]]), "the comparison gives the attack difference %+d" % diff)
	var same := _texts(_lines_for(ItemStack.exact(sword.item), "", true))
	check(same.has("  Same stats"), "the same weapon compares as Same stats")
	var hat: EquipDef = Content.item(&"leaf_cap")
	check(_texts(_lines_for(ItemStack.exact(hat), "", true)).has("Nothing worn in this slot"), "a hat with no hat worn")
	check(not _texts(_lines_for(ItemStack.exact(hat), "", false)).has("Nothing worn in this slot"), "no comparison unless asked")

func test_use_tooltips_say_what_they_restore() -> void:
	for item: ItemDef in Content.items.values():
		var u := item as UseDef
		if u == null:
			continue
		var texts := _texts(_lines_for(ItemStack.create(u)))
		var hp := u.hp_for(Game.me.max_hp())
		var mp := u.mp_for(Game.me.max_mp())
		check_eq(texts.has("Restores %d HP" % hp), hp > 0, "%s: Restores %d HP" % [u.id, hp])
		check_eq(texts.has("Restores %d MP" % mp), mp > 0, "%s: Restores %d MP" % [u.id, mp])
		if u.pet_food > 0:
			check(texts.has("Pet food: +%d fullness" % u.pet_food), "%s: says it's pet food" % u.id)

func test_scroll_ammo_chair_and_pet_tooltips() -> void:
	for item: ItemDef in Content.items.values():
		var texts := _texts(_lines_for(ItemStack.create(item)))
		if item is ScrollDef:
			var sc := item as ScrollDef
			check(texts[1].contains(sc.slot_text()), "%s: names the gear it fits" % item.id)
			check(texts.has("Success rate: %d%%" % roundi(sc.chance * 100.0)), "%s: gives its success rate" % item.id)
		elif item is AmmoDef and (item as AmmoDef).attack > 0:
			check(texts.has("Weapon Attack +%d when fired" % (item as AmmoDef).attack), "%s: gives its attack" % item.id)
		elif item is ChairDef:
			check(texts.has("While sitting: +%d HP, +%d MP each recovery" % [(item as ChairDef).regen_hp, (item as ChairDef).regen_mp]), "%s: gives its recovery" % item.id)
		elif item is PetDef:
			check(texts.has("Picks up items within %d px of you" % roundi((item as PetDef).loot_reach)), "%s: gives its reach" % item.id)

func test_pet_tooltip_shows_fullness_when_out() -> void:
	var pet: PetDef = Content.items.values().filter(func(i: ItemDef) -> bool: return i is PetDef)[0]
	await ui.edit(func(c: Character) -> void:
		c.pet = pet.id
		c.pet_full = 64)
	check(_texts(_lines_for(ItemStack.create(pet))).has("Out with you · Fullness 64/100"), "the pet that's out shows how full it is")

func test_card_tooltip_counts_cards_found() -> void:
	var m: MonsterDef = Content.monster(&"dewling")
	await ui.edit(func(c: Character) -> void: c.book.pages[m.id] = [10, 3])
	var lines := _texts(_lines_for(ItemStack.create(Content.card(m))))
	check_eq(lines[1], "Monster Book card · 3/%d found" % CardDef.SET, "the card line")

func test_tooltip_follows_its_owner() -> void:
	var stack := ItemStack.create(Content.item(&"red_potion"))
	tip.show_item(inv, stack, Vector2(100, 100))
	tip.clear(ui.hud.windows["equipment"])
	check(tip.stack == stack, "another window can't clear it")
	tip.clear(inv)
	check(tip.stack == null, "its own window clears it")
	tip.show_item(inv, stack, Vector2(100, 100))
	ui.hud.toggle_window("inventory")
	check(tip.stack == null, "closing the window clears it")

func test_tooltip_skips_drawing_for_a_closed_window() -> void:
	tip.show_item(inv, ItemStack.create(Content.item(&"red_potion")), Vector2(100, 100))
	inv.visible = false
	check(await ui.redraw(tip), "the tooltip layer still redraws")
	check(tip.stack != null, "and keeps its item until cleared")
