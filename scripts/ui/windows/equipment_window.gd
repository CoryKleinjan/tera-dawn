class_name TDEquipmentWindow
extends TDWindow
## What the hero is wearing (E): a paper doll of gear slots around a portrait. Double-click
## a worn item to take it off, drag gear here from the inventory to wear it, or drag a worn
## item onto the inventory.

const GAP := 6.0
const GRID_Y := 40.0
## Where each place sits in a 4×4 grid; the portrait fills the middle 2×2.
const LAYOUT := {
	&"ring_1": Vector2i(0, 0), &"hat": Vector2i(1, 0), &"earrings": Vector2i(2, 0), &"ring_2": Vector2i(3, 0),
	&"pendant": Vector2i(0, 1), &"weapon": Vector2i(3, 1),
	&"cape": Vector2i(0, 2), &"shield": Vector2i(3, 2),
	&"gloves": Vector2i(0, 3), &"top": Vector2i(1, 3), &"bottom": Vector2i(2, 3), &"shoes": Vector2i(3, 3),
}

var portrait: Texture2D

func _init() -> void:
	super("Equipment", Vector2(PAD * 2 + 4 * (SLOT + GAP) - GAP, GRID_Y + 4 * (SLOT + GAP) + 14))
	portrait = TDPlayer.HERO_FRAMES.get_frame_texture(&"idle", 0)

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
	var box := Rect2(PAD + SLOT + GAP, GRID_Y + SLOT + GAP, SLOT * 2 + GAP, SLOT * 2 + GAP)
	DrawUtil.round_rect(self, box, 10, Color(Palette.NIGHT, 0.55))
	if portrait:
		var s := minf(box.size.x / portrait.get_width(), box.size.y / portrait.get_height()) * 1.3
		var ps := portrait.get_size() * s
		draw_texture_rect(portrait, Rect2(box.get_center() - Vector2(ps.x / 2.0, ps.y * 0.55), ps), false)
	DrawUtil.text(self, Game.ui_font, Vector2(box.get_center().x, box.end.y - 6), "%s Lv. %d" % [Game.job.display_name, Game.level], 11, Palette.MIST, 0, 4, Palette.NIGHT)
	var dragging := _dragged_equip()
	for p in LAYOUT:
		var stack := Game.equipment.at(p)
		var r := slot_rect(p)
		draw_slot(r, stack, p == dragging, Equipment.PLACE_NAMES[p])
		if _drag_fits(p):
			DrawUtil.round_rect(self, r.grow(-2), 6, Color(Palette.SUN, 0.25))

## The gear being dragged from the inventory, if it would fit `place`.
func _drag_fits(place: StringName) -> bool:
	if not get_viewport().gui_is_dragging():
		return false
	var d: Variant = get_viewport().gui_get_drag_data()
	if not (d is Dictionary and d.get("from") == "inventory" and d.get("tab") == ItemDef.Tab.EQUIP):
		return false
	var stack := Game.inventory.at(ItemDef.Tab.EQUIP, d["index"])
	return stack != null and Equipment.fits(stack.equip_def(), place)

func _dragged_equip() -> StringName:
	if not get_viewport().gui_is_dragging():
		return &""
	var d: Variant = get_viewport().gui_get_drag_data()
	return d["place"] if d is Dictionary and d.get("from") == "equipment" else &""

func _click(at: Vector2, button: int, double: bool) -> void:
	var p := place_at(at)
	if p != &"" and button == MOUSE_BUTTON_LEFT and double:
		var problem := Game.unequip(p)
		if problem != "":
			hud.world.add_log(problem, Color("ff8a99"))
		hud.tooltip.clear(self)

func _hovered(at: Vector2) -> void:
	var p := place_at(at)
	hud.tooltip.show_item(self, Game.equipment.at(p) if p != &"" else null, get_global_mouse_position())

func _get_drag_data(at: Vector2) -> Variant:
	var p := place_at(at)
	if p == &"" or Game.equipment.at(p) == null:
		return null
	set_drag_preview(drag_preview(Game.equipment.at(p)))
	hud.tooltip.clear(self)
	return {"from": "equipment", "place": p}

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "inventory" and data.get("tab") == ItemDef.Tab.EQUIP \
		and place_at(at) != &""

func _drop_data(at: Vector2, data: Variant) -> void:
	var problem := Game.equip(data["index"], place_at(at))
	if problem != "":
		hud.world.add_log(problem, Color("ff8a99"))
