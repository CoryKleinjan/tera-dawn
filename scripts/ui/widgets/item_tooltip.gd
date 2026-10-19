class_name TDItemTooltip
extends Control
## The card that follows the mouse over an item slot: name, kind, which jobs can use it (red
## when yours can't), gear's tier, stats, gear's rune slots (filled and empty), how gear compares with
## what's worn in its slot, what a potion restores or a rune adds, the description and what
## double-clicking does. Drawn above every window.

const W := 220.0
## Room between the frame's edge and the text, inside its painted border.
const INSET := 20.0
## A new item's card fades in over this many seconds.
const FADE_IN := 0.1
## Marks each rune slot line (filled ones in the rune colour, empty ones dim).
const RUNE_MARK := "◆"

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
		if not e.jobs.is_empty():
			out.append(["%s only" % EquipDef.families_text(e.jobs), Palette.MIST if Game.me.gear.can_use(e.jobs) else Palette.BAD, 12])
		var tier := Content.gear_tier(stack.tier)
		if tier:
			out.append([tier.display_name, Palette.SUN if stack.tier > 1 else Palette.MIST, 12])
		# rolled stats show green or orange against what the piece lists, at the same tier
		var own := stack.own_stats()
		var base := e.stats.scaled(tier.stat_scale) if e.stats and tier else (e.stats if e.stats else StatBlock.new())
		for f in own.nonzero():
			var v := own.value(f)
			var col := Palette.MIST
			if v > base.value(f):
				col = Palette.GOOD
			elif v < base.value(f):
				col = Palette.WARN
			out.append(["%s: %s" % [StatBlock.LABELS[f], StatBlock.format(f, v)], col, 12])
		out.append_array(rune_lines(stack))
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
	elif item is PetDef:
		var pet := item as PetDef
		out.append(["Setup · Pet", Palette.MUTED, 11])
		out.append(["Picks up items within %d px of you" % roundi(pet.loot_reach), Palette.GOOD, 12])
		if Game.me.pet == pet.id:
			out.append(["Out with you · Fullness %d/100" % Game.me.pet_full, Palette.PET, 12])
	elif item is CardDef:
		var card := item as CardDef
		out.append(["Monster Book card · %d/%d found" % [Game.me.book.cards(card.monster), CardDef.SET], Palette.CARD, 11])
	elif item is RuneDef:
		var rune := item as RuneDef
		out.append(["Etc · Boss rune" if rune.boss else "Etc · Rune", Palette.MUTED, 11])
		out.append([rune.bonus_text(), Palette.RUNE, 12])
		out.append(["An enchanter sets it in gear for %d Dawnshards" % rune.fee, Palette.MUTED, 11])
	else:
		out.append(["Etc", Palette.MUTED, 11])
	if item.description != "":
		out.append([item.description, Color(Palette.MIST, 0.8), 11])
	if hint != "":
		out.append([hint, Color(Palette.SUN, 0.75), 11])
	return out

## A line for each of the gear's rune slots: the rune and what it adds, or that it's empty.
static func rune_lines(s: ItemStack) -> Array:
	var out := []
	for r in s.runes:
		if r:
			out.append(["%s %s: %s" % [RUNE_MARK, r.display_name, r.bonus_text()], Palette.RUNE, 12])
		else:
			out.append(["%s Empty rune slot" % RUNE_MARK, Color(Palette.MUTED, 0.6), 11])
	return out

## How wearing this would change each stat, against what's worn where it would go.
func _comparison(e: EquipDef) -> Array:
	var worn := Game.me.equipment.at(Game.me.equipment.place_for(e))
	if worn == null:
		return [["Nothing worn in this slot", Palette.GOOD, 11]]
	var out := [["vs. worn %s:" % worn.item.display_name, Palette.MUTED, 11]]
	var mine := stack.total()
	var theirs := worn.total()
	var changed := false
	for f in StatBlock.FIELDS:
		var diff := mine.value(f) - theirs.value(f)
		if diff != 0:
			changed = true
			out.append(["  %s %s" % [StatBlock.format(f, diff), StatBlock.LABELS[f]], Palette.GOOD if diff > 0 else Palette.BAD, 12])
	if not changed:
		out.append(["  Same stats", Palette.MIST, 12])
	return out

func _draw() -> void:
	if stack == null or stack.item == null or _owner == null or not _owner.visible:
		return
	# every line wraps to fit inside the frame's border
	var lines := []
	for l in _lines():
		for part in DrawUtil.wrap_text(Game.ui_font, l[0], l[2], W - INSET * 2):
			lines.append([part, l[1], l[2]])
	var h := 30.0
	for l in lines:
		h += l[2] + 5
	var view := get_viewport_rect().size
	var pos := at + Vector2(18, 12)
	if pos.x + W > view.x:
		pos.x = at.x - W - 12
	pos.y = clampf(pos.y, 4, view.y - h - 4)
	var r := Rect2(pos, Vector2(W, h))
	UiSkin.tooltip_frame().draw(get_canvas_item(), r)
	var y := pos.y + 13
	for l in lines:
		y += l[2] + 5
		DrawUtil.text(self, Game.ui_font, Vector2(pos.x + INSET, y), l[0], l[2], l[1], 1)
