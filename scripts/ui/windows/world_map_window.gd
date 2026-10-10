class_name TDWorldMapWindow
extends TDWindow
## The world map (W): the painted map (assets/sprites/ui/world_map.png) with every region's
## name, every map as a dot (towns bigger, with a gold ring), travel routes as dashed lines,
## and where you are. Hover a dot to read the map's name, region and level range. Positions
## come from MapDef.world_pos and RegionDef.label_pos, in world-map units (1000 x 600), which
## cover the whole painting: a map's world_pos is where it is drawn on the painting.

const WORLD := Vector2(1000, 600)
const NODE_PICK := 12.0
## How big the painting is drawn: 1000 x 600 world units at this many pixels each.
const MAP_SCALE := 0.66
## The strip under the painting for the hovered map, and how far its text sits in from the frame.
const INFO_H := 58.0
const INFO_X := PAD + 10

var hovered: StringName = &""

func _init() -> void:
	super("World Map", WORLD * MAP_SCALE + Vector2((PAD - 4) * 2, TITLE_H + 4 + INFO_H))

## Where the world map's area sits in the window.
func _area() -> Rect2:
	return Rect2(PAD - 4, TITLE_H + 4, WORLD.x * MAP_SCALE, WORLD.y * MAP_SCALE)

func to_screen(p: Vector2) -> Vector2:
	var a := _area()
	return a.position + p / WORLD * a.size

## The maps placed on the world map.
static func placed() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m in Content.maps.values():
		if m.world_pos != Vector2.ZERO:
			out.append(m)
	return out

func _draw_body() -> void:
	var a := _area()
	draw_texture_rect(UiSkin.tex("world_map"), a, false)
	var maps := placed()
	# trips (travel NPCs); the roads between maps are painted
	for m in maps:
		for place in m.npcs:
			for route in place.npc.travel:
				var dest: MapDef = Content.maps.get(route.target_map)
				if dest and dest.world_pos != Vector2.ZERO:
					draw_dashed_line(to_screen(m.world_pos), to_screen(dest.world_pos), Color(Palette.MIST, 0.7), 2.0, 7.0)
	# the maps
	var here: StringName = hud.world.map.id if hud and hud.world and hud.world.map else &""
	for m in maps:
		var c := to_screen(m.world_pos)
		var on := m.id == hovered
		if m.town:
			draw_circle(c, 8.5, Palette.NIGHT)
			draw_circle(c, 7.0, Palette.GOLD_TRIM)
			draw_circle(c, 4.5, Palette.PLUM)
			draw_circle(c, 2.5, Palette.SUN if on else Color("ffe7a8"))
		else:
			draw_circle(c, 5.5, Palette.NIGHT)
			draw_circle(c, 4.0, Palette.SUN if on else Palette.MIST)
		if on:
			draw_arc(c, 10.0, 0, TAU, 24, Palette.SUN, 1.5, true)
		if m.id == here:
			var pulse := 12.0 + sin(Engine.get_physics_frames() * 0.12) * 2.5
			draw_arc(c, pulse, 0, TAU, 24, Palette.NIGHT, 4.0, true)
			draw_arc(c, pulse, 0, TAU, 24, Palette.SUN, 2.0, true)
	# region names last, so no dot or road covers them
	for r in Content.regions.values():
		if r.label_pos != Vector2.ZERO:
			var at := to_screen(r.label_pos)
			DrawUtil.text(self, Game.num_font, at, r.display_name, 15, r.color.lightened(0.45), 0, 5, Palette.NIGHT)
			if r.level_text != "":
				DrawUtil.text(self, Game.ui_font, at + Vector2(0, 14), r.level_text, 11, Palette.MIST, 0, 4, Palette.NIGHT)
	_draw_info(Content.maps.get(hovered if hovered != &"" else here))

## The hovered map (or the one you're on) under the map.
func _draw_info(m: MapDef) -> void:
	if m == null:
		return
	var y := size.y - INFO_H + 23
	var r: RegionDef = Content.regions.get(m.region)
	var name := m.display_name + ("  ·  Town" if m.town else "")
	DrawUtil.text(self, Game.num_font, Vector2(INFO_X, y), name, 16, Palette.SUN, 1, 4, Palette.NIGHT)
	var bits := []
	if r:
		bits.append(r.display_name)
	if m.level_text != "":
		bits.append(m.level_text)
	if hud and hud.world and hud.world.map and m.id == hud.world.map.id:
		bits.append("You are here")
	DrawUtil.text(self, Game.ui_font, Vector2(INFO_X, y + 18), "  ·  ".join(bits), 12, Palette.MIST, 1, 3, Palette.NIGHT)

## The screen area a region's name (and level range) covers, for keeping dots off it.
func label_rect(r: RegionDef) -> Rect2:
	var at := to_screen(r.label_pos)
	var w := maxf(DrawUtil.text_width(Game.num_font, r.display_name, 15), DrawUtil.text_width(Game.ui_font, r.level_text, 11))
	return Rect2(at.x - w / 2.0, at.y - 12, w, 16 if r.level_text == "" else 30)

func _hovered(at: Vector2) -> void:
	hovered = &""
	var best := NODE_PICK
	for m in placed():
		var d := to_screen(m.world_pos).distance_to(at)
		if d < best:
			best = d
			hovered = m.id
