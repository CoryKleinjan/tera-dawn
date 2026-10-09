class_name ItemDef
extends Resource
## An item that can drop and be picked up. Currency (Dawnshards) goes straight to the wallet;
## everything else goes into the inventory tab that `tab()` names.
## Plain ItemDefs are Etc items (monster parts, quest pieces); EquipDef, UseDef, ChairDef,
## PetDef and CardDef extend this.

## The inventory tabs, in the order the window shows them.
enum Tab { EQUIP, USE, ETC, SETUP }
const TAB_NAMES := ["Equip", "Use", "Etc", "Setup"]

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Shown in the HUD and menus.
@export var icon: Texture2D
## Shown lying in the world; frames alternate to make it sparkle. Empty means use the icon.
@export var world_frames: Array[Texture2D] = []
## Shown instead when a single drop is at least `pile_amount`.
@export var pile_texture: Texture2D
@export var pile_amount := 20
@export var sprite_scale := 1.0
@export var glow_color := Color(1.0, 0.75, 0.35)
@export var is_currency := false
@export var pickup_effect: EffectDef
## How many fit in one inventory slot. Equipment never stacks.
@export var max_stack := 200
## What a shop pays for one, in Dawnshards.
@export var sell_price := 1
## Only drops while a quest wants it, and can't be dropped or sold.
@export var quest_item := false

## Which inventory tab this item goes in.
func tab() -> Tab:
	return Tab.ETC

func stack_size() -> int:
	return maxi(1, max_stack)

## The texture to show on the ground at frame `i`.
func world_texture(i := 0) -> Texture2D:
	if world_frames.is_empty():
		return icon
	return world_frames[i % world_frames.size()]
