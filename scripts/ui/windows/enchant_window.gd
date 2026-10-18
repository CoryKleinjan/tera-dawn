class_name TDEnchantWindow
extends TDWindow
## An enchanter (NpcDef.enchants): your gear on the left, your runes (the Etc tab, anything
## that isn't a rune dimmed) on the right, and the picked gear's rune slots underneath. Click
## a piece of gear, then a rune, then the rune slot to set it in; it asks first, with the fee
## (RuneDef.fee) and the rune it would replace. Setting a rune is a request the server answers
## (Gear.enchant). The button along the bottom raises the picked gear a tier for the next
## tier's fee (Gear.upgrade), asking first. Closes when you walk away.

const COLS := 4
const GAP := 4.0
const GRID_Y := 66.0
const GRID_W := COLS * (SLOT + GAP) - GAP
const RUNES_X := PAD + GRID_W + 24
## The picked gear's rune slots: bigger than item slots, side by side under the grids.
const SOCKET := 48.0
const SOCKET_GAP := 18.0
## The upgrade button along the bottom.
const UPGRADE_W := 280.0
## Room under the hint for the upgrade button.
const UPGRADE_ROOM := 36.0

var npc: TDNpc
## The gear (Equip slot) and the rune (Etc slot) picked, or -1.
var gear_slot := -1
var rune_slot := -1
var gear := SlotGrid.new(Vector2(PAD, GRID_Y), COLS, Inventory.SLOTS, SLOT, GAP)
var runes := SlotGrid.new(Vector2(RUNES_X, GRID_Y), COLS, Inventory.SLOTS, SLOT, GAP)
## A stack standing for each rune set in the picked gear, to draw and show it like a bag item.
var _shown := {}

func _init() -> void:
	var rows := ceili(Inventory.SLOTS / float(COLS))
	super("Enchanting", Vector2(RUNES_X + GRID_W + PAD, GRID_Y + rows * (SLOT + GAP) + SOCKET + 96 + UPGRADE_ROOM))

func open(who: TDNpc) -> void:
	npc = who
	gear_slot = -1
	rune_slot = -1
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -30)
	visible = true
	raise()

func _process(delta: float) -> void:
	super(delta)
	if visible and walked_away_from(npc):
		visible = false
		hud.tooltip.clear(self)

# ---------- what's picked ----------

## The picked gear, if it's still in its slot.
func picked_gear() -> ItemStack:
	var s := Game.me.inventory.at(ItemDef.Tab.EQUIP, gear_slot) if gear_slot >= 0 else null
	if s == null:
		gear_slot = -1
	return s

## The picked rune, if it's still in its slot.
func picked_rune() -> RuneDef:
	var s := Game.me.inventory.at(ItemDef.Tab.ETC, rune_slot) if rune_slot >= 0 else null
	if s == null or not s.item is RuneDef:
		rune_slot = -1
		return null
	return s.item as RuneDef

# ---------- layout ----------

func socket_rect(i: int) -> Rect2:
	var w := ItemStack.RUNE_SLOTS * SOCKET + (ItemStack.RUNE_SLOTS - 1) * SOCKET_GAP
	var y := GRID_Y + gear.rows() * (SLOT + GAP) + 34
	return Rect2(size.x / 2.0 - w / 2.0 + i * (SOCKET + SOCKET_GAP), y, SOCKET, SOCKET)

## The rune slot under `at`, or -1.
func socket_at(at: Vector2) -> int:
	for i in ItemStack.RUNE_SLOTS:
		if socket_rect(i).has_point(at):
			return i
	return -1

## What to do next, under the rune slots.
func hint() -> String:
	var g := picked_gear()
	var r := picked_rune()
	if g == null:
		return "Pick a piece of gear"
	if r == null:
		return "Pick a rune for the %s" % g.display_name()
	return "Pick a rune slot for the %s (%d Dawnshards)" % [r.display_name, r.fee]

# ---------- drawing ----------

