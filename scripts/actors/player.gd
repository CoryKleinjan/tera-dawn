class_name TDPlayer
extends Node2D
## Your own character. position is the point between the feet, in game pixels.
## Movement and climbing are hand-tuned platformer physics that run right here, so they
## feel instant. They are snappy, Hollow Knight style: he starts and stops at once, steers
## freely in the air, hops short when jump is let go early and falls faster than he rises.
## Where you are goes to the server a few times a second. Attacks, portals, looting and
## potions are requests the server answers (see Net). The attack key uses the basic attack;
## the quickslot keys use whatever skill or item is on that slot. Holding Up or Down (in the
## air) aims an attack that way.

## How tall he stands, feet to the top of his head, in game pixels at HeroBody.SCALE: speech
## bubbles and shop signs go just over it.
const HEIGHT := 68.0
## About how wide he is drawn, in game pixels: what the HUD keeps out of the way of.
const WIDTH := 42.0
## His chest above his feet (game pixels): where skill effects and shots start, and where
## loot flies to.
const CHEST := SimPlayer.CHEST
const Z := TDStage.Z_PLAYER
## Ticks between telling the server where you are (60 / 3 = 20 a second).
const REPORT_EVERY := 3

# ---------- movement (game pixels and ticks) ----------
## Acceleration on the ground and in the air.
const ACCEL_GROUND := 1.4
const ACCEL_AIR := 0.9
## Top running speed, before the speed stat.
const RUN_SPEED := 3.7
## Share of the speed kept each tick with no direction held, on the ground and in the air.
const FRICTION_GROUND := 0.45
const FRICTION_AIR := 0.7
## Upward speed of a jump, before the jump stat.
const JUMP_SPEED := -9.8
## Gravity while rising, and the stronger pull once falling.
const GRAVITY := 0.5
const FALL_GRAVITY := 0.62
const MAX_FALL := 12.0
## Letting go of jump while still rising faster than this cuts the jump short (a hop).
const JUMP_CUT := -3.0
## Upward speed of the bounce off a monster hit by a downward blow (pogo).
const POGO_SPEED := -8.5
## How fast your own landed melee blow pushes you back (game pixels a tick), and for how
## many ticks (without steering).
const RECOIL := 2.5
const RECOIL_TICKS := 4
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
const KNOCKBACK := Vector2(4.5, -4.0)
## Ticks the knockback carries you without steering, and the freeze before it (the whole
## hero holds still for a beat so the hit reads).
const HURT_LOCK := 9
const HURT_FREEZE := 4
## How strongly the screen flashes when you're hit, and in what colour.
const HURT_FLASH := 0.35
const HURT_FLASH_COLOR := Color(1.0, 0.85, 0.8)
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
## Ticks at (nearly) top speed before he picks up pace (he keeps walking, just faster).
const RUN_AFTER := 24
## Share of top speed that counts as moving flat out.
const RUN_SHARE := 0.9
## Extra top speed once he has picked up pace, as a share of RUN_SPEED.
const PACE_BONUS := 0.15
## Ticks the extra speed takes to build up fully, so it isn't a jolt.
const PACE_RAMP := 12
## Vertical speed under which a jump shows its top-of-the-arc pose.
const APEX_SPEED := 1.2
## Your own sounds (Sound.play ids) and the jingle when you faint (Sound.jingle).
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
## Skill id -> ticks before that skill can be used again (SkillDef.recharge), as the server keeps.
var recharge := {}
var inv := 0          # invincibility (blinking) ticks after being hit
var down := false     # fainted, until the server sends you back to town
var land_t := 0       # ticks of the landing pose
var cheer_t := 0      # ticks of the level-up pose
var ready_t := 0      # ticks of the combat-ready stance left after an attack
var turn_t := 0       # ticks of the turn pose
var run_t := 0        # ticks spent at top speed (faster after RUN_AFTER, see _top_speed)
var loot_cd := 0      # ticks before the loot key asks for the next item
## A cutscene walking you: -1 left, 1 right, 0 not (your keys don't work meanwhile).
var auto_walk := 0
## A cutscene holding you in a pose (CutsceneStep.Kind.POSE), or empty.
var scene_pose := &""
## Coyote time and jump buffering (see JumpGrace).
var jump_grace := JumpGrace.new()
var _reported := &""  # the animation the server last heard about
var speech := ""      # the last thing said in map chat, shown in a bubble
var speech_t := 0
var _stop_t := 0      # hit-stop ticks left (the swing holds still, see hit_stop)
var _freeze_t := 0    # ticks held still after being hit (see knock_back)
var _lock_t := 0      # ticks the knockback carries you without steering
var _jumping := false # rising from your own jump (letting go cuts it short)
var _aim := Hitbox.Aim.AHEAD  # which way the current attack aims
## The chair you're sitting on (the server said so), or empty. Moving gets you up.
var sitting: StringName = &""

