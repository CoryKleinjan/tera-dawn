class_name TDAvatar
extends Node2D
## Another player on the same map. Their own game moves them; the server passes on where
## they are and what they're doing (an animation name), and this glides there.

## How far it moves toward the reported position each tick (0..1).
const FOLLOW := 0.3

var world: TDWorld
var peer := 0
var char_name := ""
var level := 1
var target := Vector2.ZERO
var face := 1
var animation := &"idle"
var flags := 0
var known := false
var job := &""
var guild := ""
var speech := ""
var speech_t := 0
## How they're drawn: their painted layers and pet (see HeroBody).
var body: HeroBody
var companion: TDCompanion:
	get:
		return body.companion if body else null
var pet: StringName = &""
## What they wear, place -> EquipDef (drawn by their HeroBody).
var worn := {}

static func create(w: TDWorld, peer_id: int) -> TDAvatar:
	var a := TDAvatar.new()
	a.world = w
	a.peer = peer_id
	return a

## Takes the server's latest [peer, x, y, face, animation, flags] (SnapshotCodec).
func apply(state: Array) -> void:
	target = Vector2(state[1], state[2])
	face = state[3]
	# their own game sends what they're doing; the server passes on a skill's motion
	var anim := StringName(state[4])
	animation = &"idle" if anim == SkillDef.SPELL else anim # spells make no motion
	flags = state[5]
	if not known or position.distance_to(target) > 300.0:
		position = target # first sight or a portal hop: no gliding across the map
	known = true

## Takes their [name, level, job, guild, pet, worn gear], sent when it changes.
func apply_info(info: Array) -> void:
	char_name = info[0]
	level = info[1]
	job = StringName(str(info[2]))
	guild = str(info[3])
	pet = StringName(str(info[4]))
	worn = Equipment.defs_from_ids(info[5]) if info.size() > 5 and info[5] is Dictionary else {}

## They used a skill: they make its motion (a buff or spell makes none).
func play_skill(skill: SkillDef) -> void:
	if skill == null or skill.is_spell():
		return
	if skill.move and skill.move.style != MoveDef.Style.CHARGE:
		return # only a Charge swings; the other moves show in how they move
	animation = skill.animation

func fainted() -> bool:
	return flags & SnapshotFlags.PLAYER_FAINTED != 0

func step() -> void:
	position += (target - position) * FOLLOW
	if speech_t > 0:
		speech_t -= 1

func _ready() -> void:
	body = HeroBody.new(self, world, TDStage.Z_OTHER_PLAYER)

func _process(_delta: float) -> void:
	if body == null or world == null or world.map == null:
		return
	companion.visible = known
	body.visible = known
	body.draw(face, pet, animation, worn)

## Their name tag (and guild) under their feet, put in `tags` for the overlay to draw.
func draw_tag(tags: TDNameTags, at: Vector2) -> void:
	if known and not fainted():
		tags.add_name(at + Vector2(0, 4), char_name, Palette.MIST, guild)
