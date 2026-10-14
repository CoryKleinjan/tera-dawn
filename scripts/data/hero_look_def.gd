class_name HeroLookDef
extends Resource
## How the hero is drawn: his painted layers and which frames each animation shows. Every layer
## (his body, face and hair here, and each piece of gear's `EquipDef.worn`) is a SpriteFrames
## cut from the same cells (art/sheets/hero_*.json), so the layers line up frame by frame;
## each frame is a one-frame animation named after its cell ("idle1", "swing2", "rope_hold").
## HeroBody stacks them in a fixed order.

@export var body: SpriteFrames
@export var face: SpriteFrames
@export var hair: SpriteFrames
## Animation name (what TDPlayer._animation() says he is doing) -> {"frames": [frame names],
## "fps": frames a second, "loop": whether it repeats}. "<name>_<weapon kind>" is used instead
## while that kind of weapon is held (a bow's "attack_bow").
@export var animations: Dictionary = {}
## Animation names that show another's frames: "slash" plays "attack", "fall" plays "jump".
@export var same_as: Dictionary = {}

## The frame `anim` shows `seconds` after it started, holding `weapon_kind`: a frame name, or
## the first idle frame when nothing matches.
func frame_at(anim: StringName, weapon_kind: StringName, seconds: float) -> StringName:
	var a := resolve(anim, weapon_kind)
	var spec: Dictionary = animations.get(a, animations.get(&"idle", {}))
	var frames: Array = spec.get("frames", [])
	if frames.is_empty():
		return &"idle1"
	var i := int(seconds * float(spec.get("fps", 6.0)))
	i = i % frames.size() if spec.get("loop", true) else mini(i, frames.size() - 1)
	return StringName(frames[i])

## Which entry of `animations` plays for `anim` while holding `weapon_kind`.
func resolve(anim: StringName, weapon_kind: StringName) -> StringName:
	var a: StringName = same_as.get(anim, anim)
	if weapon_kind != &"":
		var held := StringName("%s_%s" % [a, weapon_kind])
		if animations.has(held):
			return held
	return a if animations.has(a) else &"idle"
