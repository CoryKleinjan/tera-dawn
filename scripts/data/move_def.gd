class_name MoveDef
extends Resource
## How a move that carries the hero looks while code-drawn effects stand in for painted ones
## (TDMoveFx): a trail of glowing motes behind him (a relic's Dash or Surge, RelicDef), or a
## bolt from where he vanished to where he landed (an ambush's leap, SkillDef.move).

enum Style {
	TRAIL,  ## motes trailing whoever moves
	BLINK,  ## a crackle where he vanishes, a jagged bolt and sparks where he lands
}

@export var style := Style.TRAIL
## Ticks a trail lasts.
@export var ticks := 12
## Its colour (values above 1 glow).
@export var color := Color(1.6, 1.4, 1.0)
