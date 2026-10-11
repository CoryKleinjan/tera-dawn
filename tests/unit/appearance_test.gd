extends TestCase
## Appearance, the character creator's choices (NewCharacter) and how a look is drawn
## (Paperdoll), against the real looks in data/looks/.

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
	check(d.weapon_kind == &"", "no weapon")
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
	# hair drawn in every pose holds what hangs behind his head; a one-piece style has a back layer
	check(hair.back_frames == null or _layer(bare, hair.back_frames).behind, "the back of long hair is behind him")
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
	var cut := _layer(dressed, Paperdoll.worn_cut(top))
	check(cut != null and not cut.behind, "a top is its cut, over him")
	check(Color(cut.tint, 1.0).is_equal_approx(top.worn_color()), "in its colour")
	check_eq(dressed.tints[Paperdoll.Region.TOP], dressed.tints[Paperdoll.Region.SKIN], "skin shows around it")
	var tunic := Paperdoll.dress(_look(Appearance.new(), {"top": "linen_tunic"}))
	check_ne(cut.tint, _layer(tunic, Paperdoll.worn_cut(Content.item(&"linen_tunic"))).tint, "two tops look different")
	var pants := Content.item(&"trail_pants") as EquipDef
	var legs := Paperdoll.dress(_look(Appearance.new(), {"bottom": "trail_pants"}))
	check(_layer(legs, Paperdoll.worn_cut(pants)) != null, "a bottom is its cut")
	check(Color(legs.tints[Paperdoll.Region.BOTTOM], 1.0).is_equal_approx(pants.worn_color()), "over his shorts in its colour, so no grey shows at its edges")

func test_every_top_bottom_and_pair_of_shoes_has_a_cut() -> void:
	for item in Content.items.values():
		var e := item as EquipDef
		if e and EquipDef.WORN_STYLE_PLACES.has(e.slot) and e.worn_frames == null:
			check_ne(e.worn_style, &"", "%s has a worn_style" % e.id)
			var cut := Paperdoll.worn_cut(e)
			check(cut != null, "%s: %s exists" % [e.id, e.worn_style_path()])
			if cut:
				for anim in Paperdoll.FRAMES.get_animation_names():
					check_eq(cut.get_frame_count(anim), Paperdoll.FRAMES.get_frame_count(anim), "%s %s plays with the body" % [e.id, anim])

func test_the_creator_preview_shows_the_starting_outfit() -> void:
	var n := NewCharacter.new()
	var gear := {}
	for kind in [EquipDef.Slot.TOP, EquipDef.Slot.BOTTOM, EquipDef.Slot.SHOES]:
		gear[EquipDef.WORN_STYLE_PLACES[kind]] = String(n.outfit[kind].id)
	var d := Paperdoll.dress(_look(n.appearance, gear))
	for kind in [EquipDef.Slot.TOP, EquipDef.Slot.BOTTOM, EquipDef.Slot.SHOES]:
		check(_layer(d, Paperdoll.worn_cut(n.outfit[kind])) != null, "%s shows" % n.outfit[kind].id)

## Where the face's middle is on a rig frame (paperdoll_layers.py FACE_AT: forward and down
## from the head's centre, in head radii, turned with the head).
func _face_centre(f: Dictionary) -> Vector2:
	var r := float(f["head_size"][0]) / 2.0
	var head := Vector2(f["head"][0], f["head"][1])
	return head + (Vector2(0.2, 0.3) * r).rotated(deg_to_rad(float(f["head_angle"])))

func test_hair_under_a_hat_leaves_the_face_clear() -> void:
	var frames: Array = Paperdoll.rig()["frames"]
	for hair in Content.looks_of(LookDef.Kind.HAIR):
		if hair.hat_frames == null:
			continue
		var img := (hair.hat_frames.get_frame_texture(&"idle", 0) as AtlasTexture).atlas.get_image()
		if img.is_compressed():
			img.decompress()
		for i in frames.size():
			var f: Dictionary = frames[i]
			if f["back"]:
				continue
			var r := float(f["head_size"][0]) / 2.0
			var at := _face_centre(f) + Vector2(i * Paperdoll.FRAME_SIZE.x, 0)
			var covered := 0
			var total := 0
			for y in range(int(at.y - r * 0.4), int(at.y + r * 0.4) + 1):
				for x in range(int(at.x - r * 0.4), int(at.x + r * 0.4) + 1):
					if Vector2(x, y).distance_to(at) <= r * 0.4:
						total += 1
						covered += 1 if img.get_pixel(x, y).a > 0.5 else 0
			check(covered <= total * 0.02, "%s frame %s: the face shows under a hat (%d of %d covered)" % [hair.id, f["name"], covered, total])

func test_a_cape_and_shield_are_tinted_layers() -> void:
	var cape := Content.item(&"petal_cape") as EquipDef
	var d := Paperdoll.dress(_look(Appearance.new(), {"cape": "petal_cape", "shield": "oak_shield"}))
	var behind := _layer(d, Paperdoll.CAPE)
	check(behind != null and behind.behind, "a cape behind him")
	check(Color(behind.tint, 1.0).is_equal_approx(cape.worn_color()), "in the cape's colour")
	check(not _layer(d, Paperdoll.CAPE_FRONT).behind, "its clasp in front, and all of it over his back when he climbs")
	check(behind.gear, "shaded in its colour like gear")
	check(_layer(d, Paperdoll.SHIELD) != null, "a shield")

