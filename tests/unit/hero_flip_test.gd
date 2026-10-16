extends TestCase
## Flip in the pose editor (HeroBody.Layer.flips): a flipped piece is drawn mirrored around the
## point it turns around, keeping where it sits and how it is turned, and is kept per frame in
## the piece's own file.

func test_a_flip_is_kept_per_frame_in_the_pieces_own_file() -> void:
	var hat := EquipDef.new()
	var l := HeroBody.Layer.new(hat)
	l.set_flipped(&"faint", true)
	check_eq(hat.flips, {&"faint": true}, "in the item's own flips")
	check(l.flipped(&"faint") and not l.flipped(&"idle1"), "only on that frame")
	l.set_flipped(&"faint", false)
	check_eq(hat.flips, {}, "flipping it back leaves nothing behind")

func test_his_own_parts_keep_their_flips_apart() -> void:
	var look := HeroLookDef.new()
	HeroBody.Layer.new(look, &"hands").set_flipped(&"idle1", true)
	check_eq(look.flips, {&"hands": {&"idle1": true}}, "his fists' flips, under their part")
	check(not HeroBody.Layer.new(look, &"body").flipped(&"idle1"), "his body isn't flipped with them")

func test_a_held_piece_keeps_its_flips_with_its_pins() -> void:
	var held := HeldDef.new()
	var sword := EquipDef.new()
	sword.held = held
	HeroBody.Layer.new(sword).set_flipped(&"swing2", true)
	check_eq(held.flips, {&"swing2": true}, "in the held piece's file, beside its pins")
	check_eq(sword.flips, {}, "not in the item's worn flips")

## Where column `u` of `s`'s picture lands across the sprite, from its origin, in the picture's
## pixels (a Sprite3D is centred on its offset, and flip_h mirrors the picture inside that).
func _x_of(s: Sprite3D, u: float) -> float:
	var w := float(s.texture.get_width())
	return s.offset.x - w / 2.0 + (w - u if s.flip_h else u)

## A 40 x 20 picture with its anchor at (10, 5), placed the way HeroBody draws a layer.
func _placed(flip: bool, face: int) -> Sprite3D:
	var who := Node2D.new()
	var body := HeroBody.new(who, null, 0.0)
	var s := Sprite3D.new()
	s.texture = ImageTexture.create_from_image(Image.create(40, 20, false, Image.FORMAT_RGBA8))
	body._place(s, s.texture, Vector2(10, 5), Vector2(100, 80), 30.0, 1.0, flip, Vector2(246, 161), face)
	who.free()
	return s

func test_a_flipped_layer_is_mirrored_around_its_anchor_and_keeps_its_turn() -> void:
	for face in [1, -1]:
		var plain := _placed(false, face)
		var flipped := _placed(true, face)
		check_near(_x_of(plain, 10.0), 0.0, "as painted, its anchor is on its pin (facing %d)" % face)
		check_near(_x_of(flipped, 10.0), 0.0, "flipped, its anchor stays on its pin (facing %d)" % face)
		check_near(_x_of(flipped, 25.0), -_x_of(plain, 25.0), "the rest mirrored around the anchor (facing %d)" % face)
		check_eq(flipped.flip_h, not plain.flip_h, "drawn the other way round (facing %d)" % face)
		check_near(flipped.rotation.z, plain.rotation.z, "turned the same (facing %d)" % face)
		plain.free()
		flipped.free()