## How you're drawn: the rig, your chair and pet (see HeroBody).
var body: HeroBody
var rig: SpriteRig:
	get:
		return body.rig if body else null
var companion: TDCompanion:
	get:
		return body.companion if body else null

func _ready() -> void:
	body = HeroBody.new(self, world, Z)
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
	world.stage.flash_screen(HURT_FLASH_COLOR, HURT_FLASH)
	# a steadying buff (Iron Body) keeps you on your feet
	if not is_climbing() and not Game.me.skills.steady():
		vel = Vector2(-KNOCKBACK.x if position.x < from_x else KNOCKBACK.x, KNOCKBACK.y)
		on_ground = false
		run_t = 0
		_jumping = false
		_freeze_t = HURT_FREEZE
		_lock_t = HURT_LOCK
		jump_grace.cancel()

## Your melee blow ahead landed: a little push back. (A downward blow already bounced you,
## see _use.)
func recoil() -> void:
	if _aim == Hitbox.Aim.AHEAD and not is_climbing():
		vel.x = -face * RECOIL
		_lock_t = maxi(_lock_t, RECOIL_TICKS)

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
	if _freeze_t > 0:
		# just hit: hold still for a beat (timers keep running on the server)
		_freeze_t -= 1
		if world.tick % REPORT_EVERY == 0:
			_report()
		return
	if action_t > 0:
		action_t -= 1
	elif ready_t > 0:
		ready_t -= 1
	if turn_t > 0:
		turn_t -= 1
	if cooldown > 0:
		cooldown -= 1
	if not recharge.is_empty():
		SimPlayer.tick_recharge(recharge)
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
	if not Game.me.skills.buffs.is_empty():
		Game.me.skills.tick_buffs() # the server ends them too; this keeps timers and speed in step
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
		_use(Game.me.skills.basic_attack())

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

## Which way an attack goes if used now: up while Up is held, down while Down is held in
## the air, else ahead.
func _held_aim() -> Hitbox.Aim:
	if _held("move_up"):
		return Hitbox.Aim.UP
	if _held("move_down") and not on_ground:
		return Hitbox.Aim.DOWN
	return Hitbox.Aim.AHEAD

## Swings right away and asks the server to work out what it hits (or casts a buff).
## A downward melee blow that meets a monster bounces you straight off it.
func _use(skill: SkillDef) -> void:
	if skill == null or is_climbing() or cooldown > 0 or recharge.has(skill.id):
		return
	var problem := Game.me.skills.use_problem(skill)
	if problem != "":
		world.add_log(problem, Palette.INFO)
		return
	cooldown = CharacterStats.attack_ticks(skill.cooldown, Game.me.stats)
	var lvl := Game.me.skills.level(skill)
	if skill.recharge_ticks(lvl) > 0:
		recharge[skill.id] = skill.recharge_ticks(lvl)
	var aim := skill.aim_for(_held_aim())
	# buffs and spells make no motion: he flashes the skill's colour and carries on
	var anim := body.use_skill(Game.me.look(), skill)
	if anim != &"":
		action_t = CharacterStats.attack_ticks(skill.action_ticks, Game.me.stats)
		action_anim = anim
		ready_t = READY_TICKS
		cheer_t = 0
		_aim = aim
	if aim == Hitbox.Aim.DOWN and not skill.is_ranged() and _meets_monster(skill, aim):
		vel.y = POGO_SPEED
		_jumping = false
	Net.ask(&"req_skill", [skill.id, position, face, aim])
	world.add_effect(skill.effect, TDWorldFx.swing_point(position, face, aim), face, null, aim)
	Sound.play(skill.cast_sound())

