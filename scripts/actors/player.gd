class_name TDPlayer
extends Node2D
## Your own character. position is the point between the feet, in game pixels.
## Movement is hand-tuned platformer physics that runs right here, so it
## feels instant. It is snappy, Hollow Knight style: he starts and stops at once, steers
## freely in the air, hops short when jump is let go early and falls faster than he rises.
## Where you are goes to the server a few times a second. Attacks, portals, looting and
## potions are requests the server answers (see Net). The attack key uses the basic attack;
## the quickslot keys use whatever skill or item is on that slot. Holding Up or Down (in the
## air) aims an attack that way.

## How tall he stands, feet to the top of his head, in game pixels: speech bubbles go just
## over it (his looks stand about this tall, HeroLookDef).
const HEIGHT := 80.0
## About how wide he is, in game pixels: what the HUD keeps out of the way of.
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
## Moves from boss relics (RelicDef.Move). A Dash's speed (game pixels a tick), how many
## ticks it lasts, and the wait before the next one on the ground (in the air it works once
## per jump). It goes 180 px, well past what a Double Jump carries you sideways (about 137),
## so a far ledge can need a Dash alone.
const DASH_SPEED := 20.0
const DASH_TICKS := 9
const DASH_COOLDOWN := 24
## A double jump's upward speed, as a share of a plain jump's.
const DOUBLE_JUMP_SHARE := 1.0
## How fast a Slam drops (game pixels a tick), and how hard the screen jolts when it lands.
const SLAM_SPEED := 14.0
const SLAM_SHAKE := 0.4
## Ticks of holding a Surge's charge before it can fly, its speed and its longest flight.
const SURGE_CHARGE := 36
const SURGE_SPEED := 12.0
const SURGE_TICKS := 50
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
## Ticks the knockback carries you without steering, and the freeze before it (he holds
## still for a beat so the hit reads).
const HURT_LOCK := 9
const HURT_FREEZE := 4
## How strongly the screen flashes when you're hit, and in what colour.
const HURT_FLASH := 0.35
const HURT_FLASH_COLOR := Color(1.0, 0.85, 0.8)
## Ticks of the hurt pose at the start of the invincibility after a hit.
const HURT_POSE_TICKS := 20
## Ticks between asking the server for the next item while the loot key is held.
const LOOT_EVERY := 4
## Ticks an attack or skill press made too early (still swinging, or on cooldown) is kept
## for: it goes off as soon as he can, so a press just before the swing ends isn't lost.
const ATTACK_BUFFER_TICKS := 8
## Ticks between portal press and the map change, so the screen fades out first.
const PORTAL_FADE_TICKS := 12
## Ticks of the combat-ready stance after an attack, before he relaxes into idle.
const READY_TICKS := 120
## Ticks the poses after a relic's move show: a double jump's flip (about its rise to the
## top), a Slam's landing and a Surge's skid to a stop on the ground.
const DOUBLE_JUMP_POSE_TICKS := 20
const SLAM_LAND_TICKS := 15
const SURGE_END_TICKS := 12
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
var hurtbox := Hitbox.new(SimPlayer.HURTBOX_SIZE)

var drop_from: Platform = null
var drop_t := 0       # ticks to fall through drop_from
var action_t := 0     # ticks left in the current attack pose
var action_anim := &"attack"
## A pose after a relic's move (see _pose), its ticks left and whether landing ends it.
var move_pose := &""
var move_pose_t := 0
var _pose_air := false
var cooldown := 0     # ticks before the next attack
## Skill id -> ticks before that skill can be used again (SkillDef.recharge), as the server keeps.
var recharge := {}
var inv := 0          # invincibility (blinking) ticks after being hit
var down := false     # fainted, until the server sends you back to town
var land_t := 0       # ticks of the landing pose
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
var _freeze_t := 0    # ticks held still after being hit (see knock_back)
var _stop_t := 0      # hit-stop: ticks held mid-swing after your melee blow lands (see hit_stop)
var _portal_t := 0    # ticks until the portal you stepped into takes you (see _interact)
## A skill pressed too early, and for how many more ticks it's kept (ATTACK_BUFFER_TICKS).
var _queued: SkillDef
var _queued_t := 0
var _lock_t := 0      # ticks the knockback carries you without steering
var _jumping := false # rising from your own jump (letting go cuts it short)
var _aim := Hitbox.Aim.AHEAD  # which way the current attack aims
## Relic moves (RelicDef.Move): ticks left in a Dash and before the next one on the
## ground, whether this jump has used its Dash and its double jump, a Slam dropping, ticks
## of a Surge's charge held (-1 when not charging) and ticks left of its flight.
var _dash_t := 0
var _dash_cd := 0
var _air_dashed := false
var _air_jumped := false
var _slamming := false
var _charge_t := -1
var _surge_t := 0
## Sitting on the ground (the server said so). Moving or getting hit gets you up.
var sitting := false

