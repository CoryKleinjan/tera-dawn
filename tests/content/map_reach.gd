extends RefCounted
## Works out which platforms of a map the player can get to, by running
## TDPlayer's movement rules (its constants, no speed or jump bonus, no coyote time) from
## every place a player arrives: the map's start, and where each portal, ship or wagon
## leading here lands. `moves_reaching` tries the moves boss relics unlock too, for secret
## ledges (PlatformDef.secret).
##
##   var reach := MapReach.new(map, arrivals)
##   reach.platform_reached(i)   # platform i (0 is the floor)

var map: MapDef
var plats: Array[Platform]
## "p<i>" for platform i -> true.
var seen := {}

## `arrivals` are where players arrive (feet positions, see arrivals_of).
func _init(m: MapDef, arrivals: Array) -> void:
	map = m
	plats = MapLayout.new(m).platforms
	var queue := []
	for at: Vector2 in arrivals:
		for n in _sim(at + Vector2(0, -1), Vector2.ZERO, 0, -1):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	while not queue.is_empty():
		for n in _edges(queue.pop_front()):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)

## Every place a player arrives on `m` (their feet): its start on the floor, where portals
## leading here land (on their target platform) and where travel routes land.
static func arrivals_of(m: MapDef) -> Array:
	var layout := MapLayout.new(m)
	var out := [Vector2(m.start_x, m.ground_y)]
	for other: MapDef in Content.maps.values():
		for po in other.portals:
			if po.target_map == m.id:
				var on := po.target_platform if po.target_platform >= 0 and po.target_platform < layout.platforms.size() else 0
				out.append(Vector2(po.target_x, layout.platforms[on].y))
	for npc: NpcDef in Content.npcs.values():
		for r in npc.travel:
			if r.target_map == m.id:
				out.append(Vector2(r.target_x, m.ground_y))
	return out

func platform_reached(i: int) -> bool:
	return seen.has("p%d" % i)

## Nodes reachable in one move from node n.
func _edges(n: String) -> Array:
	var out := []
	var i := int(n.substr(1))
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
	return out

## Runs TDPlayer's air physics until landing. Returns the platform landed on. For a relic's
## move, the first `lock` ticks carry the player along at the speed they start with (no
## steering), and the first `flat` of those stay level and can't land (a Dash or Surge).
func _sim(pos: Vector2, vel: Vector2, dir: int, drop_from: int, lock := 0, flat := 0) -> Array:
	var out := []
	var drop_t := TDPlayer.DROP_TICKS if drop_from >= 0 else 0
	for t in 400:
		if t < lock:
			pass # carried along by the skill
		elif dir != 0:
			vel.x = clampf(vel.x + dir * TDPlayer.ACCEL_AIR, -TDPlayer.RUN_SPEED, TDPlayer.RUN_SPEED)
		else:
			vel.x *= TDPlayer.FRICTION_AIR
		vel.y = 0.0 if t < flat else minf(vel.y + TDPlayer.gravity(vel.y), TDPlayer.MAX_FALL)
		var prev_y := pos.y
		pos.x = clampf(pos.x + vel.x, TDPlayer.EDGE, map.width - TDPlayer.EDGE)
		pos.y += vel.y
		if drop_t > 0:
			drop_t -= 1
		if vel.y >= 0 and t >= flat:
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

# ---------- moves from boss relics ----------

## Ticks into a jump where the reach test tries a move in the air: early, mid-rise, near
## the top and at the top (a jump tops out after about 20 ticks).
const AIR_TRIES: Array[int] = [4, 10, 16, 20]
## How far around a ledge the reach test looks for somewhere to use a move from.
const MOVE_REACH := Vector2(720, 420)
## The relic moves (RelicDef.Move) that can carry the player across or up to a ledge.
const MOVES: Array[String] = ["Dash", "Double Jump", "Surge"]

## The relic moves that carry the player onto platform `target` in one go, from somewhere
## this reach already gets to: a Dash or Surge straight from standing on a platform, or in
## the air during a jump, standing or running, a Dash or a double jump. Returns their names.
func moves_reaching(target: int) -> Array[String]:
	var out: Array[String] = []
	for move in MOVES:
		if _move_reaches(move, target):
			out.append(move)
	return out

func _move_reaches(move: String, target: int) -> bool:
	var goal := plats[target]
	var landed := "p%d" % target
	for pi in plats.size():
		var pl := plats[pi]
		if pi == target or not platform_reached(pi):
			continue
		if pl.x > goal.x + goal.w + MOVE_REACH.x or pl.x + pl.w < goal.x - MOVE_REACH.x:
			continue
		if pl.y < goal.y - MOVE_REACH.y or pl.y > goal.y + MOVE_REACH.y:
			continue
		var x := pl.x + 2.0
		while x <= pl.x + pl.w - 1.0:
			var from := Vector2(clampf(x, TDPlayer.EDGE, map.width - TDPlayer.EDGE), pl.y)
			for dir in [-1, 1]:
				if landed in _ground_move(move, from, dir):
					return true
				for run in [0, dir]:
					for k in AIR_TRIES:
						if landed in _air_move(move, from, dir, run, k):
							return true
			x += 20.0
	return false

## Where `move` used standing at `from`, facing the way `dir` points, lands.
func _ground_move(move: String, from: Vector2, dir: int) -> Array:
	match move:
		"Dash":
			return _sim(from, Vector2(dir * TDPlayer.DASH_SPEED, 0), dir, -1, TDPlayer.DASH_TICKS, TDPlayer.DASH_TICKS)
		"Surge":
			return _sim(from, Vector2(dir * TDPlayer.SURGE_SPEED, 0), dir, -1, TDPlayer.SURGE_TICKS, TDPlayer.SURGE_TICKS)
	return []

## Where `move` used `k` ticks into a jump from `from` lands: the jump standing (`run` 0) or
## running `run`, the move facing (or a double jump steering) the way `dir` points.
func _air_move(move: String, from: Vector2, dir: int, run: int, k: int) -> Array:
	if move == "Surge":
		return []
	var pos := from
	var vel := Vector2(run * TDPlayer.RUN_SPEED, TDPlayer.JUMP_SPEED)
	for t in k:
		if run != 0:
			vel.x = clampf(vel.x + run * TDPlayer.ACCEL_AIR, -TDPlayer.RUN_SPEED, TDPlayer.RUN_SPEED)
		vel.y = minf(vel.y + TDPlayer.gravity(vel.y), TDPlayer.MAX_FALL)
		pos.x = clampf(pos.x + vel.x, TDPlayer.EDGE, map.width - TDPlayer.EDGE)
		pos.y += vel.y
	if move == "Dash":
		return _sim(pos, Vector2(dir * TDPlayer.DASH_SPEED, 0), dir, -1, TDPlayer.DASH_TICKS, TDPlayer.DASH_TICKS)
	return _sim(pos, Vector2(vel.x, TDPlayer.JUMP_SPEED * TDPlayer.DOUBLE_JUMP_SHARE), dir, -1)
