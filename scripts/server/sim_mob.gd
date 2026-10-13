class_name SimMob
extends RefCounted
## A monster as the server runs it: it patrols its platform (or the stretch of it its
## SpawnDef allows), targets a player who comes in sight or hits it, chases them while
## they're level with it and attacks with its moves (MobMoves), hurts players it touches,
## and comes back some time after it is defeated. Flying monsters do the same in the air.
## Depending on its MonsterDef it may hop, stand still, or split into smaller monsters
## (those wait asleep until their parent is defeated). Bosses target whoever has hurt
## them most lately, leap to the player's platform, and get a second wind at half HP.
## Clients only see it through snapshots (see TDMob, the client-side view).

## Ticks the HP bar stays up after a hit.
const SHOW_HP_TICKS := 240
## Ticks a defeated monster takes to fade out (clients fade their view over the same time).
const DEATH_FADE_TICKS := 40
## Ticks it stays angry at whoever hit it (or woke it), and at a player it can see.
const AGGRO_TICKS := 600
const SIGHT_TICKS := 240
## It sees players at most this far above or below it (ground monsters, fliers).
const SIGHT_Y := 110.0
const FLYING_SIGHT_Y := 220.0
## Ticks it flinches after a hit, how hard it's knocked back, and how fast that slows (per tick).
const HURT_TICKS := 14
const KNOCKBACK := 3.2
const KNOCKBACK_DECAY := 0.82
## Speed while chasing, as a multiple of its walking speed.
const CHASE_SPEED := 1.3
## Ticks between changes of direction while patrolling (first walk, then later ones).
const FIRST_WALK_TICKS := Vector2i(60, 200)
const WALK_TICKS := Vector2i(60, 220)
## Chance a patrol turn stands still instead of walking.
const IDLE_CHANCE := 0.3
## Hopping monsters: pull of gravity per tick, chance to hop each tick, and the upward
## speed of a split-off monster popping out of its parent.
const HOP_GRAVITY := 0.35
const HOP_CHANCE := 1.0 / 80.0
const WAKE_HOP := 5.0
## How far around a player's hurtbox a landing shot still hits.
const SHOT_GROW := 14
## Bosses: how fast the damage they remember fades (per tick), how far ahead they cut a
## player off, how long they wait before leaping to the player's platform, and how much
## faster they move after their second wind (at half HP).
const THREAT_DECAY := 0.997
const LEAD_TICKS := 20.0
const LEAP_WAIT := 45
const RAGE_SPEED := 1.2

var map: MapInstance
var index := 0
var def: MonsterDef
var plat: Platform
## The stretch of `plat` it walks on: all of it unless its SpawnDef sets a patrol range.
var area: Platform
var health := Health.new()
var hurtbox: Hitbox
var position := Vector2.ZERO

var dir := 1
var walk_t := 0     # ticks until the next change of direction
var kx := 0.0       # knockback speed
var hurt_t := 0
var aggro := 0      # ticks left targeting `target`
var target := 0     # peer id of the player it's after
var dead := false
var death_t := 0
var respawn := 0
var phase := 0.0
var show_hp := 0    # ticks left showing the HP bar
var hop := 0.0      # height above the platform (a hop or a move; negative dives down)
var hop_v := 0.0
## Its attacks in progress and their cooldowns.
var moves: MobMoves
## Shots in the air: [peer, ticks left, where it lands, power].
var shots := []
## The monsters this one splits into (see MapDef.roster), and the one it split off.
var children: Array[SimMob] = []
var parent: SimMob
## A split-off monster waiting for its parent to be defeated.
var asleep := false
## Bosses: damage each player (peer) has done lately, whether the second wind has come,
## and ticks spent unable to reach the target.
var threat := {}
var enraged := false
var stuck_t := 0
## How fast its target is moving (smoothed, pixels per tick), to aim ahead of them.
var target_velocity := Vector2.ZERO
var _target_last := Vector2.ZERO
var _hp_seen := 0
## Who else hit it while it was after someone, and ticks it stays angry at them.
var _hit_by := 0
var _hit_t := 0
## Where it spawned: a boss that leapt elsewhere returns here when it comes back.
var _home_plat: Platform
var _home_area: Platform

