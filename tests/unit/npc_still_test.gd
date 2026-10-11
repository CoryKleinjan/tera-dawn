extends TestCase
## NPCs stand perfectly still: their two idle frames are separate drawings that shifted them
## around, and single-image NPCs used to breathe. SpriteRig.hold_still() keeps them on one frame.

func _held_rig(def: NpcDef) -> SpriteRig:
	var rig := SpriteRig.new()
	rig.setup(def.sprite_frames, def.texture, TDStage.TEXEL * def.sprite_scale)
	rig.hold_still()
	rig.play(&"idle")
	for i in 20:
		rig._process(0.25)
	return rig

func test_animated_npc_holds_its_first_idle_frame() -> void:
	var rig := _held_rig(load("res://data/npcs/guild_clerk.tres"))
	var body := rig.body as AnimatedSprite3D
	check(not body.is_playing(), "the idle loop doesn't play")
	check_eq(body.frame, 0, "on the first idle frame (the one in the dialogue portrait)")
	check_eq(body.scale, Vector3.ONE, "at full size")
	rig.free()

func test_single_image_npc_does_not_breathe() -> void:
	var rig := _held_rig(load("res://data/npcs/village_elder.tres"))
	check_eq(rig.body.scale, Vector3.ONE, "no breathing squash")
	check_eq(rig.body.rotation.z, 0.0, "no tilt")
	rig.free()
