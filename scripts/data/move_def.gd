class_name MoveDef
extends Resource
## How a job's movement skill carries the hero (SkillDef.move): a lunge, a second jump, a
## blink, a leap back or a roll. The hero moves on his own machine like every other step
## (TDPlayer); the server only pays the MP, shoves monsters out of a Charge's way, lets a
## Blink's jump through and keeps a roller from being hit (ServerMoves).

enum Style {
	CHARGE,    ## a fast, flat lunge ahead
	AIR_JUMP,  ## a second jump in mid-air, bursting forward (Flash Jump)
	BLINK,     ## an instant jump the held way, up and down included
	BACKSTEP,  ## a spring back, still facing ahead
	ROLL,      ## a low roll ahead nothing can hit
}

@export var style := Style.CHARGE
## How far it carries him at level 1, and how much further each level (game pixels).
@export var distance := 120.0
@export var distance_per_level := 0.0
## Ticks it takes (a Blink is instant). The hero can't steer meanwhile.
@export var ticks := 12
## Where it can start: on the ground, and once per jump in the air.
@export var on_ground := true
@export var in_air := true
## Nothing can hit him while it lasts (a roll).
@export var untouchable := false
## Monsters in its path it shoves aside (no damage), and how hard (times the usual push).
@export var shoves := 0
@export var shove_force := 2.5
## Colour of its code-drawn trail (values above 1 glow).
@export var color := Color(1.6, 1.4, 1.0)

func distance_at(level: int) -> float:
	return distance + distance_per_level * maxi(0, level - 1)

## Where a Blink from `from` lands, the way `face` and `aim` (Hitbox.Aim) point, at `level`,
## kept inside a map `width` wide with its floor at `ground_y`. The client and the server
## work it out alike.
func blink_to(from: Vector2, face: int, aim: Hitbox.Aim, level: int, width: float, ground_y: float) -> Vector2:
	var to := from + Hitbox.aim_direction(face, aim) * distance_at(level)
	return Vector2(clampf(to.x, TDPlayer.EDGE, width - TDPlayer.EDGE), clampf(to.y, 0.0, ground_y))
