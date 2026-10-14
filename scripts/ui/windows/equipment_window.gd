class_name TDEquipmentWindow
extends TDWindow
## What the hero is wearing (E): gear slots laid out the way a person wears them (hat on top,
## shoes at the bottom), and a panel listing what the gear adds to each stat (all of it, or the
## worn item you clicked).
## Double-click a worn item to take it off, drag gear here from the inventory to wear it, or
## drag a worn item onto the inventory.

const GAP := 6.0
const GRID_Y := 40.0
const COLS := 5
const ROWS := 6
## Where each place sits, in a COLS×ROWS grid laid out like a person facing right.
const LAYOUT := {
	&"hat": Vector2i(2, 0),
	&"earrings": Vector2i(1, 1),
	&"cape": Vector2i(1, 2), &"pendant": Vector2i(2, 2),
	&"shield": Vector2i(0, 3), &"top": Vector2i(2, 3), &"weapon": Vector2i(4, 3),
	&"ring_1": Vector2i(0, 4), &"bottom": Vector2i(2, 4), &"gloves": Vector2i(3, 4), &"ring_2": Vector2i(4, 4),
	&"shoes": Vector2i(2, 5),
}
const PANEL_W := 176.0
const ROW_H := 16.0

## The worn item whose stats the panel shows, or &"" for the whole set.
var selected: StringName = &""
## The grid LAYOUT places the slots in.
var grid := SlotGrid.new(Vector2(PAD, GRID_Y), COLS, COLS * ROWS, SLOT, GAP)

func _init() -> void:
	super("Equipment", Vector2(PAD * 2 + COLS * (SLOT + GAP) - GAP + 10 + PANEL_W, GRID_Y + ROWS * (SLOT + GAP) + 14))

func _grid_box() -> Rect2:
	return Rect2(PAD, GRID_Y, COLS * (SLOT + GAP) - GAP, ROWS * (SLOT + GAP) - GAP)

func slot_rect(place: StringName) -> Rect2:
	return grid.cell_rect(LAYOUT[place])

func place_at(at: Vector2) -> StringName:
	for p in LAYOUT:
		if slot_rect(p).has_point(at):
			return p
	return &""

func _draw_body() -> void:
	var dragging := _dragged_equip()
	for p in LAYOUT:
		var stack := Game.me.equipment.at(p)
		var r := slot_rect(p)
		draw_slot(r, stack, p == dragging, Equipment.PLACE_NAMES[p])
		if _drag_fits(p):
			DrawUtil.round_rect(self, r.grow(-2), 6, Color(Palette.SUN, 0.25))
		if p == selected and stack:
			draw_rect(r.grow(-2), Palette.SUN, false, 2.0)
	_draw_bonuses()

## The panel on the right: what the gear adds to each stat.
func _draw_bonuses() -> void:
	if selected != &"" and Game.me.equipment.at(selected) == null:
		selected = &""
	var panel := Rect2(size.x - PAD - PANEL_W, GRID_Y, PANEL_W, _grid_box().size.y)
	draw_row(panel)
	var stack := Game.me.equipment.at(selected) if selected != &"" else null
	var heading := stack.item.display_name if stack else "Gear bonuses"
	var bonus := stack.stats if stack else Game.me.equipment.bonus()
	var x := panel.position.x + 10
	var y := panel.position.y + 20
	DrawUtil.text(self, Game.ui_font, Vector2(x, y), heading, 13, Palette.SUN, 1, 3, Palette.NIGHT)
	y += 6
	var stats := bonus.nonzero()
	if stats.is_empty():
		draw_hint(Vector2(x, y + ROW_H), "Nothing worn yet." if stack == null else "No stats.")
	for f in stats:
		y += ROW_H
		DrawUtil.text(self, Game.ui_font, Vector2(x, y), StatBlock.LABELS[f], 11, Palette.MUTED, 1)
		DrawUtil.text(self, Game.ui_font, Vector2(panel.end.x - 10, y), StatBlock.format(f, bonus.value(f)), 11, Palette.GOOD, -1)
	DrawUtil.text(self, Game.ui_font, Vector2(panel.get_center().x, panel.end.y - 8),
		"Click again for all gear" if stack else "Click an item for its stats", 10, Color(Palette.MIST, 0.5))

## The gear being dragged from the inventory, if it would fit `place`.
func _drag_fits(place: StringName) -> bool:
	var d := DragPayload.dragging(self)
	if not DragPayload.is_bag_item(d, ItemDef.Tab.EQUIP):
		return false
	var stack := Game.me.inventory.at(ItemDef.Tab.EQUIP, d.index)
	return stack != null and Equipment.fits(stack.equip_def(), place)

func _dragged_equip() -> StringName:
	var d := DragPayload.dragging(self)
	return d.place if d and d.from == DragPayload.From.EQUIPMENT else &""

func _click(at: Vector2, button: int, double: bool) -> void:
	var p := place_at(at)
	if button == MOUSE_BUTTON_LEFT and not double:
		# a worn item shows its own stats in the panel; clicking it again shows the whole set
		selected = p if p != selected and p != &"" and Game.me.equipment.at(p) != null else &""
	if p != &"" and button == MOUSE_BUTTON_LEFT and double:
		Net.ask(&"req_unequip", [p, -1])
		hud.tooltip.clear(self)

func _tooltip_at(at: Vector2) -> Tip:
	var p := place_at(at)
	return Tip.new(Game.me.equipment.at(p) if p != &"" else null, "Double-click to take off")

func _get_drag_data(at: Vector2) -> Variant:
	var p := place_at(at)
	if p == &"" or Game.me.equipment.at(p) == null:
		return null
	set_drag_preview(drag_preview(Game.me.equipment.at(p).item.icon))
	hud.tooltip.clear(self)
	return DragPayload.worn(p)

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return DragPayload.is_bag_item(data, ItemDef.Tab.EQUIP) and place_at(at) != &""

func _drop_data(at: Vector2, data: Variant) -> void:
	Net.ask(&"req_equip", [DragPayload.of(data).index, place_at(at)])
