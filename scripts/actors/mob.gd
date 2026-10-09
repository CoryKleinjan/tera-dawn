class_name TDMob
extends Node2D
## A monster as a player sees it. The server runs the real monster (SimMob) and sends
## where it is and what it's doing; this glides to that spot and plays the matching
## animation, HP bar and hit flash.

## How far it moves toward the server's position each tick (0..1).
const FOLLOW := 0.35

var world: TDWorld
var index := 0
var def: MonsterDef
var plat: Platform
var target := Vector2.ZERO
var dir := 1
var hp := 1.0
var flags := 0
## False until the server has said where it is.
var known := false
var death_t := 0
## Projectiles still flying at it: it doesn't fall until they land.
var incoming := 0
var phase := randf() * 6.0
var z := 0.0

var rig: SpriteRig
var _last_x := 0.0

static func create(w: TDWorld, i: int, d: MonsterDef, p: Platform) -> TDMob:
	var m := TDMob.new()
	m.world = w
	m.index = i
	m.def = d
	m.plat = p
	return m

var dead: bool:
	get: return flags & SnapshotFlags.MOB_DEAD != 0

## Takes the server's latest [x, y, dir, hp, flags].
func apply(state: Array) -> void:
	var was_dead := dead
	target = Vector2(state[0], state[1])
	dir = state[2]
	hp = state[3] / 1000.0
	flags = state[4]
	if not known or (was_dead and not dead):
		position = target # first sight, or back from the dead: no gliding in
		death_t = 0
	if dead and not was_dead and known:
		death_t = SimMob.DEATH_FADE_TICKS
	known = true

## The server says it was defeated: start fading out now rather than at the next snapshot.
func kill() -> void:
	if not dead:
		flags |= SnapshotFlags.MOB_DEAD
		death_t = SimMob.DEATH_FADE_TICKS

## Feet position including the hover height of flying monsters.
func body_position() -> Vector2:
	return position + SimMob.hover_offset(def, phase)

func step() -> void:
	phase += 0.08
	position += (target - position) * FOLLOW
	if death_t > 0 and incoming <= 0:
		death_t -= 1

# ---------- HD-2D visuals ----------

func _ready() -> void:
	z = TDStage.Z_MONSTER + randf() * TDStage.Z_MONSTER_SPREAD
	rig = SpriteRig.new()
	rig.setup(def.sprite_frames, def.texture, TDStage.TEXEL * def.sprite_scale, def.size.x * 1.1)
	add_child(rig)
	if def.tint != Color.WHITE:
		rig.set_tint(def.tint)
	if def.light_color.a > 0.0:
		rig.add_light(def.light_color, def.light_energy, def.size.y)
	if def.aura_color.a > 0.0:
		rig.add_aura(def.aura_color, def.size.y * 0.8)
	rig.set_opacity(0.0)

func _process(_delta: float) -> void:
	if rig == null or world == null:
		return
	rig.visible = known and (not dead or death_t > 0)
	if not rig.visible:
		return
	var fallen := dead and incoming <= 0
	rig.set_opacity(clampf(death_t / 30.0, 0.0, 1.0) if fallen else 1.0)
	var hurt := flags & SnapshotFlags.MOB_HURT != 0
	rig.set_flash(hurt and Engine.get_physics_frames() % 4 < 2)
	var facing := dir
	if facing == 0:
		facing = -1 if world.player.position.x < position.x else 1
	rig.face(facing)
	var moving := absf(position.x - _last_x) > 0.01
	_last_x = position.x
	if fallen:
		rig.play(&"die")
	elif hurt:
		rig.play(&"hurt")
	elif flags & SnapshotFlags.MOB_CASTING != 0:
		rig.play(&"attack")
	elif flags & SnapshotFlags.MOB_AGGRO != 0 and moving:
		rig.play(&"attack")
	elif moving:
		rig.play(&"move")
	else:
		rig.play(&"idle")
	rig.place(body_position(), z, NAN if dead else plat.y)

## Name tag and HP bar, drawn by the overlay at this monster's projected screen position.
## A boss's HP is on the boss bar at the top of the screen instead (see draws_boss_bar).
func draw_tag(ci: CanvasItem, at: Vector2, top: Vector2) -> void:
	if dead or not known:
		return
	var label := "Lv.%d %s" % [def.level, def.display_name]
	UiSkin.draw_name_tag(ci, at + Vector2(0, 4), label, Palette.MIST)
	if flags & SnapshotFlags.MOB_SHOW_HP != 0 and not def.boss:
		UiSkin.draw_monster_hp(ci, top + Vector2(0, -16), maxf(54.0, def.size.x * 1.1), hp)

## Whether this is a living boss whose HP belongs on the boss bar.
func draws_boss_bar() -> bool:
	return def.boss and known and not dead
