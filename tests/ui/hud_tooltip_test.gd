extends TestCase
## The item tooltip for every item in the game: it starts with the item's name, says what
## kind of item it is, shows what that kind needs (the jobs that can wear it, red when yours
## can't, what a pet eats, a card's count...), compares gear with what's
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
	if item is PetDef:
		return "Setup · Pet"
	if item is CardDef:
		return "Monster Book card · "
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
	check_eq(kinds.size(), 5, "item kinds seen (gear, use, pet, card, etc)")

func test_every_item_tooltip_draws() -> void:
	for item: ItemDef in Content.items.values():
		tip.show_item(inv, ItemStack.create(item), Vector2(TDWorld.VIEW.x - 10, TDWorld.VIEW.y - 10), "hint", item is EquipDef)
		check(await ui.redraw(tip), "%s: the tooltip draws" % item.id)

func test_gear_tooltips_show_jobs_and_stats_and_ask_for_nothing() -> void:
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
		check(not texts.any(func(t: String) -> bool: return t.begins_with("Requires")), "%s: no level or stat requirement" % e.id)
		check(not texts.any(func(t: String) -> bool: return t.begins_with("Upgrades")), "%s: no upgrade slots" % e.id)
		if not e.jobs.is_empty():
			var line := "%s only" % EquipDef.families_text(e.jobs)
			var i := texts.find(line)
			if check(i >= 0, "%s: says %s" % [e.id, line]):
				check_eq(lines[i][1] == RED, not Game.me.gear.can_use(e.jobs), "%s: the job line is red exactly when a Beginner can't use it" % e.id)

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

func test_use_tooltips_say_what_pets_eat() -> void:
	for item: ItemDef in Content.items.values():
		var u := item as UseDef
		if u == null:
			continue
		var texts := _texts(_lines_for(ItemStack.create(u)))
		check(texts.has("Use"), "%s: says it's a Use item" % u.id)
		if u.pet_food > 0:
			check(texts.has("Pet food: +%d fullness" % u.pet_food), "%s: says it's pet food" % u.id)

func test_pet_tooltips() -> void:
	for item: ItemDef in Content.items.values():
		var texts := _texts(_lines_for(ItemStack.create(item)))
		if item is PetDef:
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
	var stack := ItemStack.create(Content.item(&"return_scroll"))
	tip.show_item(inv, stack, Vector2(100, 100))
	tip.clear(ui.hud.windows["equipment"])
	check(tip.stack == stack, "another window can't clear it")
	tip.clear(inv)
	check(tip.stack == null, "its own window clears it")
	tip.show_item(inv, stack, Vector2(100, 100))
	ui.hud.toggle_window("inventory")
	check(tip.stack == null, "closing the window clears it")

func test_tooltip_skips_drawing_for_a_closed_window() -> void:
	tip.show_item(inv, ItemStack.create(Content.item(&"return_scroll")), Vector2(100, 100))
	inv.visible = false
	check(await ui.redraw(tip), "the tooltip layer still redraws")
	check(tip.stack != null, "and keeps its item until cleared")
