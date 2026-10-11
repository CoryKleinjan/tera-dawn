class_name TDPlayer
extends Node2D
## Your own character. position is the point between the feet, in game pixels.
## Movement and climbing are hand-tuned platformer physics that run right here, so they
## feel instant; where you are goes to the server a few times a second. Attacks, portals,
## looting and potions are requests the server answers (see Net). The attack key uses the
## basic attack; the quickslot keys use whatever skill or item is on that slot.

const HERO_FRAMES := preload("res://assets/animations/hero.tres")
## The hero's size against everyone else's art (TDStage.TEXEL): a little smaller than the
## townsfolk (NPC art), so heroes read as young adventurers among grown-ups.
const HERO_SCALE := 0.8
## How tall he stands, feet to the top of his head, in game pixels at HERO_SCALE: speech
## bubbles and shop signs go just over it.
const HEIGHT := 78.0
## About how wide he is drawn, in game pixels: what the HUD keeps out of the way of.
const WIDTH := 48.0
## Where his light sits above his feet (game pixels).
const LIGHT_HEIGHT := 38.0
## A soft warm light that travels with every player, so heroes stand out from the scenery.
const LIGHT := Color(1.0, 0.86, 0.68)
const LIGHT_ENERGY := 0.55
const Z := TDStage.Z_PLAYER
## Ticks between telling the server where you are (60 / 3 = 20 a second).
const REPORT_EVERY := 3

# ---------- movement (game pixels and ticks) ----------
## Acceleration on the ground and in the air.
const ACCEL_GROUND := 0.8
const ACCEL_AIR := 0.28
## Top running speed, before the speed stat.
const RUN_SPEED := 3.7
## Share of the speed kept each tick with no direction held, on the ground and in the air.
const FRICTION_GROUND := 0.7
const FRICTION_AIR := 0.98
## Upward speed of a jump, before the jump stat.
const JUMP_SPEED := -9.8
const GRAVITY := 0.5
const MAX_FALL := 12.0
## Ticks spent falling through a platform after down + jump.
const DROP_TICKS := 16
## Ticks of the landing pose after a fall.
const LAND_TICKS := 6
## How much faster than his own jump takes off (game pixels a tick) he must be falling for
## touching down to show the landing pose: a drop from higher than a plain jump, not every hop.
const HARD_LANDING := 1.5
## Closest the feet get to the map's left and right edges.
const EDGE := 14.0
## Knockback speed when a monster hits you (away from it, and up).
const KNOCKBACK := Vector2(3.5, -4.5)
## Ticks of the hurt pose at the start of the invincibility after a hit.
const HURT_POSE_TICKS := 20
## Ticks of the level-up pose.
const CHEER_TICKS := 50
## Ticks between asking the server for the next item while the loot key is held.
const LOOT_EVERY := 4
## Ticks of the combat-ready stance after an attack, before he relaxes into idle.
const READY_TICKS := 120
## Ticks of the turn pose when he turns round while moving fast on the ground.
const TURN_TICKS := 5
## Ground speed above which turning round skids (kicks up dust and shows the turn pose).
const TURN_SPEED := 1.6
## Ticks at (nearly) top speed before the walk becomes a run.
const RUN_AFTER := 24
## Share of top speed that counts as running flat out.
const RUN_SHARE := 0.9
## Vertical speed under which a jump shows its top-of-the-arc pose.
const APEX_SPEED := 1.2
## The walk and run cycles play at their drawn speed at this ground speed (game pixels a
## tick), faster or slower in step with him, so his feet don't slide.
const STRIDE_SPEED := 3.7
## Your own sounds (Sound.play ids) and the jingle when you faint (Sound.jingle).
const JUMP_SOUND := &"jump"
const HURT_SOUND := &"hurt"
const PORTAL_SOUND := &"portal"
const FAINT_JINGLE := &"jingle_death"

var world: TDWorld
var vel := Vector2.ZERO
var face := 1
var on_ground := false
var platform: Platform = null
var climb: ClimbableDef = null
var hurtbox := Hitbox.new(SimPlayer.HURTBOX_SIZE)

