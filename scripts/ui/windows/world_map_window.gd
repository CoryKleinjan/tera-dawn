class_name TDWorldMapWindow
extends TDWindow
## The world map (W): every region as a coloured patch with its name, every map as a dot
## (towns bigger, with a gold ring) joined by its portals, travel routes as dashed lines, and
## where you are. Hover a dot to read the map's name, region and level range. Positions come
## from MapDef.world_pos and RegionDef.label_pos, in world-map units (1000 x 600).

const WORLD := Vector2(1000, 600)
const NODE_PICK := 12.0

var hovered: StringName = &""

func _init() -> void:
	super("World Map", Vector2(620, 430))

## Where the world map's area sits in the window.
func _area() -> Rect2:
	return Rect2(PAD, TITLE_H + 8, size.x - PAD * 2, size.y - TITLE_H - 8 - 58)

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
	DrawUtil.round_rect(self, a, 10, Color("23365e"))
	DrawUtil.round_rect(self, a.grow(-3), 8, Color("2c4777"))
	var maps := placed()
	var k := a.size.x / WORLD.x
	# region patches
	for m in maps:
		var r: RegionDef = Content.regions.get(m.region)
		if r:
			draw_circle(to_screen(m.world_pos), 52 * k, Color(r.color, 0.22))
			draw_circle(to_screen(m.world_pos), 34 * k, Color(r.color, 0.18))
	for r in Content.regions.values():
		if r.label_pos != Vector2.ZERO:
			var at := to_screen(r.label_pos)
			DrawUtil.text(self, Game.num_font, at, r.display_name, 14, r.color.lightened(0.35), 0, 4, Palette.NIGHT)
			if r.level_text != "":
				DrawUtil.text(self, Game.ui_font, at + Vector2(0, 14), r.level_text, 10, Palette.MIST, 0, 3, Palette.NIGHT)
	# roads (portals) and trips (travel NPCs)
	for m in maps:
		for n in m.neighbours():
			var other: MapDef = Content.maps.get(n)
			if other and other.world_pos != Vector2.ZERO and String(m.id) < String(n):
				draw_line(to_screen(m.world_pos), to_screen(other.world_pos), Color(Palette.SUN, 0.55), 2.0, true)
		for place in m.npcs:
			for route in place.npc.travel:
				var dest: MapDef = Content.maps.get(route.target_map)
				if dest and dest.world_pos != Vector2.ZERO:
					draw_dashed_line(to_screen(m.world_pos), to_screen(dest.world_pos), Color(Palette.MIST, 0.6), 1.5, 6.0)
	# the maps
	var here: StringName = hud.world.map.id if hud and hud.world and hud.world.map else &""
	for m in maps:
		var c := to_screen(m.world_pos)
		var on := m.id == hovered
		if m.town:
			draw_circle(c, 8.5, Color("e9b44c"))
			draw_circle(c, 6.0, Palette.PLUM)
			draw_circle(c, 3.0, Palette.SUN if on else Color("ffe7a8"))
		else:
			draw_circle(c, 5.0, Palette.NIGHT)
			draw_circle(c, 3.5, Palette.SUN if on else Color("c9b8d9"))
		if m.id == here:
			var pulse := 11.0 + sin(Engine.get_physics_frames() * 0.12) * 2.5
			draw_arc(c, pulse, 0, TAU, 24, Palette.SUN, 2.0, true)
	_draw_info(Content.maps.get(hovered if hovered != &"" else here))

## The hovered map (or the one you're on) under the map.
func _draw_info(m: MapDef) -> void:
	if m == null:
		return
	var y := size.y - 34
	var r: RegionDef = Content.regions.get(m.region)
	var name := m.display_name + ("  ·  Town" if m.town else "")
	DrawUtil.text(self, Game.num_font, Vector2(PAD + 4, y), name, 16, Palette.SUN, 1, 4, Palette.NIGHT)
	var bits := []
	if r:
		bits.append(r.display_name)
	if m.level_text != "":
		bits.append(m.level_text)
	if hud and hud.world and hud.world.map and m.id == hud.world.map.id:
		bits.append("You are here")
	DrawUtil.text(self, Game.ui_font, Vector2(PAD + 4, y + 18), "  ·  ".join(bits), 12, Palette.MIST, 1, 3, Palette.NIGHT)

func _hovered(at: Vector2) -> void:
	hovered = &""
	var best := NODE_PICK
	for m in placed():
		var d := to_screen(m.world_pos).distance_to(at)
		if d < best:
			best = d
			hovered = m.id
