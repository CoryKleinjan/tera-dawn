class_name TDWorldMapWindow
extends TDWindow
## The world map (W), in two views:
## - The **world view**: the painted map (assets/sprites/ui/world_map.png) with every region's
##   name and main city, and the major routes between regions (WorldRoutes): on foot as a row of dots,
##   ships as thin dashes. Clicking a region opens its zone view.
## - A **zone view**: one region up close, with where each exit to another region leads and a
##   back arrow to the world view, drawn one of two ways:
##   - dots: a zoomed-in part of the same painting (RegionDef.zone_rect) with every map in it
##     as a dot and the paths between them;
##   - to shape, the Hollow Knight way (RegionDef.shaped_zone): every map a room of its real
##     size where it sits in the zone (MapDef.zone_pos), with its ledges and doors, inked
##     on dark paper. Rooms show once you've been there; secret ledges, and doors behind a
##     shortcut or a fake or breakable wall, once you've found them. You're marked where you
##     stand.
## Hovering a dot, room or region tells you about it in the strip under the map. Positions on
## the painting come from MapDef.world_pos and RegionDef.label_pos/zone_rect, in world-map
## units: the painting's own pixels (WORLD). A new painting means placing every dot and region
## name on it again.

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

## A zone drawn to shape: dark paper; each room filled with its region's colour darkened by
## ROOM_SHADE (ROOM_SHADE_LIT hovered), edged lightened by ROOM_EDGE_TINT, its land lightened
## by ROOM_LAND_TINT.
const PAPER := Color("1a120b")
const ROOM_SHADE := 0.72
const ROOM_SHADE_LIT := 0.56
const ROOM_EDGE_TINT := 0.45
const ROOM_LAND_TINT := 0.15
## How far in from the map area the rooms keep (room for the exit labels at the sides).
const SHAPE_MARGIN := Vector2(70, 34)
## Room names: their size, and the smallest they shrink to before they're left to the strip.
const ROOM_LABEL := 11
const ROOM_LABEL_MIN := 8
## A door between rooms: the gap it makes in their edges and how far a way into a room you
## haven't found yet reaches out (screen pixels); how far a door keeps from a corner (game
## pixels); how far an exit's arrow reaches out of its room (screen pixels).
const DOOR_GAP := 7.0
const DOOR_STUB := 6.0
const DOOR_CORNER := 40.0
const EXIT_REACH := 22.0
## An exit's label drawn to shape: how far it lifts above its arrow when the map's edge leaves
## no room past the tip, and the dark plate it sits on over the rooms.
const EXIT_LABEL_LIFT := 14.0
const EXIT_PLATE := Color(0.1, 0.07, 0.04, 0.85)
## The you-are-here ring in a room: smaller than on the painting.
const HERE_IN_ROOM := 7.0

## Game pixels on the shown zone's map -> screen pixels (see `_shape_fit`), worked out once
## per zone.
var _fit := Transform2D()
var _fit_zone: StringName = &""

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

## Whether the zone on show is drawn to shape (RegionDef.shaped_zone).
func shaped() -> bool:
	var r: RegionDef = Content.regions.get(zone)
	return r != null and r.shaped_zone

## Where map `m` shows in the zone view: the middle of its room in a zone drawn to shape,
## else its dot on the painting.
func spot(m: MapDef) -> Vector2:
	return room_rect(m).get_center() if shaped() else to_screen(m.world_pos)

## Whether the zone view shows `m`: every dot (one not found yet as "???"), but only the
## rooms you've been to.
func shows(m: MapDef) -> bool:
	return not shaped() or known(m)

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
	if shaped():
		draw_rect(a, PAPER)
		_draw_shaped_zone()
		return
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

func _draw_here(c: Vector2, ring := 12.0) -> void:
	var pulse := ring + sin(Engine.get_physics_frames() * 0.12) * ring * 0.2
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
	_draw_zone_frame(r, h)

## The back arrow, and the strip under the map: the hovered map, else the one you're on, else
## the zone's city.
func _draw_zone_frame(r: RegionDef, here: MapDef) -> void:
	icon_button(back_rect(), "creator/arrow_left", func() -> void: open_zone(&""))
	var on := here != null and here.region == zone
	_draw_info(Content.maps.get(hovered if hovered != &"" else here.id if on else r.capital))

