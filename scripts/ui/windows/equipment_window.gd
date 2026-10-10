class_name TDEquipmentWindow
extends TDWindow
## What the hero is wearing (E): a paper doll of gear slots around a portrait, and a panel
## listing what the gear adds to each stat (all of it, or the worn item you clicked).
## Double-click a worn item to take it off, drag gear here from the inventory to wear it, or
## drag a worn item onto the inventory.

const GAP := 6.0
const GRID_Y := 40.0
## Where each place sits in a 4×4 grid; the portrait fills the middle 2×2.
const LAYOUT := {
	&"ring_1": Vector2i(0, 0), &"hat": Vector2i(1, 0), &"earrings": Vector2i(2, 0), &"ring_2": Vector2i(3, 0),
	&"pendant": Vector2i(0, 1), &"weapon": Vector2i(3, 1),
	&"cape": Vector2i(0, 2), &"shield": Vector2i(3, 2),
	&"gloves": Vector2i(0, 3), &"top": Vector2i(1, 3), &"bottom": Vector2i(2, 3), &"shoes": Vector2i(3, 3),
}

const PANEL_W := 176.0
const ROW_H := 16.0

## Your hero, dressed in what you wear.
var doll := PaperdollView.new()
## Job and level under the hero, on a layer above the doll so the hero's feet never cover it.
var caption := Control.new()
## The worn item whose stats the panel shows, or &"" for the whole set.
var selected: StringName = &""

func _init() -> void:
	super("Equipment", Vector2(PAD * 2 + 4 * (SLOT + GAP) - GAP + 10 + PANEL_W, GRID_Y + 4 * (SLOT + GAP) + 14))
	var box := _portrait_box()
	var s := minf(box.size.x / Paperdoll.FRAME_SIZE.x, box.size.y / Paperdoll.FRAME_SIZE.y) * 1.3
	doll.size = Paperdoll.FRAME_SIZE * s
	doll.position = box.get_center() - Vector2(doll.size.x / 2.0, doll.size.y * 0.55)
	doll.max_zoom = s * Paperdoll.ART_SCALE
	add_child(doll)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.draw.connect(_draw_caption)
	add_child(caption)

func _portrait_box() -> Rect2:
	return Rect2(PAD + SLOT + GAP, GRID_Y + SLOT + GAP, SLOT * 2 + GAP, SLOT * 2 + GAP)

func slot_rect(place: StringName) -> Rect2:
	var cell: Vector2i = LAYOUT[place]
	return Rect2(PAD + cell.x * (SLOT + GAP), GRID_Y + cell.y * (SLOT + GAP), SLOT, SLOT)

func place_at(at: Vector2) -> StringName:
	for p in LAYOUT:
		if slot_rect(p).has_point(at):
			return p
	return &""

func _draw_body() -> void:
	# portrait
	var box := _portrait_box()
	draw_texture_rect(UiSkin.tex("equip_doll_bg"), box, false)
	doll.set_look(Game.me.look())
	caption.queue_redraw()
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

func _draw_caption() -> void:
	var box := _portrait_box()
	DrawUtil.text(caption, Game.ui_font, Vector2(box.get_center().x, box.end.y - 6), "%s Lv. %d" % [Game.me.job.display_name, Game.me.level],
		DrawUtil.fit_size(Game.ui_font, "%s Lv. %d" % [Game.me.job.display_name, Game.me.level], 11, box.size.x - 8), Palette.MIST, 0, 4, Palette.NIGHT)

## The panel on the right: what the gear adds to each stat.
func _draw_bonuses() -> void:
	if selected != &"" and Game.me.equipment.at(selected) == null:
		selected = &""
	var panel := Rect2(size.x - PAD - PANEL_W, GRID_Y, PANEL_W, 4 * (SLOT + GAP) - GAP)
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
	if not get_viewport().gui_is_dragging():
		return false
	var d: Variant = get_viewport().gui_get_drag_data()
	if not (d is Dictionary and d.get("from") == "inventory" and d.get("tab") == ItemDef.Tab.EQUIP):
		return false
	var stack := Game.me.inventory.at(ItemDef.Tab.EQUIP, d["index"])
	return stack != null and Equipment.fits(stack.equip_def(), place)

func _dragged_equip() -> StringName:
	if not get_viewport().gui_is_dragging():
		return &""
	var d: Variant = get_viewport().gui_get_drag_data()
	return d["place"] if d is Dictionary and d.get("from") == "equipment" else &""

func _click(at: Vector2, button: int, double: bool) -> void:
	var p := place_at(at)
	if button == MOUSE_BUTTON_LEFT and not double:
		# a worn item shows its own stats in the panel; clicking it again shows the whole set
		selected = p if p != selected and p != &"" and Game.me.equipment.at(p) != null else &""
	if p != &"" and button == MOUSE_BUTTON_LEFT and double:
		Net.ask(&"req_unequip", [p, -1])
		hud.tooltip.clear(self)

func _hovered(at: Vector2) -> void:
	var p := place_at(at)
	hud.tooltip.show_item(self, Game.me.equipment.at(p) if p != &"" else null, get_global_mouse_position(), "Double-click to take off")

func _get_drag_data(at: Vector2) -> Variant:
	var p := place_at(at)
	if p == &"" or Game.me.equipment.at(p) == null:
		return null
	set_drag_preview(drag_preview(Game.me.equipment.at(p)))
	hud.tooltip.clear(self)
	return {"from": "equipment", "place": p}

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "inventory" and data.get("tab") == ItemDef.Tab.EQUIP \
		and place_at(at) != &""

func _drop_data(at: Vector2, data: Variant) -> void:
	Net.ask(&"req_equip", [data["index"], place_at(at)])
