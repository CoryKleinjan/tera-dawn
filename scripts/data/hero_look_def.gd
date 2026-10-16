class_name HeroLookDef
extends Resource
## How the hero is drawn: his painted layers and which frames each animation shows. Every layer
## (his body and fists here, each face and hairstyle's HeroStyleDef.frames and each piece of
## gear's `EquipDef.worn`) is a SpriteFrames cut from the same cells (art/sheets/hero_*.json),
## so the layers line up frame by frame; each frame is a one-frame animation named after its
## cell ("idle1", "walk2", "rope_hold"). HeroBody stacks them in a fixed order.

@export var body: SpriteFrames
## The faces and hairstyles he can have (HeroStyleDef), the first of each his default.
@export var faces: Array[Resource] = []
@export var hairs: Array[Resource] = []
## His fists painted on their own, drawn over the weapon he holds so his hand wraps its grip.
@export var hands: SpriteFrames
## Frames whose fists were painted with bare forearms, left off under long sleeves
## (EquipDef.long_sleeves).
@export var bare_arm_frames: Array[StringName] = []
## Frames whose fists are drawn over his clothes with or without a weapon out (lying down, a
## hand resting on his belly).
@export var resting_hand_frames: Array[StringName] = []
## His own parts moved by hand in the pose editor: part (&"body", &"hands"; a face or hairstyle
## keeps its own, HeroStyleDef)
## -> {frame: Vector4(x, y, degrees clockwise, places up the stack)} (HeroBody.Layer).
@export var nudges: Dictionary = {}
## His own parts drawn bigger or smaller in the pose editor: part -> {frame: size} (1.0 as
## painted).
@export var sizes: Dictionary = {}
## His own parts added to or deleted from frames in the pose editor: part -> {frame: the frame
## whose painting shows there, or &"" when deleted} (EquipDef.frame_art).
@export var frame_art: Dictionary = {}
## His own parts drawn mirrored in the pose editor (Flip): part -> {frame: true}
## (EquipDef.flips).
@export var flips: Dictionary = {}
## Animation name (what TDPlayer._animation() says he is doing) -> {"frames": [frame names],
## "fps": frames a second, "loop": whether it repeats}. "<name>_<weapon kind>" is used instead
## while that kind of weapon is held (a bow's "attack_bow").
@export var animations: Dictionary = {}
## Animation names that show another's frames: "fall" plays "jump". Anything with no frames
## shows him standing.
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
