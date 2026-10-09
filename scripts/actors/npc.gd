class_name TDNpc
extends Node2D
## A townsperson standing on a platform. Walk up and press Up to hear their next line.

const SAY_TICKS := 300

var world: TDWorld
var def: NpcDef
var face := 1
var line := -1      # index of the line being said
var say_t := 0      # ticks left showing it
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

## Says the next line; the overlay draws it in a speech bubble.
func talk() -> void:
	if def.lines.is_empty():
		return
	line = (line + 1) % def.lines.size()
	say_t = SAY_TICKS

func speech() -> String:
	return def.lines[line] if say_t > 0 and line >= 0 else ""

func step() -> void:
	if say_t > 0:
		say_t -= 1
		if absf(world.player.position.x - position.x) > 160:
			say_t = 0

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
	if say_t > 0:
		UiSkin.draw_speech(ci, top + Vector2(0, -8), speech())
	elif world.started and absf(p.position.x - position.x) < 50 and absf(p.position.y - position.y) < 8:
		UiSkin.draw_hint(ci, top + Vector2(0, -10), "↑ Talk")
