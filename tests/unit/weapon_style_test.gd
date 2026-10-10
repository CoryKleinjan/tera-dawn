extends TestCase
## How each weapon fights (WeaponStyle) and the hero animations that carry it: every motion
## plays an animation the hero has, with the weapon in his hand on every frame of it.

const KINDS: Array[StringName] = [&"sword", &"bow", &"wand", &"staff", &"claw", &"knuckle", &"gun"]

func _look(weapon: String) -> Dictionary:
	return {"appearance": {}, "gear": {"weapon": weapon} if weapon != "" else {}}

func test_each_weapon_kind_has_its_own_motions() -> void:
	check_eq(WeaponStyle.animation(&"sword", &"attack"), &"attack", "a sword swings")
	check_eq(WeaponStyle.animation(&"bow", &"attack"), &"shoot", "a bow shoots")
	check_eq(WeaponStyle.animation(&"gun", &"attack"), &"gun", "a gun fires")
	check_eq(WeaponStyle.animation(&"claw", &"attack"), &"throw", "a claw throws")
	check_eq(WeaponStyle.animation(&"knuckle", &"attack"), &"punch", "knuckles punch")
	check_eq(WeaponStyle.animation(&"staff", &"attack"), &"heavy", "a staff smashes two-handed")
	check_eq(WeaponStyle.animation(&"", &"attack"), &"punch", "bare hands punch")
	check_eq(WeaponStyle.animation(&"bow", &"cast"), &"cast", "a named animation plays as it is")

func test_every_weapon_in_the_game_has_a_style() -> void:
	for item in Content.items.values():
		var e := item as EquipDef
		if e and e.slot == EquipDef.Slot.WEAPON:
			check(WeaponStyle.MOTIONS.has(Paperdoll.kind_of(e)), "%s: %s has motions" % [e.id, Paperdoll.kind_of(e)])

func test_the_look_decides_the_motion() -> void:
	check_eq(WeaponStyle.kind_in(_look("willow_bow")), &"bow", "a bow in the look")
	check_eq(WeaponStyle.kind_in(_look("")), &"", "nothing in hand")
	check_eq(WeaponStyle.animation_for(_look("willow_bow"), &"attack"), &"shoot", "so the basic attack shoots")
	check_eq(WeaponStyle.animation_for(_look("dawn_blade"), &"slash"), &"slash", "and a sword slashes")

func test_every_motion_is_a_hero_animation_holding_the_weapon() -> void:
	var frames := TDPlayer.HERO_FRAMES
	for kind in KINDS:
		for motion in [&"attack", &"slash"]:
			var anim := WeaponStyle.animation(kind, motion)
			check(frames.has_animation(anim), "%s %s plays %s, which the hero has" % [kind, motion, anim])
			if not frames.has_animation(anim):
				continue
			check(not frames.get_animation_loop(anim), "%s plays once" % anim)
			for i in frames.get_frame_count(anim):
				var f := Paperdoll.frame_index(frames.get_frame_texture(anim, i))
				check(Paperdoll.hold(f, kind) != null, "%s frame %d has the %s in his hand" % [anim, i, kind])

func test_every_action_restarts_and_has_timing() -> void:
	var frames := TDPlayer.HERO_FRAMES
	for anim in WeaponStyle.ACTIONS:
		check(frames.has_animation(anim), "the hero has %s" % anim)
		var total := 0.0
		for i in frames.get_frame_count(anim):
			total += frames.get_frame_duration(anim, i)
		check(total / frames.get_animation_speed(anim) < 0.5, "%s is over within half a second" % anim)
	check(frames.get_frame_duration(&"attack", 0) > frames.get_frame_duration(&"attack", 1), "the wind-up holds longer than the blow")

func test_poses_still_to_draw_fall_back_to_ones_he_has() -> void:
	for anim in [&"ready", &"turn", &"skid", &"jump_apex"]:
		var a: StringName = anim
		while not TDPlayer.HERO_FRAMES.has_animation(a) and SpriteRig.FALLBACK.has(a):
			a = SpriteRig.FALLBACK[a]
		check(TDPlayer.HERO_FRAMES.has_animation(a), "%s plays as %s" % [anim, a])

func test_the_walk_keeps_step_with_him() -> void:
	check_near(TDPlayer.stride_speed(&"walk", TDPlayer.STRIDE_SPEED), 1.0, "as drawn at stride speed")
	check(TDPlayer.stride_speed(&"walk", 1.0) < TDPlayer.stride_speed(&"walk", 3.0), "slower when he's slower")
	check_eq(TDPlayer.stride_speed(&"attack", 3.0), 1.0, "a swing isn't sped up")
