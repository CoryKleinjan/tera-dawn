class_name MapLayout
extends RefCounted
## The walkable shape of a map: its platforms, portals and NPC spots.
## The server's MapInstance and the client's TDWorld each build one from the same MapDef,
## so both sides agree on where things are.

var map: MapDef
## Platform 0 is the solid floor; the rest are the map's one-way platforms in order.
var platforms: Array[Platform] = []
## The side of the room each portal that is a way out leads through (RoomExits), by portal;
## portals you press Up at aren't in it.
var ways := {}

func _init(def: MapDef) -> void:
	map = def
	platforms.append(Platform.floor_of(def))
	for d in def.platforms:
		platforms.append(Platform.from_def(d))
	for p in def.portals:
		var side := RoomExits.side_of(def, p)
		if side != RoomExits.Side.NONE:
			ways[p] = side

## The portal you press Up at that stands at `pos` (a way out of the room isn't one, see
## `way_at`), or null.
func portal_at(pos: Vector2) -> PortalDef:
	for p in map.portals:
		if ways.has(p):
			continue
		if absf(pos.x - p.x) < 34 and absf(pos.y - platforms[p.platform].y) < 4:
			return p
	return null

## Which side of the room portal `p` leads out through (NONE for a portal you press Up at).
func side_of(p: PortalDef) -> RoomExits.Side:
	return ways.get(p, RoomExits.Side.NONE)

## The way out through side edge `side` (LEFT or RIGHT) whose opening feet at `feet` are in:
## the one whose ledge is nearest below them, or null.
func side_way(feet: Vector2, side: RoomExits.Side) -> PortalDef:
	var best: PortalDef = null
	var best_gap := INF
	for p: PortalDef in ways:
		if ways[p] != side:
			continue
		var gap := platforms[p.platform].y - feet.y
		if gap >= -RoomExits.DROP_SLACK and gap <= RoomExits.OPENING and gap < best_gap:
			best = p
			best_gap = gap
	return best

## The top or bottom way (`side`) whose spot feet at `feet` are over, or null.
func spot_way(feet: Vector2, side: RoomExits.Side) -> PortalDef:
	for p: PortalDef in ways:
		if ways[p] == side and absf(feet.x - p.x) < RoomExits.SPOT:
			return p
	return null

## The way out of the room feet at `feet` are going through: in a side way's opening at the
## edge, or round a top or bottom way's spot (on its ledge, jumping up over it or dropping
## under it). The server checks a player's way out with it; their client says when.
func way_at(feet: Vector2) -> PortalDef:
	if feet.x <= RoomExits.EDGE_SLACK:
		return side_way(feet, RoomExits.Side.LEFT)
	if feet.x >= map.width - RoomExits.EDGE_SLACK:
		return side_way(feet, RoomExits.Side.RIGHT)
	for side in [RoomExits.Side.TOP, RoomExits.Side.BOTTOM]:
		var p := spot_way(feet, side)
		if p == null:
			continue
		var y := platforms[p.platform].y
		if feet.y >= y - RoomExits.OPENING and feet.y <= y + RoomExits.SINK + RoomExits.EDGE_SLACK:
			return p
	return null

## How far from a rest spot's bench (MapDef.rest_spots) feet may be and still rest there.
const REST_REACH := 90.0

## The rest spot (its index in MapDef.rest_spots) that feet at `feet` stand by, or -1.
func rest_at(feet: Vector2) -> int:
	for i in map.rest_spots.size():
		var r := map.rest_spots[i]
		if r.y < platforms.size() and absf(feet.x - r.x) <= REST_REACH and absf(platforms[r.y].y - feet.y) < 1.0:
			return i
	return -1

## The platform whose top is at the feet, or null when in the air.
func platform_under(feet: Vector2) -> Platform:
	for pl in platforms:
		if pl.contains_x(feet.x) and absf(pl.y - feet.y) < 1.0:
			return pl
	return null

## The top of whatever is under the feet (for a pet to walk on).
func ground_below(feet: Vector2) -> float:
	var best := float(map.ground_y)
	for pl in platforms:
		if pl.contains_x(feet.x) and pl.y >= feet.y - 1.0 and pl.y < best:
			best = pl.y
	return best