var grab_cd := 0      # ticks before a rope can be grabbed again
var drop_from: Platform = null
var drop_t := 0       # ticks to fall through drop_from
var action_t := 0     # ticks left in the current attack pose
var action_anim := &"attack"
var cooldown := 0     # ticks before the next attack
var inv := 0          # invincibility (blinking) ticks after being hit
var down := false     # fainted, until the server sends you back to town
var land_t := 0       # ticks of the landing pose
var cheer_t := 0      # ticks of the level-up pose
var ready_t := 0      # ticks of the combat-ready stance left after an attack
var turn_t := 0       # ticks of the turn pose
var run_t := 0        # ticks spent at top speed (a run after RUN_AFTER)
var loot_cd := 0      # ticks before the loot key asks for the next item
## Coyote time and jump buffering (see JumpGrace).
var jump_grace := JumpGrace.new()
var _reported := &""  # the animation the server last heard about
var _swing := false   # restart the attack animation on the next frame
var speech := ""      # the last thing said in map chat, shown in a bubble
var speech_t := 0
var _stop_t := 0      # hit-stop ticks left (the swing holds still, see hit_stop)
## The chair you're sitting on (the server said so), or empty. Moving gets you up.
var sitting: StringName = &""

var rig: SpriteRig
## Your chair and pet.
var companion: TDCompanion

func _ready() -> void:
	rig = SpriteRig.new()
	rig.setup(HERO_FRAMES, null, TDStage.TEXEL * HERO_SCALE / Paperdoll.ART_SCALE)
	rig.add_light(LIGHT, LIGHT_ENERGY, LIGHT_HEIGHT)
	add_child(rig)
	companion = TDCompanion.new()
	add_child(companion)
	_dress()
	Game.character_changed.connect(_dress)

## Shows your look and the gear you wear (the server sends a new copy when it changes).
func _dress() -> void:
	if Game.me:
		rig.dress(Game.me.look())

func place(x: float, y: float) -> void:
	position = Vector2(x, y)
	vel = Vector2.ZERO
	climb = null
	on_ground = true
	down = false
	sitting = &""
	platform = world.platforms[0]
	jump_grace.cancel()
	_report()

func is_climbing() -> bool:
	return climb != null

func fainted() -> bool:
	return down

## The server says you fainted. You lie there until it sends you back to town.
func faint() -> void:
	down = true
	climb = null
	sitting = &""
	Sound.jingle(FAINT_JINGLE)

## The server sat you down on a chair (or got you up, with an empty id).
func sit(chair_id: StringName) -> void:
	sitting = chair_id
	if sitting != &"":
		vel = Vector2.ZERO
		action_t = 0

## Your blow landed: hold the swing still for a few ticks (hit-stop) so it reads as a hit.
func hit_stop(ticks: int) -> void:
	if ticks > 0:
		_stop_t = maxi(_stop_t, ticks)
		rig.freeze(true)

## The server says a monster hit you: blink, get knocked away from it, and the screen jolts.
func knock_back(from_x: float) -> void:
	world.shake(0.3)
	Sound.play(HURT_SOUND)
	inv = SimPlayer.HURT_INV
	if not is_climbing():
		vel = Vector2(-KNOCKBACK.x if position.x < from_x else KNOCKBACK.x, KNOCKBACK.y)
		on_ground = false
		jump_grace.cancel()

## The server didn't accept where you said you were, and puts you back.
func correct(at: Vector2) -> void:
	position = at
	vel = Vector2.ZERO

func level_up() -> void:
	cheer_t = CHEER_TICKS

# ---------- per tick ----------

func step() -> void:
	if _stop_t > 0:
		_stop_t -= 1
		if _stop_t == 0:
			rig.freeze(false)
	if speech_t > 0:
		speech_t -= 1
	if down:
		return
	if inv > 0:
		inv -= 1
	if action_t > 0:
		action_t -= 1
	elif ready_t > 0:
		ready_t -= 1
	if turn_t > 0:
		turn_t -= 1
	if cooldown > 0:
		cooldown -= 1
	if grab_cd > 0:
		grab_cd -= 1
	if drop_t > 0:
		drop_t -= 1
	if land_t > 0:
		land_t -= 1
	if cheer_t > 0:
		cheer_t -= 1
	if loot_cd > 0:
		loot_cd -= 1
	if not Game.me.buffs.is_empty():
		Game.me.tick_buffs() # the server ends them too; this keeps timers and speed in step
	if sitting != &"":
		# any move gets you up; the server sees you move and does the same
		for a in ["move_left", "move_right", "move_up", "move_down", "jump", "attack"]:
			if _held(a):
				sitting = &""
		if sitting != &"":
			if world.tick % REPORT_EVERY == 0 or _animation() != _reported:
				_report()
			return
	_attacks()
	# hold the loot key to pick up everything in reach, one item after another
	if _held("loot") and loot_cd == 0 and not is_climbing():
		_report()
		Net.ask(&"req_loot")
		loot_cd = LOOT_EVERY
	if not _interact():
		if is_climbing():
			_climb()
		elif not _grab_climbable():
			_move()
	if world.tick % REPORT_EVERY == 0 or _animation() != _reported:
		_report()