## How you're drawn: your look and pet (see HeroBody).
var body: HeroBody
var companion: TDCompanion:
	get:
		return body.companion if body else null

func _ready() -> void:
	body = HeroBody.new(self, world, Z)

func place(x: float, y: float) -> void:
	position = Vector2(x, y)
	vel = Vector2.ZERO
	on_ground = true
	down = false
	sitting = false
	platform = world.platforms[0]
	jump_grace.cancel()
	_end_relic_moves()
	_stop_t = 0
	_portal_t = 0
	_queued = null
	_queued_t = 0
	_report()

func fainted() -> bool:
	return down

## The server says you fainted. You lie there until it sends you back to town.
func faint() -> void:
	down = true
	sitting = false
	Sound.jingle(FAINT_JINGLE)

## The server sat you down on the ground (or got you up).
func sit(down_: bool) -> void:
	sitting = down_
	if sitting:
		vel = Vector2.ZERO
		action_t = 0

## The server says a monster hit you: blink, get knocked away from it, and the screen jolts.
func knock_back(from_x: float) -> void:
	world.shake(0.3)
	Sound.play(HURT_SOUND)
	inv = SimPlayer.HURT_INV
	sitting = false # the server gets you up too
	world.stage.flash_screen(HURT_FLASH_COLOR, HURT_FLASH)
	# a steadying buff (Iron Body) keeps you on your feet
	if not Game.me.skills.steady():
		vel = Vector2(-KNOCKBACK.x if position.x < from_x else KNOCKBACK.x, KNOCKBACK.y)
		on_ground = false
		run_t = 0
		_jumping = false
		_freeze_t = HURT_FREEZE
		_lock_t = HURT_LOCK
		_end_relic_moves()
		jump_grace.cancel()

## Your melee blow landed: he holds mid-swing for `ticks` (the monster freezes too, see
## TDMob.hit_react), so the blow feels heavy. Presses meanwhile are kept, not lost.
func hit_stop(ticks: int) -> void:
	if ticks > _stop_t:
		_stop_t = ticks
		body.hold(ticks)

## Your melee blow ahead landed: a little push back. (A downward blow already bounced you,
## see _use.)
func recoil() -> void:
	if _aim == Hitbox.Aim.AHEAD:
		vel.x = -face * RECOIL
		_lock_t = maxi(_lock_t, RECOIL_TICKS)

## The server didn't accept where you said you were, and puts you back.
func correct(at: Vector2) -> void:
	position = at
	vel = Vector2.ZERO

# ---------- per tick ----------

func step() -> void:
	if speech_t > 0:
		speech_t -= 1
	if down:
		return
	if inv > 0:
		inv -= 1
	if _portal_t > 0:
		# stepping through a portal: the screen fades out, then the server moves you
		_portal_t -= 1
		if _portal_t == 0:
			Net.ask(&"req_portal")
		return
	if _stop_t > 0:
		# hit-stop: held mid-swing for a beat so the blow lands; presses are still kept
		_stop_t -= 1
		if _tapped("jump"):
			jump_grace.press()
		_attacks()
		return
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
	if drop_t > 0:
		drop_t -= 1
	if land_t > 0:
		land_t -= 1
	if move_pose_t > 0:
		move_pose_t -= 1
	if loot_cd > 0:
		loot_cd -= 1
	if not Game.me.skills.buffs.is_empty():
		Game.me.skills.tick_buffs() # the server ends them too; this keeps timers and speed in step
	if sitting:
		# the sit key again, or any move, gets you up
		var up := _tapped("sit")
		for a in ["move_left", "move_right", "move_up", "move_down", "jump", "attack"]:
			up = up or _held(a)
		if up:
			sitting = false
			Net.ask(&"req_sit", [false])
		else:
			if world.tick % REPORT_EVERY == 0 or _animation() != _reported:
				_report()
			return
	elif _tapped("sit") and _can_sit():
		_report()
		Net.ask(&"req_sit", [true])
	_attacks()
	# hold the loot key to pick up everything in reach, one item after another
	if _held("loot") and loot_cd == 0:
		_report()
		Net.ask(&"req_loot")
		loot_cd = LOOT_EVERY
	if not _interact():
		_move()
	if world.tick % REPORT_EVERY == 0 or _animation() != _reported:
		_report()

