class_name ClimbableDef
extends Resource
## A rope, vine or ladder hanging from `top` (usually a platform's top edge) down to `bottom`.

@export var x := 0.0
@export var top := 0.0
@export var bottom := 0.0
@export var style: ClimbStyleDef
## A ladder already painted into the scenery behind it (up a treehouse or a lookout): the game
## draws nothing, and `style` only sets the climbing animation.
@export var in_scenery := false
