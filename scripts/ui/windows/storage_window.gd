class_name TDStorageWindow
extends TDWindow
## Storage (from a storage keeper in town): what you keep there on the left, your bag on the
## right, with the same Equip / Use / Etc tab for both. Double-click a bag item to store the
## whole stack (it costs Character.STORE_FEE Dawnshards), or a stored item to take it back.
## The server keeps storage with the character. Closes when you walk away.

const COLS := 4
const GAP := 4.0
const GRID_Y := 74.0
const GRID_W := COLS * (SLOT + GAP) - GAP
const BAG_X := PAD + GRID_W + 24
const REACH := 170.0

var npc: TDNpc
var tab := ItemDef.Tab.ETC
## What's stored on the left, your bag on the right.
var stored := SlotGrid.new(Vector2(PAD, GRID_Y), COLS, Inventory.SLOTS, SLOT, GAP)
var bag := SlotGrid.new(Vector2(BAG_X, GRID_Y), COLS, Inventory.SLOTS, SLOT, GAP)

func _init() -> void:
	var rows := ceili(Inventory.SLOTS / float(COLS))
	super("Storage", Vector2(BAG_X + GRID_W + PAD, GRID_Y + rows * (SLOT + GAP) + 52))

func open(who: TDNpc) -> void:
	npc = who
	title = "%s's Storage" % who.def.display_name
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -30)
	visible = true
	raise()

func _process(delta: float) -> void:
	super(delta)
	if visible and (npc == null or not is_instance_valid(npc) or hud.world.player.position.distance_to(npc.position) > REACH):
		visible = false
		hud.tooltip.clear(self)

func slot_rect(i: int, in_bag: bool) -> Rect2:
	return (bag if in_bag else stored).rect(i)

## [slot, is the bag] under a point, or [-1, false].
func _slot_at(at: Vector2) -> Array:
	for in_bag in [false, true]:
		var i := (bag if in_bag else stored).at(at)
		if i >= 0:
			return [i, in_bag]
	return [-1, false]

func _draw_body() -> void:
	draw_tabs(ItemDef.TAB_NAMES, tab)
	for i in Inventory.SLOTS:
		draw_slot(slot_rect(i, false), Game.me.storage.at(tab, i))
		draw_slot(slot_rect(i, true), Game.me.inventory.at(tab, i))
	var y := size.y - 22
	DrawUtil.text(self, Game.ui_font, Vector2(PAD, y), "Stored", 12, Palette.MUTED, 1)
	DrawUtil.text(self, Game.ui_font, Vector2(BAG_X, y), "Your bag", 12, Palette.MUTED, 1)
	draw_shards(Vector2(size.x - PAD - 92, y), Game.me.shards)

func _click(at: Vector2, button: int, double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var hit := _slot_at(at)
	if double and hit[0] >= 0:
		if hit[1]:
			store(hit[0])
		else:
			take(hit[0])

func _tab_clicked(i: int) -> void:
	tab = i as ItemDef.Tab

## Stores bag slot `i` of the open tab.
func store(i: int) -> void:
	if Game.me.inventory.at(tab, i):
		Net.ask(&"req_store", [npc.def.id, tab, i])
		hud.tooltip.clear(self)

## Takes storage slot `i` of the open tab back into the bag.
func take(i: int) -> void:
	if Game.me.storage.at(tab, i):
		Net.ask(&"req_retrieve", [npc.def.id, tab, i])
		hud.tooltip.clear(self)

func _tooltip_at(at: Vector2) -> Tip:
	var hit := _slot_at(at)
	if hit[0] < 0:
		return null
	var stack := (Game.me.inventory if hit[1] else Game.me.storage).at(tab, hit[0])
	return Tip.new(stack, "Double-click to store (%d Dawnshards)" % Character.STORE_FEE if hit[1] else "Double-click to take out")
