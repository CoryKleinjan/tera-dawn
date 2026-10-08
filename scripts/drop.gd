class_name TDDrop
extends Node2D
## A Dawnshard pile dropped by a monster. Picked up by walking over it.

var world: TDWorld
var vel := Vector2.ZERO
var floor_y := 0.0
var amount := 1
var t := 0
var spin := randf() * 6.0
var taken := false

func step() -> void:
	t += 1
	spin += 0.1
	if vel.y != 0.0 or position.y < floor_y:
		vel.y += 0.45
		position += vel
		if position.y >= floor_y:
			position.y = floor_y
			vel = Vector2.ZERO
	var p := world.player
	if not taken and t > 25 and p.dead == 0 and absf(position.x - p.position.x) < 26 and absf(position.y - p.position.y) < 50:
		taken = true
		Game.shards += amount
		world.add_log("Picked up %d Dawnshards" % amount, GameData.MIST)
		queue_free()
	elif t > 3600:
		queue_free()

var gem: Sprite3D
var glow: Sprite3D
var shine: OmniLight3D

func _ready() -> void:
	gem = TDStage.sprite(TDStage.tex("shard"), 1, false)
	gem.offset = Vector2.ZERO
	gem.modulate = Color(1.5, 1.4, 1.2)
	add_child(gem)
	glow = TDStage.glow_sprite(TDStage.tex("glow"), Color(1.0, 0.7, 0.3, 0.6))
	glow.pixel_size = TDStage.PIXEL * 0.7
	add_child(glow)
	shine = TDStage.light(Color("ffd166"), 0.8, 1.8)
	add_child(shine)

func _process(_delta: float) -> void:
	if gem == null:
		return
	var hover := sin(spin * 2.0) * 2.0 if vel == Vector2.ZERO else 0.0
	var p := TDStage.to3d(position + Vector2(0, -10 - hover), 0.5)
	gem.position = p
	gem.scale = Vector3(absf(cos(spin)) * 0.7 + 0.3, 1, 1)
	glow.position = p + Vector3(0, 0, -0.02)
	shine.position = p + Vector3(0, 0.2, 0.4)