func _init(m: MapInstance, i: int, d: MonsterDef, p: Platform, patrol: Platform = null) -> void:
	map = m
	index = i
	def = d
	plat = p
	area = patrol if patrol else p
	_home_plat = plat
	_home_area = area
	hurtbox = Hitbox.new(d.size)
	moves = MobMoves.new(self)
	_reset()

func _reset() -> void:
	plat = _home_plat
	area = _home_area
	var half := def.size.x / 2.0
	health.reset(def.max_hp)
	_hp_seen = health.hp
	position = Vector2(randf_range(area.x + half, area.x + area.w - half), plat.y)
	dir = -1 if randf() < 0.5 else 1
	walk_t = randi_range(FIRST_WALK_TICKS.x, FIRST_WALK_TICKS.y)
	kx = 0.0
	hurt_t = 0
	aggro = 0
	target = 0
	dead = false
	death_t = 0
	show_hp = 0
	phase = randf() * 6.0
	hop = 0.0
	hop_v = 0.0
	shots.clear()
	asleep = false
	threat.clear()
	enraged = false
	stuck_t = 0
	target_velocity = Vector2.ZERO
	_hit_by = 0
	_hit_t = 0
	moves.reset()

## Puts a split-off monster to sleep until its parent is defeated.
func sleep() -> void:
	dead = true
	death_t = 0
	asleep = true

## Its parent was just defeated at `x`: it pops out there, angry at `by`.
func wake(x: float, by: int) -> void:
	_reset()
	var half := def.size.x / 2.0
	position.x = clampf(x, area.x + half, area.x + area.w - half)
	hop_v = WAKE_HOP
	aggro = AGGRO_TICKS
	target = by

func hurt(from_face: int, by: int) -> void:
	hurt_t = HURT_TICKS
	# in the middle of a move it isn't knocked out of it
	kx = 0.0 if moves.busy() else from_face * KNOCKBACK
	show_hp = SHOW_HP_TICKS
	threat[by] = threat.get(by, 0.0) + maxf(1.0, _hp_seen - health.hp)
	_hp_seen = health.hp
	# hitting it gets its attention, unless it's already busy with someone it can see:
	# then it turns on them once it loses that one
	var current := map.players.get(target) as SimPlayer if aggro > 0 else null
	if current == null or not sees(current) or target == by:
		if target != by:
			_track(map.players.get(by) as SimPlayer, true)
		target = by
		aggro = maxi(aggro, AGGRO_TICKS)
	else:
		_hit_by = by
		_hit_t = AGGRO_TICKS

func die() -> void:
	dead = true
	death_t = DEATH_FADE_TICKS
	respawn = randi_range(def.respawn_ticks.x, def.respawn_ticks.y)
	moves.cancel()
	hop = 0.0

## Forgets `peer` (they left the map).
func forget(peer: int) -> void:
	threat.erase(peer)
	if _hit_by == peer:
		_hit_t = 0
	if target == peer:
		target = 0
		aggro = 0

## How far above its feet a monster's body floats: flying monsters hover and bob (by
## `phase`), others don't. Clients (TDMob) use the same.
static func hover_offset(d: MonsterDef, phase_now: float) -> Vector2:
	if d.flying:
		return Vector2(0, -d.hover_height + sin(phase_now * 1.5) * 6.0)
	return Vector2.ZERO

## Feet position including the hover height of flying monsters, hops and dives.
func body_position() -> Vector2:
	if def.flying:
		return position + hover_offset(def, phase) + Vector2(0, -hop)
	return position + Vector2(0, -hop)

