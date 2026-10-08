class_name NpcDef
extends Resource
## A townsperson the player can talk to. Place one on a map with an NpcPlacement.

@export var id: StringName
@export var display_name := ""
## A short role shown under the name ("Village Elder").
@export var title := ""
@export var texture: Texture2D
@export var sprite_frames: SpriteFrames
@export var sprite_scale := 1.0
## Lines said in order, one per press of Up; it loops back to the start.
@export_multiline var lines: PackedStringArray = []
