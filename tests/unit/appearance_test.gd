extends TestCase
## Appearance, the character creator's choices (NewCharacter) and how a look is drawn
## (Paperdoll, LookShapes), against the real looks in data/looks/.

func _beginner() -> JobDef:
	return Content.job(Character.START_JOB)

func _look(a: Appearance, gear := {}) -> Dictionary:
	return {"appearance": a.to_dict(), "gear": gear}

# ---------- Appearance ----------

func test_every_kind_has_creator_options() -> void:
	for kind in LookDef.Kind.values():
		check(Content.looks_of(kind).size() >= 4, "%s has at least four options" % LookDef.KIND_NAMES[kind])

func test_a_new_appearance_takes_the_first_option_of_each_kind() -> void:
	var a := Appearance.new()
	for kind in LookDef.Kind.values():
		check_eq(a.part(kind), Content.looks_of(kind)[0], LookDef.KIND_NAMES[kind])

func test_the_default_look_is_the_hero_as_drawn() -> void:
	var d := Paperdoll.dress(_look(Appearance.new()))
	check_eq(d.tints[Paperdoll.Region.SKIN].a, 0.0, "his skin keeps its painted colour")
	check(d.overlays.is_empty(), "no hat or weapon")
	var hair := Content.looks_of(LookDef.Kind.HAIR)[0]
	check_eq(d.layers.filter(func(l: Paperdoll.Layer) -> bool: return l.frames == hair.frames).size(), 1, "his hair")

func test_cycling_wraps_both_ways() -> void:
	var a := Appearance.new()
	var options := Content.looks_of(LookDef.Kind.HAIR)
	a.cycle(LookDef.Kind.HAIR, -1)
	check_eq(a.hair, options[-1].id, "back from the first is the last")
	a.cycle(LookDef.Kind.HAIR, 1)
	check_eq(a.hair, options[0].id, "and forward again is the first")

func test_appearance_round_trips_and_ignores_bad_ids() -> void:
	var a := Appearance.random(_rng())
	var b := Appearance.new()
	b.load_dict(a.to_dict())
	check_eq(b.to_dict(), a.to_dict(), "round trip")
	b.load_dict({"hair": "no_such_hair", "skin": String(a.eyes)})
	check_eq(b.hair, a.hair, "an unknown hair keeps the current one")
	check_eq(b.skin, a.skin, "an eye colour isn't a skin")

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng

# ---------- NewCharacter ----------

func test_the_creator_offers_a_top_bottom_and_shoes_to_beginners() -> void:
	var kinds := NewCharacter.outfit_kinds(_beginner())
	check_eq(kinds, [EquipDef.Slot.TOP, EquipDef.Slot.BOTTOM, EquipDef.Slot.SHOES], "outfit kinds")
	for kind in kinds:
		check(NewCharacter.outfit_options(_beginner(), kind).size() >= 3, "three or more %s" % EquipDef.SLOT_NAMES[kind])
	for e in _beginner().creator_gear:
		check_eq(e.required_level, 0, "%s can be worn at level 1" % e.id)
		check(e.jobs.is_empty(), "%s fits any job" % e.id)

func test_the_default_outfit_is_the_jobs_own_starting_gear() -> void:
	var n := NewCharacter.new()
	check_eq(n.outfit[EquipDef.Slot.TOP].id, &"linen_tunic", "top")
	check_eq(n.outfit[EquipDef.Slot.BOTTOM].id, &"trail_pants", "bottom")
	check(n.outfit.has(EquipDef.Slot.SHOES), "shoes picked too")
	var ids := n.starting_gear(_beginner()).map(func(e: EquipDef) -> StringName: return e.id)
	check_has(ids, &"training_sword", "the starting sword stays")

func test_an_outfit_choice_replaces_that_starting_piece() -> void:
	var n := NewCharacter.new()
	n.cycle_outfit(_beginner(), EquipDef.Slot.TOP, 1)
	var top: EquipDef = n.outfit[EquipDef.Slot.TOP]
	check_ne(top.id, &"linen_tunic", "a different top")
	var gear := n.starting_gear(_beginner())
	check_has(gear, top, "worn")
	check(not Content.item(&"linen_tunic") in gear, "the tunic isn't")

