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

func test_without_the_weapon_on_its_frame_the_shot_leaves_from_the_fist() -> void:
	var at: Variant = HeroBody.muzzle_of(_worn([&"hunters_bow"]), &"attack", 1)
	check(at is Vector2 and (at as Vector2).x > 0.0, "a bow shot starts at his hand: %s" % at)

func test_a_sword_alone_has_no_muzzle() -> void:
	check_eq(HeroBody.muzzle_of(_worn([&"squire_sword"]), &"attack", 1), null, "nothing to shoot from")
