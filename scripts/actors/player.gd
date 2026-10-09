class_name TDPlayer
extends Node2D
## The player character. position is the point between the feet, in game pixels.
## Movement and climbing are hand-tuned platformer physics; attacks are SkillDefs
## (see Game.SKILL_BINDINGS) resolved by the world.

const HERO_FRAMES := preload("res://assets/animations/hero.tres")
const Z := TDStage.Z_PLAYER
const FAINT_TICKS := 150

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
var inv := 0          # invincibility ticks after being hit
var faint_t := 0      # ticks left lying fainted
var land_t := 0       # ticks of the landing pose
var cheer_t := 0      # ticks of the level-up pose
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
	platform = world.platforms[0]

func is_climbing() -> bool:
	return climb != null

func fainted() -> bool:
	return faint_t > 0

func faint() -> void:
	faint_t = FAINT_TICKS
	climb = null

func level_up() -> void:
	cheer_t = 50

# ---------- per tick ----------

func step() -> void:
	if faint_t > 0:
		faint_t -= 1
		if faint_t == 0:
			_revive()
		return
	for t in ["inv", "action_t", "cooldown", "grab_cd", "drop_t", "land_t", "cheer_t"]:
		if get(t) > 0:
			set(t, get(t) - 1)
	if world.tick % 120 == 0:
		Game.health.heal(2 + Game.level / 3)
		Game.mp = mini(Game.max_mp(), Game.mp + 2 + Game.level / 4)

	_attacks()
	if _interact():
		return
	if is_climbing():
		_climb()
		return
	if _grab_climbable():
		return
	_move()

func _revive() -> void:
	Game.health.reset(Game.max_hp())
	Game.health.set_hp(ceili(Game.max_hp() / 2.0))
	Game.mp = ceili(Game.max_mp() / 2.0)
	inv = 120
	world.load_map(Game.START_MAP)

func _attacks() -> void:
	if is_climbing() or cooldown > 0:
		return
	for action in Game.SKILL_BINDINGS:
		if Input.is_action_just_pressed(action):
			_use(Content.skill(Game.SKILL_BINDINGS[action]))
			return

func _use(skill: SkillDef) -> void:
	if skill == null:
		return
	if not Game.spend_mp(skill.mp_cost):
		world.add_log("Not enough MP for %s." % skill.display_name, Color("8cc6ff"))
		return
	action_t = skill.action_ticks
	action_anim = skill.animation
	cooldown = skill.cooldown
	cheer_t = 0
	_swing = true
	world.use_skill(skill)
	world.add_effect(skill.effect, position + Vector2(0, -40), face)

## Up on the ground: enter a portal, or talk to the NPC in front of you.
func _interact() -> bool:
	if not (Input.is_action_just_pressed("move_up") and on_ground):
		return false
	var portal := world.portal_at(position)
	if portal:
		world.load_map(portal.target_map, portal.target_x)
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
	var c := world.climbable_near(position)
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
	var max_speed := 3.7
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
			vel.y = -9.8
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
	rig.set_opacity(0.0 if inv > 0 and inv % 8 < 4 and not fainted() else 1.0)

func _animation() -> StringName:
	if fainted():
		return &"faint"
	if is_climbing():
		var moving := Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down")
		return climb.style.climb_animation if moving and climb.style else &"climb_idle"
	if action_t > 0:
		return action_anim
	if inv > 70: # just got hit (the world sets inv = 90)
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
	var best := float(world.map.ground_y)
	for pl in world.platforms:
		if pl.contains_x(position.x) and pl.y >= position.y - 1.0 and pl.y < best:
			best = pl.y
	return best
