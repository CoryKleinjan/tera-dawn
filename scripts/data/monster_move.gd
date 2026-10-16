class_name MonsterMove
extends Resource
## One attack a monster can use on the player it targets (see MonsterDef.moves). Every
## move starts with a wind-up (it stops and glows) so it can be seen coming and dodged,
## then plays out, then the monster rests for a moment. SimMob's MobMoves runs them.
## Shared presets live in data/monster_moves/ so one change tunes a whole family.
## Distances are in game pixels, speeds in pixels per tick, times in ticks (60 Hz).

enum Kind {
	## A short quick hop forward into the player (bite, pinch, claw).
	LUNGE,
	## Dashes along its platform at `speed` for up to `distance`.
	CHARGE,
	## Jumps in an arc (`height` high) to where the player is.
	POUNCE,
	## Rears up and stomps: hurts players on the ground within `radius`.
	SLAM,
	## Fliers: dives at the player and climbs back up.
	SWOOP,
	## Fires `projectile` at where the player is; it can be dodged while it flies.
	SHOT,
	## Fades out and reappears behind the player, then swipes.
	BLINK,
}

@export var id: StringName
@export var kind := Kind.LUNGE
## Used only when the target is between `min_reach` and `reach` away (horizontally).
@export var min_reach := 0.0
@export var reach := 120.0
## Ticks of wind-up before it strikes.
@export var windup := 30
## Ticks before this move can be used again (after it ends).
@export var cooldown := 180
## Damage: the monster's attack times this.
@export var power := 1.0
## Lunge and charge: how far it goes. Swoop and pounce: the most they cover.
@export var distance := 60.0
## Lunge, charge and swoop: pixels per tick.
@export var speed := 4.0
## Pounce: how high the arc goes.
@export var height := 70.0
## Slam: how far either side of its feet the stomp reaches.
@export var radius := 110.0
## Ticks it stands still after the move.
@export var recover := 24
## Shot: what it fires.
@export var projectile: ProjectileDef

## The monster's animation for this move (its kind: "lunge", "charge", ...). Its wind-up
## plays "<name>_windup". Either falls back to the attack pose and a lean when the monster
## has no such frames.
func animation_name() -> StringName:
	return StringName((Kind.keys()[kind] as String).to_lower())
