class_name TDAvatar
extends Node2D
## Another player on the same map. Their own game moves them; the server passes on where
## they are and which animation they're playing, and this glides there and plays it.

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
## How they're drawn: the rig, their chair and pet (see HeroBody).
var body: HeroBody
var rig: SpriteRig:
	get:
		return body.rig if body else null
var companion: TDCompanion:
	get:
		return body.companion if body else null
var chair: StringName = &""
var pet: StringName = &""
## Their appearance and the gear that shows (Character.look()).
var look := {}
## How far they moved sideways on the last tick (their walk keeps step with it).
var _moved_x := 0.0

static func create(w: TDWorld, peer_id: int) -> TDAvatar:
	var a := TDAvatar.new()
	a.world = w
	a.peer = peer_id
	return a

## Takes the server's latest [peer, x, y, face, animation, flags] (SnapshotCodec).
func apply(state: Array) -> void:
	target = Vector2(state[1], state[2])
	face = state[3]
	# their own game sends the animation it plays; the server passes on a skill's motion,
	# which plays as their weapon does it (WeaponStyle)
	var anim := WeaponStyle.animation_for(look, StringName(state[4]))
	if WeaponStyle.is_spell(anim):
		anim = &"idle" # spells make no motion (play_skill flashes them)
	if body and anim != animation and WeaponStyle.is_action(anim):
		body.restart()
	animation = anim
	flags = state[5]
	if not known or position.distance_to(target) > 300.0:
		position = target # first sight or a portal hop: no gliding across the map
	known = true

## Takes their [name, level, job, guild, chair, pet, look], sent when it changes.
func apply_info(info: Array) -> void:
	char_name = info[0]
	level = info[1]
	job = StringName(str(info[2]))
	guild = str(info[3])
	chair = StringName(str(info[4]))
	pet = StringName(str(info[5]))
	if info[6] is Dictionary:
		look = info[6]

## They used a skill: restart its animation even if it's the same one as last time (a buff
## or spell makes no motion: they flash its colour instead).
func play_skill(skill: SkillDef) -> void:
	if skill == null or body == null:
		return
	if skill.move and skill.move.style != MoveDef.Style.CHARGE:
		return # only a Charge swings; the other moves show in how they move
	var anim := body.use_skill(look, skill)
	if anim != &"":
		animation = anim

func fainted() -> bool:
	return flags & SnapshotFlags.PLAYER_FAINTED != 0

func step() -> void:
	var before := position.x
	position += (target - position) * FOLLOW
	_moved_x = position.x - before
	if speech_t > 0:
		speech_t -= 1

func _ready() -> void:
	body = HeroBody.new(self, world, TDStage.Z_OTHER_PLAYER)

func _process(_delta: float) -> void:
	if body == null or world == null or world.map == null:
		return
	rig.visible = known
	companion.visible = known
	var climbing := flags & SnapshotFlags.PLAYER_CLIMBING != 0
	var blinking := flags & SnapshotFlags.PLAYER_BLINK != 0 and not fainted()
	body.veil = HeroBody.HIDDEN_VEIL_OTHERS if flags & SnapshotFlags.PLAYER_HIDDEN != 0 else 1.0
	body.draw(&"faint" if fainted() else animation, HeroBody.stride_speed(animation, _moved_x), face, climbing, blinking, Engine.get_physics_frames(), chair, pet)
	rig.dress(look)

## Their name tag (and guild) under their feet, put in `tags` for the overlay to draw.
func draw_tag(tags: TDNameTags, at: Vector2) -> void:
	if known and not fainted():
		tags.add_name(at + Vector2(0, 4), char_name, Palette.MIST, guild)
