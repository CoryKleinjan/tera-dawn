extends TestCase
## Fists under long sleeves (EquipDef.long_sleeves): a frame's fists painted for long sleeves
## (HeroLookDef.SLEEVED, only what shows past the cuffs) show instead of the ones painted with
## bare forearms, where the frame has some.

## His fists painted for idle1 and pinning, and for long sleeves on pinning only.
func _fists(sleeved: bool) -> HeroBody.Layer:
	var look := HeroLookDef.new()
	look.hands = SpriteFrames.new()
	for f in [&"idle1", &"pinning", &"pinning_sleeved"]:
		look.hands.add_animation(f)
	var l := HeroBody.Layer.new(look, &"hands")
	l.sleeved = sleeved
	return l

func test_long_sleeves_show_the_fists_painted_for_them() -> void:
	check_eq(_fists(true).art(&"pinning"), &"pinning_sleeved", "under long sleeves: the painting for them")
	check_eq(_fists(false).art(&"pinning"), &"pinning", "bare arms: the frame's own painting")
	check_eq(_fists(true).art(&"idle1"), &"idle1", "a frame with none for long sleeves keeps its own")

func test_only_a_top_with_long_sleeves_gives_his_fists_long_sleeves() -> void:
	var robe := EquipDef.new()
	robe.long_sleeves = true
	check(HeroBody.fists({&"top": robe}).sleeved, "under a robe")
	check(not HeroBody.fists({&"top": EquipDef.new()}).sleeved, "under a top with short sleeves")
	check(not HeroBody.fists({}).sleeved, "with no top")
