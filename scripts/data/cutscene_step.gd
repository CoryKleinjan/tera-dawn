class_name CutsceneStep
extends Resource
## One step of a CutsceneDef: move the camera, fade, show the black bars, have someone say
## a line, walk someone somewhere, and so on. Steps run in order; most wait until they're
## done before the next one starts (see `wait`).
##
## "Someone" (`who`, `speaker`) is HERO for your own hero, or the id of an NPC standing on
## the map the cutscene plays on.

enum Kind {
	## Waits `ticks`.
	WAIT,
	## Fades the screen to black (`amount` 1) or back in (0) over `ticks`.
	FADE,
	## Slides the black bars at the top and bottom in (`amount` 1) or out (0) over `ticks`.
	BARS,
	## Glides the camera's centre to `at` (game pixels) over `ticks`, easing in and out.
	CAMERA,
	## Keeps the camera on `who` until another camera step.
	CAMERA_FOLLOW,
	## Hands the camera back to your hero; it glides back over about `ticks`.
	CAMERA_BACK,
	## `speaker` says `text` in the speech box until the player presses on.
	SAY,
	## `who` walks to `x` on the platform they stand on, `speed` game pixels a tick.
	MOVE,
	## `who` turns to `face` (-1 left, 1 right).
	FACE,
	## Shows (`shown` on) or hides `who`.
	SHOW,
	## Starts music track `sound` (a Sound.music id). The map's own track comes back after.
	MUSIC,
	## Plays sound effect `sound` (a Sound.play id).
	SOUND,
}

## `who` / `speaker` for your own hero.
const HERO := &"hero"
## How fast people walk in a MOVE step unless it says otherwise, in game pixels a tick.
const WALK_SPEED := 1.6

@export var kind := Kind.WAIT
## WAIT, FADE, BARS, CAMERA and CAMERA_BACK: how long it takes, in ticks (60 a second).
@export var ticks := 60
## FADE and BARS: where it ends, 0 (gone) to 1 (full).
@export_range(0.0, 1.0) var amount := 1.0
## CAMERA: where the camera's centre goes, in game pixels.
@export var at := Vector2.ZERO
## CAMERA_FOLLOW, MOVE, FACE and SHOW: who.
@export var who: StringName
## MOVE: where they walk to (game pixels across the map), and how fast.
@export var x := 0.0
@export var speed := WALK_SPEED
## FACE: -1 left, 1 right.
@export var face := 1
## SHOW: whether they're shown.
@export var shown := true
## SAY: who's talking (HERO, an NPC id, or empty for a narrator with no name or portrait),
## the name over the speech when it isn't theirs (an NPC known by another name for now), and
## what they say.
@export var speaker: StringName
@export var speaker_name := ""
@export_multiline var text := ""
## MUSIC and SOUND: the track or sound id.
@export var sound: StringName
## Whether the next step waits for this one to finish (CAMERA, MOVE, FADE and BARS can run
## on while the next steps play; the others always finish first).
@export var wait := true

## What's wrong with this step ("" if nothing): a line someone forgot, an NPC id that
## doesn't exist, a step with no time to run.
func problem() -> String:
	match kind:
		Kind.WAIT, Kind.FADE, Kind.BARS, Kind.CAMERA:
			if ticks <= 0:
				return "%s needs ticks above 0" % Kind.keys()[kind]
		Kind.SAY:
			if text.strip_edges() == "":
				return "SAY has no text"
			if speaker != &"" and not _known(speaker):
				return "SAY speaker %s is not the hero or an NPC" % speaker
		Kind.CAMERA_FOLLOW, Kind.MOVE, Kind.FACE, Kind.SHOW:
			if who == &"":
				return "%s needs someone in `who`" % Kind.keys()[kind]
			if not _known(who):
				return "%s: %s is not the hero or an NPC" % [Kind.keys()[kind], who]
			if kind == Kind.MOVE and speed <= 0.0:
				return "MOVE needs a speed above 0"
			if kind == Kind.FACE and face not in [-1, 1]:
				return "FACE needs -1 or 1"
		Kind.MUSIC:
			if sound == &"" or not Sound.has_music(sound):
				return "MUSIC track %s does not exist" % sound
		Kind.SOUND:
			if sound == &"" or not Sound.has_sound(sound):
				return "SOUND %s does not exist" % sound
	return ""

## The NPCs this step needs on the map (none for the hero or a narrator).
func npcs() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in [who, speaker]:
		if id != &"" and id != HERO and id not in out:
			out.append(id)
	return out

static func _known(id: StringName) -> bool:
	return id == HERO or Content.npcs.has(id)