func test_choices_survive_the_trip_to_the_server() -> void:
	var n := NewCharacter.new()
	n.roll(_beginner(), _rng())
	var back := NewCharacter.from_dict(n.to_dict())
	check_eq(back.appearance.to_dict(), n.appearance.to_dict(), "appearance")
	check_eq(back.to_dict()["outfit"], n.to_dict()["outfit"], "outfit")

func test_the_server_only_accepts_what_the_creator_offers() -> void:
	var made := {"look": {"hair": "hair_long", "skin": "nope"}, "outfit": ["dawnbreaker_claymore", "reed_sandals", "no_item"]}
	var n := NewCharacter.from_dict(made)
	check_eq(n.appearance.hair, &"hair_long", "a real hairstyle")
	check_eq(n.appearance.skin, Appearance.new().skin, "an unknown skin is the default")
	var ids := n.starting_gear(_beginner()).map(func(e: EquipDef) -> StringName: return e.id)
	check(not &"dawnbreaker_claymore" in ids, "gear the creator doesn't offer is ignored")
	check_has(ids, &"reed_sandals", "offered shoes are kept")

func test_a_look_left_out_of_the_creator_cant_be_picked() -> void:
	var hidden_look := LookDef.new()
	hidden_look.id = &"hair_secret"
	hidden_look.kind = LookDef.Kind.HAIR
	hidden_look.creator = false
	Content.looks[hidden_look.id] = hidden_look
	var n := NewCharacter.from_dict({"look": {"hair": "hair_secret"}})
	check_eq(n.appearance.hair, Appearance.new().hair, "not offered: the default")
	var a := Appearance.new()
	a.load_dict({"hair": "hair_secret"})
	check_eq(a.hair, &"hair_secret", "but a saved character can still have it")
	Content.looks.erase(hidden_look.id)

func test_create_uses_the_choices() -> void:
	var n := NewCharacter.new()
	n.appearance.hair = &"hair_ponytail"
	n.outfit[EquipDef.Slot.SHOES] = Content.item(&"clay_clogs")
	var c := Character.create("Pip", Character.START_JOB, n)
	check_eq(c.job.id, Character.START_JOB, "starts in the starting job")
	check_eq(c.appearance.hair, &"hair_ponytail", "hair")
	check_eq(c.equipment.at(&"shoes").item.id, &"clay_clogs", "shoes worn")
	check_eq(c.look()["gear"]["shoes"], "clay_clogs", "and shown")

func test_appearance_is_saved_with_the_character() -> void:
	var n := NewCharacter.new()
	n.appearance.eyes = &"eyes_violet"
	var c := Character.create("Pip", Character.START_JOB, n)
	var back := Character.create("Pip")
	back.load_dict(c.to_dict())
	check_eq(back.appearance.eyes, &"eyes_violet", "eyes saved")

func test_a_save_from_before_appearances_gets_the_default_look() -> void:
	var c := Character.create("Old")
	var data := c.to_dict()
	data.erase("appearance")
	var back := Character.create("Old")
	back.load_dict(data)
	check_eq(back.appearance.to_dict(), Appearance.new().to_dict(), "default look")

# ---------- Paperdoll ----------

func _layer(d: Paperdoll, frames: SpriteFrames) -> Paperdoll.Layer:
	for l in d.layers:
		if l.frames == frames:
			return l
	return null

func test_looks_recolour_the_hero() -> void:
	var a := Appearance.new()
	a.skin = &"skin_umber"
	a.hair_color = &"hair_color_frost"
	a.eyes = &"eyes_leaf"
	var d := Paperdoll.dress(_look(a))
	check_eq(d.tints[Paperdoll.Region.SKIN], Content.look(&"skin_umber").color, "skin")
	check_eq(d.tints[Paperdoll.Region.TOP], Content.look(&"skin_umber").color, "a bare chest is skin too")
	check_eq(_layer(d, a.part(LookDef.Kind.HAIR).frames).tint, Content.look(&"hair_color_frost").color, "hair")
	check_eq(_layer(d, a.part(LookDef.Kind.FACE).detail_frames).tint, Content.look(&"eyes_leaf").color, "eyes")

