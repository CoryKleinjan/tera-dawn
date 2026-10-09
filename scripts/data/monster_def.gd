class_name MonsterDef
extends Resource
## Everything that makes one kind of monster: stats, looks and loot.
## Add a monster by saving a new MonsterDef in data/monsters/ (see ARCHITECTURE.md).
## Distances are in game pixels, speeds in pixels per physics tick (60 Hz).

@export var id: StringName
@export var display_name := ""
@export var level := 1
@export var max_hp := 10
## Damage dealt to the player on contact, before the player's defence.
@export var attack := 5
@export var exp_reward := 1
@export var speed := 1.0
## The hurtbox: width and height in game pixels, standing on the feet.
@export var size := Vector2(36, 30)
## Shown with a "Boss" badge and a wider HP bar.
@export var boss := false
## Ground monsters patrol their platform; flying ones do the same in the air above it.
@export var flying := false
@export var hover_height := 50.0

@export_group("Looks")
## Animated monsters: SpriteFrames with idle, move, attack, hurt and die (missing ones fall back to idle).
@export var sprite_frames: SpriteFrames
## Single-image monsters: animated procedurally with bobbing and squash.
@export var texture: Texture2D
## Multiplies the sprite's size in the world.
@export var sprite_scale := 1.0
## A light carried by the monster (Ember Boar's mane). Alpha 0 means no light.
@export var light_color := Color(0, 0, 0, 0)
@export var light_energy := 1.4
## Glowing particles drifting up off the monster (embers). Alpha 0 means none.
@export var aura_color := Color(0, 0, 0, 0)

@export_group("Loot")
@export var drops: Array[DropEntry] = []
## Ticks before a slain monster returns, picked between x and y.
@export var respawn_ticks := Vector2i(360, 540)
