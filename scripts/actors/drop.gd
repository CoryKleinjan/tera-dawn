class_name TDDrop
extends Node2D
## An item lying on the ground, as a player sees it. The server keeps the real one
## (SimDrop) and decides who picks it up; this plays the same flight so it lands in the
## same spot, and sparkles until the server says it's gone.

var world: TDWorld
var id := 0
var item: ItemDef
var amount := 1
var flight: DropFlight
var t := 0
var spin := randf() * 6.0

var gem: Sprite3D
var glow: Sprite3D
var shine: OmniLight3D

## Builds one from the server's [id, item id, amount, flight, age].
static func create(w: TDWorld, snap: Array) -> TDDrop:
	var d := TDDrop.new()
	d.world = w
	d.id = snap[0]
	d.item = Content.item(snap[1])
	d.amount = snap[2]
	d.flight = DropFlight.from_array(snap[3])
	d.t = snap[4]
	d.position = d.flight.position
	return d

func step() -> void:
	t += 1
	spin += 0.1
	flight.step()
	position = flight.position

func _ready() -> void:
	var big := item.pile_texture != null and amount >= item.pile_amount
	var tex: Texture2D = item.pile_texture if big else item.world_texture()
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
	var resting := flight.resting()
	var hover := sin(spin * 2.0) * 2.0 if resting else 0.0
	var p := TDStage.to3d(position + Vector2(0, -2 - hover), TDStage.Z_DROP)
	gem.position = p
	if item.world_frames.size() > 1 and not (item.pile_texture and amount >= item.pile_amount):
		gem.texture = item.world_texture(int(spin * 0.8))
	glow.position = p + Vector3(0, 0.4, -0.02)
	shine.position = p + Vector3(0, 0.6, 0.4)
