class_name TDPlayer
extends Node2D
## Your own character. position is the point between the feet, in game pixels.
## Movement and climbing are hand-tuned platformer physics that run right here, so they
## feel instant; where you are goes to the server a few times a second. Attacks, portals,
## looting and potions are requests the server answers (see Net), and attacks are
## SkillDefs (see Game.SKILL_BINDINGS).

const HERO_FRAMES := preload("res://assets/animations/hero.tres")
const Z := TDStage.Z_PLAYER
## Ticks between telling the server where you are (60 / 3 = 20 a second).
const REPORT_EVERY := 3

var world: TDWorld
var vel := Vector2.ZERO
var face := 1
var on_ground := false
var platform: Platform = null
var climb: ClimbableDef = null
var hurtbox := Hitbox.new(Vector2(28, 64))

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
var loot_cd := 0      # ticks before the loot key asks for the next item
var _reported := &""  # the animation the server last heard about
var _swing := false   # restart the attack animation on the next frame

var rig: SpriteRig

func _ready() -> void:
	rig = SpriteRig.new()
	rig.setup(HERO_FRAMES, null, TDStage.TEXEL, 40.0)
	add_child(rig)

func place(x: float, y: float) -> void:
	position = Vector2(x, y)
	vel = Vector2.ZERO
	climb = null
	on_ground = true
	down = false
	platform = world.platforms[0]
	_report()

func is_climbing() -> bool:
	return climb != null

func fainted() -> bool:
	return down

## The server says you fainted. You lie there until it sends you back to town.
func faint() -> void:
	down = true
	climb = null

## The server says a monster hit you: blink, and get knocked away from it.
func knock_back(from_x: float) -> void:
	inv = 90
	if not is_climbing():
		vel = Vector2(-3.5 if position.x < from_x else 3.5, -4.5)
		on_ground = false

## The server didn't accept where you said you were, and puts you back.
func correct(at: Vector2) -> void:
	position = at
	vel = Vector2.ZERO

func level_up() -> void:
	cheer_t = 50

# ---------- per tick ----------

func step() -> void:
	if down:
		return
	for t in ["inv", "action_t", "cooldown", "grab_cd", "drop_t", "land_t", "cheer_t", "loot_cd"]:
		if get(t) > 0:
			set(t, get(t) - 1)
	_attacks()
	# hold the loot key to pick things up one after another
	if Input.is_action_pressed("loot") and loot_cd == 0 and not is_climbing():
		_report()
		Net.ask(&"req_loot")
		loot_cd = 8
	if not _interact():
		if is_climbing():
			_climb()
		elif not _grab_climbable():
			_move()
	if world.tick % REPORT_EVERY == 0 or _animation() != _reported:
		_report()

## Tells the server where you are and what you're doing.
func _report() -> void:
	_reported = _animation()
	Net.ask(&"req_move", [position, face, _reported, is_climbing()])

func _attacks() -> void:
	if is_climbing() or cooldown > 0:
		return
	for action in Game.SKILL_BINDINGS:
		if Input.is_action_just_pressed(action):
			_use(Content.skill(Game.SKILL_BINDINGS[action]))
			return

## Swings right away and asks the server to work out what it hits.
func _use(skill: SkillDef) -> void:
	if skill == null:
		return
	if Game.me.mp < skill.mp_cost:
		world.add_log("Not enough MP for %s." % skill.display_name, Color("8cc6ff"))
		return
	action_t = skill.action_ticks
	action_anim = skill.animation
	cooldown = skill.cooldown
	cheer_t = 0
	_swing = true
	Net.ask(&"req_skill", [skill.id, position, face])
	world.add_effect(skill.effect, position + Vector2(0, -40), face)

## Up on the ground: enter a portal, or talk to the NPC in front of you.
func _interact() -> bool:
	if not (Input.is_action_just_pressed("move_up") and on_ground):
		return false
	if world.layout.portal_at(position):
		_report()
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
	if Input.is_action_pressed("move_up"):
		position.y -= 2.6
	if Input.is_action_pressed("move_down"):
		position.y += 2.6
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	if Input.is_action_just_pressed("jump") and (left or right):
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
	if Input.is_action_pressed("move_up") and position.y > c.top + 1:
		climb = c
	elif Input.is_action_pressed("move_down") and on_ground and absf(position.y - c.top) < 3:
		climb = c
		position.y = c.top + 8
	else:
		return false
	position.x = c.x
	vel = Vector2.ZERO
	on_ground = false
	return true

func _move() -> void:
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var rooted := action_t > 0 and on_ground
	var acc := 0.8 if on_ground else 0.28
	var max_speed := 3.7 * CharacterStats.speed_multiplier(Game.me.stats)
	if left and not right and not rooted:
		vel.x = maxf(-max_speed, vel.x - acc)
		face = -1
	elif right and not left and not rooted:
		vel.x = minf(max_speed, vel.x + acc)
		face = 1
	else:
		vel.x *= 0.7 if on_ground else 0.98
	if absf(vel.x) < 0.05:
		vel.x = 0

	if Input.is_action_just_pressed("jump") and on_ground:
		if Input.is_action_pressed("move_down") and platform != null and not platform.solid:
			drop_from = platform
			drop_t = 16
			vel.y = 1
		else:
			vel.y = -9.8 * CharacterStats.jump_multiplier(Game.me.stats)
		on_ground = false

	vel.y = minf(vel.y + 0.5, 12.0)
	var prev_y := position.y
	var was_falling := vel.y > 4.0
	position.x = clampf(position.x + vel.x, 14.0, float(world.map.width) - 14.0)
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
				if was_falling:
					land_t = 6
				break
	if position.y > float(world.map.height):
		position.y = float(world.map.ground_y)
		vel.y = 0

# ---------- HD-2D visuals ----------

func _process(_delta: float) -> void:
	if rig == null or world == null or world.map == null:
		return
	rig.place(position, Z, NAN if is_climbing() or fainted() or not _over_ground() else _ground_y())
	rig.play(_animation(), _swing)
	_swing = false
	rig.face(1 if is_climbing() else face)
	if Game.me.job:
		rig.set_tint(Game.me.job.tint)
	rig.set_opacity(0.0 if inv > 0 and inv % 8 < 4 and not fainted() else 1.0)

func _animation() -> StringName:
	if fainted():
		return &"faint"
	if is_climbing():
		var moving := Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down")
		return climb.style.climb_animation if moving and climb.style else &"climb_idle"
	if action_t > 0:
		return action_anim
	if inv > 70: # just got hit (knock_back sets inv = 90)
		return &"hurt"
	if not on_ground:
		return &"jump" if vel.y < 0 else &"fall"
	if land_t > 0:
		return &"land"
	if cheer_t > 0:
		return &"level_up"
	if absf(vel.x) > 0.3:
		return &"walk"
	if Input.is_action_pressed("move_down"):
		return &"crouch"
	return &"idle"

func _over_ground() -> bool:
	return on_ground or _ground_y() - position.y < 200.0

## The top of whatever is under the feet (for the shadow).
func _ground_y() -> float:
	return world.layout.ground_below(position)
