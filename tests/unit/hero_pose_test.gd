extends TestCase
## The hero's resting poses: one standing frame and a blink (hero_idle_test), his size next to
## the townsfolk, and his blinking now and then.

func test_idle_is_one_still_frame_with_a_blink() -> void:
	for body in Paperdoll.BODIES:
		var frames: SpriteFrames = Paperdoll.BODIES[body]
		check_eq(frames.get_frame_count(&"idle"), 1, "%s: idle holds still" % body)
		if not check(frames.has_animation(&"blink"), "%s has a blink" % body):
			continue
		var idle := Paperdoll.frame_index(frames.get_frame_texture(&"idle", 0))
		var blink := Paperdoll.frame_index(frames.get_frame_texture(&"blink", 0))
		check(idle != blink, "%s: the blink is its own frame (its face has the eyes shut)" % body)

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