func step() -> void:
	phase += 0.08
	_step_shots()
	if dead:
		if death_t > 0:
			death_t -= 1
		elif parent:
			asleep = true
		elif not asleep:
			respawn -= 1
			if respawn <= 0:
				_reset()
		return
	if show_hp > 0:
		show_hp -= 1
	if def.boss and not enraged and health.fraction() <= 0.5:
		enraged = true
		map.broadcast(&"ev_mob_move", [index, &"rage", body_position().x, body_position().y])
	var chased := _update_target()
	moves.tick()
	if hurt_t > 0:
		hurt_t -= 1
	if moves.busy():
		moves.step(chased)
	elif hurt_t > 0:
		if not def.stationary:
			position.x += kx
		kx *= KNOCKBACK_DECAY
	elif not (chased and moves.try_start(chased)):
		_walk(chased)
	if def.jumps and not def.flying and not moves.busy():
		if hop <= 0.0 and hurt_t == 0 and randf() < HOP_CHANCE:
			hop_v = def.jump_power
		hop += hop_v
		hop_v -= HOP_GRAVITY
		if hop <= 0.0:
			hop = 0.0
			hop_v = 0.0
	var half := def.size.x / 2.0
	if position.x < area.x + half:
		position.x = area.x + half
		if dir < 0:
			dir = 1
	if position.x > area.x + area.w - half:
		position.x = area.x + area.w - half
		if dir > 0:
			dir = -1
	if moves.hidden:
		return
	var body := hurtbox.rect_at(body_position())
	for p in map.players.values():
		if body.intersects(p.hurtbox.rect_at(p.position)):
			map.touch_player(p, self)

## Walking: after its target when it has one and can reach them, else patrolling.
func _walk(chased: SimPlayer) -> void:
	if def.stationary:
		if chased:
			dir = -1 if chased.position.x < position.x else 1
		return
	var speed := def.speed * (RAGE_SPEED if enraged else 1.0)
	if chased and _level_with(chased):
		stuck_t = 0
		var dx := chased.position.x - position.x
		if def.keep_distance > 0.0 and absf(dx) < def.keep_distance and not moves.close_ready(chased):
			# a shooter backs away from a player crowding it
			position.x -= signf(dx) * speed * CHASE_SPEED
			return
		dir = -1 if dx < 0.0 else 1
		var goal := chased.position.x
		if def.boss:
			goal += clampf(target_velocity.x * LEAD_TICKS, -120.0, 120.0) # cuts them off
		if absf(goal - position.x) > 4.0:
			position.x += signf(goal - position.x) * speed * CHASE_SPEED
		return
	if chased and def.boss and _try_leap(chased):
		return
	walk_t -= 1
	if walk_t <= 0:
		walk_t = randi_range(WALK_TICKS.x, WALK_TICKS.y)
		dir = 0 if randf() < IDLE_CHANCE else (-1 if randf() < 0.5 else 1)
	position.x += dir * speed

## Whether `p` is level with it (on its platform, or in the air above it), so it can
## chase them. Fliers chase anyone within their sight height.
func _level_with(p: SimPlayer) -> bool:
	if def.flying:
		return absf(p.position.y - plat.y) <= FLYING_SIGHT_Y
	return absf(p.position.y - plat.y) <= SIGHT_Y and p.position.y <= plat.y + 6.0

## Bosses: after a moment unable to reach `p`, leaps to the platform they stand on.
func _try_leap(p: SimPlayer) -> bool:
	var pl := _platform_of(p)
	if pl == null or pl == plat or pl.w < def.size.x:
		stuck_t = 0
		return false
	stuck_t += 1
	if stuck_t < LEAP_WAIT:
		return false
	var half := def.size.x / 2.0
	var x := clampf(p.position.x - signf(p.position.x - position.x) * (half + 40.0), pl.x + half, pl.x + pl.w - half)
	if absf(x - position.x) > MobMoves.LEAP_X or absf(pl.y - plat.y) > MobMoves.LEAP_Y:
		return false
	stuck_t = 0
	moves.leap(pl, x)
	return true

## The platform `p` stands on, or null in the air or on a rope.
func _platform_of(p: SimPlayer) -> Platform:
	for pl in map.layout.platforms:
		if pl.contains_x(p.position.x) and absf(pl.y - p.position.y) < 6.0:
			return pl
	return null

# ---------- targeting ----------

## Whether `p` can be targeted at all: on the map, awake and not watching a cutscene.
func can_target(p: SimPlayer) -> bool:
	return p != null and p.map == map and not p.fainted() and not p.in_scene()

## Whether it notices `p`: within its sight across and not too far above or below.
func sees(p: SimPlayer) -> bool:
	if not can_target(p):
		return false
	var dy := absf(p.position.y - plat.y)
	# bosses watch the platforms around them too: they can leap there
	var reach_y := MobMoves.LEAP_Y if def.boss else (FLYING_SIGHT_Y if def.flying else SIGHT_Y)
	return absf(p.position.x - position.x) <= def.sight and dy <= reach_y

