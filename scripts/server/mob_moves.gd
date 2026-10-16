class_name MobMoves
extends RefCounted
## Runs a monster's moves (MonsterDef.moves, see MonsterMove) on the server: picks one
## that fits how far away its target is, winds up, plays it out (moving the monster and
## hurting players it reaches), then rests. SimMob owns it and calls step() each tick.
## Bosses pick smarter: they go through their moves in order (a pattern the player can
## learn), aim where the player is heading, chain a charge or pounce into a slam, and leap
## to the player's platform. After their second wind each move is followed at once by the
## next one in the pattern.

enum Phase { NONE, WINDUP, ACTIVE, RECOVER }

## Ticks between one move ending and the next starting (bosses wait less).
const GAP_TICKS := 45
const BOSS_GAP_TICKS := 20
## After its second wind a boss follows each move with the next this quickly.
const COMBO_GAP_TICKS := 6
## Players further above or below than this are out of reach of ground moves, shots
## and pounces.
const GROUND_Y_RANGE := 90.0
const SHOT_Y_RANGE := 180.0
const POUNCE_Y_RANGE := 160.0
## A slam only hurts players this close to the ground (jumping over it dodges it).
const SLAM_FEET := 14.0
## Ticks a slam's stomp pose lasts, a lunge's little hop height, a blink's vanish.
const SLAM_TICKS := 10
const LUNGE_HOP := 14.0
const BLINK_TICKS := 16
## How far behind the player a blink lands.
const BLINK_BEHIND := 64.0
## Ticks a pounce or a leap is in the air.
const POUNCE_TICKS := 32
## How far a boss leaps to reach the player's platform.
const LEAP_X := 460.0
const LEAP_Y := 280.0
## How much quicker a boss's moves come back and wind up after its second wind.
const RAGE_COOLDOWN := 0.7
const RAGE_WINDUP := 0.8
## A chained slam winds up this much quicker than a fresh one.
const COMBO_WINDUP := 0.4
## Ticks it shows its attack pose after a move.
const POSE_TICKS := 12
## How far around a player a move's hit still lands.
const HIT_GROW := 4.0
## Shortest wait before the first move after it (re)appears.
const FIRST_TICKS := 40

var mob: SimMob
var phase := Phase.NONE
var t := 0          # ticks left in this phase
var index := -1     # the move in progress (into def.moves), or -1 for a leap
var last := -1      # the move used last
var cool := PackedInt32Array()
var gap := 0
## The point it aims at (bosses lead the player).
var aim := Vector2.ZERO
## Peers this move already hurt (each player is hit once per move).
var hit: Array[int] = []
## Motion of the move in progress: from where, to where, over how many ticks, how high.
var from := Vector2.ZERO
var to := Vector2.ZERO
var span := 1
var elapsed := 0
var arc := 0.0
var dive := 0.0
## A leap's platform, entered on landing.
var leap_to: Platform
var hidden := false
var _blinked := false
## A boss after its second wind: the next move follows straight on, ready or not.
var _follow_up := false
## The move in progress is such a follow-up (it doesn't start another).
var _following := false

func _init(m: SimMob) -> void:
	mob = m
	cool.resize(m.def.moves.size())
	reset()

func reset() -> void:
	phase = Phase.NONE
	index = -1
	last = -1
	gap = 0
	hidden = false
	leap_to = null
	_follow_up = false
	_following = false
	hit.clear()
	for i in cool.size():
		cool[i] = randi_range(FIRST_TICKS, maxi(FIRST_TICKS, mob.def.moves[i].cooldown / 2))

func busy() -> bool:
	return phase != Phase.NONE

func winding() -> bool:
	return phase == Phase.WINDUP

## Showing its attack pose: while striking and just after.
func posing() -> bool:
	return phase == Phase.ACTIVE or (phase == Phase.RECOVER and current() != null and t > _recover_ticks() - POSE_TICKS)

func current() -> MonsterMove:
	return mob.def.moves[index] if index >= 0 else null

## Counts down cooldowns; call every tick it's alive.
func tick() -> void:
	for i in cool.size():
		if cool[i] > 0:
			cool[i] -= 1
	if gap > 0 and not busy():
		gap -= 1

## Starts a move on `p` if one is ready and fits. True when one started.
func try_start(p: SimPlayer) -> bool:
	if gap > 0 or busy():
		return false
	if mob.def.boss:
		return _next_in_pattern(p)
	var ready: Array[int] = []
	for i in cool.size():
		if cool[i] <= 0 and fits(mob.def.moves[i], p):
			ready.append(i)
	if ready.is_empty():
		return false
	start(ready[randi() % ready.size()], p)
	return true

## Bosses: the first move after the last one (in MonsterDef.moves order) that is ready
## and fits; a follow-up after the second wind doesn't wait for its cooldown.
func _next_in_pattern(p: SimPlayer) -> bool:
	var follow := _follow_up
	_follow_up = false
	for k in cool.size():
		var i := (last + 1 + k) % cool.size()
		if (follow or cool[i] <= 0) and fits(mob.def.moves[i], p):
			start(i, p)
			_following = follow
			return true
	return false

