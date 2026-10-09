class_name SimMob
extends RefCounted
## A monster as the server runs it: it patrols its platform, chases whoever hit it last
## while they stand on its platform, hurts players it touches, and comes back some time
## after it is defeated. Flying monsters do the same in the air.
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

## Feet position including the hover height of flying monsters.
func body_position() -> Vector2:
	if def.flying:
		return position + Vector2(0, -def.hover_height + sin(phase * 1.5) * 6.0)
	return position

func step() -> void:
	phase += 0.08
	if dead:
		if death_t > 0:
			death_t -= 1
		else:
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
		position.x += kx
		kx *= 0.82
	else:
		var chased := map.players.get(target) as SimPlayer if aggro > 0 else null
		if chased and chased.stands_on(plat):
			dir = -1 if chased.position.x < position.x else 1
			position.x += dir * def.speed * 1.3
		else:
			walk_t -= 1
			if walk_t <= 0:
				walk_t = randi_range(60, 220)
				dir = 0 if randf() < 0.3 else (-1 if randf() < 0.5 else 1)
			position.x += dir * def.speed
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
	return [position.x, position.y, dir, roundi(health.fraction() * 1000.0), flags]