## Standing still on the ground with nothing else going on (the server checks too).
func _can_sit() -> bool:
	return on_ground and not fainted() and action_t == 0 and not _relic_moving() \
		and scene_pose == &"" and absf(vel.x) < 0.01

## Whether an input is held, unless typing or minding a shop.
func _held(action: StringName) -> bool:
	return not world.input_blocked() and Input.is_action_pressed(action)

func _tapped(action: StringName) -> bool:
	return not world.input_blocked() and Input.is_action_just_pressed(action)

## Tells the server where you are and what you're doing.
func _report() -> void:
	_reported = _animation()
	Net.ask(&"req_move", [position, face, _reported])

func _attacks() -> void:
	# items on quickslots work even mid-swing
	for i in Game.QUICKSLOT_ACTIONS.size():
		if _tapped(Game.QUICKSLOT_ACTIONS[i]):
			use_quickslot(i)
			return
	if _tapped("attack"):
		_press(Game.me.skills.basic_attack())
	elif _queued_t > 0:
		if _stop_t == 0:
			_queued_t -= 1 # a hit-stop doesn't eat into the wait
		if _ready_for(_queued):
			var skill := _queued
			_queued = null
			_queued_t = 0
			_use(skill)
	elif _held("attack") and cooldown == 0 and _stop_t == 0:
		# holding the attack key keeps swinging (quietly stops if it can't)
		var basic := Game.me.skills.basic_attack()
		if _ready_for(basic) and Game.me.skills.use_problem(basic) == "":
			_use(basic)

## A skill key went down: use it now, or keep it for a few ticks if he's still busy.
func _press(skill: SkillDef) -> void:
	if skill == null:
		return
	if _ready_for(skill):
		_queued = null
		_queued_t = 0
		_use(skill)
	else:
		_queued = skill
		_queued_t = ATTACK_BUFFER_TICKS

## Whether `skill` could go off this tick as far as timing goes (no cooldown,
## no recharge, not held by hit-stop).
func _ready_for(skill: SkillDef) -> bool:
	return skill != null and cooldown == 0 and _stop_t == 0 and not recharge.has(skill.id)

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
	_press(Content.skills.get(q[1]))

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
	if skill == null or cooldown > 0 or recharge.has(skill.id):
		return
	var problem := Game.me.skills.use_problem(skill)
	if problem != "":
		world.add_log(problem, Palette.INFO)
		return
	var ambush_to := _ambush_spot(skill)
	if skill.ambush > 0.0 and ambush_to == Vector2.INF:
		world.add_log("There are no monsters ahead to ambush.", Palette.INFO)
		return
	cooldown = CharacterStats.attack_ticks(skill.cooldown, Game.me.stats)
	var lvl := Game.me.skills.level(skill)
	if skill.recharge_ticks(lvl) > 0:
		recharge[skill.id] = skill.recharge_ticks(lvl)
	var aim := skill.aim_for(_held_aim())
	# buffs and spells make no motion: he carries on with what he was doing
	if not skill.is_spell():
		action_t = CharacterStats.attack_ticks(skill.action_ticks, Game.me.stats)
		action_anim = skill.animation
		ready_t = READY_TICKS
		_aim = aim
	if aim == Hitbox.Aim.DOWN and not skill.is_ranged() and _meets_monster(skill, aim):
		vel.y = POGO_SPEED
		_jumping = false
	if ambush_to != Vector2.INF:
		var from := position
		position = ambush_to
		vel = Vector2.ZERO
		on_ground = false
		_jumping = false
		if skill.move:
			TDMoveFx.play(world, skill.move, from, position, self)
	Net.ask(&"req_skill", [skill.id, position, face, aim])
	world.add_effect(skill.effect, TDWorldFx.swing_point(position, face, aim), face, null, aim)
	Sound.play(skill.cast_sound())

## Where an ambush (SkillDef.ambush) lands among the monsters this screen shows, kept on
## the map; Vector2.INF for any other skill or when no monsters are ahead. The server works
## it out the same way and has the last word.
func _ambush_spot(skill: SkillDef) -> Vector2:
	if skill.ambush <= 0.0:
		return Vector2.INF
	var bodies: Array[Vector2] = []
	for m in world.mobs():
		if not m.dead:
			bodies.append(m.body_position())
	var to := skill.ambush_spot(position, face, bodies)
	if to == Vector2.INF:
		return to
	return Vector2(clampf(to.x, EDGE, float(world.map.width) - EDGE), clampf(to.y, 0.0, float(world.map.ground_y)))

