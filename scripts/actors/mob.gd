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
## Tint for a root on it (moss green), code-drawn until painted effects.
const ROOT_TINT := Color(0.75, 1.05, 0.7)
## Stunned (SkillDef.stun): code-drawn stars circling over its head until painted effects
## replace them: how many, how wide their circle (screen pixels), how fast they go round.
const STUN_STARS := 3
const STUN_RADIUS := 20.0
const STUN_SPIN := 0.006
const STUN_COLOR := Color(1.0, 0.92, 0.45)
## How fast a flier drops to the ground when slammed and rises again after (share per tick).
const DOWN_SPEED := 0.2
## Physics ticks a hit flashes the monster white: one short flash per hit, not a strobe.
const HIT_FLASH_TICKS := 5
## Ticks a defeated boss stays on screen: its whole death animation, then the fade
## (others take SimMob.DEATH_FADE_TICKS).
const BOSS_DEATH_TICKS := 120
## Code-side motion on top of the painted frames (it only moves the whole picture):
## how much the walk speeds up or slows with how fast it really moves (so feet don't
## slide), the stretch on take-off and squash on landing, the idle's breathing (share of
## its height, and how fast), how far a strike lurches forward (game pixels), the lean back
## when hurt and the topple of a defeated monster (radians), how far that topple slides it
## back (game pixels), and how long a respawned monster takes to pop up (seconds).
const WALK_PACE := Vector2(0.75, 1.8)
const TAKEOFF_STRETCH := 0.7
const LAND_SQUASH := 0.8
const BREATH := 0.025
const BREATH_RATE := 0.6
const STRIKE_LURCH := 8.0
const HURT_TILT := 0.14
const DEATH_TILT := 1.25
const DEATH_SLIDE := 18.0
const SPAWN_POP_TIME := 0.3

var world: TDWorld
var index := 0
var def: MonsterDef
var plat: Platform
var target := Vector2.ZERO
var dir := 1
var hp := 1.0
var flags := 0
## The move it is using: 1 + its index in def.moves, 0 for none.
var move := 0
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
var _flash_until := 0   # physics tick the current hit flash ends on
var _was_hurt := false
## How visible it is (fades out and in for a blink), and whether it shows its second wind.
var _fade := 1.0
## The tint last given to the rig (see _tint).
var _tinted := Color.WHITE
## How much of a flier's hover it shows: 0 while a slam holds it down (SkillDef.slam).
var _hover := 1.0
## How fast it really moved last tick (game pixels), for the walk's pace.
var _pace := 0.0
## The way the last hit pushed it (1 or -1): it flinches and falls away from that.
var _push := 0
## How far a strike has thrown it forward (game pixels, fading) and the tilt it shows now.
var _lurch := 0.0
var _tilt := 0.0
## Seconds since it (re)appeared, for the spawn pop; flags last frame, for take-offs,
## landings and strikes starting.
var _shown_t := SPAWN_POP_TIME
var _last_flags := 0

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
	move = state[5] if state.size() > 5 else 0
	if not known or (was_dead and not dead) or (was_hidden and flags & SnapshotFlags.MOB_HIDDEN == 0):
		position = target # first sight, back from the dead or from a blink: no gliding in
		death_t = 0
		if was_dead and not dead:
			_shown_t = 0.0 # respawned: pop up
	if dead and not was_dead and known:
		death_t = death_ticks()
	known = true

## The server says it was defeated: start fading out now rather than at the next snapshot.
func kill() -> void:
	if not dead:
		flags |= SnapshotFlags.MOB_DEAD
		death_t = death_ticks()

## Ticks it takes to fall and fade out once defeated.
func death_ticks() -> int:
	return BOSS_DEATH_TICKS if def.boss else SimMob.DEATH_FADE_TICKS

## It was hit (by an attack facing `face`): a squash, a small push back and, for your own
## hits, a few frames of hit-stop so the blow lands.
func hit_react(face: int, stop_ticks := 0) -> void:
	_recoil = 6.0 * face
	if face != 0:
		_push = face
	_stop_t = maxi(_stop_t, stop_ticks)
	_flash_until = Engine.get_physics_frames() + HIT_FLASH_TICKS
	if rig:
		rig.squash(1.0)

## Feet position including the hover height of flying monsters.
func body_position() -> Vector2:
	return position + SimMob.hover_offset(def, phase) * _hover

## body_position() where it is drawn this frame (between ticks, see TDWorld.drawn), with
## its hit recoil.
func drawn_body_position() -> Vector2:
	return world.drawn(self) + SimMob.hover_offset(def, phase) * _hover + Vector2(_recoil + _lurch, 0)

func step() -> void:
	_recoil *= 0.75
	_lurch *= 0.8
	if _stop_t > 0:
		# hit-stop: hold still for a moment
		_stop_t -= 1
		if rig:
			rig.freeze(_stop_t > 0)
		return
	phase += 0.08
	var was := position.x
	position += (target - position) * FOLLOW
	_pace = absf(position.x - was)
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

