extends TestCase
## The hero's resting and moving poses: he stands still apart from a blink now and then, and
## whatever he holds points the way he faces (forward, or straight up or down), never back
## at where he came from. Weapon angles come from art/sheets/paperdoll_rig.json through
## tools/art/paperdoll_layers.py into the hero's rig.

## Frames where he isn't swinging: standing, walking, running, in the air, landing, crouched
## and flinching. Wind-ups and follow-throughs are free to point back.
const REST_FRAMES: Array[String] = ["idle1", "blink", "walk1", "walk2", "walk3", "walk4",
	"run1", "run2", "run3", "run4", "jump", "fall", "land", "crouch", "hit", "hurt"]

func _frame(name: String) -> int:
	var frames: Array = Paperdoll.rig().get("frames", [])
	for i in frames.size():
		if frames[i].get("name") == name:
			return i
	return -1

func test_idle_is_one_still_frame_with_a_blink() -> void:
	var frames := TDPlayer.HERO_FRAMES
	check_eq(frames.get_frame_count(&"idle"), 1, "idle holds still")
	check(frames.has_animation(&"blink"), "the hero has a blink")
	if not frames.has_animation(&"blink"):
		return
	var idle := Paperdoll.frame_index(frames.get_frame_texture(&"idle", 0))
	var blink := Paperdoll.frame_index(frames.get_frame_texture(&"blink", 0))
	check(idle != blink, "the blink is its own frame (its face has the eyes shut)")
	var strip := Paperdoll.STRIP.get_image()
	var w := int(Paperdoll.FRAME_SIZE.x)
	var h := int(Paperdoll.FRAME_SIZE.y)
	check(strip.get_region(Rect2i(idle * w, 0, w, h)).get_data() == strip.get_region(Rect2i(blink * w, 0, w, h)).get_data(),
		"and the same body as idle, so only the eyes move")
	check_eq(Paperdoll.hold(blink, &"sword"), Paperdoll.hold(idle, &"sword"), "holding the weapon the same way")

func test_held_weapons_point_forward_at_rest_and_on_the_move() -> void:
	for name in REST_FRAMES:
		var f := _frame(name)
		if not check(f >= 0, "the rig has a %s frame" % name):
			continue
		for kind in Paperdoll.rig()["frames"][f].get("holds", {}):
			var h: Variant = Paperdoll.hold(f, StringName(kind))
			if h == null:
				continue
			# angle: clockwise from pointing right (the way he faces); up or down is fine
			check(cos(h["angle"]) > -0.02, "%s: the %s points forward or up/down, not back (%d degrees)" % [name, kind, roundi(rad_to_deg(h["angle"]))])

func test_weapon_reach_follows_the_art_however_it_was_drawn() -> void:
	# sword, wand and staff art is drawn slanted on the sheet: its reach is along the blade
	for kind in [&"sword", &"wand", &"staff", &"gun"]:
		check(Paperdoll.weapon_reach(kind) > 30.0, "a %s reaches well past the fist (%.0f)" % [kind, Paperdoll.weapon_reach(kind)])

func test_the_hero_is_smaller_than_the_townsfolk() -> void:
	var hero := TDPlayer.HERO_FRAMES.get_frame_texture(&"idle", 0).get_image()
	var drawn := hero.get_used_rect().size.y * TDStage.TEXEL * TDPlayer.HERO_SCALE / Paperdoll.ART_SCALE
	check_near(drawn, TDPlayer.HEIGHT, "HEIGHT is how tall he's drawn", 3.0)
	for npc: NpcDef in Content.npcs.values():
		var tex: Texture2D = npc.texture if npc.texture else (npc.sprite_frames.get_frame_texture(&"idle", 0) if npc.sprite_frames else null)
		if tex == null:
			continue
		var tall := tex.get_image().get_used_rect().size.y * TDStage.TEXEL * npc.sprite_scale
		check(drawn < tall, "%s (%.0f px) stands taller than the hero (%.0f px)" % [npc.id, tall, drawn])

func test_he_blinks_now_and_then_while_standing() -> void:
	var rig := SpriteRig.new()
	rig.setup(TDPlayer.HERO_FRAMES, null, 0.01, 30.0)
	add_child(rig)
	var body := rig.body as AnimatedSprite3D
	rig.play(&"idle")
	rig._blink(SpriteRig.BLINK_EVERY.y + 0.1)
	check_eq(body.animation, &"blink", "the eyes shut after a while")
	rig.play(&"idle")
	check_eq(body.animation, &"blink", "standing on doesn't cut the blink short")
	rig._blink(SpriteRig.BLINK_TIME + 0.01)
	check_eq(body.animation, &"idle", "and open again")
	rig._blink(SpriteRig.BLINK_EVERY.x * 0.5)
	check_eq(body.animation, &"idle", "not straight away again")
	rig.play(&"walk")
	check_eq(body.animation, &"walk", "walking off ends it")
	rig.queue_free()

func test_speeding_up_into_a_run_keeps_his_step() -> void:
	var rig := SpriteRig.new()
	rig.setup(TDPlayer.HERO_FRAMES, null, 0.01, 30.0)
	add_child(rig)
	var body := rig.body as AnimatedSprite3D
	rig.play(&"walk")
	body.set_frame_and_progress(2, 0.5)
	rig.play(&"run")
	check_eq(body.animation, &"run", "running")
	check_eq(body.frame, 2, "on the same step of the cycle")
	rig.play(&"idle")
	rig.play(&"walk")
	check_eq(body.frame, 0, "starting from a stand begins the cycle")
	rig.queue_free()