## Whether a close move (anything but a shot) is ready and `p` is in its reach.
func close_ready(p: SimPlayer) -> bool:
	for i in cool.size():
		var mv: MonsterMove = mob.def.moves[i]
		if mv.kind != MonsterMove.Kind.SHOT and cool[i] <= 0 and fits(mv, p):
			return true
	return false

## Whether `mv` can reach `p` from here.
func fits(mv: MonsterMove, p: SimPlayer) -> bool:
	var dx := absf(p.position.x - mob.position.x)
	if dx < mv.min_reach or dx > mv.reach:
		return false
	var dy := absf(p.position.y - mob.plat.y)
	match mv.kind:
		MonsterMove.Kind.SHOT:
			return dy <= SHOT_Y_RANGE
		MonsterMove.Kind.SWOOP:
			return mob.def.flying and dy <= SHOT_Y_RANGE
		MonsterMove.Kind.BLINK:
			return dy <= SHOT_Y_RANGE and p.stands_on(mob.area)
		MonsterMove.Kind.POUNCE:
			return not mob.def.stationary and dy <= POUNCE_Y_RANGE
		MonsterMove.Kind.SLAM:
			return dy <= GROUND_Y_RANGE
	return not mob.def.stationary and dy <= GROUND_Y_RANGE

func start(i: int, p: SimPlayer, quick := false) -> void:
	index = i
	var mv := current()
	phase = Phase.WINDUP
	t = roundi(mv.windup * (RAGE_WINDUP if mob.enraged else 1.0) * (COMBO_WINDUP if quick else 1.0))
	t = maxi(1, t)
	hit.clear()
	_aim_at(p, mv.windup)

## Leaps to platform `pl`, landing at `x` (bosses following the player).
func leap(pl: Platform, x: float) -> void:
	index = -1
	phase = Phase.ACTIVE
	hit.clear()
	leap_to = pl
	_fly(Vector2(x, pl.y), POUNCE_TICKS, 60.0 + maxf(0.0, mob.position.y - pl.y) * 0.6)
	mob.dir = 1 if x > mob.position.x else -1

## Where to aim at `p`: where they are, or for bosses where they're heading in `ticks`.
func _aim_at(p: SimPlayer, ticks: int) -> void:
	if p == null:
		return
	aim = p.position
	if mob.def.boss:
		aim.x += clampf(mob.target_velocity.x * ticks, -160.0, 160.0)
	mob.dir = -1 if aim.x < mob.position.x else 1

## One tick of the move in progress; `p` is its target (or null when it's gone).
func step(p: SimPlayer) -> void:
	match phase:
		Phase.WINDUP:
			t -= 1
			# keeps turning to follow its target until it strikes
			_aim_at(p, t)
			if t <= 0:
				_strike(p)
		Phase.ACTIVE:
			_active(p)
		Phase.RECOVER:
			t -= 1
			if t <= 0:
				_end()

func _strike(p: SimPlayer) -> void:
	var mv := current()
	phase = Phase.ACTIVE
	var dir := mob.dir
	match mv.kind:
		MonsterMove.Kind.LUNGE:
			_slide(mob.position.x + dir * mv.distance, mv.distance / mv.speed, LUNGE_HOP)
		MonsterMove.Kind.CHARGE:
			var sp := mv.speed * (SimMob.RAGE_SPEED if mob.enraged else 1.0)
			_slide(mob.position.x + dir * mv.distance, mv.distance / sp, 0.0)
		MonsterMove.Kind.POUNCE:
			var x := clampf(aim.x, mob.position.x - mv.distance, mob.position.x + mv.distance)
			_fly(Vector2(_clamp_x(x), mob.position.y), POUNCE_TICKS, mv.height)
		MonsterMove.Kind.SWOOP:
			var x := clampf(aim.x + dir * 40.0, mob.position.x - mv.distance, mob.position.x + mv.distance)
			_fly(Vector2(_clamp_x(x), mob.position.y), absf(x - mob.position.x) / mv.speed + 10.0, 0.0)
			# dives so its body comes down to the player's feet
			var feet := p.position.y if p else mob.plat.y
			dive = clampf(feet - (mob.position.y - mob.def.hover_height), 0.0, mob.def.hover_height + 20.0) if mob.def.flying else 0.0
		MonsterMove.Kind.SLAM:
			t = SLAM_TICKS
			_slam(mv)
		MonsterMove.Kind.SHOT:
			var target := aim
			if p and mob.def.boss:
				var ticks := mob.muzzle().distance_to(p.position) / maxf(1.0, mv.projectile.speed)
				target.x = p.position.x + clampf(mob.target_velocity.x * ticks, -160.0, 160.0)
			mob.shoot(index, Vector2(target.x, (p.position.y if p else aim.y) - SimPlayer.CHEST), p.peer if p else 0)
			_recover()
		MonsterMove.Kind.BLINK:
			hidden = true
			_blinked = false
			t = BLINK_TICKS
			mob.map.broadcast(&"ev_mob_move", [mob.index, &"blink", mob.body_position().x, mob.body_position().y])

