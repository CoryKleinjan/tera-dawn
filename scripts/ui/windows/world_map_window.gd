class_name TDWorldMapWindow
extends TDWindow
## The world map (W), in two views:
## - The **world view**: the painted map (assets/sprites/ui/world_map.png) with every region's
##   name and main city, and the major routes between regions (WorldRoutes): on foot as a row of dots,
##   ships as thin dashes. Clicking a region opens its zone view.
## - A **zone view**: one region up close (for now a zoomed-in part of the same painting,
##   RegionDef.zone_rect) with every map in it as a dot, the paths between them, and where each
##   exit to another region leads. A back arrow returns to the world view.
## Hovering a dot or a region tells you about it in the strip under the map. Positions come
## from MapDef.world_pos and RegionDef.label_pos/zone_rect, in world-map units: the painting's
## own pixels (WORLD). A new painting means placing every dot and region name on it again.

## The painting's size in pixels: the world-map units.
const WORLD := Vector2(955, 629)
## The painted land and sea inside the painting's paper scroll: zone views stay inside it.
const INNER := Rect2(28, 32, 899, 562)
const NODE_PICK := 12.0
## How near (screen pixels) a region's city or fields must be to pick the region on the world view.
const REGION_PICK := 40.0
## How big the painting is drawn: screen pixels per world-map unit (the same both ways, so
## the painting keeps its shape).
const MAP_SCALE := 0.63
## The strip under the painting for the hovered map, and how far its text sits in from the frame.
const INFO_H := 58.0
const INFO_X := PAD + 10
## The back arrow in the zone view's top left corner (the creator's painted arrow).
const BACK_SIZE := Vector2(34, 30)
## Routes and paths: soft dots on foot, thin dashes by ship, on a dark edge.
const ROAD_EDGE := Color(0.12, 0.08, 0.16, 0.85)
const TRIP := Color("ffcf5a")
const ROUTE := Color("fff1cc")
const ROUTE_DOT_GAP := 9.0

## The region shown up close, or none for the world view.
var zone: StringName = &""
## How a field the player hasn't been to yet is named and drawn.
const UNKNOWN := "???"
const UNKNOWN_DOT := Color(0.55, 0.5, 0.45)

## The hovered map (zone view) and region (world view).
var hovered: StringName = &""
var hovered_region: StringName = &""

func _init() -> void:
	super("World Map", WORLD * MAP_SCALE + Vector2((PAD - 4) * 2, TITLE_H + 4 + INFO_H))

## Where the world map's area sits in the window.
func _area() -> Rect2:
	return Rect2(PAD - 4, TITLE_H + 4, WORLD.x * MAP_SCALE, WORLD.y * MAP_SCALE)

## The part of the painting on show (world-map units): all of it, or the zone's part of it
## widened to the painting's shape and kept inside the scroll's border (INNER).
func view() -> Rect2:
	var r: RegionDef = Content.regions.get(zone)
	return zone_view(r) if r else Rect2(Vector2.ZERO, WORLD)

static func zone_view(r: RegionDef) -> Rect2:
	var s := r.zone_rect.size
	if s.x / s.y < WORLD.aspect():
		s.x = s.y * WORLD.aspect()
	else:
		s.y = s.x / WORLD.aspect()
	s = s.min(INNER.size)
	var at := (r.zone_rect.get_center() - s / 2.0).clamp(INNER.position, INNER.end - s)
	return Rect2(at, s)

func to_screen(p: Vector2) -> Vector2:
	var a := _area()
	var v := view()
	return a.position + (p - v.position) / v.size * a.size

## The maps placed on the world map.
static func placed() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m in Content.maps.values():
		if m.world_pos != Vector2.ZERO:
			out.append(m)
	return out

## The maps of `region` placed on the world map.
static func placed_in(region: StringName) -> Array[MapDef]:
	return placed().filter(func(m: MapDef) -> bool: return m.region == region)

## Where a region's city is on the painting.
static func capital_pos(r: RegionDef) -> Vector2:
	var c: MapDef = Content.maps.get(r.capital)
	return c.world_pos if c else r.label_pos

## Shows `region` up close (or the world view for none).
func open_zone(region: StringName) -> void:
	zone = region
	var r: RegionDef = Content.regions.get(region)
	title = "World Map" if r == null else "World Map  ·  %s" % r.display_name
	hovered = &""
	hovered_region = &""
	queue_redraw()

