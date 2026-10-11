class_name CharacterPart
extends RefCounted
## One part of a Character's rules that keeps its own state: its skills (SkillBook), its
## Ability Points (AbilityPoints) and its gear (Gear). A part only keeps a weak reference
## back to its Character, so the two don't keep each other alive.

## The Character this part belongs to.
var character: Character:
	get:
		return _character.get_ref()

var _character: WeakRef

func _init(c: Character) -> void:
	_character = weakref(c)
