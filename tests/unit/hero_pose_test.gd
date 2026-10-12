extends TestCase
## The hero's resting and moving poses: he stands still apart from a blink now and then, and
## whatever he holds points the way he faces (forward, or straight up or down), never back
## at where he came from. Weapon angles come from art/sheets/paperdoll_rig.json through
## tools/art/paperdoll_layers.py into the hero's rig.

## Frames where he isn't swinging: standing, walking, running with his arm forward, in the air,
## landing, crouched and flinching. Wind-ups, follow-throughs and run1-2 (his weapon arm swings
## back as he runs) are free to point back.
const REST_FRAMES: Array[String] = ["idle1", "blink", "walk1", "walk2", "walk3", "walk4",
	"run3", "run4", "jump", "fall", "land", "crouch", "hit", "hurt"]

func _frame(name: String) -> int:
	var frames: Array = Paperdoll.rig().get("frames", [])
	for i in frames.size():
		if frames[i].get("name") == name:
			return i
	return -1

func test_idle_is_one_still_frame_with_a_blink() -> void:
	var frames := HeroBody.FRAMES
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
			# a claw, and a gun's barrel, point along his forearm, wherever it hangs (Cory 2026-10-11:
			# a gun needn't point forward, it must sit in his hand)
			if h == null or kind in ["claw", "gun"]:
				continue
			# angle: clockwise from pointing right (the way he faces); up or down is fine
			check(cos(h["angle"]) > -0.02, "%s: the %s points forward or up/down, not back (%d degrees)" % [name, kind, roundi(rad_to_deg(h["angle"]))])

func test_weapon_reach_follows_the_art_however_it_was_drawn() -> void:
	# sword, wand and staff art is drawn slanted on the sheet: its reach is along the blade
	for kind in [&"sword", &"wand", &"staff", &"gun"]:
		check(Paperdoll.weapon_reach(kind) > 30.0, "a %s reaches well past the fist (%.0f)" % [kind, Paperdoll.weapon_reach(kind)])

func test_the_hero_is_smaller_than_the_townsfolk() -> void:
	var hero := HeroBody.FRAMES.get_frame_texture(&"idle", 0).get_image()
	var drawn := hero.get_used_rect().size.y * TDStage.TEXEL * HeroBody.SCALE / Paperdoll.ART_SCALE
	check_near(drawn, TDPlayer.HEIGHT, "HEIGHT is how tall he's drawn", 3.0)
	for npc: NpcDef in Content.npcs.values():
		var tex: Texture2D = npc.texture if npc.texture else (npc.sprite_frames.get_frame_texture(&"idle", 0) if npc.sprite_frames else null)
		if tex == null:
			continue
		var tall := tex.get_image().get_used_rect().size.y * TDNpc.texel(npc) / TDStage.art_density(tex)
		check(drawn < tall, "%s (%.0f px) stands taller than the hero (%.0f px)" % [npc.id, tall, drawn])

func test_he_blinks_now_and_then_while_standing() -> void:
	var rig := SpriteRig.new()
	rig.setup(HeroBody.FRAMES, null, 0.01)
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
	rig.setup(HeroBody.FRAMES, null, 0.01)
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

func test_weapons_are_held_in_the_right_spot() -> void:
	# grip_share: where the fist sits along the weapon, 0 = the back end, 1 = the tip
	var weapons: Dictionary = Paperdoll.rig().get("weapons", {})
	check(not weapons.is_empty(), "the rig records where each weapon is held")
	for name in weapons:
		var w: Dictionary = weapons[name]
		var share: float = w.get("grip_share", -1.0)
		match w.get("kind"):
			"sword":
				check(share >= 0.0 and share < 0.3, "%s is held by the handle (%.2f along)" % [name, share])
			"wand":
				check(share > 0.35 and share < 0.65, "%s is held near the middle (%.2f along)" % [name, share])
			"staff":
				check(share > 0.25 and share < 0.45, "%s is held low on the handle (%.2f along)" % [name, share])
		check_eq(int(w.get("dots_left", -1)), 0, "%s has no grip-marker dots left in the art" % name)

## His walk alternates a stride and a passing step (Paperdoll.PASSING_STEPS), so his legs
## move, and each passing step splits his legs where the art has a gap between his feet.
func test_the_walk_has_passing_steps_between_strides() -> void:
	var steps := Paperdoll.stride_steps()
	var passing: Array[int] = []
	for s in steps:
		passing.append(int(s.x))
	var walk: Array[bool] = []
	for i in HeroBody.FRAMES.get_frame_count(&"walk"):
		walk.append(Paperdoll.frame_index(HeroBody.FRAMES.get_frame_texture(&"walk", i)) in passing)
	check_eq(steps.size(), Paperdoll.PASSING_STEPS.size(), "every passing step is a frame of the rig")
	for i in walk.size():
		check(walk[i] != walk[(i + 1) % walk.size()], "walk frame %d and the next are a stride and a passing step" % (i + 1))
	var strip := Paperdoll.STRIP.get_image()
	var ground := int(Paperdoll.FRAME_SIZE.y) - 8
	for s in steps:
		var x := int(s.x * Paperdoll.FRAME_SIZE.x + s.y)
		check(strip.get_pixel(x, ground).a < 0.5, "frame %d splits between his feet" % int(s.x))

## The fall pose is painted leaning well over, so the rig turns him partway upright about his
## hips (HeroBody.UPRIGHT), mirrored with the way he faces, and straight again once he lands.
func test_the_fall_is_turned_partway_upright_about_his_hips() -> void:
	var rig := SpriteRig.new()
	rig.setup(HeroBody.FRAMES, null, 0.01)
	rig.upright = HeroBody.UPRIGHT
	add_child(rig)
	var body := rig.body
	var feet := Vector2(300, 200)
	var u: Dictionary = HeroBody.UPRIGHT[&"fall"]
	check(float(u["angle"]) > 0.0 and float(u["angle"]) < 15.0, "turned back some of the painted lean, not past upright")
	for dir in [1, -1]:
		rig.place(feet, 0.0)
		rig.play(&"fall")
		rig.face(dir)
		var side := 1.0 if dir > 0 else -1.0
		check_near(body.rotation.z, -deg_to_rad(float(u["angle"])) * side, "facing %d: turned clockwise on the art as drawn, mirrored" % dir, 0.0001)
		var px: Vector2 = u["pivot"]
		var pivot := Vector3((px.x - Paperdoll.FRAME_SIZE.x / 2.0) * side, Paperdoll.FRAME_SIZE.y - px.y, 0.0) * body.pixel_size
		var at := body.position + pivot.rotated(Vector3.BACK, body.rotation.z)
		check((at - (TDStage.to3d(feet) + pivot)).length() < 0.0001, "facing %d: his hips stay where they were drawn" % dir)
	rig.play(&"land")
	check_eq(body.rotation.z, 0.0, "landing stands him straight")
	check((body.position - TDStage.to3d(feet)).length() < 0.0001, "on his feet")
	rig.queue_free()