## The map you're on (the town outside, for a room).
func _here() -> StringName:
	return hud.world.map.outside() if hud and hud.world and hud.world.map else &""

func _draw_body() -> void:
	var a := _area()
	var tex := UiSkin.tex("world_map")
	var v := view()
	var k := Vector2(tex.get_size()) / WORLD
	draw_texture_rect_region(tex, a, Rect2(v.position * k, v.size * k))
	if zone == &"":
		_draw_world()
	else:
		_draw_zone()

# ---------- world view ----------

func _draw_world() -> void:
	for route in WorldRoutes.routes():
		var from := to_screen(capital_pos(Content.regions[route.a]))
		var to := to_screen(capital_pos(Content.regions[route.b]))
		var lit: bool = hovered_region in [route.a, route.b]
		_draw_route(from, to, route.by, lit)
	var here: MapDef = Content.maps.get(_here())
	for r: RegionDef in Content.regions.values():
		var c: MapDef = Content.maps.get(r.capital)
		if c:
			_draw_dot(to_screen(c.world_pos), true, r.id == hovered_region)
	if here and here.world_pos != Vector2.ZERO:
		if not here.town:
			_draw_dot(to_screen(here.world_pos), false, false)
		_draw_here(to_screen(here.world_pos))
	# region names last, so no dot or road covers them
	for r: RegionDef in Content.regions.values():
		if r.label_pos != Vector2.ZERO:
			var at := to_screen(r.label_pos)
			var col := Palette.SUN if r.id == hovered_region else r.color.lightened(0.45)
			DrawUtil.text(self, Game.num_font, at, r.display_name, 15, col, 0, 5, Palette.NIGHT)
	_draw_region_info(Content.regions.get(hovered_region))

## A route between regions or a path between a zone's maps, kept light so it doesn't cover
## the painting: on foot a row of soft dots, a trip thin dashes; gold when `lit`.
func _draw_route(from: Vector2, to: Vector2, by: String, lit: bool) -> void:
	var col: Color = Palette.SUN if lit else Color(ROUTE, 0.8)
	if by == "Walk":
		var steps := maxi(1, int(from.distance_to(to) / ROUTE_DOT_GAP))
		for i in steps + 1:
			var c := from.lerp(to, float(i) / steps)
			draw_circle(c, 2.6, ROAD_EDGE)
			draw_circle(c, 1.7, col)
	else:
		draw_dashed_line(from, to, ROAD_EDGE, 3.5, 8.0)
		draw_dashed_line(from, to, col, 1.6, 8.0)

## Whether the player has found `m`: towns are always shown, fields once visited.
static func known(m: MapDef) -> bool:
	return m.town or Game.me == null or Game.me.visited.has(String(m.id))

func _draw_dot(c: Vector2, town: bool, on: bool, found := true) -> void:
	if not found:
		draw_circle(c, 4.5, Palette.NIGHT)
		draw_circle(c, 3.0, Palette.SUN if on else UNKNOWN_DOT)
	elif town:
		draw_circle(c, 8.5, Palette.NIGHT)
		draw_circle(c, 7.0, Palette.GOLD_TRIM)
		draw_circle(c, 4.5, Palette.PLUM)
		draw_circle(c, 2.5, Palette.SUN if on else Color("ffe7a8"))
	else:
		draw_circle(c, 5.5, Palette.NIGHT)
		draw_circle(c, 4.0, Palette.SUN if on else Palette.MIST)
	if on:
		draw_arc(c, 10.0, 0, TAU, 24, Palette.SUN, 1.5, true)

func _draw_here(c: Vector2) -> void:
	var pulse := 12.0 + sin(Engine.get_physics_frames() * 0.12) * 2.5
	draw_arc(c, pulse, 0, TAU, 24, Palette.NIGHT, 4.0, true)
	draw_arc(c, pulse, 0, TAU, 24, Palette.SUN, 2.0, true)