## Whether an input is held, unless typing or minding a shop.
func _held(action: StringName) -> bool:
	return not world.input_blocked() and Input.is_action_pressed(action)

func _tapped(action: StringName) -> bool:
	return not world.input_blocked() and Input.is_action_just_pressed(action)

## Tells the server where you are and what you're doing.
func _report() -> void:
	_reported = _animation()
	Net.ask(&"req_move", [position, face, _reported, is_climbing()])

func _attacks() -> void:
	# items on quickslots work even mid-swing or on a rope
	for i in Game.QUICKSLOT_ACTIONS.size():
		if _tapped(Game.QUICKSLOT_ACTIONS[i]):
			use_quickslot(i)
			return
	if _tapped("attack"):
		_use(Game.me.basic_attack())

## Does what's on quickslot `i`: a skill, or the first stack of an item.
func use_quickslot(i: int) -> void:
	var q: Array = Game.me.quickslots[i]
	if q.is_empty():
		return
	if q[0] == &"item":
		var item: ItemDef = Content.items.get(q[1])
		var slot := Game.me.inventory.find(item)
		if slot >= 0:
			Net.ask(&"req_setup" if item.tab() == ItemDef.Tab.SETUP else &"req_use_item", [slot])
		return
	_use(Content.skills.get(q[1]))

## Swings right away and asks the server to work out what it hits (or casts a buff).
func _use(skill: SkillDef) -> void:
	if skill == null or is_climbing() or cooldown > 0:
		return
	var problem := Game.me.use_problem(skill)
	if problem != "":
		world.add_log(problem, Palette.INFO)
		return
	cooldown = skill.cooldown
	var anim := WeaponStyle.animation_for(Game.me.look(), skill.animation)
	if WeaponStyle.is_spell(anim):
		# buffs and spells make no motion: he flashes the skill's colour and carries on
		rig.pulse(skill.flash_color())
	else:
		action_t = skill.action_ticks
		action_anim = anim
		ready_t = READY_TICKS
		cheer_t = 0
		_swing = true
	Net.ask(&"req_skill", [skill.id, position, face])
	world.add_effect(skill.effect, position + Vector2(0, -40), face)
	Sound.play(skill.cast_sound())

## Up on the ground: enter a portal, or talk to the NPC in front of you.
func _interact() -> bool:
	if not (_tapped("move_up") and on_ground):
		return false
	if world.layout.portal_at(position):
		_report()
		# fade out before asking: a local server answers at once, and the next map's
		# fade-in (TDWorld.enter_map) must come after this
		world.stage.fade_to(1.0)
		Sound.play(PORTAL_SOUND)
		Net.ask(&"req_portal")
		return true
	var npc := world.npc_near(position)
	if npc:
		npc.talk()
		face = 1 if npc.position.x > position.x else -1
		return true
	return false

func _climb() -> void:
	vel = Vector2.ZERO
	if _held("move_up"):
		position.y -= 2.6
	if _held("move_down"):
		position.y += 2.6
	var left := _held("move_left")
	var right := _held("move_right")
	if _tapped("jump") and (left or right):
		var dir := -1 if left else 1
		climb = null
		grab_cd = 20
		vel = Vector2(3.0 * dir, -5.5)
		face = dir
	elif position.y <= climb.top:
		position.y = climb.top
		_leave_climb()
	elif position.y >= climb.bottom:
		position.y = climb.bottom
		_leave_climb()

func _leave_climb() -> void:
	climb = null
	on_ground = true
	grab_cd = 10
	for pl in world.platforms:
		if pl.contains_x(position.x) and absf(pl.y - position.y) < 1.0:
			platform = pl

func _grab_climbable() -> bool:
	if grab_cd > 0:
		return false
	var c := world.layout.climbable_near(position)
	if c == null:
		return false
	if _held("move_up") and on_ground and world.npc_near(position):
		return false # Up next to someone talks to them (see _interact)
	if _held("move_up") and position.y > c.top + 1:
		climb = c
	elif _held("move_down") and on_ground and absf(position.y - c.top) < 3:
		climb = c
		position.y = c.top + 8
	else:
		return false
	position.x = c.x
	vel = Vector2.ZERO
	on_ground = false
	jump_grace.cancel()
	return true

