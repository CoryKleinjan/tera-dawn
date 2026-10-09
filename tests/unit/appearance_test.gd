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
	for r in [Paperdoll.Region.SKIN, Paperdoll.Region.EYES, Paperdoll.Region.HAIR]:
		check_eq(d.tints[r].a, 0.0, "region %d keeps its painted colour" % r)
	check(d.overlays.is_empty(), "no stand-ins")

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

func test_looks_recolour_the_hero() -> void:
	var a := Appearance.new()
	a.skin = &"skin_umber"
	a.hair_color = &"hair_color_frost"
	a.eyes = &"eyes_leaf"
	var d := Paperdoll.dress(_look(a))
	check_eq(d.tints[Paperdoll.Region.SKIN], Content.look(&"skin_umber").color, "skin")
	check_eq(d.tints[Paperdoll.Region.HAIR], Content.look(&"hair_color_frost").color, "hair")
	check_eq(d.tints[Paperdoll.Region.EYES], Content.look(&"eyes_leaf").color, "eyes")

func test_hairstyles_and_faces_add_stand_ins_in_the_hair_colour() -> void:
	var a := Appearance.new()
	a.hair = &"hair_ponytail"
	a.face = &"face_rosy"
	a.hair_color = &"hair_color_moss"
	var d := Paperdoll.dress(_look(a))
	var shapes := d.overlays.map(func(o: Paperdoll.Overlay) -> StringName: return o.shape)
	check_eq(shapes, [&"hair_ponytail", &"blush"], "hair then face")
	check_eq(d.overlays[0].color, Content.look(&"hair_color_moss").color, "ponytail in the hair colour")

func test_gear_not_worn_is_hidden_and_bare_places_get_plain_clothes() -> void:
	var d := Paperdoll.dress(_look(Appearance.new()))
	for r in [Paperdoll.Region.CAPE, Paperdoll.Region.SHIELD, Paperdoll.Region.WEAPON]:
		check_eq(d.hidden[r], 1.0, "region %d hidden" % r)
	check_eq(d.tints[Paperdoll.Region.TOP].a, 1.0, "an undershirt")

func test_worn_gear_recolours_its_part_of_the_hero() -> void:
	var cape := Content.item(&"petal_cape") as EquipDef
	var d := Paperdoll.dress(_look(Appearance.new(), {"cape": "petal_cape", "top": "berry_smock"}))
	check_eq(d.hidden[Paperdoll.Region.CAPE], 0.0, "cape shown")
	var tint := d.tints[Paperdoll.Region.CAPE]
	check(Color(tint, 1.0).is_equal_approx(cape.worn_color()), "in the cape's colour")
	check_ne(d.tints[Paperdoll.Region.TOP], Paperdoll.dress(_look(Appearance.new(), {"top": "linen_tunic"})).tints[Paperdoll.Region.TOP], "two tops look different")

func test_hats_and_weapons_other_than_swords_get_stand_ins() -> void:
	var d := Paperdoll.dress(_look(Appearance.new(), {"hat": "iron_helm", "weapon": "willow_bow"}))
	var shapes := d.overlays.map(func(o: Paperdoll.Overlay) -> StringName: return o.shape)
	check_eq(shapes, [&"helm", &"bow"], "a helm and a bow")
	check_eq(d.hidden[Paperdoll.Region.WEAPON], 1.0, "the painted sword makes way for the bow")
	var sword := Paperdoll.dress(_look(Appearance.new(), {"weapon": "dawn_blade"}))
	check_eq(sword.hidden[Paperdoll.Region.WEAPON], 0.0, "a sword keeps the painted sword")
	check(sword.tints[Paperdoll.Region.WEAPON].a > 0.0, "in its own colour")
	check(sword.overlays.is_empty(), "with no stand-in")

func test_every_hat_and_weapon_has_a_stand_in() -> void:
	for item in Content.items.values():
		var e := item as EquipDef
		if e and e.slot in [EquipDef.Slot.HAT, EquipDef.Slot.WEAPON] and e.worn_frames == null:
			var shape := e.worn_shape()
			check(shape == &"sword" or LookShapes.has(shape), "%s: stand-in %s exists" % [e.id, shape])

func test_every_look_shape_is_a_stand_in_that_exists() -> void:
	for l: LookDef in Content.looks.values():
		if l.shape != &"":
			check(LookShapes.has(l.shape), "%s: %s" % [l.id, l.shape])

func test_every_stand_in_draws_something() -> void:
	for shape in LookShapes.SHAPES:
		var img := LookShapes.texture(shape, Color(0.4, 0.6, 0.9)).get_image()
		check(not img.is_invisible(), "%s draws" % shape)

func test_icon_colours_are_taken_from_the_icon() -> void:
	var leaf := Content.item(&"leaf_cap") as EquipDef
	var c := leaf.worn_color()
	check(c.g > c.r and c.g > c.b, "the leaf cap is green (%s)" % c)

func test_the_rig_has_every_frame_of_the_hero() -> void:
	var frames: Array = Paperdoll.rig()["frames"]
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
	check(Paperdoll.place_overlay(&"blush", climbing) == null, "no face while climbing away from the camera")