## Keeps `target` up to date and returns them (or null): it keeps after whoever it's
## angry at while it can see them (or for a while after they hit it), and otherwise
## turns on the nearest player it sees. Bosses go for whoever hurt them most lately.
func _update_target() -> SimPlayer:
	for peer in threat.keys():
		threat[peer] *= THREAT_DECAY
	if aggro > 0:
		aggro -= 1
	if _hit_t > 0:
		_hit_t -= 1
	var p := map.players.get(target) as SimPlayer if target != 0 else null
	if p and not can_target(p):
		p = null
		aggro = 0
	if p and sees(p):
		aggro = maxi(aggro, SIGHT_TICKS)
	if aggro <= 0:
		p = null
	if def.boss:
		var top := _most_threat()
		if top:
			p = top
			aggro = maxi(aggro, SIGHT_TICKS)
	if p == null and _hit_t > 0 and can_target(map.players.get(_hit_by) as SimPlayer):
		p = map.players.get(_hit_by)
		aggro = _hit_t
		_hit_t = 0
	if p == null:
		p = _nearest_seen()
		if p:
			aggro = SIGHT_TICKS
	if p == null:
		if target != 0:
			moves.cancel()
		target = 0
		return null
	_track(p, p.peer != target)
	target = p.peer
	return p

func _most_threat() -> SimPlayer:
	var best: SimPlayer = null
	var most := 0.5
	for peer in threat:
		var p := map.players.get(peer) as SimPlayer
		if can_target(p) and threat[peer] > most:
			best = p
			most = threat[peer]
	return best

func _nearest_seen() -> SimPlayer:
	var best: SimPlayer = null
	for p: SimPlayer in map.players.values():
		if sees(p) and (best == null or absf(p.position.x - position.x) < absf(best.position.x - position.x)):
			best = p
	return best

## Follows how fast `p` moves (to aim ahead of them); `fresh` starts over on a new target.
func _track(p: SimPlayer, fresh: bool) -> void:
	if p == null:
		return
	if fresh:
		target_velocity = Vector2.ZERO
	else:
		target_velocity = target_velocity * 0.85 + (p.position - _target_last) * 0.15
	_target_last = p.position

# ---------- shots ----------

## Where its shots leave from.
func muzzle() -> Vector2:
	return body_position() + Vector2(dir * def.size.x * 0.4, -def.size.y * 0.55)

## Fires move `move_index` (a shot) at the point `aim`, meant for `peer`.
func shoot(move_index: int, aim: Vector2, peer: int) -> void:
	var mv: MonsterMove = def.moves[move_index]
	dir = -1 if aim.x < position.x else 1
	var ticks := ceili(muzzle().distance_to(aim) / maxf(1.0, mv.projectile.speed))
	shots.append([peer, ticks, aim, mv.power])
	map.broadcast(&"ev_mob_shot", [index, move_index, aim.x, aim.y])

## Shots land where it aimed: whoever it was meant for is hit if they're there.
func _step_shots() -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Array = shots[i]
		s[1] -= 1
		if s[1] > 0:
			continue
		shots.remove_at(i)
		var p := map.players.get(s[0]) as SimPlayer
		if p and p.hurtbox.rect_at(p.position).grow(SHOT_GROW).has_point(s[2]):
			map.hurt_player(p, def, position.x, s[3])

## What clients need to draw it: [x, y, dir, hp fraction (0..1000), flags].
func snapshot() -> Array:
	var flags := 0
	if dead:
		flags |= SnapshotFlags.MOB_DEAD
	if hurt_t > 0:
		flags |= SnapshotFlags.MOB_HURT
	if aggro > 0:
		flags |= SnapshotFlags.MOB_AGGRO
	if show_hp > 0:
		flags |= SnapshotFlags.MOB_SHOW_HP
	if moves.posing():
		flags |= SnapshotFlags.MOB_CASTING
	if moves.winding() and not dead:
		flags |= SnapshotFlags.MOB_WINDUP
	if moves.hidden:
		flags |= SnapshotFlags.MOB_HIDDEN
	if enraged:
		flags |= SnapshotFlags.MOB_ENRAGED
	return [position.x, position.y - hop, dir, roundi(health.fraction() * 1000.0), flags]
