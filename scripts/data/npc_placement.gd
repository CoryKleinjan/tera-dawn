class_name NpcPlacement
extends Resource
## Where an NPC stands on a map.

@export var npc: NpcDef
@export var x := 0.0
@export var platform := 0
## 1 faces right, -1 faces left.
@export var face := 1
## Someone who moves around as a quest chain goes on (a guide walking ahead of you) is placed
## once per spot, each placement shown only for part of the chain. Empty: always there.
## Shown only once you've taken this quest:
@export var after_taking: QuestDef
## Gone once you've taken this quest:
@export var until_taking: QuestDef
## Gone once you've handed this quest in:
@export var until_done: QuestDef

## Whether `c` sees this NPC standing here (see after_taking, until_taking, until_done).
func shown_to(c: Character) -> bool:
	var book := c.quests
	if after_taking and not (book.active.has(after_taking.id) or book.done.has(after_taking.id)):
		return false
	if until_taking and (book.active.has(until_taking.id) or book.done.has(until_taking.id)):
		return false
	if until_done and book.done.has(until_done.id):
		return false
	return true