func _active(p: SimPlayer) -> void:
	var mv := current()
	if mv and mv.kind == MonsterMove.Kind.SLAM:
		t -= 1
		if t <= 0:
			_recover()
		return
	if mv and mv.kind == MonsterMove.Kind.BLINK and not _blinked:
		t -= 1
		if t > 0:
			return
		# reappears behind the player and swipes
		_blinked = true
		hidden = false
		if p:
			mob.position.x = _clamp_x(p.position.x - p.face * BLINK_BEHIND)
			mob.dir = -1 if p.position.x < mob.position.x else 1
		mob.map.broadcast(&"ev_mob_move", [mob.index, &"blink", mob.body_position().x, mob.body_position().y])
		_slide(mob.position.x + mob.dir * mv.distance, mv.distance / mv.speed, 0.0)
		return
	elapsed += 1
	var s := clampf(float(elapsed) / span, 0.0, 1.0)
	mob.position = from.lerp(to, s)
	mob.hop = 4.0 * arc * s * (1.0 - s) - dive * sin(PI * s)
	if index >= 0:
		_hit_touching(mv)
	if elapsed >= span:
		mob.hop = 0.0
		dive = 0.0
		_landed(p)

func _landed(p: SimPlayer) -> void:
	var mv := current()
	if leap_to:
		mob.plat = leap_to
		mob.area = leap_to
		leap_to = null
		mob.position.y = mob.plat.y
		if not mob.def.flying:
			mob.map.broadcast(&"ev_mob_move", [mob.index, &"land", mob.position.x, mob.position.y])
		_end()
		return
	if mv.kind == MonsterMove.Kind.POUNCE:
		mob.map.broadcast(&"ev_mob_move", [mob.index, &"land", mob.position.x, mob.position.y])
	# bosses chain a charge or pounce straight into a slam when the player is close
	if mob.def.boss and p and mv.kind in [MonsterMove.Kind.CHARGE, MonsterMove.Kind.POUNCE]:
		for i in cool.size():
			var next: MonsterMove = mob.def.moves[i]
			if next.kind == MonsterMove.Kind.SLAM and absf(p.position.x - mob.position.x) <= next.radius:
				cool[index] = _cooldown(mv)
				last = index
				start(i, p, true)
				return
	_recover()

func _recover() -> void:
	phase = Phase.RECOVER
	t = _recover_ticks()

func _recover_ticks() -> int:
	var mv := current()
	return maxi(1, mv.recover if mv else 1)

func _end() -> void:
	if index >= 0:
		cool[index] = _cooldown(current())
		last = index
	var moved := index >= 0
	phase = Phase.NONE
	index = -1
	hidden = false
	mob.hop = 0.0
	gap = BOSS_GAP_TICKS if mob.def.boss else GAP_TICKS
	# after its second wind a boss strings two moves together
	_follow_up = moved and mob.def.boss and mob.enraged and not _following
	_following = false
	if _follow_up:
		gap = COMBO_GAP_TICKS

func _cooldown(mv: MonsterMove) -> int:
	return roundi(mv.cooldown * (RAGE_COOLDOWN if mob.enraged else 1.0))

## Stops the move in progress (the monster was defeated or its target left).
func cancel() -> void:
	if leap_to:
		leap_to = null
	if busy():
		_end()
	_follow_up = false

# ---------- motion and hits ----------

## Moves along the platform to `x` over `ticks`, hopping `hop_height` (lunge, charge).
func _slide(x: float, ticks: float, hop_height: float) -> void:
	_fly(Vector2(_clamp_x(x), mob.position.y), ticks, hop_height)

func _fly(dest: Vector2, ticks: float, height: float) -> void:
	from = mob.position
	to = dest
	span = maxi(1, ceili(ticks))
	elapsed = 0
	arc = height
	dive = 0.0

func _clamp_x(x: float) -> float:
	var half := mob.def.size.x / 2.0
	var a := leap_to if leap_to else mob.area
	return clampf(x, a.x + half, a.x + a.w - half)

func _hit_touching(mv: MonsterMove) -> void:
	var body := mob.hurtbox.rect_at(mob.body_position()).grow(HIT_GROW)
	for p: SimPlayer in mob.map.players.values():
		if p.peer in hit or not body.intersects(p.hurtbox.rect_at(p.position)):
			continue
		hit.append(p.peer)
		mob.map.hurt_player(p, mob.def, mob.position.x, mv.power)

func _slam(mv: MonsterMove) -> void:
	mob.map.broadcast(&"ev_mob_move", [mob.index, &"slam", mob.position.x, mob.position.y])
	for p: SimPlayer in mob.map.players.values():
		if absf(p.position.x - mob.position.x) <= mv.radius and absf(p.position.y - mob.plat.y) <= SLAM_FEET:
			mob.map.hurt_player(p, mob.def, mob.position.x, mv.power)
