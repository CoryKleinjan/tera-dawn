extends TestCase
## How each weapon fights (WeaponStyle) and the hero animations that carry it: every motion
## plays an animation the hero has, with the weapon in his hand on every frame of it, except
## buffs and spells, which play none (a flash of the skill's colour instead).

const KINDS: Array[StringName] = [&"sword", &"bow", &"wand", &"staff", &"star", &"knuckle", &"gun"]

func _look(weapon: String) -> Dictionary:
	return {"appearance": {}, "gear": {"weapon": weapon} if weapon != "" else {}}

func test_each_weapon_kind_has_its_own_motions() -> void:
	check_eq(WeaponStyle.animation(&"sword", &"attack"), &"attack", "a sword swings")
	check_eq(WeaponStyle.animation(&"bow", &"attack"), &"shoot", "a bow shoots")
	check_eq(WeaponStyle.animation(&"gun", &"attack"), &"gun", "a gun fires")
	check_eq(WeaponStyle.animation(&"star", &"attack"), &"throw", "a star is thrown")
	check_eq(WeaponStyle.animation(&"knuckle", &"attack"), &"punch", "knuckles punch")
	check_eq(WeaponStyle.animation(&"staff", &"attack"), &"heavy", "a staff smashes two-handed")
	check_eq(WeaponStyle.animation(&"", &"attack"), &"punch", "bare hands punch")
	check_eq(WeaponStyle.animation(&"bow", &"throw"), &"throw", "a named animation plays as it is")
	check(WeaponStyle.is_spell(WeaponStyle.animation(&"bow", &"cast")), "cast is a spell whatever the weapon")
	check(WeaponStyle.is_spell(WeaponStyle.animation(&"wand", &"slash")), "a wand's big move is a spell")

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
	var frames := HeroBody.FRAMES
	for kind in KINDS:
		for motion in [&"attack", &"slash"]:
			var anim := WeaponStyle.animation(kind, motion)
			if WeaponStyle.is_spell(anim):
				check(not frames.has_animation(anim), "spells (%s %s) have no pose" % [kind, motion])
				continue
			check(frames.has_animation(anim), "%s %s plays %s, which the hero has" % [kind, motion, anim])
			if not frames.has_animation(anim):
				continue
			check(not frames.get_animation_loop(anim), "%s plays once" % anim)

func test_every_action_restarts_and_has_timing() -> void:
	var frames := HeroBody.FRAMES
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
		while not HeroBody.FRAMES.has_animation(a) and SpriteRig.FALLBACK.has(a):
			a = SpriteRig.FALLBACK[a]
		check(HeroBody.FRAMES.has_animation(a), "%s plays as %s" % [anim, a])

func test_the_walk_keeps_step_with_him() -> void:
	check_near(HeroBody.stride_speed(&"walk", HeroBody.STRIDE_SPEED), 1.0, "as drawn at stride speed")
	check(HeroBody.stride_speed(&"walk", 1.0) < HeroBody.stride_speed(&"walk", 3.0), "slower when he's slower")
	check_eq(HeroBody.stride_speed(&"attack", 3.0), 1.0, "a swing isn't sped up")

func test_buffs_and_spells_flash_their_own_colour() -> void:
	var seen := {}
	for skill: SkillDef in Content.skills.values():
		var spell := skill.kind == SkillDef.Kind.BUFF or skill.magic or WeaponStyle.is_spell(skill.animation)
		if not spell:
			continue
		check(skill.flash.a > 0.0, "%s flashes a colour" % skill.id)
		var key := skill.flash.to_html()
		check(not seen.has(key), "%s has its own colour (%s has it too)" % [skill.id, seen.get(key, "")])
		seen[key] = skill.id