## Whether `skill` aimed `aim` from here meets a living monster, as this screen shows them
## (the server decides the damage; this only lets the bounce happen at once).
func _meets_monster(skill: SkillDef, aim: Hitbox.Aim) -> bool:
	var area := Hitbox.aimed_area(position, face, aim, skill.reach, skill.height)
	for m in world.mobs():
		if not m.dead and area.intersects(Hitbox.new(m.def.size).rect_at(m.body_position())):
			return true
	return false

## Up on the ground: enter a portal, or talk to the NPC in front of you.
func _interact() -> bool:
	if not (_tapped("move_up") and on_ground):
		return false
	var portal := world.layout.portal_at(position)
	if portal and portal.open_to(Game.me):
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

## The pull of gravity on someone moving up or down at `vy`: stronger once falling, so a
## jump drops back faster than it rose (MapReach runs the same rule).
static func gravity(vy: float) -> float:
	return FALL_GRAVITY if vy >= 0.0 else GRAVITY

## Top ground speed: `base` at first, rising by PACE_BONUS over PACE_RAMP ticks once he
## has kept moving flat out for RUN_AFTER ticks.
func _top_speed(base: float) -> float:
	var built := clampf(float(run_t - RUN_AFTER) / PACE_RAMP, 0.0, 1.0)
	return base * (1.0 + PACE_BONUS * built)

func _move() -> void:
	var left := _held("move_left") or auto_walk < 0
	var right := _held("move_right") or auto_walk > 0
	# knocked back (or recoiling from your own blow): carried along without steering
	var rooted := _lock_t > 0
	if _lock_t > 0:
		_lock_t -= 1
	var acc := ACCEL_GROUND if on_ground else ACCEL_AIR
	var base_speed := RUN_SPEED * CharacterStats.speed_multiplier(Game.me.stats)
	var max_speed := _top_speed(base_speed)
	var was_face := face
	# mid-swing he keeps facing the way he swung, even moving the other way
	var turns := action_t == 0
	if left and not right and not rooted:
		vel.x = maxf(-max_speed, vel.x - acc)
		if turns:
			face = -1
	elif right and not left and not rooted:
		vel.x = minf(max_speed, vel.x + acc)
		if turns:
			face = 1
	elif not rooted:
		vel.x *= FRICTION_GROUND if on_ground else FRICTION_AIR
	if absf(vel.x) < 0.05:
		vel.x = 0
	if face != was_face and on_ground and absf(vel.x) > TURN_SPEED:
		turn_t = TURN_TICKS
		world.fx.dust(position, -face, 5)
	# the pace builds on the ground and carries through a jump; stopping or turning loses it
	if absf(vel.x) < base_speed * RUN_SHARE or (left == right) or rooted:
		run_t = 0
	elif on_ground:
		run_t += 1

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
			_jumping = true
		on_ground = false
	# letting go of jump on the way up turns it into a short hop
	if _jumping and not _held("jump") and vel.y < JUMP_CUT:
		vel.y = JUMP_CUT
	if vel.y >= 0.0:
		_jumping = false

	vel.y = minf(vel.y + gravity(vel.y), MAX_FALL)
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
	if body == null or world == null or world.map == null:
		return
	var anim := _animation()
	body.veil = HeroBody.HIDDEN_VEIL if Game.me.skills.hidden() else 1.0
	body.draw(anim, HeroBody.stride_speed(anim, vel.x), face, is_climbing(), inv > 0 and not fainted(), inv, sitting, Game.me.pet)

func _animation() -> StringName:
	if scene_pose != &"":
		return scene_pose
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
		return &"walk" # a faster pace just speeds up the walk (see HeroBody.stride_speed)
	if _held("move_down"):
		return &"crouch"
	if ready_t > 0:
		return &"ready"
	return &"idle"