func _process(delta: float) -> void:
	if rig == null or world == null:
		return
	rig.visible = known and (not dead or death_t > 0)
	if not rig.visible:
		return
	var fallen := dead and incoming <= 0
	var hidden := flags & SnapshotFlags.MOB_HIDDEN != 0
	_fade = move_toward(_fade, 0.0 if hidden else 1.0, 0.25)
	rig.set_opacity(clampf(death_t / 30.0, 0.0, 1.0) if fallen else _fade)
	# a short white flash when a hit lands (hit_react), or when the server says it was hurt
	var hurt := flags & SnapshotFlags.MOB_HURT != 0
	if hurt and not _was_hurt:
		_flash_until = maxi(_flash_until, Engine.get_physics_frames() + HIT_FLASH_TICKS)
	_was_hurt = hurt
	rig.set_flash(Engine.get_physics_frames() < _flash_until)
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
	var mv := current_move()
	var windup := StringName(String(mv.animation_name()) + "_windup") if mv else &""
	var recover := StringName(String(mv.animation_name()) + "_recover") if mv else &""
	var roar := &"phase" if flags & SnapshotFlags.MOB_ENRAGED != 0 else &"intro"
	if fallen:
		rig.play(&"die")
	elif flags & SnapshotFlags.MOB_TOSSED != 0:
		rig.play(&"knock_up")
	elif flags & (SnapshotFlags.MOB_FLOORED | SnapshotFlags.MOB_DOWNED) != 0:
		rig.play(&"knock_down")
	elif flags & SnapshotFlags.MOB_CASTING != 0:
		rig.play(mv.animation_name() if mv and rig.has(mv.animation_name()) else &"attack")
	elif flags & SnapshotFlags.MOB_ROARING != 0:
		# a boss's intro or second-wind roar
		rig.play(roar if rig.has(roar) else &"attack")
	elif mv and not winding and rig.has(recover):
		# getting its balance back after a move
		rig.play(recover)
	elif hurt or stunned:
		rig.play(&"hurt")
	elif winding and rig.has(windup):
		rig.play(windup)
	elif winding:
		rig.play(&"idle")
		lean = Vector2(-facing * LEAN, 0)
	elif flags & SnapshotFlags.MOB_AIRBORNE != 0 and rig.has(&"jump"):
		rig.play(&"jump")
	elif moving:
		rig.play(&"move")
	else:
		rig.play(&"idle")
	_animate(facing, fallen, delta)
	rig.place(drawn_body_position() + lean, z)

## The code-side motion over its painted frames: the walk keeping pace, a stretch on
## take-off and squash on landing, a lurch into each strike, breathing at idle, a flinch
## when hurt, a topple when defeated and a pop when it appears. It only moves, stretches
## and tilts the whole picture, never repaints it.
func _animate(facing: int, fallen: bool, delta: float) -> void:
	var started := flags & ~_last_flags
	var ended := _last_flags & ~flags
	_last_flags = flags
	_shown_t += delta
	if started & SnapshotFlags.MOB_AIRBORNE:
		rig.stretch(TAKEOFF_STRETCH)
	elif ended & SnapshotFlags.MOB_AIRBORNE:
		rig.squash(LAND_SQUASH)
	if started & SnapshotFlags.MOB_CASTING and not dead:
		_lurch = STRIKE_LURCH * facing
		rig.squash(0.6)
	var walking := rig.current == &"move" and def.speed > 0.0
	rig.set_speed(clampf(_pace / def.speed, WALK_PACE.x, WALK_PACE.y) if walking else 1.0)
	var scale := Vector2.ONE
	var tilt := 0.0
	var away := _push if _push != 0 else -facing
	if fallen and not def.boss:
		# knocked over backwards, sliding a little, as it fades (bosses paint their own fall)
		var t := 1.0 - float(death_t) / float(death_ticks())
		var fall := ease(clampf(t * 2.0, 0.0, 1.0), 0.5)
		tilt = away * DEATH_TILT * fall
		_lurch = away * DEATH_SLIDE * fall
	elif rig.current == &"hurt":
		tilt = away * HURT_TILT
	elif rig.current == &"idle" and not stunned():
		# phase gains 0.08 a tick: this breathes BREATH_RATE times a second
		var b := sin(phase / (0.08 * 60.0) * BREATH_RATE * TAU)
		scale = Vector2(1.0 - b * BREATH * 0.6, 1.0 + b * BREATH)
	_tilt = lerpf(_tilt, tilt, 0.35)
	if _shown_t < SPAWN_POP_TIME:
		# appearing: grows up out of the ground with a little overshoot
		var k := ease(_shown_t / SPAWN_POP_TIME, 0.4)
		var grow := 0.4 + 0.6 * k + sin(k * PI) * 0.12
		scale *= Vector2(grow, grow)
	rig.set_pose(scale, _tilt)

## The move it is using right now, or null.
func current_move() -> MonsterMove:
	return def.moves[move - 1] if move > 0 and move <= def.moves.size() else null

## Its own tint, warmed when enraged and coloured by a root on it.
func _tint() -> Color:
	var out := def.tint
	if flags & SnapshotFlags.MOB_ENRAGED != 0:
		out *= RAGE_TINT
	if flags & SnapshotFlags.MOB_ROOTED != 0:
		out *= ROOT_TINT
	return out

## HP bar and name tag, drawn by the overlay at this monster's projected screen position
## (the tag goes in `tags`, which keeps tags apart). A boss's HP is on the boss bar at the
## top of the screen instead (see draws_boss_bar).
func draw_tag(ci: CanvasItem, at: Vector2, top: Vector2, tags: TDNameTags) -> void:
	if dead or not known:
		return
	if shows_tag():
		tags.add_name(at + Vector2(0, 4), def.display_name, Palette.MIST)
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
