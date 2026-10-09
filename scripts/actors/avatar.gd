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
## The sign over their shop, or "" when they aren't minding one.
var shop_title := ""
var speech := ""
var speech_t := 0
var rig: SpriteRig
## Their chair and pet.
var companion: TDCompanion
var chair: StringName = &""
var pet: StringName = &""
## Their appearance and the gear that shows (Character.look()).
var look := {}
var _swing := false

static func create(w: TDWorld, peer_id: int) -> TDAvatar:
	var a := TDAvatar.new()
	a.world = w
	a.peer = peer_id
	return a

## Takes the server's latest [peer, name, x, y, face, animation, level, flags, job, guild,
## chair, pet, look, shop sign].
func apply(state: Array) -> void:
	char_name = state[1]
	target = Vector2(state[2], state[3])
	face = state[4]
	var anim := StringName(state[5])
	_swing = _swing or (anim != animation and anim in [&"attack", &"slash"])
	animation = anim
	level = state[6]
	flags = state[7]
	job = StringName(str(state[8])) if state.size() > 8 else &""
	guild = str(state[9]) if state.size() > 9 else ""
	chair = StringName(str(state[10])) if state.size() > 10 else &""
	pet = StringName(str(state[11])) if state.size() > 11 else &""
	if state.size() > 12 and state[12] is Dictionary:
		look = state[12]
	shop_title = str(state[13]) if state.size() > 13 else ""
	if not known or position.distance_to(target) > 300.0:
		position = target # first sight or a portal hop: no gliding across the map
	known = true

## They used a skill: restart its animation even if it's the same one as last time.
func play_skill(skill: SkillDef) -> void:
	if skill:
		animation = skill.animation
		_swing = true

func fainted() -> bool:
	return flags & SnapshotFlags.PLAYER_FAINTED != 0

func step() -> void:
	position += (target - position) * FOLLOW
	if speech_t > 0:
		speech_t -= 1

func _ready() -> void:
	rig = SpriteRig.new()
	rig.setup(TDPlayer.HERO_FRAMES, null, TDStage.TEXEL * TDPlayer.HERO_SCALE, 40.0)
	add_child(rig)
	companion = TDCompanion.new()
	add_child(companion)

func _process(_delta: float) -> void:
	if rig == null or world == null or world.map == null:
		return
	rig.visible = known
	var climbing := flags & SnapshotFlags.PLAYER_CLIMBING != 0
	var airborne := climbing or fainted() or world.layout.ground_below(position) - position.y > 200.0
	rig.place(position + Vector2(0, -companion.seat_lift()), TDStage.Z_OTHER_PLAYER, NAN if airborne else world.layout.ground_below(position))
	rig.play(&"faint" if fainted() else animation, _swing)
	_swing = false
	rig.face(1 if climbing else face)
	rig.dress(look)
	var blink := flags & SnapshotFlags.PLAYER_BLINK != 0 and not fainted() and Engine.get_physics_frames() % 8 < 4
	rig.set_opacity(0.0 if blink else 1.0)
	companion.visible = known
	companion.set_chair(chair)
	companion.set_pet(pet, position)
	companion.follow(position, face, TDStage.Z_OTHER_PLAYER, world.layout.ground_below(position))

## Name tag (and guild) under their feet, drawn by the overlay.
func draw_tag(ci: CanvasItem, at: Vector2) -> void:
	if known and not fainted():
		UiSkin.draw_name_tag(ci, at + Vector2(0, 4), char_name, Palette.MIST)
		if guild != "":
			UiSkin.draw_guild_tag(ci, at + Vector2(0, 26), guild)
