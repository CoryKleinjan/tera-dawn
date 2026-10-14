class_name HeroBody
extends RefCounted
## How a hero shows in the world, yours (TDPlayer) or another player's (TDAvatar). The hero's
## look is being restarted from Cory's original reference (art/reference/hero.png), so for now
## he has no sprite of his own: only the chair he sits on and the pet trotting after him
## (TDCompanion) show. His new look goes here, so both kinds of hero draw it the same way.
##
##   body = HeroBody.new(self, world, z)   # in _ready: adds the companion
##   body.draw(face, chair, pet)           # every frame

## The chair they sit on and the pet trotting after them.
var companion: TDCompanion
var _owner: Node2D
var _world: TDWorld
var _z: float

## Adds the companion to `owner`, drawn at depth `z` (TDStage.Z_*).
func _init(owner: Node2D, world: TDWorld, z: float) -> void:
	_owner = owner
	_world = world
	_z = z
	companion = TDCompanion.new()
	owner.add_child(companion)

## Draws the hero this frame, between his last two ticks (TDWorld.drawn), facing `face`: his
## chair and pet (item ids, or empty) follow him.
func draw(face: int, chair: StringName, pet: StringName) -> void:
	var at := _world.drawn(_owner)
	companion.set_chair(chair)
	companion.set_pet(pet, _owner.position)
	companion.follow(at, face, _z, _world.layout.ground_below(_owner.position))
