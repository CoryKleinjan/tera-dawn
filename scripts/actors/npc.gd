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
	rig.set_tint(def.tint)
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

## "?" when you can hand a quest in to them, "!" when they have one for you, "..." when
## one you're doing goes back to them, else "".
func quest_marker() -> String:
	var me := Game.me
	var offers := false
	var waiting := false
	for q in Content.quests_of(def.id):
		var s := me.quests.status(q, me)
		if s == QuestLog.Status.READY and q.turn_in_npc() == def.id:
			return "?"
		offers = offers or (s == QuestLog.Status.AVAILABLE and q.giver == def.id)
		waiting = waiting or (s == QuestLog.Status.ACTIVE and q.turn_in_npc() == def.id)
	return "!" if offers else ("..." if waiting else "")

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
	var near := world.started and absf(p.position.x - position.x) < 50 and absf(p.position.y - position.y) < 8
	if near:
		UiSkin.draw_hint(ci, top + Vector2(0, -10), "↑ Talk")
	var marker := quest_marker() if world.started else ""
	if marker != "":
		var bob := sin(Time.get_ticks_msec() / 220.0) * 3.0
		UiSkin.draw_quest_marker(ci, top + Vector2(0, (-36.0 if near else -6.0) + bob), marker)
