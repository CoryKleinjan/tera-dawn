class_name SimPlayer
extends RefCounted
## A connected player as the server sees them: their Character, where they are, and the
## timers the server keeps for them (attack cooldown, invincibility, fainting).
##
## Movement runs on the player's own machine, like MapleStory, so it feels instant. The
## client reports where it is a few times a second and the server checks the report is
## possible. Everything else (hits, EXP, items, HP and MP) the server decides.

const FAINT_TICKS := 150
## Fastest a report may move the player per tick: well above running and falling speed.
const MAX_STEP := 16.0
## Ticks of invincibility after a monster touch.
const HURT_INV := 90

var peer := 0
var character: Character
var map: MapInstance
var position := Vector2.ZERO
var face := 1
## The animation the client says it is playing, passed on to everyone else on the map.
var animation := &"idle"
var climbing := false
var hurtbox := Hitbox.new(Vector2(28, 64))

var cooldown := 0     # ticks before the next attack
var inv := 0          # invincibility ticks after being hit
var faint_t := 0      # ticks left lying fainted
var item_cd := 0      # ticks before another potion can be used
var since_move := 0   # ticks since the last movement report

## The client needs a fresh copy of the whole Character (inventory, gear, stats).
var dirty_character := false
## HP, MP, EXP or Dawnshards changed.
var dirty_vitals := false

func _init(p: int, c: Character) -> void:
	peer = p
	character = c

func fainted() -> bool:
	return faint_t > 0

func stands_on(plat: Platform) -> bool:
	return not fainted() and absf(position.y - plat.y) < 6 and plat.contains_x(position.x)

## Applies a movement report. False (and the position stays) when it isn't possible.
func report_move(at: Vector2, facing: int, anim: StringName, on_rope: bool) -> bool:
	var ticks := maxi(1, since_move)
	since_move = 0
	if fainted() or at.distance_to(position) > MAX_STEP * ticks + 40.0:
		return false
	position = Vector2(clampf(at.x, 0.0, float(map.def.width)), clampf(at.y, -200.0, float(map.def.height)))
	face = 1 if facing >= 0 else -1
	animation = anim
	climbing = on_rope
	return true

## Runs the player's timers and HP / MP regeneration. True when they've lain fainted long
## enough to be sent back to town.
func step() -> bool:
	since_move += 1
	for t in ["cooldown", "inv", "item_cd"]:
		if get(t) > 0:
			set(t, get(t) - 1)
	if faint_t > 0:
		faint_t -= 1
		return faint_t == 0
	if map.tick % 120 == 0:
		character.health.heal(2 + character.level / 3)
		character.restore_mp(2 + character.level / 4)
		dirty_vitals = true
	return false

## What other clients need to draw this player: [peer, name, x, y, face, animation, level, flags].
func snapshot() -> Array:
	var flags := 0
	if fainted():
		flags |= TDAvatar.FAINTED
	if inv > 0:
		flags |= TDAvatar.BLINK
	if climbing:
		flags |= TDAvatar.CLIMBING
	return [peer, character.name, position.x, position.y, face, animation, character.level, flags, character.job.id]
