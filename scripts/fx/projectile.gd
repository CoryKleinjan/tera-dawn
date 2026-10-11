class_name TDProjectile
extends Node2D
## A ProjectileDef in flight: from the shooter to a monster (then `on_land` runs, which
## shows the damage) or to a fixed point when it hit nothing. Waits `delay` ticks first,
## so several hits leave one after another.

var world: TDWorld
var def: ProjectileDef
var target: TDMob
var to := Vector2.ZERO
var delay := 0
var on_land: Callable
var sprite: Sprite3D
var glow: OmniLight3D
var _angle := 0.0

static func create(w: TDWorld, d: ProjectileDef, from: Vector2, dest: Vector2, wait: int, mob: TDMob, landed: Callable) -> TDProjectile:
	var p := TDProjectile.new()
	p.world = w
	p.def = d
	p.position = from
	p.to = dest
	p.delay = wait
	p.target = mob
	p.on_land = landed
	return p

func _ready() -> void:
	sprite = TDStage.effect_sprite(def.texture, Color(def.energy, def.energy, def.energy), def.texel)
	sprite.visible = false
	add_child(sprite)
	if def.light_color.a > 0.0:
		glow = TDStage.light(def.light_color, 1.6, 2.5)
		glow.visible = false
		add_child(glow)

## Where it's flying now: the monster's middle, or the fixed end point.
func _aim() -> Vector2:
	if is_instance_valid(target):
		return target.body_position() + Vector2(0, -target.def.size.y / 2.0)
	return to

func step() -> void:
	if delay > 0:
		delay -= 1
		return
	var aim := _aim()
	var d := aim - position
	if d.length() <= def.speed:
		position = aim
		if on_land.is_valid():
			on_land.call()
		queue_free()
		return
	position += d.normalized() * def.speed
	_angle = _angle + def.spin * TAU if def.spin != 0.0 else atan2(-d.y, d.x)
	_sync()

func _sync() -> void:
	sprite.visible = true
	sprite.position = TDStage.to3d(position, TDStage.Z_EFFECT)
	sprite.rotation.z = _angle
	if glow:
		glow.visible = true
		glow.position = TDStage.to3d(position, TDStage.Z_EFFECT + 0.4)