func test_gloves_are_a_tinted_layer_over_him() -> void:
	var gloves := Content.item(&"work_gloves") as EquipDef
	var d := Paperdoll.dress(_look(Appearance.new(), {"gloves": "work_gloves"}))
	var layer := _layer(d, Paperdoll.GLOVES)
	check(layer != null and not layer.behind, "gloves over him")
	check(Color(layer.tint, 1.0).is_equal_approx(gloves.worn_color()), "in the gloves' colour")

func test_hats_are_a_layer_over_his_hair() -> void:
	var helm := Content.item(&"iron_helm") as EquipDef
	var d := Paperdoll.dress(_look(Appearance.new(), {"hat": "iron_helm"}))
	var hat := _layer(d, Paperdoll.hat_frames(helm))
	check(hat != null and not hat.behind and hat.gear, "a helm over him, shaded in its colour")
	check(Paperdoll.hat_frames(helm).resource_path.ends_with("hat_helm.tres"), "drawn as a helm")
	check(Color(hat.tint, 1.0).is_equal_approx(helm.worn_color()), "in the helm's colour")
	var hair := Content.looks_of(LookDef.Kind.HAIR)[0]
	check(d.layers.find(_layer(d, hair.hat_frames)) < d.layers.find(hat), "over the hair left under it")

func test_a_hat_sits_on_his_head() -> void:
	var cap := Paperdoll.hat_frames(Content.item(&"leaf_cap") as EquipDef)
	for anim in [&"idle", &"rope"]:
		var tex := cap.get_frame_texture(anim, 0) as AtlasTexture
		var img := tex.atlas.get_image()
		img.decompress()
		var box := img.get_region(Rect2i(tex.region)).get_used_rect()
		var f := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(anim, 0))
		var head: Vector2 = Paperdoll.anchor(f, &"head")
		check(box.size.x > 0, "%s: the cap draws" % anim)
		check(absf(box.get_center().x - head.x) < 20 * Paperdoll.ART_SCALE and box.position.y < head.y, "%s: on top of his head" % anim)

func test_a_weapon_is_a_layer_in_his_fist() -> void:
	var bow := Content.item(&"willow_bow") as EquipDef
	var d := Paperdoll.dress(_look(Appearance.new(), {"weapon": "willow_bow"}))
	var held := Paperdoll.weapon_layers(bow)
	var front := _layer(d, held["front"])
	check(front != null and not front.behind, "the bow is drawn over him")
	check(Color(front.tint, 1.0).is_equal_approx(held["tint"]), "in the bow's colour, or its own picture's")
	check(held["tint"] == Color.WHITE or Color(held["tint"], 1.0).is_equal_approx(bow.worn_color()), "the bow's colour tints the template")
	check(held.has("behind") == false or _layer(d, held["behind"]).behind, "a behind twin goes under him")

func test_every_weapon_has_layers_and_a_hold() -> void:
	for item in Content.items.values():
		var e := item as EquipDef
		if e and e.slot == EquipDef.Slot.WEAPON and e.worn_frames == null:
			var held := Paperdoll.weapon_layers(e)
			check(held["front"] is SpriteFrames, "%s has a layer" % e.id)
			check(Paperdoll.weapon_reach(Paperdoll.kind_of(e)) > 0.0, "%s reaches past the fist" % e.id)
	var attack := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(&"attack", 1))
	for kind in ["sword", "bow", "wand", "staff", "claw", "knuckle", "gun"]:
		check(Paperdoll.hold(attack, kind) != null, "%s is in his hand mid-attack" % kind)
	var climbing := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(&"rope", 0))
	check(Paperdoll.hold(climbing, &"sword") == null, "his hands are on the rope")

func test_every_hat_has_its_shape_drawn() -> void:
	for item in Content.items.values():
		var e := item as EquipDef
		if e and e.slot == EquipDef.Slot.HAT and e.worn_frames == null and e.look_shape != &"":
			check(ResourceLoader.exists(Paperdoll.HAT_DIR + String(e.look_shape) + ".tres"), "%s: a %s layer" % [e.id, e.look_shape])

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

func test_no_face_while_climbing() -> void:
	var climbing := Paperdoll.frame_index(Paperdoll.FRAMES.get_frame_texture(&"rope", 0))
	check(Paperdoll.anchor(climbing, &"face") == null, "no face while climbing away from the camera")

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
			var near := int(3 * Paperdoll.ART_SCALE)
			for dy in range(-near, near + 1):
				for dx in range(-near, near + 1):
					var p := Vector2i(at) + Vector2i(i * int(Paperdoll.FRAME_SIZE.x) + dx, dy)
					if p.x >= i * Paperdoll.FRAME_SIZE.x and p.x < (i + 1) * Paperdoll.FRAME_SIZE.x and p.y >= 0 and p.y < img.get_height():
						on_body = on_body or img.get_pixelv(p).a > 0.5
			check(on_body, "%s: %s is on the body" % [frames[i]["name"], key])