func back_rect() -> Rect2:
	return Rect2(_area().position + Vector2(6, 6), BACK_SIZE)

## The zone's ways out to other regions, each {"map": the map it leaves from, "region": where
## it leads, "by", "from"/"to": the road on screen (cut at the view's edge), "label",
## "label_at"}. Walking exits come from the portals; trips from the zone's travel NPCs. In a
## zone drawn to shape a walking exit leaves its room through the edge by its portal.
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
				legs.append([inside, outside.world_pos, outside.id])
		else:
			var mine: RegionDef = Content.regions[zone]
			legs.append([Content.maps.get(mine.capital), capital_pos(other), &""])
		for leg in legs:
			var inside: MapDef = leg[0]
			if inside == null:
				continue
			var from := to_screen(inside.world_pos)
			var to := clip_to(from, to_screen(leg[1]), a)
			if shaped():
				var road := _shaped_exit(inside, leg[2], leg[1])
				from = road[0]
				to = clip_to(from, road[1], a)
			var dir := (to - from).normalized()
			var label := "To " + other.display_name + ("" if route.by == "Walk" else " (%s)" % route.by)
			var w := DrawUtil.text_width(Game.ui_font, label, 11)
			var at := to - dir * 14.0 + Vector2(0, 4)
			if shaped():
				# past the arrow's tip, or above the arrow when the map's edge leaves no room there
				at = to + Vector2(dir.x * (w / 2.0 + 4.0), dir.y * 12.0 + 4.0)
				if absf(clampf(at.x, a.position.x + w / 2.0 + 4, a.end.x - w / 2.0 - 4) - at.x) > 1.0:
					at.y -= EXIT_LABEL_LIFT
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
	for id in (doors_out(m) if shaped() else WorldRoutes.linked(m.id)):
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
	elif shaped():
		for m in placed_in(zone):
			if shows(m) and room_rect(m).grow(2.0).has_point(at):
				hovered = m.id
	else:
		var best := NODE_PICK
		for m in placed_in(zone):
			var d := to_screen(m.world_pos).distance_to(at)
			if d < best:
				best = d
				hovered = m.id
	queue_redraw()

# ---------- zone view drawn to shape ----------

## The area a zone's rooms cover on its zone map (game pixels, MapDef.zone_pos): every room,
## found or not, so the view never shifts as you explore.
static func zone_bounds(region: StringName) -> Rect2:
	var out := Rect2()
	var first := true
	for m in placed_in(region):
		out = m.zone_rect() if first else out.merge(m.zone_rect())
		first = false
	return out

## Game pixels on the shown zone's map -> screen pixels: its rooms fit inside the map area,
## less SHAPE_MARGIN, in the middle.
func _shape_fit() -> Transform2D:
	if _fit_zone == zone:
		return _fit
	var bounds := zone_bounds(zone)
	var room := _area().grow_individual(-SHAPE_MARGIN.x, -SHAPE_MARGIN.y, -SHAPE_MARGIN.x, -SHAPE_MARGIN.y)
	var k := 1.0
	if bounds.has_area():
		k = minf(room.size.x / bounds.size.x, room.size.y / bounds.size.y)
	_fit = Transform2D(0.0, Vector2(k, k), 0.0, room.get_center() - bounds.get_center() * k)
	_fit_zone = zone
	return _fit

## Where a point on the zone map (game pixels) shows on screen.
func zone_to_screen(p: Vector2) -> Vector2:
	return _shape_fit() * p

## Where point `at` of map `m` (game pixels in it) shows on screen.
func _in_room(m: MapDef, at: Vector2) -> Vector2:
	return _shape_fit() * (m.zone_pos + at)

## The screen area map `m`'s room covers.
func room_rect(m: MapDef) -> Rect2:
	var fit := _shape_fit()
	return Rect2(fit * m.zone_pos, m.zone_rect().size * fit.get_scale())

## Whether the zone map shows platform `i` (from 1) of `m`: every ledge but a secret one you
## haven't stood on yet.
static func ledge_shown(m: MapDef, i: int) -> bool:
	return not m.platforms[i - 1].secret or Game.me == null or Game.me.found_secret(m.ledge_secret(i))