func test_every_face_and_hairstyle_has_art() -> void:
	for kind in [LookDef.Kind.FACE, LookDef.Kind.HAIR]:
		for l in Content.looks_of(kind):
			check(l.frames != null, "%s has art" % l.id)
			if kind == LookDef.Kind.FACE:
				check(l.detail_frames != null, "%s has irises" % l.id)
			for anim in Paperdoll.FRAMES.get_animation_names():
				check_eq(l.frames.get_frame_count(anim), Paperdoll.FRAMES.get_frame_count(anim), "%s %s plays with the body" % [l.id, anim])

func test_long_hair_hangs_behind_and_a_hat_swaps_the_hair() -> void:
	var a := Appearance.new()
	a.hair = &"hair_long"
	var hair := Content.look(&"hair_long")
	var bare := Paperdoll.dress(_look(a))
	check(_layer(bare, hair.back_frames).behind, "the back of long hair is behind him")
	check(not _layer(bare, hair.frames).behind, "the front over him")
	var hatted := Paperdoll.dress(_look(a, {"hat": "iron_helm"}))
	check(_layer(hatted, hair.hat_frames) != null, "the under-hat hair")
	check(_layer(hatted, hair.frames) == null and _layer(hatted, hair.back_frames) == null, "instead of the rest")

func test_bare_places_and_worn_clothes() -> void:
	var d := Paperdoll.dress(_look(Appearance.new()))
	check(d.layers.all(func(l: Paperdoll.Layer) -> bool: return l.frames != Paperdoll.CAPE and l.frames != Paperdoll.SHIELD), "no cape or shield")
	check_eq(d.tints[Paperdoll.Region.BOTTOM].a, 0.0, "his own shorts")
	var top := Content.item(&"berry_smock") as EquipDef
	var dressed := Paperdoll.dress(_look(Appearance.new(), {"top": "berry_smock"}))
	check(Color(dressed.tints[Paperdoll.Region.TOP], 1.0).is_equal_approx(top.worn_color()), "a top colours his chest")
	check_ne(dressed.tints[Paperdoll.Region.TOP], Paperdoll.dress(_look(Appearance.new(), {"top": "linen_tunic"})).tints[Paperdoll.Region.TOP], "two tops look different")

func test_a_cape_and_shield_are_tinted_layers() -> void:
	var cape := Content.item(&"petal_cape") as EquipDef
	var d := Paperdoll.dress(_look(Appearance.new(), {"cape": "petal_cape", "shield": "oak_shield"}))
	var behind := _layer(d, Paperdoll.CAPE)
	check(behind != null and behind.behind, "a cape behind him")
	check(Color(behind.tint, 1.0).is_equal_approx(cape.worn_color()), "in the cape's colour")
	check(not _layer(d, Paperdoll.CAPE_BACK_VIEW).behind, "and over his back when he climbs")
	check(_layer(d, Paperdoll.SHIELD) != null, "a shield")

func test_hats_and_weapons_are_drawn_on_top() -> void:
	var d := Paperdoll.dress(_look(Appearance.new(), {"hat": "iron_helm", "weapon": "willow_bow"}))
	var shapes := d.overlays.map(func(o: Paperdoll.Overlay) -> StringName: return o.shape)
	check_eq(shapes, [&"helm", &"bow"], "a helm and a bow")
	var sword := Paperdoll.dress(_look(Appearance.new(), {"weapon": "dawn_blade"}))
	check_eq(sword.overlays.map(func(o: Paperdoll.Overlay) -> StringName: return o.shape), [&"sword"], "a sword")

