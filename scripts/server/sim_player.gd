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
const HURTBOX_SIZE := Vector2(19, 40)
## Their chest above their feet: where monsters aim their shots (and TDPlayer.CHEST).
const CHEST := 34.0
## Ticks between MP regeneration, and what's regained each time: a base plus
## level / divisor, plus the character's regen bonus. Sitting regains the base part twice.
const REGEN_EVERY := 120
const REGEN_BASE := 2
const REGEN_MP_LEVELS := 4
## Ticks between getting a health segment back on its own (plus the regen bonus's); sitting
## halves it.
const HEART_REGEN_EVERY := 600

var peer := 0
var character: Character
var map: MapInstance
var position := Vector2.ZERO
var face := 1
## The animation the client says it is playing, passed on to everyone else on the map.
var animation := &"idle"
## Sitting on the ground (see TDServer.on_sit). Moving or getting hit gets them up.
var sitting := false
var hurtbox := Hitbox.new(HURTBOX_SIZE)

var cooldown := 0     # ticks before the next attack
## Skill id -> ticks before that skill can be used again (SkillDef.recharge).
var recharge := {}
var inv := 0          # invincibility ticks after being hit
var faint_t := 0      # ticks left lying fainted
var item_cd := 0      # ticks before another potion can be used
var since_move := 0   # ticks since the last movement report
var hurt_here := false # took damage since arriving on this map (a boss beaten untouched counts)
## The cutscene playing on their screen (a CutsceneDef id, see ServerScenes), or empty.
## Monsters leave them alone meanwhile.
var scene: StringName = &""
var scene_t := 0      # ticks before a scene that never ended stops anyway
var scene_then: SceneSpot  # the scene spot whose scene is playing: it sends them on when it ends

## The client needs a fresh copy of the whole Character (inventory, gear, stats).
var dirty_character := false
## HP, MP, EXP or Dawnshards changed.
var dirty_vitals := false

func _init(p: int, c: Character) -> void:
	peer = p
	character = c

func fainted() -> bool:
	return faint_t > 0

## Hidden by a buff (Dark Sight): monsters can't see, touch or hit them.
func hidden() -> bool:
	return character.skills.hidden()

## Counts down a skill id -> ticks table of recharges, dropping the ones that are done.
## The client (TDPlayer) keeps its own table the same way.
static func tick_recharge(table: Dictionary) -> void:
	for id in table.keys():
		table[id] -= 1
		if table[id] <= 0:
			table.erase(id)

## Watching a cutscene: monsters don't touch or shoot them.
func in_scene() -> bool:
	return scene != &""

func stands_on(plat: Platform) -> bool:
	return not fainted() and absf(position.y - plat.y) < 6 and plat.contains_x(position.x)

## Applies a movement report. False (and the position stays) when it isn't possible.
## Moving gets you up.
func report_move(at: Vector2, facing: int, anim: StringName) -> bool:
	var ticks := maxi(1, since_move)
	since_move = 0
	if fainted() or at.distance_to(position) > MAX_STEP * ticks + 40.0:
		return false
	if sitting and at.distance_to(position) > 2.0:
		sitting = false
	position = Vector2(clampf(at.x, 0.0, float(map.def.width)), clampf(at.y, -200.0, float(map.def.height)))
	face = 1 if facing >= 0 else -1
	animation = anim
	return true

## Runs the player's timers and heart / MP regeneration. True when they've lain fainted long
## enough to be sent back to town.
func step() -> bool:
	since_move += 1
	if cooldown > 0:
		cooldown -= 1
	if not recharge.is_empty():
		tick_recharge(recharge)
	if inv > 0:
		inv -= 1
	if item_cd > 0:
		item_cd -= 1
	if faint_t > 0:
		faint_t -= 1
		return faint_t == 0
	if not character.skills.buffs.is_empty():
		for s in character.skills.tick_buffs():
			map.tell(self, "%s wore off." % s.display_name, Palette.MIST)
			dirty_character = true
	if map.tick % REGEN_EVERY == 0:
		var times := 2 if sitting else 1
		character.restore_mp((REGEN_BASE + character.level / REGEN_MP_LEVELS) * times + character.skills.regen_bonus().y)
		dirty_vitals = true
	if map.tick % (HEART_REGEN_EVERY / (2 if sitting else 1)) == 0 and character.health.hp < character.health.max_hp:
		character.health.heal(1 + character.skills.regen_bonus().x)
		dirty_vitals = true
	return false

## Where this player is and what they're doing, sent many times a second:
## [peer, x, y, face, animation, flags] (see SnapshotCodec).
func motion() -> Array:
	var flags := 0
	if fainted():
		flags |= SnapshotFlags.PLAYER_FAINTED
	if inv > 0:
		flags |= SnapshotFlags.PLAYER_BLINK
	if hidden():
		flags |= SnapshotFlags.PLAYER_HIDDEN
	return [peer, position.x, position.y, face, animation, flags]

## What else other clients need to show this player, which changes rarely:
## [name, job, guild, pet, look (HeroLookDef.id)].
func info() -> Array:
	return [character.name, character.job.id, character.guild, character.pet, character.look]
