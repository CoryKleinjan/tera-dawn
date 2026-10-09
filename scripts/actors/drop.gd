class_name TDDrop
extends Node2D
## An item lying on the ground after a monster drops it. Walk over it to pick it up.

var world: TDWorld
var item: ItemDef
var amount := 1
var vel := Vector2.ZERO
var floor_y := 0.0
var t := 0
var spin := randf() * 6.0
var taken := false

var gem: Sprite3D
var glow: Sprite3D
var shine: OmniLight3D

static func create(w: TDWorld, it: ItemDef, n: int, at: Vector2, ground: float) -> TDDrop:
	var d := TDDrop.new()
	d.world = w
	d.item = it
	d.amount = n
	d.position = at
	d.floor_y = ground
	d.vel = Vector2(randf_range(-1.6, 1.6), randf_range(-6, -4))
	return d

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
	if not taken and t > 25 and not p.fainted() and absf(position.x - p.position.x) < 26 and absf(position.y - p.position.y) < 50:
		_pick_up()
	elif t > 3600:
		queue_free()

func _pick_up() -> void:
	taken = true
	if item.is_currency:
		Game.shards += amount
	world.add_log("Picked up %d %s" % [amount, item.display_name], Palette.MIST)
	world.add_effect(item.pickup_effect, position + Vector2(0, -16), 1)
	queue_free()

func _ready() -> void:
	var big := item.pile_texture != null and amount >= item.pile_amount
	var tex: Texture2D = item.pile_texture if big else item.world_frames[0]
	gem = TDStage.sprite(tex, TDStage.TEXEL * item.sprite_scale, false)
	gem.modulate = Color(1.3, 1.25, 1.15)
	add_child(gem)
	glow = TDStage.glow_sprite(load("res://assets/sprites/fx/glow.png"), Color(item.glow_color, 0.6))
	glow.pixel_size = TDStage.TEXEL / TDStage.PX * 0.7
	add_child(glow)
	shine = TDStage.light(item.glow_color, 0.8, 1.8)
	add_child(shine)

func _process(_delta: float) -> void:
	if gem == null:
		return
	var resting := vel == Vector2.ZERO
	var hover := sin(spin * 2.0) * 2.0 if resting else 0.0
	var p := TDStage.to3d(position + Vector2(0, -2 - hover), TDStage.Z_DROP)
	gem.position = p
	if item.world_frames.size() > 1 and not (item.pile_texture and amount >= item.pile_amount):
		gem.texture = item.world_frames[int(spin * 0.8) % item.world_frames.size()]
	glow.position = p + Vector3(0, 0.4, -0.02)
	shine.position = p + Vector3(0, 0.6, 0.4)
