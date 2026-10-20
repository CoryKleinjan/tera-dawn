class_name NpcDef
extends Resource
## A townsperson the player can talk to. Place one on a map with an NpcPlacement.
## Pressing Up next to them opens their dialogue window: their greeting, then what they
## offer (chatting through `lines`, their shop, and more as the game grows).

@export var id: StringName
@export var display_name := ""
## A short role shown under the name ("Village Elder").
@export var title := ""
@export var texture: Texture2D
@export var sprite_frames: SpriteFrames
@export var sprite_scale := 1.0
## What they say when the dialogue window opens.
@export_multiline var greeting := ""
## Small talk, one line each time "Chat" is picked; it loops back to the start.
@export_multiline var lines: PackedStringArray = []
## What they sell, or null if they don't run a shop.
@export var shop: ShopDef
## Jobs they can advance characters into (job ids).
@export var instructs: Array[StringName] = []
## Keeps players' storage.
@export var storage := false
## Sets runes in gear (TDEnchantWindow; the fee is each RuneDef.fee).
@export var enchants := false
## Trips they offer (ships, wagons...).
@export var travel: Array[TravelRoute] = []
