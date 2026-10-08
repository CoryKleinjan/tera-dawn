class_name TDEffect
extends Node2D
## Short-lived hit sparks, sword trails and the level-up burst, built from lights, particles and glow shaders.

var world: TDWorld
var kind := "spark"
var face := 1
var t := 0
var flash: OmniLight3D
var trail: ShaderMaterial
var beam: ShaderMaterial
var root: Node3D

func _life() -> int:
	return {"levelup": 120, "slash": 24, "swish": 14}.get(kind, 24)

func _ready() -> void:
	root = Node3D.new()
	root.position = TDStage.to3d(position, 0.6)
	add_child(root)
	var at := Vector3.ZERO
	match kind:
		"spark":
			var burst := TDStage.particles(Color(3.0, 2.4, 1.4), 16, 0.16)
			burst.one_shot = true
			burst.explosiveness = 1.0
			burst.lifetime = 0.35
			burst.direction = Vector3.UP
			burst.spread = 180.0
			burst.gravity = Vector3.ZERO
			burst.initial_velocity_min = 4.0
			burst.initial_velocity_max = 8.0
			burst.damping_min = 12.0
			burst.damping_max = 16.0
			burst.scale_amount_min = 0.5
			burst.scale_amount_max = 1.3
			burst.position = at
			burst.emitting = true
			root.add_child(burst)
			flash = TDStage.light(Color("ffd8a0"), 2.5, 3.0)
			flash.position = at + Vector3(0, 0, 0.6)
			root.add_child(flash)
		"slash", "swish":
			var big := kind == "slash"
			var q := QuadMesh.new()
			q.size = Vector2(6.5, 4.5) if big else Vector2(3.4, 2.6)
			trail = ShaderMaterial.new()
			trail.shader = load("res://shaders/slash.gdshader")
			trail.set_shader_parameter("face", float(face))
			if not big:
				trail.set_shader_parameter("color_a", Color("f4f1ff"))
				trail.set_shader_parameter("color_b", Color("a9b7ff"))
				trail.set_shader_parameter("energy", 1.8)
			q.material = trail
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = at + Vector3(face * (2.2 if big else 1.3), 0, 0.2)
			root.add_child(mi)
			flash = TDStage.light(Color("ffc070") if big else Color("c8d0ff"), 4.0 if big else 1.5, 6.0 if big else 3.0)
			flash.position = at + Vector3(face * 2.0, 0, 1.0)
			root.add_child(flash)
		"levelup":
			var q := QuadMesh.new()
			q.size = Vector2(2.6, 5.5)
			beam = ShaderMaterial.new()
			beam.shader = load("res://shaders/beam.gdshader")
			q.material = beam
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.position = Vector3(0, 2.75, 0.4)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			var rise := TDStage.particles(Color(2.6, 2.0, 0.9), 40, 0.14)
			rise.lifetime = 1.2
			rise.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			rise.emission_box_extents = Vector3(0.8, 0.1, 0.3)
			rise.direction = Vector3.UP
			rise.spread = 10.0
			rise.gravity = Vector3.ZERO
			rise.initial_velocity_min = 2.0
			rise.initial_velocity_max = 4.0
			rise.position = Vector3(0, 0, 0.5)
			root.add_child(rise)
			flash = TDStage.light(Color("ffd166"), 4.0, 8.0)
			flash.position = Vector3(0, 2.0, 1.2)
			root.add_child(flash)
	_sync()

func step() -> void:
	t += 1
	if kind == "levelup":
		position = world.player.position
	if t > _life():
		queue_free()
	_sync()

func _sync() -> void:
	var k := float(t) / _life()
	if flash:
		flash.light_energy *= 0.86
	if trail:
		trail.set_shader_parameter("progress", k)
	if kind == "levelup":
		root.position = TDStage.to3d(position, 0.2)
		beam.set_shader_parameter("fade", 1.0 - k)

## The "LEVEL UP!" caption, drawn by the overlay so it stays sharp.
func draw_caption(ci: CanvasItem, at: Vector2) -> void:
	var k := float(t) / _life()
	DrawUtil.text(ci, Game.num_font, at + Vector2(0, -100 - k * 40), "LEVEL UP!", 40, Color(GameData.SUN, 1.0 - k), 0, 10, Color(GameData.PLUM, 1.0 - k))