## Where a door of room `m`, standing at `at` (game pixels in `m`), meets the edge it shares
## with the room it leads to, `to`, on the zone map, and which way it leads out of `m`, as
## [point, direction]; empty when the two rooms don't touch.
static func door_edge(m: MapDef, to: MapDef, at: Vector2) -> Array:
	var a := m.zone_rect()
	var b := to.zone_rect()
	var p := m.zone_pos + at
	var right := is_equal_approx(a.end.x, b.position.x)
	if right or is_equal_approx(b.end.x, a.position.x):
		var lo := maxf(a.position.y, b.position.y)
		var hi := minf(a.end.y, b.end.y)
		if hi > lo:
			return [Vector2(a.end.x if right else a.position.x, _along(p.y, lo, hi)), Vector2.RIGHT if right else Vector2.LEFT]
	var down := is_equal_approx(a.end.y, b.position.y)
	if down or is_equal_approx(b.end.y, a.position.y):
		var lo := maxf(a.position.x, b.position.x)
		var hi := minf(a.end.x, b.end.x)
		if hi > lo:
			return [Vector2(_along(p.x, lo, hi), a.end.y if down else a.position.y), Vector2.DOWN if down else Vector2.UP]
	return []

## `v` kept on the shared stretch of edge `lo`..`hi`, off its corners where there's room.
static func _along(v: float, lo: float, hi: float) -> float:
	var keep := minf(DOOR_CORNER, (hi - lo) / 2.0)
	return clampf(v, lo + keep, hi - keep)

## Whether the zone view draws portal `p` of room `m` as a door into room `to`: a way you can
## use (not a shortcut, or a way behind a wall, you haven't found yet) between two rooms of the
## zone that touch. A boss arena's way home isn't a door.
func _door_shown(m: MapDef, p: PortalDef, to: MapDef) -> bool:
	if to == m or to.region != zone or to.world_pos == Vector2.ZERO or p.one_way or p.after_boss:
		return false
	if Game.me and not p.open_to(Game.me):
		return false
	return not door_edge(m, to, Vector2(p.x, m.surface_y(p.platform))).is_empty()

## The doors the zone view draws, each [room, point on screen, direction out of the room,
## whether the room beyond is shown], from every room you've been to (see `_door_shown`).
func room_doors() -> Array:
	var out := []
	for m in placed_in(zone):
		if not shows(m):
			continue
		for p in m.portals:
			var to: MapDef = Content.maps.get(p.target_map)
			if to and _door_shown(m, p, to):
				var edge := door_edge(m, to, Vector2(p.x, m.surface_y(p.platform)))
				out.append([m, zone_to_screen(edge[0]), edge[1], shows(to)])
	return out

## The maps the zone view shows a door from `m` into.
func doors_out(m: MapDef) -> Array[StringName]:
	var out: Array[StringName] = []
	for p in m.portals:
		var to: MapDef = Content.maps.get(p.target_map)
		if to and not to.id in out and _door_shown(m, p, to):
			out.append(to.id)
	return out

func _draw_shaped_zone() -> void:
	var r: RegionDef = Content.regions[zone]
	var rooms := placed_in(zone).filter(shows)
	var fill := r.color.darkened(ROOM_SHADE)
	var lit := r.color.darkened(ROOM_SHADE_LIT)
	var edge := r.color.lightened(ROOM_EDGE_TINT)
	for m: MapDef in rooms:
		draw_rect(room_rect(m), lit if m.id == hovered else fill)
	for m: MapDef in rooms:
		_draw_room_land(m, r.color.lightened(ROOM_LAND_TINT))
	for m: MapDef in rooms:
		draw_rect(room_rect(m), edge, false, 1.5)
	for door in room_doors():
		var at: Vector2 = door[1]
		var out: Vector2 = door[2]
		var along := Vector2(absf(out.y), absf(out.x)) * DOOR_GAP / 2.0
		draw_line(at - along, at + along, lit if door[0].id == hovered else fill, 3.0)
		if not door[3]:
			draw_line(at, at + out * DOOR_STUB, edge, 1.5)  # a way on into a room not found yet
	for exit in zone_exits():
		_draw_route(exit.from, exit.to, exit.by, exit.map == hovered)
	for m: MapDef in rooms:
		_draw_room_name(m)
	for exit in zone_exits():
		var w := DrawUtil.text_width(Game.ui_font, exit.label, 11)
		draw_rect(Rect2(exit.label_at - Vector2(w / 2.0 + 4.0, 13), Vector2(w + 8.0, 18)), EXIT_PLATE)
		DrawUtil.text(self, Game.ui_font, exit.label_at, exit.label, 11, TRIP, 0, 4, Palette.NIGHT)
	var here: MapDef = Content.maps.get(_here())
	if here and here.region == zone:
		_draw_here(_here_spot(here), HERE_IN_ROOM)
	_draw_zone_frame(r, here)

