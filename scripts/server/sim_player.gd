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
## Ticks of invincibility after a monster touch (the client blinks for as long).
const HURT_INV := 90
## The player's hurtbox, the same on the server and the client (TDPlayer).
const HURTBOX_SIZE := Vector2(28, 64)
## Ticks between HP / MP regeneration, and what's regained each time: a base plus
## level / divisor, plus the character's regen bonus and their chair's.
const REGEN_EVERY := 120
const REGEN_BASE := 2
const REGEN_HP_LEVELS := 3
const REGEN_MP_LEVELS := 4

var peer := 0
var character: Character
var map: MapInstance
var position := Vector2.ZERO
var face := 1
## The animation the client says it is playing, passed on to everyone else on the map.
var animation := &"idle"
var climbing := false
## The chair (a ChairDef id) they're sitting on, or empty.
var chair: StringName = &""
var hurtbox := Hitbox.new(HURTBOX_SIZE)

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
## Moving gets you up off a chair.
func report_move(at: Vector2, facing: int, anim: StringName, on_rope: bool) -> bool:
	var ticks := maxi(1, since_move)
	since_move = 0
	if fainted() or at.distance_to(position) > MAX_STEP * ticks + 40.0:
		return false
	if chair != &"" and (at.distance_to(position) > 2.0 or on_rope):
		chair = &""
	position = Vector2(clampf(at.x, 0.0, float(map.def.width)), clampf(at.y, -200.0, float(map.def.height)))
	face = 1 if facing >= 0 else -1
	animation = anim
	climbing = on_rope
	return true

## Runs the player's timers and HP / MP regeneration. True when they've lain fainted long
## enough to be sent back to town.
func step() -> bool:
	since_move += 1
	if cooldown > 0:
		cooldown -= 1
	if inv > 0:
		inv -= 1
	if item_cd > 0:
		item_cd -= 1
	if faint_t > 0:
		faint_t -= 1
		return faint_t == 0
	if not character.buffs.is_empty():
		for s in character.tick_buffs():
			map.tell(self, "%s wore off." % s.display_name, Palette.MIST)
			dirty_character = true
	if map.tick % REGEN_EVERY == 0:
		var bonus := character.regen_bonus()
		var seat := Content.items.get(chair) as ChairDef
		if seat:
			bonus += Vector2i(seat.regen_hp, seat.regen_mp)
		character.health.heal(REGEN_BASE + character.level / REGEN_HP_LEVELS + bonus.x)
		character.restore_mp(REGEN_BASE + character.level / REGEN_MP_LEVELS + bonus.y)
		dirty_vitals = true
	return false

## What other clients need to draw this player: [peer, name, x, y, face, animation, level,
## flags, job, guild, chair, pet] (the map adds their shop sign).
func snapshot() -> Array:
	var flags := 0
	if fainted():
		flags |= SnapshotFlags.PLAYER_FAINTED
	if inv > 0:
		flags |= SnapshotFlags.PLAYER_BLINK
	if climbing:
		flags |= SnapshotFlags.PLAYER_CLIMBING
	return [peer, character.name, position.x, position.y, face, animation, character.level, flags, character.job.id, character.guild, chair, character.pet]
