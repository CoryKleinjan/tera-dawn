extends RefCounted
## Works out which platforms and ropes of a map the player can get to, by running
## TDPlayer's movement rules (its constants, no speed or jump bonus, no coyote time) from
## every place a player arrives: the map's start, and where each portal, ship or wagon
## leading here lands.
##
##   var reach := MapReach.new(map, arrivals)
##   reach.platform_reached(i)   # platform i (0 is the floor)

var map: MapDef
var plats: Array[Platform]
## "p<i>" for platform i, "c<i>" for climbable i -> true.
var seen := {}

func _init(m: MapDef, arrivals: Array) -> void:
	map = m
	plats = MapLayout.new(m).platforms
	var queue := []
	for x in arrivals:
		for n in _sim(Vector2(x, m.ground_y - 1), Vector2.ZERO, 0, -1):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	while not queue.is_empty():
		for n in _edges(queue.pop_front()):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)

## Every x where a player arrives on `m`: its start, portals leading here and travel routes.
static func arrivals_of(m: MapDef) -> Array:
	var out := [m.start_x]
	for other: MapDef in Content.maps.values():
		for po in other.portals:
			if po.target_map == m.id:
				out.append(po.target_x)
	for npc: NpcDef in Content.npcs.values():
		for r in npc.travel:
			if r.target_map == m.id:
				out.append(r.target_x)
	return out

func platform_reached(i: int) -> bool:
	return seen.has("p%d" % i)

func climbable_reached(i: int) -> bool:
	return seen.has("c%d" % i)

## Nodes reachable in one move from node n.
func _edges(n: String) -> Array:
	var out := []
	var i := int(n.substr(1))
	if n[0] == "p":
		var pl := plats[i]
		var xs := []
		var x := pl.x + 2.0
		while x <= pl.x + pl.w - 2.0:
			xs.append(x)
			x += 10.0
		xs.append(pl.x + pl.w - 1.0)
		for sx in xs:
			sx = clampf(sx, TDPlayer.EDGE, map.width - TDPlayer.EDGE)
			for dir in [-1, 0, 1]:
				# a jump standing still, or running and holding a direction
				out.append_array(_sim(Vector2(sx, pl.y), Vector2(dir * TDPlayer.RUN_SPEED, TDPlayer.JUMP_SPEED), dir, -1))
			if not pl.solid:
				out.append_array(_sim(Vector2(sx, pl.y), Vector2(0, 1), 0, i)) # down + jump
		# walk off each end
		for e in [[pl.x - 1.0, -1], [pl.x + pl.w + 1.0, 1]]:
			if e[0] > TDPlayer.EDGE and e[0] < map.width - TDPlayer.EDGE:
				out.append_array(_sim(Vector2(e[0], pl.y), Vector2(e[1] * TDPlayer.RUN_SPEED, 0), e[1], -1))
		# up or down onto a rope or ladder from here
		for ci in map.climbables.size():
			var c: ClimbableDef = map.climbables[ci]
			if absf(c.x - clampf(c.x, pl.x, pl.x + pl.w)) < 16 and pl.y > c.top - 2 and pl.y <= c.bottom + 2:
				out.append("c%d" % ci)
	else:
		var c: ClimbableDef = map.climbables[i]
		# off the top and the bottom
		for y in [c.top, c.bottom]:
			var stood := false
			for pi in plats.size():
				if plats[pi].contains_x(c.x) and absf(plats[pi].y - y) < 1.0:
					out.append("p%d" % pi)
					stood = true
			if not stood:
				out.append_array(_sim(Vector2(c.x, y), Vector2.ZERO, 0, -1))
		# jump off sideways at any height
		var y := c.top + 4.0
		while y < c.bottom:
			for dir in [-1, 1]:
				out.append_array(_sim(Vector2(c.x, y), Vector2(3.0 * dir, -5.5), dir, -1))
			y += 10.0
	return out

## Runs TDPlayer's air physics until landing. Returns the platform landed on, plus every
## rope or ladder passed close enough to grab with Up held.
func _sim(pos: Vector2, vel: Vector2, dir: int, drop_from: int) -> Array:
	var out := []
	var drop_t := TDPlayer.DROP_TICKS if drop_from >= 0 else 0
	for t in 400:
		if dir != 0:
			vel.x = clampf(vel.x + dir * TDPlayer.ACCEL_AIR, -TDPlayer.RUN_SPEED, TDPlayer.RUN_SPEED)
		else:
			vel.x *= TDPlayer.FRICTION_AIR
		vel.y = minf(vel.y + TDPlayer.gravity(vel.y), TDPlayer.MAX_FALL)
		var prev_y := pos.y
		pos.x = clampf(pos.x + vel.x, TDPlayer.EDGE, map.width - TDPlayer.EDGE)
		pos.y += vel.y
		if drop_t > 0:
			drop_t -= 1
		if t > 1:
			for ci in map.climbables.size():
				var c: ClimbableDef = map.climbables[ci]
				if absf(pos.x - c.x) < 16 and pos.y > c.top + 1 and pos.y <= c.bottom + 2:
					out.append("c%d" % ci)
		if vel.y >= 0:
			for pi in plats.size():
				if pi == drop_from and drop_t > 0:
					continue
				var pl := plats[pi]
				if pl.contains_x(pos.x) and prev_y <= pl.y and pos.y >= pl.y:
					out.append("p%d" % pi)
					return out
		if pos.y > map.height:
			out.append("p0")
			return out
	return out
