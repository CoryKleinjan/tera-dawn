class_name TDMob
extends Node2D
## A monster as a player sees it. The server runs the real monster (SimMob) and sends
## where it is and what it's doing; this glides to that spot and plays the matching
## animation, HP bar and hit flash.

## How far it moves toward the server's position each tick (0..1).
const FOLLOW := 0.35
## How far it leans back while winding up a move (game pixels), and a boss's tint after
## its second wind.
const LEAN := 4.0
const RAGE_TINT := Color(1.15, 0.8, 0.75)
## Tints for what player skills do to it, code-drawn until painted effects: hexed (violet),
## rooted (moss green), burning (ember red).
const HEX_TINT := Color(0.85, 0.65, 1.1)
const ROOT_TINT := Color(0.75, 1.05, 0.7)
const BURN_TINT := Color(1.2, 0.75, 0.6)
## Stunned (SkillDef.stun): code-drawn stars circling over its head until painted effects
## replace them: how many, how wide their circle (screen pixels), how fast they go round.
const STUN_STARS := 3
const STUN_RADIUS := 20.0
const STUN_SPIN := 0.006
const STUN_COLOR := Color(1.0, 0.92, 0.45)
## How fast a flier drops to the ground when slammed and rises again after (share per tick).
const DOWN_SPEED := 0.2

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
## Hit reaction: how far it is pushed back (game pixels, fading) and hit-stop ticks left.
var _recoil := 0.0
var _stop_t := 0
## How visible it is (fades out and in for a blink), and whether it shows its second wind.
var _fade := 1.0
## The tint last given to the rig (see _tint).
var _tinted := Color.WHITE
## How much of a flier's hover it shows: 0 while a slam holds it down (SkillDef.slam).
var _hover := 1.0

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
	var was_hidden := flags & SnapshotFlags.MOB_HIDDEN != 0
	target = Vector2(state[0], state[1])
	dir = state[2]
	hp = state[3] / 1000.0
	flags = state[4]
	if not known or (was_dead and not dead) or (was_hidden and flags & SnapshotFlags.MOB_HIDDEN == 0):
		position = target # first sight, back from the dead or from a blink: no gliding in
		death_t = 0
	if dead and not was_dead and known:
		death_t = SimMob.DEATH_FADE_TICKS
	known = true

## The server says it was defeated: start fading out now rather than at the next snapshot.
func kill() -> void:
	if not dead:
		flags |= SnapshotFlags.MOB_DEAD
		death_t = SimMob.DEATH_FADE_TICKS

## It was hit (by an attack facing `face`): a squash, a small push back and, for your own
## hits, a few frames of hit-stop so the blow lands.
func hit_react(face: int, stop_ticks := 0) -> void:
	_recoil = 6.0 * face
	_stop_t = maxi(_stop_t, stop_ticks)
	if rig:
		rig.squash(1.0)

## Feet position including the hover height of flying monsters.
func body_position() -> Vector2:
	return position + SimMob.hover_offset(def, phase) * _hover

## body_position() where it is drawn this frame (between ticks, see TDWorld.drawn), with
## its hit recoil.
func drawn_body_position() -> Vector2:
	return world.drawn(self) + SimMob.hover_offset(def, phase) * _hover + Vector2(_recoil, 0)

func step() -> void:
	_recoil *= 0.75
	if _stop_t > 0:
		# hit-stop: hold still for a moment
		_stop_t -= 1
		if rig:
			rig.freeze(_stop_t > 0)
		return
	phase += 0.08
	position += (target - position) * FOLLOW
	_hover = move_toward(_hover, 0.0 if flags & SnapshotFlags.MOB_DOWNED != 0 else 1.0, DOWN_SPEED)
	if death_t > 0 and incoming <= 0:
		death_t -= 1

# ---------- Visuals ----------

