extends TestCase
## Standing still, the hero breathes (rises and settles a little from his feet up) and blinks
## now and then, in the world and in menus alike. NPCs don't (npc_still_test).

func _rig() -> SpriteRig:
	var rig := HeroBody.make_rig(TDStage.PRIORITY_PLAYER)
	rig.play(&"idle")
	return rig

func _run(rig: SpriteRig, anim: StringName, seconds: float) -> void:
	for i in int(seconds / 0.05):
		rig.play(anim)
		rig._process(0.05)

func test_he_breathes_from_his_feet_while_standing() -> void:
	var rig := _rig()
	var tallest := 1.0
	for i in 80: # 4 s, over a whole breath
		rig.play(&"idle")
		rig._process(0.05)
		tallest = maxf(tallest, rig.body.scale.y)
	check(tallest > 1.0 + SpriteRig.BREATH_RISE * 0.5, "he rises as he breathes in (tallest %.4f)" % tallest)
	check(tallest <= 1.0 + SpriteRig.BREATH_RISE + 0.0001, "only slightly")
	check_eq(rig.body.offset.y, (rig.body as AnimatedSprite3D).sprite_frames.get_frame_texture(&"idle", 0).get_height() / 2.0,
		"the body's origin stays at his feet, so they don't move")
	rig.free()

func test_he_stops_breathing_when_he_walks() -> void:
	var rig := _rig()
	_run(rig, &"idle", 1.75) # the top of a breath
	_run(rig, &"walk", 1.0)
	check_eq(rig.body.scale, Vector3.ONE, "back to his drawn size on the move")
	rig.free()

func test_his_gear_moves_with_him() -> void:
	var rig := _rig()
	rig.dress({"appearance": {}, "gear": {}})
	check(rig.paperdoll.get_parent() == rig.body, "his layers hang off the body, so breathing stretches them together")
	rig.free()

func test_he_blinks_every_few_seconds() -> void:
	var rig := _rig()
	var blinks := 0
	var last := &"idle"
	for i in 400: # 20 s
		rig.play(&"idle")
		rig._process(0.05)
		var a := (rig.body as AnimatedSprite3D).animation
		if a == &"blink" and last != &"blink":
			blinks += 1
		last = a
	check(blinks >= int(20.0 / SpriteRig.BLINK_EVERY.y), "blinks now and then (%d in 20 s)" % blinks)
	check(blinks <= int(20.0 / SpriteRig.BLINK_EVERY.x) * 2 + 1, "but not all the time")
	rig.free()

func test_he_blinks_and_breathes_in_menus() -> void:
	var view := PaperdollView.new()
	var rig := view._rig
	check(not rig._frozen, "the menu picks his frames without freezing his idle life")
	var blinked := false
	var tallest := 1.0
	for i in 160: # 8 s
		rig.play(&"idle")
		rig._process(0.05)
		blinked = blinked or (rig.body as AnimatedSprite3D).animation == &"blink"
		tallest = maxf(tallest, rig.body.scale.y)
	check(blinked, "he blinks")
	check(tallest > 1.0, "and breathes")
	view.free()