## A room's land: its floor, its ledges (raised land filled down to what it stands on; secret
## ones once found).
func _draw_room_land(m: MapDef, land: Color) -> void:
	var k := _shape_fit().get_scale()
	var floor_at := _in_room(m, Vector2(0, m.ground_y))
	draw_rect(Rect2(floor_at, Vector2(m.width, m.height - m.ground_y) * k), Color(land, 0.45))
	draw_line(floor_at, floor_at + Vector2(m.width * k.x, 0), land, 1.5)
	for i in range(1, m.platforms.size() + 1):
		if not ledge_shown(m, i):
			continue
		var d := m.platforms[i - 1]
		var left := _in_room(m, Vector2(d.x, d.y))
		if d.solid:
			var below := m.surface_y(m.land_under(i))
			draw_rect(Rect2(left, Vector2(d.width, below - d.y) * k), Color(land, 0.3))
		draw_line(left, left + Vector2(d.width * k.x, 0), land, 1.5)

## A room's name in its middle, when it fits there (the strip under the map names any room).
func _draw_room_name(m: MapDef) -> void:
	var box := room_rect(m)
	var size := DrawUtil.fit_size(Game.ui_font, m.display_name, ROOM_LABEL, box.size.x - 4.0, ROOM_LABEL_MIN)
	if DrawUtil.text_width(Game.ui_font, m.display_name, size) > box.size.x - 2.0 or box.size.y < size + 4:
		return
	var col := Palette.SUN if m.id == hovered else Color("fff4dc")
	var c := box.get_center()
	DrawUtil.text(self, Game.ui_font, Vector2(c.x, DrawUtil.cap_baseline(c.y, size)), m.display_name, size, col, 0, 3, Palette.NIGHT)

## Where you are in a zone drawn to shape: where you stand in your room, or (inside a
## building) at its door in the town.
func _here_spot(here: MapDef) -> Vector2:
	var world := hud.world if hud else null
	if world and world.map and world.player:
		if world.map.id == here.id:
			return _in_room(here, world.player.position)
		for p in here.portals:
			if p.target_map == world.map.id:
				return _in_room(here, Vector2(p.x, here.surface_y(p.platform)))
	return room_rect(here).get_center()

## The road out of the zone from room `inside`, drawn to shape, as [from, to] on screen: out
## through the edge nearest its portal to `outside` (a map of the other region), EXIT_REACH
## long; for a trip (no `outside`), from the room's middle towards `far` (where the other
## region's city is on the painting).
func _shaped_exit(inside: MapDef, outside: StringName, far: Vector2) -> Array:
	var box := room_rect(inside)
	for p in inside.portals:
		if p.target_map != outside:
			continue
		var at := _in_room(inside, Vector2(p.x, inside.surface_y(p.platform)))
		var gaps := {Vector2.LEFT: at.x - box.position.x, Vector2.RIGHT: box.end.x - at.x, Vector2.UP: at.y - box.position.y, Vector2.DOWN: box.end.y - at.y}
		var out := Vector2.LEFT
		for dir: Vector2 in gaps:
			if gaps[dir] < gaps[out]:
				out = dir
		var from: Vector2 = at + out * float(gaps[out])
		return [from, from + out * EXIT_REACH]
	var c := box.get_center()
	var mine: RegionDef = Content.regions[zone]
	return [c, c + (far - capital_pos(mine)).normalized() * WORLD.length()]