func _ready() -> void:
	z = TDStage.Z_MONSTER + randf() * TDStage.Z_MONSTER_SPREAD
	rig = SpriteRig.new()
	rig.setup(def.sprite_frames, def.texture, TDStage.TEXEL * def.sprite_scale)
	add_child(rig)
	if def.tint != Color.WHITE:
		rig.set_tint(def.tint)
	_tinted = def.tint
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
	var hidden := flags & SnapshotFlags.MOB_HIDDEN != 0
	_fade = move_toward(_fade, 0.0 if hidden else 1.0, 0.25)
	rig.set_opacity(clampf(death_t / 30.0, 0.0, 1.0) if fallen else _fade)
	var hurt := flags & SnapshotFlags.MOB_HURT != 0
	rig.set_flash(hurt and Engine.get_physics_frames() % 4 < 2)
	# stunned: frozen mid-flinch until it comes round
	var stunned := stunned()
	if _stop_t == 0:
		rig.freeze(stunned)
	# winding up a move: a warm pulse and a lean back, so it never comes out of nowhere
	var winding := flags & SnapshotFlags.MOB_WINDUP != 0 and not dead
	rig.set_glow(0.5 + 0.5 * sin(Time.get_ticks_msec() / 45.0) if winding else 0.0)
	var tint := _tint()
	if tint != _tinted:
		_tinted = tint
		rig.set_tint(tint)
	var facing := dir
	if facing == 0:
		facing = -1 if world.player.position.x < position.x else 1
	rig.face(facing)
	var moving := absf(position.x - _last_x) > 0.01
	_last_x = position.x
	var lean := Vector2.ZERO
	if fallen:
		rig.play(&"die")
	elif flags & SnapshotFlags.MOB_CASTING != 0:
		rig.play(&"attack")
	elif hurt or stunned:
		rig.play(&"hurt")
	elif winding:
		rig.play(&"idle")
		lean = Vector2(-facing * LEAN, 0)
	elif moving:
		rig.play(&"move")
	else:
		rig.play(&"idle")
	rig.place(drawn_body_position() + lean, z)

## Its own tint, warmed when enraged and coloured by a hex, root or burn on it.
func _tint() -> Color:
	var out := def.tint
	if flags & SnapshotFlags.MOB_ENRAGED != 0:
		out *= RAGE_TINT
	if flags & SnapshotFlags.MOB_HEXED != 0:
		out *= HEX_TINT
	if flags & SnapshotFlags.MOB_ROOTED != 0:
		out *= ROOT_TINT
	if flags & SnapshotFlags.MOB_BURNING != 0:
		out *= BURN_TINT
	return out

## HP bar and name tag, drawn by the overlay at this monster's projected screen position
## (the tag goes in `tags`, which keeps tags apart). A boss's HP is on the boss bar at the
## top of the screen instead (see draws_boss_bar).
func draw_tag(ci: CanvasItem, at: Vector2, top: Vector2, tags: TDNameTags) -> void:
	if dead or not known:
		return
	if shows_tag():
		tags.add_name(at + Vector2(0, 4), "Lv.%d %s" % [def.level, def.display_name], Palette.MIST)
	if flags & SnapshotFlags.MOB_SHOW_HP != 0 and not def.boss:
		WorldSkin.draw_monster_hp(ci, top + Vector2(0, -16), maxf(54.0, def.size.x * 1.1), hp)
	if stunned():
		_draw_stun(ci, top + Vector2(0, -44))

func stunned() -> bool:
	return flags & SnapshotFlags.MOB_STUNNED != 0 and not dead

## Stars circling over a stunned monster's head (`at`, on screen).
func _draw_stun(ci: CanvasItem, at: Vector2) -> void:
	var turn := Time.get_ticks_msec() * STUN_SPIN
	for i in STUN_STARS:
		var a := turn + TAU * i / STUN_STARS
		var p := at + Vector2(cos(a) * STUN_RADIUS, sin(a) * STUN_RADIUS * 0.35)
		var r := 5.0 + 1.5 * sin(a)
		ci.draw_circle(p, r + 2.0, Color(0.25, 0.15, 0.05, 0.8))
		ci.draw_circle(p, r, STUN_COLOR)

## Whether its name tag shows: only while it's hurt (its HP bar is up) or for a boss, so a
## field of monsters isn't a field of labels.
func shows_tag() -> bool:
	return known and not dead and (flags & SnapshotFlags.MOB_SHOW_HP != 0 or def.boss)

## Whether this is a living boss whose HP belongs on the boss bar.
func draws_boss_bar() -> bool:
	return def.boss and known and not dead
