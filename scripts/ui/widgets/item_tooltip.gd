class_name TDItemTooltip
extends Control
## The card that follows the mouse over an item slot: name, kind, requirements (red when
## not met), stats, how gear compares with what's worn in its slot, what a potion restores,
## the description and what double-clicking does. Drawn above every window.

const W := 220.0
## A new item's card fades in over this many seconds.
const FADE_IN := 0.1

var stack: ItemStack
var at := Vector2.ZERO
var _owner: Control
var hint := ""
## Gear only: also list how it differs from what's worn where it would go.
var compare := false
var _alpha := 0.0

func _process(delta: float) -> void:
	_alpha = minf(1.0, _alpha + delta / FADE_IN) if stack != null else 0.0
	modulate.a = _alpha
	queue_redraw()

## Shows `s` near `mouse` on behalf of `owner_window` (null hides it), with a `hint` line
## at the bottom, and for gear in the bag a comparison with what's worn if `compare_worn`.
func show_item(owner_window: Control, s: ItemStack, mouse: Vector2, hint_text := "", compare_worn := false) -> void:
	_owner = owner_window
	if s == null or stack == null or s.item != stack.item:
		_alpha = 0.0
	stack = s
	at = mouse
	hint = hint_text
	compare = compare_worn

## Hides the tooltip if `owner_window` is the one showing it.
func clear(owner_window: Control) -> void:
	if _owner == owner_window:
		stack = null

func _lines() -> Array:
	var out := []  # [text, colour, size]
	var item := stack.item
	out.append([stack.display_name(), Palette.SUN, 15])
	var e := item as EquipDef
	if e:
		var kind := " (%s)" % String(e.weapon_kind).capitalize() if e.weapon_kind != &"" else ""
		out.append(["Equip · %s%s" % [e.slot_name(), kind], Palette.MUTED, 11])
		if e.ammo != &"":
			out.append(["Fires %ss" % e.ammo, Palette.MIST, 12])
		if not e.jobs.is_empty():
			out.append(["%s only" % EquipDef.families_text(e.jobs), Palette.MIST if Game.me.can_use(e.jobs) else Palette.BAD, 12])
		var reqs := e.requirements()
		for key in reqs:
			var have := Game.me.level if key == &"level" else Game.me.stats.value(key)
			var label: String = "Level" if key == &"level" else StatBlock.LABELS[key]
			out.append(["Requires %s %d" % [label, reqs[key]], Palette.MIST if have >= reqs[key] else Palette.BAD, 12])
		var base := e.stats if e.stats else StatBlock.new()
		for f in stack.stats.nonzero():
			var v := stack.stats.value(f)
			var col := Palette.MIST
			if v > base.value(f):
				col = Palette.GOOD
			elif v < base.value(f):
				col = Palette.WARN
			out.append(["%s: %s" % [StatBlock.LABELS[f], StatBlock.format(f, v)], col, 12])
		out.append(["Upgrades available: %d" % stack.slots_left(), Palette.MUTED, 11])
		if compare:
			out.append_array(_comparison(e))
	elif item is UseDef:
		var u := item as UseDef
		out.append(["Use", Palette.MUTED, 11])
		var hp := u.hp_for(Game.me.max_hp())
		var mp := u.mp_for(Game.me.max_mp())
		if hp > 0:
			out.append(["Restores %d HP" % hp, Palette.HP, 12])
		if mp > 0:
			out.append(["Restores %d MP" % mp, Palette.MP, 12])
		if u.pet_food > 0:
			out.append(["Pet food: +%d fullness" % u.pet_food, Palette.PET, 12])
	elif item is ChairDef:
		var ch := item as ChairDef
		out.append(["Setup · Chair", Palette.MUTED, 11])
		out.append(["While sitting: +%d HP, +%d MP each recovery" % [ch.regen_hp, ch.regen_mp], Palette.GOOD, 12])
	elif item is PetDef:
		var pet := item as PetDef
		out.append(["Setup · Pet", Palette.MUTED, 11])
		out.append(["Picks up items within %d px of you" % roundi(pet.loot_reach), Palette.GOOD, 12])
		if Game.me.pet == pet.id:
			out.append(["Out with you · Fullness %d/100" % Game.me.pet_full, Palette.PET, 12])
	elif item is CardDef:
		var card := item as CardDef
		out.append(["Monster Book card · %d/%d found" % [Game.me.book.cards(card.monster), CardDef.SET], Palette.CARD, 11])
	elif item is ScrollDef:
		var sc := item as ScrollDef
		out.append(["Upgrade scroll · %s" % sc.slot_text(), Palette.MUTED, 11])
		out.append(["Success rate: %d%%" % roundi(sc.chance * 100.0), Palette.SUN, 12])
		if sc.stats:
			for f in sc.stats.nonzero():
				out.append(["%s +%s" % [StatBlock.LABELS[f], StatBlock.format(f, sc.stats.value(f))], Palette.MIST, 12])
	elif item is AmmoDef:
		var a := item as AmmoDef
		out.append(["Ammo · %ss" % String(a.kind).capitalize(), Palette.MUTED, 11])
		if a.attack > 0:
			out.append(["Weapon Attack +%d when fired" % a.attack, Palette.MIST, 12])
	else:
		out.append(["Etc", Palette.MUTED, 11])
	if item.description != "":
		for l in UiSkin.wrap_text(Game.ui_font, item.description, 11, W - 28):
			out.append([l, Color(Palette.MIST, 0.8), 11])
	if hint != "":
		out.append([hint, Color(Palette.SUN, 0.75), 11])
	return out

## How wearing this would change each stat, against what's worn where it would go.
func _comparison(e: EquipDef) -> Array:
	var worn := Game.me.equipment.at(Game.me.equipment.place_for(e))
	if worn == null:
		return [["Nothing worn in this slot", Palette.GOOD, 11]]
	var out := [["vs. worn %s:" % worn.item.display_name, Palette.MUTED, 11]]
	var changed := false
	for f in StatBlock.FIELDS:
		var diff := stack.stats.value(f) - worn.stats.value(f)
		if diff != 0:
			changed = true
			out.append(["  %s %s" % [StatBlock.format(f, diff), StatBlock.LABELS[f]], Palette.GOOD if diff > 0 else Palette.BAD, 12])
	if not changed:
		out.append(["  Same stats", Palette.MIST, 12])
	return out

func _draw() -> void:
	if stack == null or stack.item == null or _owner == null or not _owner.visible:
		return
	var lines := _lines()
	var h := 22.0
	for l in lines:
		h += l[2] + 5
	var view := get_viewport_rect().size
	var pos := at + Vector2(18, 12)
	if pos.x + W > view.x:
		pos.x = at.x - W - 12
	pos.y = clampf(pos.y, 4, view.y - h - 4)
	var r := Rect2(pos, Vector2(W, h))
	UiSkin.tooltip_frame().draw(get_canvas_item(), r)
	var y := pos.y + 10
	for l in lines:
		y += l[2] + 5
		DrawUtil.text(self, Game.ui_font, Vector2(pos.x + 14, y), l[0], l[2], l[1], 1)