## The hovered region under the map: its name, levels and routes.
func _draw_region_info(r: RegionDef) -> void:
	var y := size.y - INFO_H + 23
	if r == null:
		DrawUtil.text(self, Game.ui_font, Vector2(INFO_X, y + 8), "Click a region to see its maps.", 12, Palette.MIST, 1, 3, Palette.NIGHT)
		return
	var city: MapDef = Content.maps.get(r.capital)
	var name := r.display_name + ("  ·  " + city.display_name if city else "")
	DrawUtil.text(self, Game.num_font, Vector2(INFO_X, y), name, 16, Palette.SUN, 1, 4, Palette.NIGHT)
	var bits := []
	var ways := []
	for route in WorldRoutes.routes_of(r.id):
		var other: RegionDef = Content.regions.get(WorldRoutes.other_end(route, r.id))
		if other:
			ways.append(other.display_name + ("" if route.by == "Walk" else " (%s)" % route.by))
	if not ways.is_empty():
		bits.append("Routes: " + ", ".join(ways))
	bits.append("Click to open")
	DrawUtil.text(self, Game.ui_font, Vector2(INFO_X, y + 18), "  ·  ".join(bits), 12, Palette.MIST, 1, 3, Palette.NIGHT)

## The region at `at` on the world view: the one whose name is there, else the one with a
## city or field nearest to it.
func region_at(at: Vector2) -> StringName:
	for r: RegionDef in Content.regions.values():
		if r.label_pos != Vector2.ZERO and label_rect(r).has_point(at):
			return r.id
	var best := REGION_PICK
	var found: StringName = &""
	for m in placed():
		var d := to_screen(m.world_pos).distance_to(at)
		if d < best and Content.regions.has(m.region):
			best = d
			found = m.region
	return found

# ---------- zone view ----------

func _draw_zone() -> void:
	var r: RegionDef = Content.regions[zone]
	var maps := placed_in(zone)
	var here := _here()
	# paths between the zone's maps
	for pair in WorldRoutes.links():
		var a: MapDef = Content.maps.get(pair[0])
		var b: MapDef = Content.maps.get(pair[1])
		if a.region == zone and b.region == zone:
			var lit: bool = hovered in [a.id, b.id]
			_draw_route(to_screen(a.world_pos), to_screen(b.world_pos), "Walk", lit)
	# exits to other regions: a route to the edge of the view, labelled with where it leads
	for exit in zone_exits():
		_draw_route(exit.from, exit.to, exit.by, exit.map == hovered)
	for m in maps:
		_draw_dot(to_screen(m.world_pos), m.town, m.id == hovered, known(m))
	for m in maps:
		var c := to_screen(m.world_pos)
		DrawUtil.text(self, Game.ui_font, c + Vector2(0, 19 if m.town else 16), m.display_name if known(m) else UNKNOWN, 11,
			Palette.SUN if m.id == hovered else Color("fff4dc"), 0, 4, Palette.NIGHT)
	for exit in zone_exits():
		DrawUtil.text(self, Game.ui_font, exit.label_at, exit.label, 11, TRIP, 0, 4, Palette.NIGHT)
	var h: MapDef = Content.maps.get(here)
	if h and h.region == zone:
		_draw_here(to_screen(h.world_pos))
	icon_button(back_rect(), "creator/arrow_left", func() -> void: open_zone(&""))
	_draw_info(Content.maps.get(hovered if hovered != &"" else here if h and h.region == zone else r.capital))

func back_rect() -> Rect2:
	return Rect2(_area().position + Vector2(6, 6), BACK_SIZE)

## The zone's ways out to other regions, each {"map": the map it leaves from, "region": where
## it leads, "by", "from"/"to": the road on screen (cut at the view's edge), "label",
## "label_at"}. Walking exits come from the portals; trips from the zone's travel NPCs.
func zone_exits() -> Array:
	var out := []
	var a := _area().grow(-2)
	for route in WorldRoutes.routes_of(zone):
		var other: RegionDef = Content.regions.get(WorldRoutes.other_end(route, zone))
		if other == null:
			continue
		var legs := []
		if route.by == "Walk":
			for pair in route.crossings:
				var inside: MapDef = Content.maps[pair[0]] if Content.maps[pair[0]].region == zone else Content.maps[pair[1]]
				var outside: MapDef = Content.maps[pair[1]] if inside.id == pair[0] else Content.maps[pair[0]]
				legs.append([inside, outside.world_pos])
		else:
			var mine: RegionDef = Content.regions[zone]
			legs.append([Content.maps.get(mine.capital), capital_pos(other)])
		for leg in legs:
			var inside: MapDef = leg[0]
			if inside == null:
				continue
			var from := to_screen(inside.world_pos)
			var to := clip_to(from, to_screen(leg[1]), a)
			var dir := (to - from).normalized()
			var label := "To " + other.display_name + ("" if route.by == "Walk" else " (%s)" % route.by)
			var w := DrawUtil.text_width(Game.ui_font, label, 11)
			var at := to - dir * 14.0 + Vector2(0, 4)
			at.x = clampf(at.x, a.position.x + w / 2.0 + 4, a.end.x - w / 2.0 - 4)
			at.y = clampf(at.y, a.position.y + 14, a.end.y - 6)
			out.append({"map": inside.id, "region": other.id, "by": route.by, "from": from, "to": to, "label": label, "label_at": at})
	return out

