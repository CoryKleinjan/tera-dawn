class_name SimMob
extends RefCounted
## A monster as the server runs it: it patrols its platform, chases whoever hit it last
## while they stand on its platform, hurts players it touches, and comes back some time
## after it is defeated. Flying monsters do the same in the air. Depending on its
## MonsterDef it may hop, stand still, shoot at players, or split into smaller monsters
## (those wait asleep until their parent is defeated).
## Clients only see it through snapshots (see TDMob, the client-side view).

## Ticks the HP bar stays up after a hit.
const SHOW_HP_TICKS := 240

var map: MapInstance
var index := 0
var def: MonsterDef
var plat: Platform
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
var cast_t := 0     # ticks it stands still after shooting
## Shots in the air: [peer, ticks left, where it lands].
var shots := []
## The monsters this one splits into (see MapDef.roster), and the one it split off.
var children: Array[SimMob] = []
var parent: SimMob
## A split-off monster waiting for its parent to be defeated.
var asleep := false

func _init(m: MapInstance, i: int, d: MonsterDef, p: Platform) -> void:
	map = m
	index = i
	def = d
	plat = p
	hurtbox = Hitbox.new(d.size)
	_reset()

func _reset() -> void:
	var half := def.size.x / 2.0
	health.reset(def.max_hp)
	position = Vector2(randf_range(plat.x + half, plat.x + plat.w - half), plat.y)
	dir = -1 if randf() < 0.5 else 1
	walk_t = randi_range(60, 200)
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
	shot_t = randi_range(30, maxi(31, def.shot_cooldown))
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
	position.x = clampf(x, plat.x + half, plat.x + plat.w - half)
	hop_v = 5.0
	aggro = 600
	target = by

func hurt(from_face: int, by: int) -> void:
	hurt_t = 14
	kx = from_face * 3.2
	aggro = 600
	target = by
	show_hp = SHOW_HP_TICKS

func die() -> void:
	dead = true
	death_t = 40
	respawn = randi_range(def.respawn_ticks.x, def.respawn_ticks.y)

## Feet position including the hover height of flying monsters and hops.
func body_position() -> Vector2:
	if def.flying:
		return position + Vector2(0, -def.hover_height + sin(phase * 1.5) * 6.0)
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
		if not def.stationary:
			position.x += kx
		kx *= 0.82
	elif cast_t > 0:
		cast_t -= 1
	else:
		var chased := map.players.get(target) as SimPlayer if aggro > 0 else null
		if def.stationary:
			pass
		elif chased and chased.stands_on(plat):
			dir = -1 if chased.position.x < position.x else 1
			position.x += dir * def.speed * 1.3
		else:
			walk_t -= 1
			if walk_t <= 0:
				walk_t = randi_range(60, 220)
				dir = 0 if randf() < 0.3 else (-1 if randf() < 0.5 else 1)
			position.x += dir * def.speed
		if def.shot:
			shot_t -= 1
			if shot_t <= 0:
				var aim := _shot_target(chased)
				if aim:
					_shoot(aim)
	if def.jumps and not def.flying:
		if hop <= 0.0 and hurt_t == 0 and randf() < 1.0 / 80.0:
			hop_v = def.jump_power
		hop += hop_v
		hop_v -= 0.35
		if hop <= 0.0:
			hop = 0.0
			hop_v = 0.0
	if position.x < plat.x + half:
		position.x = plat.x + half
		if dir < 0:
			dir = 1
	if position.x > plat.x + plat.w - half:
		position.x = plat.x + plat.w - half
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
	return not p.fainted() and absf(p.position.x - position.x) <= def.shot_range and absf(p.position.y - position.y) <= 180.0

## Where its shots leave from.
func muzzle() -> Vector2:
	return body_position() + Vector2(dir * def.size.x * 0.4, -def.size.y * 0.55)

func _shoot(p: SimPlayer) -> void:
	dir = -1 if p.position.x < position.x else 1
	shot_t = def.shot_cooldown + randi_range(0, 40)
	cast_t = 24
	var aim := p.position + Vector2(0, -30)
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
		if p and p.hurtbox.rect_at(p.position).grow(14).has_point(s[2]):
			map.hurt_player(p, def, position.x)

## What clients need to draw it: [x, y, dir, hp fraction (0..1000), flags].
func snapshot() -> Array:
	var flags := 0
	if dead:
		flags |= TDMob.DEAD
	if hurt_t > 0:
		flags |= TDMob.HURT
	if aggro > 0:
		flags |= TDMob.AGGRO
	if show_hp > 0:
		flags |= TDMob.SHOW_HP
	if cast_t > 0:
		flags |= TDMob.CASTING
	return [position.x, position.y - hop, dir, roundi(health.fraction() * 1000.0), flags]
