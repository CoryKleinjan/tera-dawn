extends TestCase
## Shots leave from his punching fist (HeroBody.muzzle_of) until the job sets put a weapon in
## his hand.

func test_every_look_shoots_from_in_front_of_him_at_chest_height() -> void:
	for look in HeroLookDef.all():
		var at := HeroBody.muzzle_of(look, 1)
		check(at.x > 10.0, "%s: in front of him: %s" % [look.id, at])
		check(at.y < -TDPlayer.CHEST / 2.0 and at.y > -TDPlayer.HEIGHT, "%s: up off the ground, below his head: %s" % [look.id, at])
		check_eq(HeroBody.muzzle_of(look, -1), Vector2(-at.x, at.y), "%s: facing left, the same spot mirrored" % look.id)

func test_the_fist_is_on_the_attacks_last_frame() -> void:
	for look in HeroLookDef.all():
		var last := look.frames.get_frame_count(HeroBody.ATTACK) - 1
		var img := look.frames.get_frame_texture(HeroBody.ATTACK, last).get_image()
		var p := Vector2i(look.fist.round())
		check(img.get_pixelv(p).a > 0.5, "%s: the fist point is painted: %s" % [look.id, p])
