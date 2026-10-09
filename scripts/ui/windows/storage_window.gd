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

func _tab_rect(t: int) -> Rect2:
	var w := (size.x - PAD * 2) / ItemDef.Tab.size()
	return Rect2(PAD + t * w - 3, 36, w + 6, 26)

func slot_rect(i: int, bag: bool) -> Rect2:
	return Rect2((BAG_X if bag else PAD) + (i % COLS) * (SLOT + GAP), GRID_Y + (i / COLS) * (SLOT + GAP), SLOT, SLOT)

## [slot, is the bag] under a point, or [-1, false].
func _slot_at(at: Vector2) -> Array:
	for bag in [false, true]:
		for i in Inventory.SLOTS:
			if slot_rect(i, bag).has_point(at):
				return [i, bag]
	return [-1, false]

func _draw_body() -> void:
	for t in ItemDef.Tab.size():
		draw_tab(_tab_rect(t), ItemDef.TAB_NAMES[t], t == tab)
	for i in Inventory.SLOTS:
		draw_slot(slot_rect(i, false), Game.me.storage.at(tab, i))
		draw_slot(slot_rect(i, true), Game.me.inventory.at(tab, i))
	var y := size.y - 22
	DrawUtil.text(self, Game.ui_font, Vector2(PAD, y), "Stored", 12, Color("c9b8d9"), 1)
	DrawUtil.text(self, Game.ui_font, Vector2(BAG_X, y), "Your bag", 12, Color("c9b8d9"), 1)
	draw_texture_rect(UiSkin.tex("icon_dawnshard"), Rect2(size.x - PAD - 92, y - 16, 22, 20), false)
	DrawUtil.text(self, Game.num_font, Vector2(size.x - PAD - 64, y), str(Game.me.shards), 15, Palette.SUN, 1, 4, Palette.NIGHT)

func _click(at: Vector2, button: int, double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	for t in ItemDef.Tab.size():
		if _tab_rect(t).has_point(at):
			tab = t as ItemDef.Tab
			return
	var hit := _slot_at(at)
	if double and hit[0] >= 0:
		if hit[1]:
			store(hit[0])
		else:
			take(hit[0])

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

func _hovered(at: Vector2) -> void:
	var hit := _slot_at(at)
	if hit[0] < 0:
		hud.tooltip.show_item(self, null, Vector2.ZERO)
		return
	var stack := (Game.me.inventory if hit[1] else Game.me.storage).at(tab, hit[0])
	var hint := "Double-click to store (%d Dawnshards)" % Character.STORE_FEE if hit[1] else "Double-click to take out"
	hud.tooltip.show_item(self, stack, get_global_mouse_position(), hint if stack else "")
