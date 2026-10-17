class_name RelicDef
extends ItemDef
## A boss's relic: picking it up unlocks a move for good, on every job, the way Hollow Knight
## hands out its moves (Character.relics). It never goes in the bag. A boss drops it
## (MonsterDef.relic) for everyone at the fight who hasn't got it yet, and only they can take
## theirs. They are the hero's only movement moves and cost nothing; he does them on his own
## machine (TDPlayer), and the server only breaks what a Slam lands on.

enum Move {
	DASH,         ## a quick, flat burst ahead, on the ground and once per jump in the air
	DOUBLE_JUMP,  ## a second jump in mid-air
	SLAM,         ## Down + Jump in the air: a straight drop that breaks what it lands on
	SURGE,        ## hold Down and Dash on the ground to charge, let go to fly straight ahead
}

@export var move := Move.DASH
## The move's name, for the line that says it was learned ("Dash").
@export var move_name := ""
## Colour of the move's code-drawn trail (values above 1 glow), until painted effects come.
@export var trail := Color(1.4, 1.4, 1.6)

## A trail for the move lasting `ticks` (TDMoveFx).
func trail_move(ticks: int) -> MoveDef:
	var m := MoveDef.new()
	m.ticks = ticks
	m.color = trail
	return m
