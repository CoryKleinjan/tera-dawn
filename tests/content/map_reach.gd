extends RefCounted
## Works out which platforms and ropes of a map the player can get to, by running
## TDPlayer's movement rules (its constants, no speed or jump bonus, no coyote time) from
## every place a player arrives: the map's start, and where each portal, ship or wagon
## leading here lands. `skills_reaching` tries the jobs' movement skills too, for secret
## ledges (PlatformDef.secret).
##
##   var reach := MapReach.new(map, arrivals)
##   reach.platform_reached(i)   # platform i (0 is the floor)

var map: MapDef
var plats: Array[Platform]
## "p<i>" for platform i, "c<i>" for climbable i -> true.
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
## rope or ladder passed close enough to grab with Up held. For a movement skill, the first
## `lock` ticks carry the player along at the speed they start with (no steering), and the
## first `flat` of those stay level and can't land (a Charge).
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
		if t > 1:
			for ci in map.climbables.size():
				var c: ClimbableDef = map.climbables[ci]
				if absf(pos.x - c.x) < 16 and pos.y > c.top + 1 and pos.y <= c.bottom + 2:
					out.append("c%d" % ci)
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

# ---------- movement skills ----------

## Ticks into a jump where the reach test tries a skill in the air: early, mid-rise, near
## the top and at the top (a jump tops out after about 20 ticks).
const AIR_TRIES: Array[int] = [4, 10, 16, 20]
## How far around a ledge the reach test looks for somewhere to use a skill from.
const SKILL_REACH := Vector2(520, 420)

## The movement skills (SkillDef.move) that carry the player onto platform `target` in one
## go, at level 1, from somewhere this reach already gets to: straight from standing on a
## platform (a Charge, Rolling Dash, Backstep Leap or Blink) or in the air during a jump,
## standing or running (any of them but the roll). Returns their ids.
func skills_reaching(target: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for s: SkillDef in Content.skills.values():
		if s.move and _skill_reaches(s.move, target):
			out.append(s.id)
	return out

func _skill_reaches(move: MoveDef, target: int) -> bool:
	var goal := plats[target]
	var landed := "p%d" % target
	for pi in plats.size():
		var pl := plats[pi]
		if pi == target or not platform_reached(pi):
			continue
		if pl.x > goal.x + goal.w + SKILL_REACH.x or pl.x + pl.w < goal.x - SKILL_REACH.x:
			continue
		if pl.y < goal.y - SKILL_REACH.y or pl.y > goal.y + SKILL_REACH.y:
			continue
		var x := pl.x + 2.0
		while x <= pl.x + pl.w - 1.0:
			var from := Vector2(clampf(x, TDPlayer.EDGE, map.width - TDPlayer.EDGE), pl.y)
			for dir in [-1, 1]:
				if landed in _ground_move(move, from, dir, pl):
					return true
				for run in [0, dir]:
					for k in AIR_TRIES:
						if landed in _air_move(move, from, dir, run, k):
							return true
			x += 20.0
	return false

## Where `move` used standing at `from` on `pl`, facing (or for a Backstep Leap, springing)
## the way `dir` points, lands.
func _ground_move(move: MoveDef, from: Vector2, dir: int, pl: Platform) -> Array:
	var speed := move.distance_at(1) / maxf(1.0, move.ticks)
	match move.style:
		MoveDef.Style.CHARGE:
			return _sim(from, Vector2(dir * speed, 0), dir, -1, move.ticks, move.ticks)
		MoveDef.Style.BACKSTEP:
			return _sim(from, Vector2(dir * speed, TDPlayer.BACKSTEP_LIFT), dir, -1, move.ticks)
		MoveDef.Style.BLINK:
			return _blink(move, from, dir)
		MoveDef.Style.ROLL:
			# rolled off the end of the platform with some of the roll left
			var out := []
			var edge := Vector2(pl.x + pl.w + 1.0 if dir > 0 else pl.x - 1.0, pl.y)
			for left in range(move.ticks, 0, -4):
				out.append_array(_sim(edge, Vector2(dir * speed, 0), dir, -1, left))
			return out
	return []

## Where `move` used `k` ticks into a jump from `from` lands: the jump standing (`run` 0) or
## running `run`, the move facing (or springing) the way `dir` points.
func _air_move(move: MoveDef, from: Vector2, dir: int, run: int, k: int) -> Array:
	if not move.in_air:
		return []
	var pos := from
	var vel := Vector2(run * TDPlayer.RUN_SPEED, TDPlayer.JUMP_SPEED)
	for t in k:
		if run != 0:
			vel.x = clampf(vel.x + run * TDPlayer.ACCEL_AIR, -TDPlayer.RUN_SPEED, TDPlayer.RUN_SPEED)
		vel.y = minf(vel.y + TDPlayer.gravity(vel.y), TDPlayer.MAX_FALL)
		pos.x = clampf(pos.x + vel.x, TDPlayer.EDGE, map.width - TDPlayer.EDGE)
		pos.y += vel.y
	var speed := move.distance_at(1) / maxf(1.0, move.ticks)
	match move.style:
		MoveDef.Style.CHARGE:
			return _sim(pos, Vector2(dir * speed, 0), dir, -1, move.ticks, move.ticks)
		MoveDef.Style.AIR_JUMP:
			return _sim(pos, Vector2(dir * speed, TDPlayer.AIR_JUMP_SPEED), dir, -1, move.ticks)
		MoveDef.Style.BACKSTEP:
			return _sim(pos, Vector2(dir * speed, TDPlayer.BACKSTEP_LIFT), dir, -1, move.ticks)
		MoveDef.Style.BLINK:
			return _blink(move, pos, dir)
	return []

## Where a Blink from `from` lands: ahead the way `dir` points, or straight up or down,
## then falling, steering either way or not at all.
func _blink(move: MoveDef, from: Vector2, dir: int) -> Array:
	var out := []
	for aim in [Hitbox.Aim.AHEAD, Hitbox.Aim.UP, Hitbox.Aim.DOWN]:
		var to := move.blink_to(from, dir, aim, 1, float(map.width), float(map.ground_y))
		for steer in [-1, 0, 1]:
			out.append_array(_sim(to, Vector2.ZERO, steer, -1))
	return out