func test_every_hat_and_weapon_has_a_picture() -> void:
	for item in Content.items.values():
		var e := item as EquipDef
		if e and e.slot in [EquipDef.Slot.HAT, EquipDef.Slot.WEAPON] and e.worn_frames == null:
			check(LookShapes.has(e.worn_shape()), "%s: %s exists" % [e.id, e.worn_shape()])

func test_every_picture_draws_something() -> void:
	for shape in LookShapes.SHAPES.keys() + LookShapes.WEAPONS:
		var img := LookShapes.texture(shape, Color(0.4, 0.6, 0.9)).get_image()
		check(not img.is_invisible(), "%s draws" % shape)
	for kind in LookShapes.WEAPONS:
		check(LookShapes.pivot(kind) != Vector2.ZERO, "%s has a grip" % kind)

func test_icon_colours_are_taken_from_the_icon() -> void:
	var leaf := Content.item(&"leaf_cap") as EquipDef
	var c := leaf.worn_color()
	check(c.g > c.r and c.g > c.b, "the leaf cap is green (%s)" % c)

func test_the_rig_has_every_frame_of_the_hero() -> void:
	var frames: Array = Paperdoll.rig()["frames"]
	check_eq(Vector2(Paperdoll.rig()["frame_size"][0], Paperdoll.rig()["frame_size"][1]), Paperdoll.FRAME_SIZE, "FRAME_SIZE matches the art")
	check_eq(frames.size(), int(Paperdoll.STRIP.get_width() / Paperdoll.FRAME_SIZE.x), "one rig entry per frame")
	check_eq(Paperdoll.MASK.get_size(), Paperdoll.STRIP.get_size(), "the region map matches the strip")
	for anim in Paperdoll.FRAMES.get_animation_names():
		for i in Paperdoll.FRAMES.get_frame_count(anim):
			var f := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(anim, i))
			check(Paperdoll.anchor(f, &"head_top") != null, "%s %d has a head" % [anim, i])

func test_stand_ins_sit_on_the_hero_and_mirror() -> void:
	var idle := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(&"idle", 0))
	var hat: Dictionary = Paperdoll.place_overlay(&"cap", idle)
	var head: Vector2 = Paperdoll.anchor(idle, &"head")
	check(absf(hat["centre"].x - head.x) < 12 and hat["centre"].y < head.y, "a cap sits on top of the head")
	var left: Dictionary = Paperdoll.place_overlay(&"cap", idle, true)
	check_near(left["centre"].x, Paperdoll.FRAME_SIZE.x - hat["centre"].x, "mirrored across the frame")
	var climbing := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(&"rope", 0))
	check(Paperdoll.anchor(climbing, &"face") == null, "no face while climbing away from the camera")
	var cap: Dictionary = Paperdoll.place_overlay(&"cap", climbing)
	var top: Vector2 = Paperdoll.anchor(climbing, &"head_top")
	check(absf(cap["centre"].x - top.x) < 8, "a hat stays on his head while he climbs")

func test_the_weapon_hand_and_shield_sit_on_the_body() -> void:
	var img := Paperdoll.MASK.get_image()
	img.decompress()
	var frames: Array = Paperdoll.rig()["frames"]
	for i in frames.size():
		for key in [&"grip", &"shield"]:
			var at: Variant = Paperdoll.anchor(i, key)
			if at == null:
				continue
			var on_body := false
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var p := Vector2i(at) + Vector2i(i * int(Paperdoll.FRAME_SIZE.x) + dx, dy)
					if p.x >= i * Paperdoll.FRAME_SIZE.x and p.x < (i + 1) * Paperdoll.FRAME_SIZE.x and p.y >= 0 and p.y < img.get_height():
						on_body = on_body or img.get_pixelv(p).a > 0.5
			check(on_body, "%s: %s is on the body" % [frames[i]["name"], key])

func test_hats_turn_with_the_head() -> void:
	var lying := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(&"faint", 1))
	var hat: Dictionary = Paperdoll.place_overlay(&"cap", lying)
	check(absf(hat["angle"]) > 1.0, "the cap lies down with him")