func _move() -> void:
	var left := _held("move_left")
	var right := _held("move_right")
	var rooted := action_t > 0 and on_ground
	var acc := ACCEL_GROUND if on_ground else ACCEL_AIR
	var max_speed := RUN_SPEED * CharacterStats.speed_multiplier(Game.me.stats)
	var was_face := face
	if left and not right and not rooted:
		vel.x = maxf(-max_speed, vel.x - acc)
		face = -1
	elif right and not left and not rooted:
		vel.x = minf(max_speed, vel.x + acc)
		face = 1
	else:
		vel.x *= FRICTION_GROUND if on_ground else FRICTION_AIR
	if absf(vel.x) < 0.05:
		vel.x = 0
	if face != was_face and on_ground and absf(vel.x) > TURN_SPEED:
		turn_t = TURN_TICKS
		world.fx.dust(position, -face, 5)
	run_t = run_t + 1 if on_ground and absf(vel.x) >= max_speed * RUN_SHARE else 0

	# a jump works a few ticks after walking off a ledge, and a press just before
	# landing goes off on landing (see JumpGrace); dropping through needs footing
	if _tapped("jump"):
		jump_grace.press()
	if jump_grace.can_jump(on_ground):
		jump_grace.cancel()
		if on_ground and _held("move_down") and platform != null and not platform.solid:
			drop_from = platform
			drop_t = DROP_TICKS
			vel.y = 1
		else:
			vel.y = JUMP_SPEED * CharacterStats.jump_multiplier(Game.me.stats)
			Sound.play(JUMP_SOUND)
		on_ground = false

	vel.y = minf(vel.y + GRAVITY, MAX_FALL)
	var prev_y := position.y
	var hard_landing := vel.y > -JUMP_SPEED * CharacterStats.jump_multiplier(Game.me.stats) + HARD_LANDING
	var was_falling := vel.y > 4.0
	position.x = clampf(position.x + vel.x, EDGE, float(world.map.width) - EDGE)
	position.y += vel.y
	on_ground = false
	if vel.y >= 0:
		for pl in world.platforms:
			if pl == drop_from and drop_t > 0:
				continue
			if pl.contains_x(position.x) and prev_y <= pl.y and position.y >= pl.y:
				position.y = pl.y
				vel.y = 0
				on_ground = true
				platform = pl
				if hard_landing:
					land_t = LAND_TICKS
				if was_falling:
					world.fx.dust(position, 0, 6 if hard_landing else 3)
				break
	if position.y > float(world.map.height):
		position.y = float(world.map.ground_y)
		vel.y = 0
	jump_grace.step(on_ground)

# ---------- HD-2D visuals ----------

func _process(_delta: float) -> void:
	if rig == null or world == null or world.map == null:
		return
	var at := world.drawn(self)
	rig.place(at + Vector2(0, -companion.seat_lift()), Z)
	var anim := _animation()
	rig.play(anim, _swing)
	rig.set_speed(stride_speed(anim, vel.x))
	_swing = false
	rig.face(1 if is_climbing() else face)
	rig.set_opacity(0.0 if inv > 0 and inv % 8 < 4 and not fainted() else 1.0)
	companion.set_chair(sitting)
	companion.set_pet(Game.me.pet, position)
	companion.follow(at, face, Z, world.layout.ground_below(position))

func _animation() -> StringName:
	if fainted():
		return &"faint"
	if sitting != &"":
		return &"sit"
	if is_climbing():
		var moving := _held("move_up") or _held("move_down")
		return climb.style.climb_animation if moving and climb.style else &"climb_idle"
	if action_t > 0:
		return action_anim
	if inv > SimPlayer.HURT_INV - HURT_POSE_TICKS and inv <= SimPlayer.HURT_INV: # just got hit (see knock_back)
		return &"hurt"
	if not on_ground:
		if absf(vel.y) < APEX_SPEED:
			return &"jump_apex"
		return &"jump" if vel.y < 0 else &"fall"
	if land_t > 0:
		return &"land"
	if cheer_t > 0:
		return &"level_up"
	if turn_t > 0:
		return &"turn"
	if absf(vel.x) > 0.3:
		return &"run" if run_t >= RUN_AFTER else &"walk"
	if _held("move_down"):
		return &"crouch"
	if ready_t > 0:
		return &"ready"
	return &"idle"

## How fast an animation plays for a ground speed: walking and running keep step with him.
static func stride_speed(anim: StringName, speed_x: float) -> float:
	if anim in [&"walk", &"run"]:
		return clampf(absf(speed_x) / STRIDE_SPEED, 0.55, 1.4)
	return 1.0
