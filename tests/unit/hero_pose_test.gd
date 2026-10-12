extends TestCase
## The hero's resting and moving poses: one standing frame and a blink (hero_idle_test), and
## every weapon kind held the same way in his front fist on every frame (Cory 2026-10-12:
## weapons keep their place in his hand in every picture). Weapon holds come from
## art/sheets/paperdoll_rig.json ("arm" and "holds") through tools/art/paperdoll_layers.py into
## the hero's rig.

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

# The only frames where a weapon kind leaves its angle to the forearm, each one Cory approved
# (tools/art/paperdoll/weapons.py APPROVED lists the same): the bow sitting, turned up off his
# knee clear of the floor (2026-10-12).
const APPROVED := {"bow": ["sit"]}

func test_every_weapon_keeps_its_grip_and_angle_to_the_forearm() -> void:
	# the rig's "arm" is his front fist and the way his forearm points; each kind sits in that
	# fist at one angle to the forearm, on the other side of it where the rig's arm "mirror" says (falling, his arm
	# flung up behind his head), but never bigger or smaller, so nothing turns or flips in his hand
	var frames: Array = Paperdoll.rig().get("frames", [])
	var offsets := {}
	for f in frames.size():
		var fname: String = frames[f]["name"]
		var arm: Variant = frames[f].get("arm")
		for kind in frames[f].get("holds", {}):
			var h: Variant = Paperdoll.hold(f, StringName(kind))
			if not check(arm is Array and h != null, "%s: the %s is held only where the rig gives his front fist" % [fname, kind]):
				continue
			check_near(h["grip"].distance_to(Vector2(arm[0], arm[1])), 0.0, "%s: the %s is in his front fist" % [fname, kind], 0.6)
			if fname in APPROVED.get(kind, []):
				continue
			var off := absf(wrapf(rad_to_deg(h["angle"]) - float(arm[2]), -180.0, 180.0))
			if not offsets.has(kind):
				offsets[kind] = off
			check_near(off, offsets[kind], "%s: the %s keeps its angle to his forearm (%.0f, not %.0f degrees)" % [fname, kind, off, offsets[kind]], 0.6)

func test_every_weapon_is_in_his_hand_on_every_frame_but_climbing_and_levelup() -> void:
	var frames: Array = Paperdoll.rig().get("frames", [])
	var kinds: Array = frames[_frame("idle1")].get("holds", {}).keys()
	check(kinds.size() >= 7, "idle1 holds every weapon kind (%d)" % kinds.size())
	for f in frames.size():
		var fname: String = frames[f]["name"]
		var held: Dictionary = frames[f].get("holds", {})
		if frames[f].get("back", false) or fname == "levelup":
			check(held.is_empty(), "%s: no weapon in his hand" % fname)
			continue
		for kind in kinds:
			check(held.has(kind), "%s: the %s is in his hand" % [fname, kind])

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
	if rig._twice: # now and then he blinks twice in a row, but never three times
		rig._blink(SpriteRig.DOUBLE_BLINK_GAP + 0.01)
		check_eq(body.animation, &"blink", "a second blink straight after")
		rig._blink(SpriteRig.BLINK_TIME + 0.01)
		check_eq(body.animation, &"idle", "open again after the second")
		check(not rig._twice, "never a third")
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
			"wand", "staff":
				check(share > 0.35 and share < 0.65, "%s is held near the middle (%.2f along)" % [name, share])
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
