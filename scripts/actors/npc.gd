class_name TDNpc
extends Node2D
## A townsperson standing on a platform. Walk up and press Up to open their dialogue
## window (see TDDialogueWindow).

## Everyone's NPC art is drawn this much smaller than other art (TDStage.TEXEL), so the
## townsfolk stand a little taller than the hero (HeroBody.SCALE), as in MapleStory.
const SCALE := 0.78

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
	rig.setup(def.sprite_frames, def.texture, texel(def))
	rig.set_tint(def.tint)
	add_child(rig)
	rig.hold_still()

## Game pixels per art pixel for `npc`'s art.
static func texel(npc: NpcDef) -> float:
	return TDStage.TEXEL * SCALE * npc.sprite_scale

## How big they're drawn, in game pixels (feet to the top of their art).
func body_size() -> Vector2:
	return rig.body.get_item_rect().size * rig.body.pixel_size * TDStage.PX

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
	rig.place(position, TDStage.Z_NPC)
	rig.face(face)

## Name tag (and title) under the NPC, put in `tags`, which keeps tags apart; the quest
## marker over them, and a hint when the player is close enough to talk.
func draw_tag(ci: CanvasItem, at: Vector2, top: Vector2, tags: TDNameTags) -> void:
	var tag_top := at + Vector2(0, 4)
	var rect := UiSkin.name_tag_rect(tag_top, def.display_name)
	if def.title != "":
		var w := DrawUtil.text_width(Game.ui_font, def.title, 10)
		rect = rect.merge(Rect2(tag_top.x - w / 2.0, rect.end.y, w, 15))
	var title := def.title
	tags.add(rect, func(c: CanvasItem, offset: Vector2) -> void:
		UiSkin.draw_name_tag(c, tag_top + offset, def.display_name, Palette.SUN)
		if title != "":
			DrawUtil.text(c, Game.ui_font, tag_top + offset + Vector2(0, 32), title, 10, Palette.MIST, 0, 4, Palette.NIGHT))
	var p := world.player
	var near := world.started and absf(p.position.x - position.x) < 50 and absf(p.position.y - position.y) < 8
	if near:
		UiSkin.draw_hint(ci, top + Vector2(0, -10), "↑ Talk")
	var marker := quest_marker() if world.started else ""
	if marker != "":
		var bob := sin(Time.get_ticks_msec() / 220.0) * 3.0
		UiSkin.draw_quest_marker(ci, top + Vector2(0, (-36.0 if near else -6.0) + bob), marker)