## Whether `skill` aimed `aim` from here meets a living monster, as this screen shows them
## (the server decides the damage; this only lets the bounce happen at once).
func _meets_monster(skill: SkillDef, aim: Hitbox.Aim) -> bool:
	var area := Hitbox.aimed_area(position, face, aim, skill.reach, skill.height)
	for m in world.mobs():
		if not m.dead and area.intersects(Hitbox.new(m.def.size).rect_at(m.body_position())):
			return true
	return false

## Up on the ground: enter a portal, try a gated one's gate (the server opens it with its key,
## or says it's shut), or talk to the NPC in front of you.
func _interact() -> bool:
	if not (_tapped("move_up") and on_ground):
		return false
	var portal := world.layout.portal_at(position)
	if portal and portal.shows_to(Game.me) and portal.gated_for(Game.me):
		_report()
		Net.ask(&"req_portal")
		return true
	if portal and portal.open_to(Game.me):
		_report()
		# fade out before asking: a local server answers at once, and the next map's
		# fade-in (TDWorld.enter_map) must come after this
		world.stage.fade_to(1.0)
		Sound.play(PORTAL_SOUND)
		_portal_t = PORTAL_FADE_TICKS
		return true
	var npc := world.npc_near(position)
	if npc:
		npc.talk()
		face = 1 if npc.position.x > position.x else -1
		return true
	return false

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
	_relic_moves()
	# knocked back (or recoiling from your own blow, or carried by a relic's move): along
	# without steering
	var rooted := _lock_t > 0 or _relic_moving()
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
	if _relic_moving():
		pass # a jump pressed meanwhile is kept for a few ticks (JumpGrace)
	elif jump_grace.can_jump(on_ground):
		jump_grace.cancel()
		if on_ground and _held("move_down") and platform != null and not platform.solid:
			drop_from = platform
			drop_t = DROP_TICKS
			vel.y = 1
		else:
			vel.y = JUMP_SPEED * CharacterStats.jump_multiplier(Game.me.stats)
			_jumping = true
		on_ground = false
	elif _tapped("jump") and not on_ground:
		_air_jump()
	# letting go of jump on the way up turns it into a short hop
	if _jumping and not _held("jump") and vel.y < JUMP_CUT:
		vel.y = JUMP_CUT
	if vel.y >= 0.0:
		_jumping = false

	# a Dash or Surge flies flat ahead at its own speed, even in the air, and a Slam drops
	# straight down
	var flat := _dash_t > 0 or _surge_t > 0
	if _dash_t > 0:
		_dash_t -= 1
		vel.x = face * DASH_SPEED
	elif _surge_t > 0:
		_surge_t -= 1
		vel.x = face * SURGE_SPEED
		if _surge_t == 0 and on_ground:
			_pose(&"surge_end", SURGE_END_TICKS)
	if _slamming:
		vel = Vector2(0.0, SLAM_SPEED)
	else:
		vel.y = 0.0 if flat else minf(vel.y + gravity(vel.y), MAX_FALL)
	var prev_y := position.y
	var hard_landing := vel.y > -JUMP_SPEED * CharacterStats.jump_multiplier(Game.me.stats) + HARD_LANDING
	var was_falling := vel.y > 4.0
	position.x = clampf(position.x + vel.x, EDGE, float(world.map.width) - EDGE)
	position.y += vel.y
	# a Surge stops at the map's edge
	if _surge_t > 0 and (position.x <= EDGE or position.x >= float(world.map.width) - EDGE):
		_surge_t = 0
	on_ground = false
	if vel.y >= 0:
		for pl in world.platforms:
			if pl == drop_from and drop_t > 0:
				continue
			# a little slack: position is single precision, so standing on a top like 472.7
			# leaves the feet a hair below it
			if pl.contains_x(position.x) and prev_y <= pl.y + 0.01 and position.y >= pl.y:
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
	if on_ground:
		_air_dashed = false
		_air_jumped = false
		if _pose_air:
			move_pose_t = 0
		if _slamming:
			_slam_landed()

# ---------- moves from boss relics (RelicDef.Move) ----------

## Whether a relic's move carries him this tick (a Dash, a Surge or its charge, a Slam).
func _relic_moving() -> bool:
	return _dash_t > 0 or _surge_t > 0 or _charge_t >= 0 or _slamming

func _end_relic_moves() -> void:
	_dash_t = 0
	_surge_t = 0
	_charge_t = -1
	_slamming = false
	move_pose_t = 0

## Shows `anim` for `ticks` after a relic's move (the moves themselves show while they last,
## _animation); with `air`, landing ends it.
func _pose(anim: StringName, ticks: int, air := false) -> void:
	move_pose = anim
	move_pose_t = ticks
	_pose_air = air

