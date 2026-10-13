class_name WorldCamera
extends RefCounted
## Where TDWorld's camera looks: it follows your hero, a little ahead of the way they walk,
## moves up or down only once they land somewhere new, glides between ticks and shakes on
## big hits. `pos` is the top left of the world_view()-sized box it shows, in game pixels;
## the stage aims its 3D camera there (TDStage.follow).

## How close the camera is: below 1 shows more of the world around the hero (the HUD keeps
## its size). Every map must be at least TDWorld.world_view() big on a 16:10 screen, or the
## camera would show past its edges; content_world_test checks it.
const ZOOM := 0.88
## How far ahead of the hero the camera looks in the direction they walk, in game pixels.
const LOOK_AHEAD := 70.0
## The camera only follows a jump once the hero is this far above or below where they last stood.
const DEAD_ZONE := 90.0
## Where the ground the hero stands on sits in the view: this share of the way down.
const STAND_AT := 0.62

var world: TDWorld
var pos := Vector2.ZERO
var _prev := Vector2.ZERO
var look := 0.0
## The height the camera keeps to: where the hero last stood (see aim()).
var floor_y := 0.0
## Screen shake strength (0..1); it fades by itself (see shake()).
var _shake := 0.0
## Where a cutscene holds the camera's centre (game pixels), or null to follow the hero.
## The cutscene moves it smoothly itself, so the camera sits exactly there.
var scene_center: Variant = null

func _init(w: TDWorld) -> void:
	world = w

## Where the camera wants to be: around the hero, kept inside the map.
func target() -> Vector2:
	var view := TDWorld.world_view()
	return Vector2(
		clampf(world.player.position.x + look - view.x / 2.0, 0, maxf(0.0, float(world.map.width) - view.x)),
		clampf(floor_y - view.y * STAND_AT, 0, maxf(0.0, float(world.map.height) - view.y)))

## The top left of the view centred on `center`, kept inside the map.
func box_at(center: Vector2) -> Vector2:
	var view := TDWorld.world_view()
	return Vector2(
		clampf(center.x - view.x / 2.0, 0, maxf(0.0, float(world.map.width) - view.x)),
		clampf(center.y - view.y / 2.0, 0, maxf(0.0, float(world.map.height) - view.y)))

## The centre of what the camera shows now, in game pixels.
func center() -> Vector2:
	return pos + TDWorld.world_view() / 2.0

## Jumps straight to the target (a new map), keeping its aim.
func jump_to_target() -> void:
	pos = target()

## Puts the camera on the hero at once (a new map, a respawn), with nothing to glide from.
func snap() -> void:
	floor_y = world.player.position.y
	look = 0.0
	pos = target()
	_prev = pos
	world.stage.follow(pos)

## Moves the camera's aim one tick: a little ahead of the way the hero walks, and up or
## down only once they land somewhere new (or jump or fall well past where they stood).
func aim() -> void:
	var player := world.player
	if absf(player.vel.x) > 0.3:
		look = move_toward(look, player.face * LOOK_AHEAD, 1.6)
	var y := player.position.y
	if player.on_ground or player.is_climbing() or absf(y - floor_y) > DEAD_ZONE:
		floor_y += (y - floor_y) * (1.0 if absf(y - floor_y) > 400.0 else 0.25)

## Shakes the screen (a crit, a boss slam, getting hit): 0.3 is a nudge, 1 is a big hit.
## Off when the player turned screen shake off in the video settings.
func shake(amount: float) -> void:
	if Settings.video.screen_shake:
		_shake = minf(1.0, maxf(_shake, amount))

## One physics tick: aim, glide toward the target, and let the shake fade.
func step() -> void:
	_prev = pos
	aim()
	if scene_center is Vector2:
		pos = box_at(scene_center)
	else:
		pos += (target() - pos) * Vector2(0.12, 0.1)
	_shake = maxf(0.0, _shake - 0.04)

## Every frame: aims the stage between the last two ticks, shaken if it's shaking.
func draw() -> void:
	var at := _prev.lerp(pos, Engine.get_physics_interpolation_fraction())
	if _shake > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		var k := _shake * _shake * 9.0
		at += Vector2(sin(t * 71.0), cos(t * 53.0)) * k
	world.stage.follow(at)
