class_name MapLayout
extends RefCounted
## The walkable shape of a map: its platforms, ropes and ladders, portals and NPC spots.
## The server's MapInstance and the client's TDWorld each build one from the same MapDef,
## so both sides agree on where things are.

var map: MapDef
## Platform 0 is the solid floor; the rest are the map's one-way platforms in order.
var platforms: Array[Platform] = []

func _init(def: MapDef) -> void:
	map = def
	platforms.append(Platform.floor_of(def))
	for d in def.platforms:
		platforms.append(Platform.from_def(d))

func climbable_near(pos: Vector2) -> ClimbableDef:
	for c in map.climbables:
		if absf(pos.x - c.x) < 16 and pos.y > c.top - 2 and pos.y <= c.bottom + 2:
			return c
	return null

func portal_at(pos: Vector2) -> PortalDef:
	for p in map.portals:
		if absf(pos.x - p.x) < 34 and absf(pos.y - platforms[p.platform].y) < 4:
			return p
	return null

## The platform whose top is at the feet, or null when in the air.
func platform_under(feet: Vector2) -> Platform:
	for pl in platforms:
		if pl.contains_x(feet.x) and absf(pl.y - feet.y) < 1.0:
			return pl
	return null

## The top of whatever is under the feet (for shadows).
func ground_below(feet: Vector2) -> float:
	var best := float(map.ground_y)
	for pl in platforms:
		if pl.contains_x(feet.x) and pl.y >= feet.y - 1.0 and pl.y < best:
			best = pl.y
	return best
