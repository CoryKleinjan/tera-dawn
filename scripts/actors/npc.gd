class_name TDNpc
extends Node2D
## A townsperson standing on a platform. Walk up and press Up to open their dialogue
## window (see TDDialogueWindow).

var world: TDWorld
var def: NpcDef
var face := 1
var rig: SpriteRig

static func create(w: TDWorld, placement: NpcPlacement, p: Platform) -> TDNpc:
	var n := TDNpc.new()
	n.world = w
	n.def = placement.npc
	n.face = placement.face
	n.position = Vector2(placement.x, p.y)
	return n

func _ready() -> void:
	rig = SpriteRig.new()
	rig.setup(def.sprite_frames, def.texture, TDStage.TEXEL * def.sprite_scale, 40.0)
	add_child(rig)

## Opens their dialogue window.
func talk() -> void:
	world.hud.open_dialogue(self)

## The picture shown in their dialogue window: their sprite, or the first idle frame.
func portrait() -> Texture2D:
	if def.texture:
		return def.texture
	if def.sprite_frames and def.sprite_frames.has_animation(&"idle"):
		return def.sprite_frames.get_frame_texture(&"idle", 0)
	return null

func step() -> void:
	pass

func _process(_delta: float) -> void:
	if rig == null:
		return
	rig.place(position, TDStage.Z_NPC, position.y)
	rig.face(face)

## Name tag under the NPC, and a hint when the player is close enough to talk.
func draw_tag(ci: CanvasItem, at: Vector2, top: Vector2) -> void:
	UiSkin.draw_name_tag(ci, at + Vector2(0, 4), def.display_name, Palette.SUN)
	if def.title != "":
		DrawUtil.text(ci, Game.ui_font, at + Vector2(0, 36), def.title, 10, Palette.MIST, 0, 4, Palette.NIGHT)
	var p := world.player
	if world.started and absf(p.position.x - position.x) < 50 and absf(p.position.y - position.y) < 8:
		UiSkin.draw_hint(ci, top + Vector2(0, -10), "↑ Talk")