## The point where the line from `from` (inside `r`) towards `to` leaves `r`, or `to` itself
## when it is inside.
static func clip_to(from: Vector2, to: Vector2, r: Rect2) -> Vector2:
	if r.has_point(to):
		return to
	var d := to - from
	var t := 1.0
	if d.x > 0.0:
		t = minf(t, (r.end.x - from.x) / d.x)
	elif d.x < 0.0:
		t = minf(t, (r.position.x - from.x) / d.x)
	if d.y > 0.0:
		t = minf(t, (r.end.y - from.y) / d.y)
	elif d.y < 0.0:
		t = minf(t, (r.position.y - from.y) / d.y)
	return from + d * maxf(t, 0.0)

## The hovered map (or the one you're on) under the map.
func _draw_info(m: MapDef) -> void:
	if m == null:
		return
	var y := size.y - INFO_H + 23
	var r: RegionDef = Content.regions.get(m.region)
	if not known(m):
		DrawUtil.text(self, Game.num_font, Vector2(INFO_X, y), UNKNOWN, 16, Palette.SUN, 1, 4, Palette.NIGHT)
		DrawUtil.text(self, Game.ui_font, Vector2(INFO_X, y + 18), "%sNot explored yet" % ((r.display_name + "  ·  ") if r else ""), 12, Palette.MIST, 1, 3, Palette.NIGHT)
		return
	var name := m.display_name + ("  ·  Town" if m.town else "")
	DrawUtil.text(self, Game.num_font, Vector2(INFO_X, y), name, 16, Palette.SUN, 1, 4, Palette.NIGHT)
	var bits := []
	if r:
		bits.append(r.display_name)
	if m.id == _here():
		bits.append("You are here")
	var ways := []
	for id in WorldRoutes.linked(m.id):
		var to: MapDef = Content.maps.get(id)
		if to:
			ways.append(to.display_name if known(to) else UNKNOWN)
	if not ways.is_empty():
		bits.append("Leads to " + ", ".join(ways))
	DrawUtil.text(self, Game.ui_font, Vector2(INFO_X, y + 18), "  ·  ".join(bits), 12, Palette.MIST, 1, 3, Palette.NIGHT)

## The screen area a region's name covers, for keeping dots off it.
func label_rect(r: RegionDef) -> Rect2:
	var at := to_screen(r.label_pos)
	var w := DrawUtil.text_width(Game.num_font, r.display_name, 15)
	return Rect2(at.x - w / 2.0, at.y - 12, w, 16)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button == MOUSE_BUTTON_RIGHT and zone != &"":
		open_zone(&"")
	elif button != MOUSE_BUTTON_LEFT:
		return
	elif zone == &"":
		var r := region_at(at)
		if r != &"":
			Sound.play(Sound.CLICK)
			open_zone(r)
	else:
		for exit in zone_exits():
			var w := DrawUtil.text_width(Game.ui_font, exit.label, 11)
			if Rect2(exit.label_at - Vector2(w / 2.0, 12), Vector2(w, 16)).has_point(at):
				Sound.play(Sound.CLICK)
				open_zone(exit.region)
				return

func _hovered(at: Vector2) -> void:
	hovered = &""
	hovered_region = &""
	if zone == &"":
		hovered_region = region_at(at)
	else:
		var best := NODE_PICK
		for m in placed_in(zone):
			var d := to_screen(m.world_pos).distance_to(at)
			if d < best:
				best = d
				hovered = m.id
	queue_redraw()
