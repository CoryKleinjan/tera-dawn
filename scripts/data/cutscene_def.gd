class_name CutsceneDef
extends Resource
## A cutscene: steps that play in order on one player's screen (the camera moves, people
## talk and walk, the screen fades), while their controls and the HUD are put away. Add one
## by saving a CutsceneDef in data/cutscenes/, then point a map's `intro_scene` or a
## quest's `start_scene` / `finish_scene` at it. Each character sees each cutscene once.
## TDCutscenePlayer plays them; see docs/architecture/cutscenes.md.

@export var id: StringName
## Holding the menu key (Esc) skips to the end.
@export var skippable := true
@export var steps: Array[CutsceneStep] = []

## Everything wrong with it, one line each (empty when it's fine).
func problems() -> Array[String]:
	var out: Array[String] = []
	if steps.is_empty():
		out.append("%s has no steps" % id)
	for i in steps.size():
		var s := steps[i]
		if s == null:
			out.append("%s step %d is empty" % [id, i + 1])
			continue
		var p := s.problem()
		if p != "":
			out.append("%s step %d: %s" % [id, i + 1, p])
	return out

## Every NPC it needs standing on the map it plays on.
func npcs() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in steps:
		if s == null:
			continue
		for n in s.npcs():
			if n not in out:
				out.append(n)
	return out
