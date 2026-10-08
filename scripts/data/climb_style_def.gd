class_name ClimbStyleDef
extends Resource
## How a kind of climbable looks and which climbing animation the player uses on it.

@export var id: StringName
## Drawn at the top end (optional), repeated down the middle, and at the bottom end (optional).
@export var top: Texture2D
@export var middle: Texture2D
@export var bottom: Texture2D
@export var texel := 1.25
## "rope" or "ladder" (hero animations).
@export var climb_animation := &"rope"