## The Dash key: a Dash, or with Down held on the ground a Surge's charge, which flies once
## it is ready and the key is let go (let go sooner, it fizzles). Jump or Dash ends a Surge.
func _relic_moves() -> void:
	if _dash_cd > 0:
		_dash_cd -= 1
	if _charge_t >= 0:
		vel.x = 0.0
		if _held("dash"):
			_charge_t += 1
			return
		if _charge_t >= SURGE_CHARGE:
			_surge_t = SURGE_TICKS
			_trail(RelicDef.Move.SURGE, SURGE_TICKS)
		_charge_t = -1
		return
	if _surge_t > 0:
		if _tapped("jump") or _tapped("dash"):
			_surge_t = 0
		return
	if not _tapped("dash") or _dash_t > 0 or _slamming:
		return
	if on_ground and _held("move_down") and Game.me.has_move(RelicDef.Move.SURGE):
		_charge_t = 0
		vel.x = 0.0
		return
	if not Game.me.has_move(RelicDef.Move.DASH) or (_dash_cd > 0 if on_ground else _air_dashed):
		return
	_dash_t = DASH_TICKS
	_dash_cd = DASH_COOLDOWN
	if not on_ground:
		_air_dashed = true
	_jumping = false
	_trail(RelicDef.Move.DASH, DASH_TICKS)

## Jump pressed in mid-air past the ledge grace: with Down held a Slam, else a double jump
## (each from its relic).
func _air_jump() -> void:
	if _held("move_down") and Game.me.has_move(RelicDef.Move.SLAM):
		jump_grace.cancel()
		_slamming = true
		_jumping = false
		return
	if _air_jumped or not Game.me.has_move(RelicDef.Move.DOUBLE_JUMP):
		return
	jump_grace.cancel()
	_air_jumped = true
	vel.y = JUMP_SPEED * DOUBLE_JUMP_SHARE * CharacterStats.jump_multiplier(Game.me.stats)
	_jumping = true
	_pose(&"double_jump", DOUBLE_JUMP_POSE_TICKS, true)
	world.fx.dust(position, 0, 4)
	_trail(RelicDef.Move.DOUBLE_JUMP, DOUBLE_JUMP_POSE_TICKS)

## A Slam hit the ground: the screen jolts, its painted impact bursts where he landed and the
## server breaks what it landed on.
func _slam_landed() -> void:
	_slamming = false
	_pose(&"slam_land", SLAM_LAND_TICKS)
	world.shake(SLAM_SHAKE)
	world.fx.dust(position, 0, 10)
	var relic := Game.me.relic_for(RelicDef.Move.SLAM)
	if relic and relic.effect:
		world.fx.add_effect(relic.effect, position, face)
	Net.ask(&"req_slam", [position])

## Relic move `m`'s painted effect round him, or its code-drawn trail for `ticks`.
func _trail(m: RelicDef.Move, ticks: int) -> void:
	var relic := Game.me.relic_for(m)
	if relic == null:
		return
	if relic.effect:
		world.fx.add_effect(relic.effect, position, face, self)
	else:
		TDMoveFx.play(world, relic.trail_move(ticks), position, position, self)

# ---------- Visuals ----------

func _process(_delta: float) -> void:
	if body == null or world == null or world.map == null:
		return
	body.draw(face, Game.me.pet, _animation(), HeroLookDef.of(Game.me.look))

## What he is doing, as an animation name: the server passes it on to everyone else.
func _animation() -> StringName:
	if scene_pose != &"":
		return scene_pose
	if fainted():
		return &"faint"
	if sitting:
		return &"sit"
	if _slamming:
		return &"slam"
	if _charge_t >= 0:
		return &"surge_charge"
	if _dash_t > 0:
		return &"dash"
	if _surge_t > 0:
		return &"surge"
	if action_t > 0:
		return action_anim
	if move_pose_t > 0:
		return move_pose
	if inv > SimPlayer.HURT_INV - HURT_POSE_TICKS and inv <= SimPlayer.HURT_INV: # just got hit (see knock_back)
		return &"hurt"
	if not on_ground:
		if absf(vel.y) < APEX_SPEED:
			return &"jump_apex"
		return &"jump" if vel.y < 0 else &"fall"
	if land_t > 0:
		return &"land"
	if turn_t > 0:
		return &"turn"
	if absf(vel.x) > 0.3:
		return &"walk" # a faster pace is still a walk
	if _held("move_down"):
		return &"crouch"
	if ready_t > 0:
		return &"ready"
	return &"idle"
