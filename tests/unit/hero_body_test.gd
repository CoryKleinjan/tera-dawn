extends TestCase
## The painted hero (HeroBody, HeroLookDef): every look plays everything he does, attacks and
## skills share the attack, and frames run at their own speed.

## What TDPlayer._animation() says he is doing, outside skills and cutscenes.
const MOVES := [&"idle", &"walk", &"jump", &"jump_apex", &"fall", &"land", &"hurt", &"faint",
	&"sit", &"crouch", &"dash", &"surge_charge", &"surge", &"surge_end", &"slam", &"slam_land",
	&"double_jump", &"attack"]

func test_every_look_has_every_move() -> void:
	check(not HeroLookDef.all().is_empty(), "there is a look")
	for look in HeroLookDef.all():
		for m in MOVES:
			check(look.frames.has_animation(m), "%s has %s" % [look.id, m])

func test_every_outfit_has_every_move_and_a_real_look() -> void:
	for o: HeroOutfitDef in Content.outfits.values():
		check(Content.looks.has(o.look), "%s paints a look there is" % o.id)
		check(o.armor != &"" or o.weapon != &"", "%s wears something" % o.id)
		for piece in [o.armor, o.weapon]:
			check(piece == &"" or Content.items.get(piece) is EquipDef, "%s wears gear there is (%s)" % [o.id, piece])
		for m in MOVES:
			check(o.frames.has_animation(m), "%s has %s" % [o.id, m])

func test_gear_with_no_painting_leaves_his_look_as_painted() -> void:
	var look := HeroLookDef.all()[0]
	for s: GearSetDef in Content.gear_sets.values():
		for pair in [[s.armor.id, s.weapon.id], [s.armor.id, &""], [&"", s.weapon.id]]:
			if HeroOutfitDef.find(look.id, pair[0], pair[1]) == null:
				check(look.frames_for(pair[0], pair[1]) == look.frames, "%s / %s: as painted" % pair)
	check(look.frames_for(&"", &"") == look.frames, "nothing worn: as painted")

func test_looks_come_in_order_and_an_unknown_one_is_the_first() -> void:
	var looks := HeroLookDef.all()
	for i in looks.size() - 1:
		check(looks[i].order <= looks[i + 1].order, "in order")
	check(HeroLookDef.of(&"no_such_look") == looks[0], "the first look")
	check(HeroLookDef.of(looks[-1].id) == looks[-1], "a look by its id")

func test_skill_motions_play_the_attack_and_poses_stand() -> void:
	var frames := HeroLookDef.all()[0].frames
	check_eq(HeroBody.resolve(frames, &"walk"), &"walk", "its own")
	for skill: SkillDef in Content.skills.values():
		if not frames.has_animation(skill.animation):
			check_eq(HeroBody.resolve(frames, skill.animation), HeroBody.ATTACK, "%s plays the attack" % skill.id)
	for pose: StringName in HeroBody.STANDING:
		check_eq(HeroBody.resolve(frames, pose), &"idle", "%s stands" % pose)

func test_frames_run_at_their_speed_and_hold_at_the_end() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation(&"a")
	frames.set_animation_speed(&"a", 10.0)
	frames.set_animation_loop(&"a", false)
	for i in 3:
		frames.add_frame(&"a", PlaceholderTexture2D.new(), 2.0 if i == 1 else 1.0)
	check_eq(HeroBody.frame_at(frames, &"a", 0.05), 0, "first")
	check_eq(HeroBody.frame_at(frames, &"a", 0.25), 1, "the long middle frame")
	check_eq(HeroBody.frame_at(frames, &"a", 0.35), 2, "last")
	check_eq(HeroBody.frame_at(frames, &"a", 5.0), 2, "held on the last")
	frames.set_animation_loop(&"a", true)
	check_eq(HeroBody.frame_at(frames, &"a", 0.45), 0, "a loop goes round")

func test_timed_moves_spread_over_their_ticks() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation(&"a")
	frames.set_animation_speed(&"a", 100.0)
	frames.set_animation_loop(&"a", false)
	for i in 3:
		frames.add_frame(&"a", PlaceholderTexture2D.new(), 2.0 if i == 1 else 1.0)
	var second := Engine.physics_ticks_per_second
	check_eq(HeroBody.frame_at(frames, &"a", 0.2, second), 0, "first")
	check_eq(HeroBody.frame_at(frames, &"a", 0.5, second), 1, "the long middle frame")
	check_eq(HeroBody.frame_at(frames, &"a", 0.9, second), 2, "last, just as the move ends")
	for move: StringName in HeroBody.TIMED:
		check(HeroLookDef.all()[0].frames.has_animation(move), "%s is painted" % move)

func test_the_looks_stand_about_as_tall_as_he_is() -> void:
	for look in HeroLookDef.all():
		var tex := look.frames.get_frame_texture(&"idle", 0)
		var used := TextureBounds.used_rect(tex)
		var tall := used.size.y * TDStage.TEXEL / TDStage.art_density(tex)
		check(absf(tall - TDPlayer.HEIGHT) < TDPlayer.HEIGHT * 0.1, "%s stands %.0f px tall" % [look.id, tall])
