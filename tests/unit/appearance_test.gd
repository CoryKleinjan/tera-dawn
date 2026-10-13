extends TestCase
## Appearance, the character creator's choices (NewCharacter) and how a look is drawn
## (Paperdoll), against the real looks in data/looks/.

func _beginner() -> JobDef:
	return Content.job(Character.START_JOB)

func _look(a: Appearance, gear := {}) -> Dictionary:
	return {"appearance": a.to_dict(), "gear": gear}

# ---------- Appearance ----------

func test_every_kind_has_creator_options() -> void:
	# one boy's and one girl's hairstyle for now (Cory 2026-10-13); four or more skin tones and
	# hair colours; the face and eyes are painted on each body, so there are none to pick
	check_eq(Content.looks_of(LookDef.Kind.HAIR).size(), 2, "a boy's and a girl's hairstyle")
	for kind in [LookDef.Kind.SKIN, LookDef.Kind.HAIR_COLOR]:
		check(Content.looks_of(kind).size() >= 4, "%s has at least 4 options" % LookDef.KIND_NAMES[kind])
	for kind in [LookDef.Kind.FACE, LookDef.Kind.EYES]:
		check(Content.looks_of(kind).is_empty(), "no %s options" % LookDef.KIND_NAMES[kind])

func test_a_new_appearance_takes_the_first_option_of_each_kind() -> void:
	var a := Appearance.new()
	for kind in LookDef.Kind.values():
		var options := Content.looks_of(kind)
		check_eq(a.part(kind), options[0] if not options.is_empty() else null, LookDef.KIND_NAMES[kind])

func test_the_default_look_is_the_boy_as_drawn() -> void:
	var d := Paperdoll.dress(_look(Appearance.new()))
	check_eq(d.frames, Paperdoll.BODIES[&"boy"], "the boy's body")
	check_eq(d.tints[Paperdoll.Region.SKIN].a, 0.0, "his skin keeps its painted colour")
	check(d.weapon_kind == &"", "no weapon")
	check(d.head_cut == null, "his whole head")
	var hair := Content.looks_of(LookDef.Kind.HAIR)[0]
	check_eq(d.layers.size(), 1, "only his hair over him")
	check(d.layers[0].strip == Paperdoll.hair_strip(hair, &"") and d.layers[0].strip != null, "his hair")

func test_the_hairstyle_picks_the_body() -> void:
	for hair in Content.looks_of(LookDef.Kind.HAIR):
		check(Paperdoll.BODIES.has(hair.body), "%s is on a body" % hair.id)
		var a := Appearance.new()
		a.hair = hair.id
		check_eq(Paperdoll.dress(_look(a)).frames, Paperdoll.BODIES.get(hair.body), "%s: its body" % hair.id)
	check_eq(Content.look(&"hair_ponytail").body, &"girl", "the ponytail is the girl's")

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
	b.load_dict({"hair": "no_such_hair", "skin": String(a.hair_color)})
	check_eq(b.hair, a.hair, "an unknown hair keeps the current one")
	check_eq(b.skin, a.skin, "a hair colour isn't a skin")

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
	var made := {"look": {"hair": "hair_ponytail", "skin": "nope"}, "outfit": ["dawnbreaker_claymore", "reed_sandals", "no_item"]}
	var n := NewCharacter.from_dict(made)
	check_eq(n.appearance.hair, &"hair_ponytail", "a real hairstyle")
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
	n.appearance.hair_color = Content.looks_of(LookDef.Kind.HAIR_COLOR)[-1].id
	var c := Character.create("Pip", Character.START_JOB, n)
	var back := Character.create("Pip")
	back.load_dict(c.to_dict())
	check_eq(back.appearance.hair_color, n.appearance.hair_color, "hair colour saved")

func test_a_save_from_before_appearances_gets_the_default_look() -> void:
	var c := Character.create("Old")
	var data := c.to_dict()
	data.erase("appearance")
	var back := Character.create("Old")
	back.load_dict(data)
	check_eq(back.appearance.to_dict(), Appearance.new().to_dict(), "default look")

# ---------- Paperdoll ----------

const HAT_SHAPES: Array[StringName] = [&"helm", &"tricorn", &"bandana", &"hood", &"wizard"]

func _hair_layer(d: Paperdoll, a: Appearance, shape := &"") -> Paperdoll.Layer:
	var strip := Paperdoll.hair_strip(a.part(LookDef.Kind.HAIR), shape)
	for l in d.layers:
		if strip and l.strip == strip:
			return l
	return null

func _strip_layer(d: Paperdoll, strip: Texture2D) -> Paperdoll.Layer:
	for l in d.layers:
		if strip and l.strip == strip:
			return l
	return null

