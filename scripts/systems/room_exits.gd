class_name RoomExits
## Ways between rooms, the Hollow Knight way. In a zone drawn to shape (RegionDef.shaped_zone)
## a field's portals are openings in the room rather than portals you press Up at: walk or
## jump off the room's side where one is and you come out at the matching side of the next
## room, still moving; jump up at a top one, or Down + Jump at a bottom one to drop into the
## room below. Building doors, docks, quest portals and a boss arena's way home stay portals
## (Up). The client and the server both ask MapLayout, which works each portal's side out
## once with these rules, so they agree on where the ways are.

enum Side { NONE, LEFT, RIGHT, TOP, BOTTOM }

## How far from a side edge a portal may stand and still be the way out through it, when its
## two maps don't touch on a zone map (a town, or a path into the next zone).
const SIDE_REACH := 300.0
## How high a side way's opening reaches above the ledge it leaves from (game pixels): feet
## anywhere from the ledge up to this go through, so jumping through counts too.
const OPENING := 220.0
## How far short of the edge a side way's ledge may stop, and how far under it the feet may
## have dropped walking off that end and still go through (game pixels).
const LEDGE_SHORT := 40.0
const DROP_SLACK := 24.0
## How close to a side edge the feet must be to go through a way there (game pixels): the
## hero stops a little short of the edge (TDPlayer.EDGE).
const EDGE_SLACK := 30.0
## How far either side of a top or bottom way's spot it takes you (game pixels).
const SPOT := 40.0
## How far a jump at a top way must carry the feet above its ledge before it takes you.
const RISE := 40.0
## How far a drop at a bottom way falls below its ledge before it takes you.
const SINK := 40.0
## How far in from the edge someone coming through a side way arrives (game pixels).
const ARRIVE_IN := 60.0
## How far above its ledge someone dropping in through a top way appears, falling.
const DROP_IN := 140.0

## Which side of room `m` portal `p` leads out through, or NONE for a portal you press Up at.
static func side_of(m: MapDef, p: PortalDef) -> RoomExits.Side:
	if p.door or p.opens_after or p.while_on or (p.one_way and p.after_boss) or m.interior:
		return Side.NONE
	var r: RegionDef = Content.regions.get(m.region)
	var to: MapDef = Content.maps.get(p.target_map)
	if r == null or not r.shaped_zone or to == null or to.interior or _dock(m) or _dock(to):
		return Side.NONE
	if to.region == m.region and not m.town and not to.town:
		var s := touching(m, to)
		if s != Side.NONE:
			return s
	# a town, or a path into the next zone: the side it stands by
	if p.x <= SIDE_REACH:
		return Side.LEFT
	if p.x >= m.width - SIDE_REACH:
		return Side.RIGHT
	return Side.NONE

## The side of room `m` that room `to` touches on their zone map, or NONE.
static func touching(m: MapDef, to: MapDef) -> RoomExits.Side:
	var a := m.zone_rect()
	var b := to.zone_rect()
	if is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x):
		if minf(a.end.y, b.end.y) > maxf(a.position.y, b.position.y):
			return Side.RIGHT if is_equal_approx(a.end.x, b.position.x) else Side.LEFT
	if is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y):
		if minf(a.end.x, b.end.x) > maxf(a.position.x, b.position.x):
			return Side.BOTTOM if is_equal_approx(a.end.y, b.position.y) else Side.TOP
	return Side.NONE

## A dock map belongs to its town (MapDef.return_map) and keeps its portals.
static func _dock(m: MapDef) -> bool:
	return m.town and m.return_map != &""

## The way back from the room portal `p` of map `m` leads to: the portal there leading to `m`
## through the facing side, or null (a one-way way, or a plain portal at the far end).
static func way_back(m: MapDef, p: PortalDef) -> PortalDef:
	var to: MapDef = Content.maps.get(p.target_map)
	if to == null:
		return null
	var want := facing(side_of(m, p))
	for q in to.portals:
		if q.target_map == m.id and side_of(to, q) == want:
			return q
	return null

## Where along its ledge someone coming into room `m` through its way `back` on side `arrive`
## stands: a step in from a side edge (on the ledge), or on a top or bottom way's spot.
static func arrival_x(m: MapDef, back: PortalDef, arrive: RoomExits.Side) -> float:
	var lo := 0.0
	var hi := float(m.width)
	if back.platform > 0:
		var d := m.platforms[back.platform - 1]
		lo = d.x
		hi = d.x + d.width
	match arrive:
		Side.LEFT:
			return clampf(ARRIVE_IN, lo + ARRIVE_IN / 2.0, hi)
		Side.RIGHT:
			return clampf(m.width - ARRIVE_IN, lo, hi - ARRIVE_IN / 2.0)
	return back.x

## The side you come in through after leaving through side `s`.
static func facing(s: RoomExits.Side) -> RoomExits.Side:
	match s:
		Side.LEFT:
			return Side.RIGHT
		Side.RIGHT:
			return Side.LEFT
		Side.TOP:
			return Side.BOTTOM
		Side.BOTTOM:
			return Side.TOP
	return Side.NONE
