class_name HeldDef
extends Resource
## A weapon or off-hand as the hero holds it, the MapleStory way: ONE painting, pinned to its
## spot on each of his frames, turned and stacked per frame. Placed by hand in
## tools/hero_grip_editor.tscn, which saves back to this file.

## Where the piece goes in his stack on a frame (HeroBody.layers).
enum Layer { BEHIND, UNDER_TOP, OVER_CLOTHES, OVER_HANDS }

## The painting, cut like his other layers (one frame, "held").
@export var frames: SpriteFrames
## The point of the painting that sits on the pin (the middle of a grip), in its pixels.
@export var anchor: Vector2
## Frame name -> Vector4(x, y, turn in degrees clockwise, Layer): where the anchor sits on that
## frame, in the frame's pixels. Frames not listed show it put away.
@export var pins: Dictionary = {}

func texture() -> Texture2D:
	return frames.get_frame_texture(&"held", 0) if frames else null

func shows(frame: StringName) -> bool:
	return pins.has(frame)

func layer(frame: StringName) -> Layer:
	return int((pins[frame] as Vector4).w) as Layer