func test_looks_recolour_the_hero() -> void:
	var a := Appearance.new()
	a.skin = &"skin_umber"
	a.hair_color = &"hair_color_frost"
	var d := Paperdoll.dress(_look(a))
	check_eq(d.tints[Paperdoll.Region.SKIN], Content.look(&"skin_umber").color, "skin")
	check_eq(_hair_layer(d, a).tint, Content.look(&"hair_color_frost").color, "hair")

func test_every_hairstyle_has_its_hair_bare_and_under_each_hat_shape() -> void:
	# the hair under each hat follows that shape's template cell (Cory 2026-10-13)
	for hair in Content.looks_of(LookDef.Kind.HAIR):
		for shape in [&""] + HAT_SHAPES:
			var strip := Paperdoll.hair_strip(hair, shape)
			if check(strip != null, "%s %s has hair" % [hair.id, shape]):
				check_eq(strip.get_size(), Paperdoll.STRIP.get_size(), "%s %s is laid out like the body" % [hair.id, shape])
	for shape in HAT_SHAPES:
		check(ResourceLoader.exists(Paperdoll.head_cut_path(shape)), "a %s cuts his head" % shape)

func test_a_hat_swaps_the_hair_for_its_shapes() -> void:
	for hair in Content.looks_of(LookDef.Kind.HAIR):
		var a := Appearance.new()
		a.hair = hair.id
		var d := Paperdoll.dress(_look(a, {"hat": "squire_helm"}))
		check(_hair_layer(d, a, &"helm") != null, "%s: the helm's hair" % hair.id)
		check(_hair_layer(d, a) == null, "%s: not the bare hair" % hair.id)
		check_eq(d.head_cut, load(Paperdoll.head_cut_path(&"helm")), "%s: his head cut under it" % hair.id)
		var helm := _strip_layer(d, Paperdoll.worn_strip(Content.item(&"squire_helm") as EquipDef))
		check(helm != null and d.layers.find(helm) > d.layers.find(_hair_layer(d, a, &"helm")), "%s: the helm over the hair" % hair.id)

func test_worn_gear_is_its_own_art() -> void:
	var d := Paperdoll.dress(_look(Appearance.new(), {"top": "squire_jerkin", "bottom": "squire_trousers"}))
	var top := _strip_layer(d, Paperdoll.worn_strip(Content.item(&"squire_jerkin") as EquipDef))
	var bottom := _strip_layer(d, Paperdoll.worn_strip(Content.item(&"squire_trousers") as EquipDef))
	check(top != null and bottom != null, "the jerkin and trousers are drawn")
	if top and bottom:
		check(d.layers.find(bottom) < d.layers.find(top), "the jerkin over the trousers")
		check_eq(top.tint, Color.WHITE, "in their painted colours")
		check_eq(top.strip.get_size(), Paperdoll.STRIP.get_size(), "laid out like the body")
	var plain := Paperdoll.dress(_look(Appearance.new(), {"top": "linen_tunic"}))
	check_eq(plain.layers.size(), 1, "gear with no art yet draws nothing (his hair only)")

func test_gear_art_is_named_for_items() -> void:
	# a worn picture without an item is art nobody wears
	var dir := DirAccess.open(Paperdoll.LAYER_DIR)
	for f in dir.get_files():
		if f.begins_with("worn_item_") and f.ends_with(".png"):
			var id := StringName(f.trim_prefix("worn_item_").trim_suffix(".png"))
			check(Content.items.has(id), "%s is an item" % id)

func test_the_rig_has_every_frame_of_the_hero() -> void:
	var frames: Array = Paperdoll.rig()["frames"]
	check_eq(Vector2(Paperdoll.rig()["frame_size"][0], Paperdoll.rig()["frame_size"][1]), Paperdoll.FRAME_SIZE, "FRAME_SIZE matches the art")
	check_eq(frames.size(), int(Paperdoll.STRIP.get_width() / Paperdoll.FRAME_SIZE.x), "one rig entry per frame")
	check_eq(Paperdoll.MASK.get_size(), Paperdoll.STRIP.get_size(), "the region map matches the strip")
	for body in Paperdoll.BODIES:
		var anims: SpriteFrames = Paperdoll.BODIES[body]
		check_eq(anims.get_animation_names(), Paperdoll.FRAMES.get_animation_names(), "%s has every animation" % body)
		for anim in anims.get_animation_names():
			for i in anims.get_frame_count(anim):
				var f := Paperdoll.frame_index(anims.get_frame_texture(anim, i))
				check(Paperdoll.anchor(f, &"head_top") != null, "%s %s %d has a head" % [body, anim, i])
				check_eq(frames[f].get("body"), String(body), "%s %s %d is on its own body" % [body, anim, i])

func test_a_weapon_without_a_hold_is_held_as_a_sword() -> void:
	check_eq(Paperdoll.kind_of(Content.item(&"willow_bow") as EquipDef), Paperdoll.DEFAULT_WEAPON, "until weapons are drawn")