func _draw_body() -> void:
	var bag := Game.me.inventory
	draw_label(Vector2(PAD, GRID_Y - 10), "Your gear", Palette.MUTED)
	draw_label(Vector2(RUNES_X, GRID_Y - 10), "Your runes", Palette.MUTED)
	for i in Inventory.SLOTS:
		draw_slot(gear.rect(i), bag.at(ItemDef.Tab.EQUIP, i))
		var held := bag.at(ItemDef.Tab.ETC, i)
		draw_slot(runes.rect(i), held, held != null and not held.item is RuneDef)
	var g := picked_gear()
	if g:
		draw_rect(gear.rect(gear_slot).grow(1), Palette.HILITE, false, 2.0)
	if picked_rune():
		draw_rect(runes.rect(rune_slot).grow(1), Palette.HILITE, false, 2.0)
	var top := socket_rect(0).position.y
	if g:
		DrawUtil.text(self, Game.ui_font, Vector2(size.x / 2.0, top - 10), g.display_name(), 13, Palette.SUN, 0, 3, Palette.NIGHT)
	for i in ItemStack.RUNE_SLOTS:
		var rune: RuneDef = g.runes[i] if g else null
		draw_slot(socket_rect(i), _stack_of(rune), false, "Empty" if g else "")
	var line := hint()
	DrawUtil.text(self, Game.ui_font, Vector2(size.x / 2.0, top + SOCKET + 22), line,
		DrawUtil.fit_size(Game.ui_font, line, 12, size.x - PAD * 2), Palette.MIST, 0)
	_draw_upgrade(g)
	draw_shards(Vector2(size.x - PAD - 92, size.y - 22), Game.me.shards)

## The button that raises the picked gear a tier: its next tier and fee, dim when there's
## nothing to raise, it's at the top or the fee is more than you have.
func _draw_upgrade(g: ItemStack) -> void:
	var r := bottom_button_rect(PAD, UPGRADE_W)
	var next := g.next_tier() if g else null
	if g == null:
		draw_button(r, "Upgrade", false, true)
	elif next == null:
		draw_button(r, "Highest tier", false, true)
	else:
		add_button(r, "Upgrade to %s (%d Dawnshards)" % [next.display_name, next.fee], upgrade, Game.me.shards >= next.fee, true)

func _stack_of(rune: RuneDef) -> ItemStack:
	if rune == null:
		return null
	if not _shown.has(rune):
		_shown[rune] = ItemStack.create(rune)
	return _shown[rune]

# ---------- input ----------

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var i := gear.at(at)
	if i >= 0:
		gear_slot = i if Game.me.inventory.at(ItemDef.Tab.EQUIP, i) else -1
		return
	i = runes.at(at)
	if i >= 0:
		var held := Game.me.inventory.at(ItemDef.Tab.ETC, i)
		rune_slot = i if held and held.item is RuneDef else -1
		return
	i = socket_at(at)
	if i >= 0:
		enchant(i)

## Asks to set the picked rune in rune slot `socket` of the picked gear, after saying what
## it costs and what it replaces.
func enchant(socket: int) -> void:
	var g := picked_gear()
	var r := picked_rune()
	if g == null or r == null:
		return
	var old := g.runes[socket]
	var question := "Set the %s in the %s for %d Dawnshards?" % [r.display_name, g.display_name(), r.fee]
	if old:
		question += " The %s in that slot is lost." % old.display_name
	var from := [gear_slot, rune_slot]
	hud.confirm.open(question, "Enchant", func() -> void:
		# only if the same gear and rune are still there and the enchanter still open
		var bag := Game.me.inventory
		var held := bag.at(ItemDef.Tab.ETC, from[1])
		if visible and bag.at(ItemDef.Tab.EQUIP, from[0]) == g and held and held.item == r:
			Net.ask(&"req_enchant", [npc.def.id, from[0], from[1], socket]))

## Asks to raise the picked gear a tier, after saying what it costs.
func upgrade() -> void:
	var g := picked_gear()
	var next := g.next_tier() if g else null
	if next == null:
		return
	var question := "Upgrade the %s to %s for %d Dawnshards? It keeps its runes and look." % [g.display_name(), next.display_name, next.fee]
	var from := gear_slot
	var to := g.tier
	hud.confirm.open(question, "Upgrade", func() -> void:
		# only if the same gear, still at that tier, is there and the enchanter still open
		if visible and Game.me.inventory.at(ItemDef.Tab.EQUIP, from) == g and g.tier == to:
			Net.ask(&"req_upgrade", [npc.def.id, from]))

func _tooltip_at(at: Vector2) -> Tip:
	var bag := Game.me.inventory
	var i := gear.at(at)
	if i >= 0:
		return Tip.new(bag.at(ItemDef.Tab.EQUIP, i), "Click to enchant it")
	i = runes.at(at)
	if i >= 0:
		var held := bag.at(ItemDef.Tab.ETC, i)
		return Tip.new(held, "Click to pick it" if held and held.item is RuneDef else "")
	i = socket_at(at)
	var g := picked_gear()
	if i >= 0 and g:
		return Tip.new(_stack_of(g.runes[i]))
	return null
