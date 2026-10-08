class_name ItemDef
extends Resource
## An item that can drop and be picked up. Currency (Dawnshards) goes straight to the wallet.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Shown in the HUD and menus.
@export var icon: Texture2D
## Shown lying in the world; frames alternate to make it sparkle.
@export var world_frames: Array[Texture2D] = []
## Shown instead when a single drop is at least `pile_amount`.
@export var pile_texture: Texture2D
@export var pile_amount := 20
@export var sprite_scale := 1.0
@export var glow_color := Color(1.0, 0.75, 0.35)
@export var is_currency := false
@export var pickup_effect: EffectDef
