class_name HeroStyleDef
extends Resource
## One of the hero's faces or hairstyles (HeroLookDef.faces, HeroLookDef.hairs): its painted
## frames and where it sits on each frame, set by hand in the pose editor
## (scenes/dev/hero_pose_editor.tscn). Each style keeps its own places, so a new one can sit
## differently from the others.

@export var id: StringName
@export var display_name := ""
## Cut from the same cells as his body (art/sheets/hero_<face or hair>.json).
@export var frames: SpriteFrames
## Frame -> Vector4(x, y, degrees clockwise, places up the stack) it is moved by (HeroBody.Layer).
@export var nudges: Dictionary = {}
## Frame -> how big it is drawn (1.0 as painted).
@export var sizes: Dictionary = {}
## Frame -> the frame whose painting shows there, or &"" when deleted (EquipDef.frame_art).
@export var frame_art: Dictionary = {}
