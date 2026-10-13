class_name TDMoveFx
extends Node2D
## The code-drawn look of a job's movement skill (SkillDef.move), in its MoveDef colour, until
## painted effects replace it: a trail of glowing motes behind whoever moves, and for a Blink
## a crackle where they vanish, a jagged bolt to where they land and sparks on arrival.
## Lives on the world's fx layer and removes itself when done.

## Motes left behind each tick of a trail, and how fast they drift.
const TRAIL_MOTES := 3
const TRAIL_SPEED := 0.35
## Sparks in a Blink's crackle and arrival, and how fast they fly.
const CRACKLE_SPARKS := 12
const CRACKLE_SPEED := 1.1
## Ticks the bolt takes to fade, its zigzag (game pixels to each side) and its kinks.
const BOLT_TICKS := 14
const BOLT_JAG := 12.0
const BOLT_KINKS := 7
## How far above the feet the trail and bolt run: about the middle of the body.
const MID := 30.0

var world: TDWorld
var move: MoveDef
## Who it trails (null for a Blink, which only flashes).
var follow: Node2D
var t := 0
var ticks := 0
var _bolt: MeshInstance3D
var _glow: OmniLight3D

## Plays `move` for someone at `from` (their feet) who ends at `to` (a Blink) or moves on as
## `who` (everything else).
static func play(w: TDWorld, m: MoveDef, from: Vector2, to: Vector2, who: Node2D) -> TDMoveFx:
	var fx := TDMoveFx.new()
	fx.world = w
	fx.move = m
	fx.position = from
	if m.style == MoveDef.Style.BLINK:
		fx.ticks = BOLT_TICKS
		fx._blink(from, to)
	else:
		fx.follow = who
		fx.ticks = m.ticks
		w.fx.dust(from, 0, 6)
	w.fx_layer.add_child(fx)
	return fx

func _blink(from: Vector2, to: Vector2) -> void:
	var a := from + Vector2(0, -MID)
	var b := to + Vector2(0, -MID)
	world.fx.burst(a, move.color, CRACKLE_SPARKS, CRACKLE_SPEED)
	world.fx.burst(b, move.color, CRACKLE_SPARKS, CRACKLE_SPEED)
	world.fx.flash(b, move.color, 2.5)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var across := (b - a).orthogonal().normalized()
	for i in BOLT_KINKS + 1:
		var k := float(i) / BOLT_KINKS
		var jag := 0.0 if i == 0 or i == BOLT_KINKS else randf_range(-BOLT_JAG, BOLT_JAG)
		mesh.surface_add_vertex(TDStage.to3d(a.lerp(b, k) + across * jag, TDStage.Z_EFFECT))
	mesh.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = move.color
	_bolt = MeshInstance3D.new()
	_bolt.mesh = mesh
	_bolt.material_override = mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.stage.map_root.add_child(_bolt)

func _ready() -> void:
	if follow:
		_glow = TDStage.light(move.color, 1.2, 3.0)
		world.stage.map_root.add_child(_glow)

func step() -> void:
	t += 1
	if t > ticks:
		queue_free()
		return
	var k := float(t) / ticks
	if _bolt:
		(_bolt.material_override as StandardMaterial3D).albedo_color.a = move.color.a * (1.0 - k)
	if is_instance_valid(follow):
		var at := follow.position + Vector2(0, -MID)
		world.fx.burst(at, move.color, TRAIL_MOTES, TRAIL_SPEED)
		if _glow:
			_glow.position = TDStage.to3d(at, TDStage.Z_EFFECT + 0.6)
			_glow.light_energy = 1.2 * (1.0 - k)

func _exit_tree() -> void:
	for n in [_bolt, _glow]:
		if is_instance_valid(n):
			n.queue_free()
