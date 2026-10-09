class_name ChairDef
extends ItemDef
## A chair, like MapleStory's: double-click it in the Setup tab to sit on it. Sitting
## restores more HP and MP each time they regenerate, until you move.

## Extra HP and MP each time HP and MP regenerate while sitting on it.
@export var regen_hp := 10
@export var regen_mp := 5
## How big the chair looks under the sitter.
@export var seat_scale := 0.7

func tab() -> Tab:
	return Tab.SETUP

func stack_size() -> int:
	return 1
