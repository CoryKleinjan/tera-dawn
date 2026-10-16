extends TestCase
## Shots leave from the weapon (HeroBody.muzzle_of): a held piece's muzzle on the frame the
## shot leaves on, else his shooting fist there.

func _worn(ids: Array) -> Dictionary:
	var out := {}
	for id: StringName in ids:
		var e: EquipDef = Content.item(id)
		out[&"shield" if e.slot == EquipDef.Slot.SHIELD else &"weapon"] = e
	return out

func test_a_wand_shot_leaves_from_its_tip() -> void:
	var worn := _worn([&"novice_wand", &"novice_tome"])
	var at: Vector2 = HeroBody.muzzle_of(worn, &"slash", 1)
	check(at.x > 0.0 and at.y < -TDPlayer.CHEST / 2.0, "in front of him and up off the ground: %s" % at)
	var back: Vector2 = HeroBody.muzzle_of(worn, &"slash", -1)
	check_eq(back, Vector2(-at.x, at.y), "facing left, the same spot mirrored")

func test_a_flipped_weapon_shoots_from_its_mirrored_tip() -> void:
	var worn := _worn([&"novice_wand"])
	var wand: EquipDef = worn[&"weapon"]
	var move := HeroBody.LOOK.resolve(&"slash", wand.weapon_kind)
	var frame: StringName = HeroBody.MUZZLES.frames.get(move, HeroBody.LOOK.frame_at(move, &"", 0.0))
	var plain: Vector2 = HeroBody.muzzle_of(worn, &"slash", 1)
	wand.held.flips[frame] = true
	var flipped: Vector2 = HeroBody.muzzle_of(worn, &"slash", 1)
	wand.held.flips.erase(frame)
	# both from the wand's grip, along and across the wand as it is turned on that frame
	var pin: Vector4 = wand.held.pins[frame]
	var size := HeroBody.LOOK.body.get_frame_texture(frame, 0).get_size()
	var grip := Vector2(pin.x - size.x / 2.0, pin.y - size.y) * TDStage.TEXEL / TDStage.frames_density(HeroBody.LOOK.body)
	var a := (plain - grip).rotated(-deg_to_rad(pin.z))
	var b := (flipped - grip).rotated(-deg_to_rad(pin.z))
	check(absf(a.x) > 1.0, "the tip is off to one side of the grip: %s" % a)
	check_near(b.x, -a.x, "flipped, the tip is on the other side", 0.01)
	check_near(b.y, a.y, "at the same height along the wand", 0.01)

func test_without_the_weapon_on_its_frame_the_shot_leaves_from_the_fist() -> void:
	var at: Variant = HeroBody.muzzle_of(_worn([&"hunters_bow"]), &"attack", 1)
	check(at is Vector2 and (at as Vector2).x > 0.0, "a bow shot starts at his hand: %s" % at)

func test_a_sword_alone_has_no_muzzle() -> void:
	check_eq(HeroBody.muzzle_of(_worn([&"squire_sword"]), &"attack", 1), null, "nothing to shoot from")
