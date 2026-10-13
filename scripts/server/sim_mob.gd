class_name SimMob
extends RefCounted
## A monster as the server runs it: it patrols its platform (or the stretch of it its
## SpawnDef allows), chases whoever hit it last while they stand on its platform, hurts
## players it touches, and comes back some time after it is defeated. Flying monsters do
## the same in the air. Depending on its
## MonsterDef it may hop, stand still, shoot at players, or split into smaller monsters
## (those wait asleep until their parent is defeated).
## Clients only see it through snapshots (see TDMob, the client-side view).

## Ticks the HP bar stays up after a hit.
const SHOW_HP_TICKS := 240
## Ticks a defeated monster takes to fade out (clients fade their view over the same time).
const DEATH_FADE_TICKS := 40
## Ticks it keeps chasing whoever hit it (or woke it).
const AGGRO_TICKS := 600
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
## Players further above or below than this are out of shooting range.
const SHOT_Y_RANGE := 180.0
## Ticks it stands still after shooting, and the most extra random wait before the next shot.
const CAST_TICKS := 24
## For this many ticks before a shot, clients see it wind up (MOB_WINDUP), so it's fair.
const WINDUP_TICKS := 22
const SHOT_JITTER := 40
## Shortest wait before its first shot.
const FIRST_SHOT_TICKS := 30
## How far around a player's hurtbox a landing shot still hits.
const SHOT_GROW := 14

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
var aggro := 0      # ticks left chasing `target`
var target := 0     # peer id of whoever hit it last
var dead := false
var death_t := 0
var respawn := 0
var phase := 0.0
var show_hp := 0    # ticks left showing the HP bar
var hop := 0.0      # height of a hop above the platform
var hop_v := 0.0
var shot_t := 0     # ticks until it may shoot again
var winding := false # about to shoot someone in range (shown as a wind-up glow)
var cast_t := 0     # ticks it stands still after shooting
## Shots in the air: [peer, ticks left, where it lands].
var shots := []
## The monsters this one splits into (see MapDef.roster), and the one it split off.
var children: Array[SimMob] = []
var parent: SimMob
## A split-off monster waiting for its parent to be defeated.
var asleep := false

func _init(m: MapInstance, i: int, d: MonsterDef, p: Platform, patrol: Platform = null) -> void:
	map = m
	index = i
	def = d
	plat = p
	area = patrol if patrol else p
	hurtbox = Hitbox.new(d.size)
	_reset()

func _reset() -> void:
	var half := def.size.x / 2.0
	health.reset(def.max_hp)
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
	shot_t = randi_range(FIRST_SHOT_TICKS, maxi(FIRST_SHOT_TICKS + 1, def.shot_cooldown))
	cast_t = 0
	shots.clear()
	asleep = false

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
	kx = from_face * KNOCKBACK
	aggro = AGGRO_TICKS
	target = by
	show_hp = SHOW_HP_TICKS

func die() -> void:
	dead = true
	death_t = DEATH_FADE_TICKS
	respawn = randi_range(def.respawn_ticks.x, def.respawn_ticks.y)

## How far above its feet a monster's body floats: flying monsters hover and bob (by
## `phase`), others don't. Clients (TDMob) use the same.
static func hover_offset(d: MonsterDef, phase_now: float) -> Vector2:
	if d.flying:
		return Vector2(0, -d.hover_height + sin(phase_now * 1.5) * 6.0)
	return Vector2.ZERO

## Feet position including the hover height of flying monsters and hops.
func body_position() -> Vector2:
	if def.flying:
		return position + hover_offset(def, phase)
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
	if aggro > 0:
		aggro -= 1
	var half := def.size.x / 2.0
	if hurt_t > 0:
		hurt_t -= 1
		winding = false
		if not def.stationary:
			position.x += kx
		kx *= KNOCKBACK_DECAY
	elif cast_t > 0:
		cast_t -= 1
		winding = false
	else:
		var chased := map.players.get(target) as SimPlayer if aggro > 0 else null
		if def.stationary:
			pass
		elif chased and chased.stands_on(plat):
			dir = -1 if chased.position.x < position.x else 1
			position.x += dir * def.speed * CHASE_SPEED
		else:
			walk_t -= 1
			if walk_t <= 0:
				walk_t = randi_range(WALK_TICKS.x, WALK_TICKS.y)
				dir = 0 if randf() < IDLE_CHANCE else (-1 if randf() < 0.5 else 1)
			position.x += dir * def.speed
		if def.shot:
			shot_t -= 1
			winding = shot_t <= WINDUP_TICKS and _shot_target(chased) != null
			if shot_t <= 0:
				var aim := _shot_target(chased)
				if aim:
					_shoot(aim)
					winding = false  # the wind-up ends with the shot
	if def.jumps and not def.flying:
		if hop <= 0.0 and hurt_t == 0 and randf() < HOP_CHANCE:
			hop_v = def.jump_power
		hop += hop_v
		hop_v -= HOP_GRAVITY
		if hop <= 0.0:
			hop = 0.0
			hop_v = 0.0
	if position.x < area.x + half:
		position.x = area.x + half
		if dir < 0:
			dir = 1
	if position.x > area.x + area.w - half:
		position.x = area.x + area.w - half
		if dir > 0:
			dir = -1
	var body := hurtbox.rect_at(body_position())
	for p in map.players.values():
		if body.intersects(p.hurtbox.rect_at(p.position)):
			map.touch_player(p, self)

## Who to shoot: whoever it's chasing, or for aggressive monsters the nearest player, if
## they're in range.
func _shot_target(chased: SimPlayer) -> SimPlayer:
	if chased and _in_range(chased):
		return chased
	if not def.aggressive:
		return null
	var best: SimPlayer = null
	for p in map.players.values():
		if _in_range(p) and (best == null or absf(p.position.x - position.x) < absf(best.position.x - position.x)):
			best = p
	return best

func _in_range(p: SimPlayer) -> bool:
	return not p.fainted() and not p.in_scene() and absf(p.position.x - position.x) <= def.shot_range and absf(p.position.y - position.y) <= SHOT_Y_RANGE

## Where its shots leave from.
func muzzle() -> Vector2:
	return body_position() + Vector2(dir * def.size.x * 0.4, -def.size.y * 0.55)

func _shoot(p: SimPlayer) -> void:
	dir = -1 if p.position.x < position.x else 1
	shot_t = def.shot_cooldown + randi_range(0, SHOT_JITTER)
	cast_t = CAST_TICKS
	var aim := p.position + Vector2(0, -SimPlayer.CHEST)
	var ticks := ceili(muzzle().distance_to(aim) / maxf(1.0, def.shot.speed))
	shots.append([p.peer, ticks, aim])
	map.broadcast(&"ev_mob_shot", [index, aim.x, aim.y])

## Shots land where the player was when it fired: still there, they're hit.
func _step_shots() -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Array = shots[i]
		s[1] -= 1
		if s[1] > 0:
			continue
		shots.remove_at(i)
		var p := map.players.get(s[0]) as SimPlayer
		if p and p.hurtbox.rect_at(p.position).grow(SHOT_GROW).has_point(s[2]):
			map.hurt_player(p, def, position.x)

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
	if cast_t > 0:
		flags |= SnapshotFlags.MOB_CASTING
	if winding and not dead:
		flags |= SnapshotFlags.MOB_WINDUP
	return [position.x, position.y - hop, dir, roundi(health.fraction() * 1000.0), flags]
