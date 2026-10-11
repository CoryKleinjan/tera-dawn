extends TestCase
## SceneryBuilder: ropes, vines and ladders cast no shadows, like characters.

func _texture(w: int, h: int) -> Texture2D:
	return ImageTexture.create_from_image(Image.create(w, h, false, Image.FORMAT_RGBA8))

func test_climbable_pieces_cast_no_shadow() -> void:
	var st := ClimbStyleDef.new()
	st.texel = 1.0
	st.top = _texture(16, 20)
	st.middle = _texture(16, 30)
	st.bottom = _texture(24, 10)
	var c := ClimbableDef.new()
	c.x = 100.0
	c.top = 100.0
	c.bottom = 400.0
	c.style = st
	var root := Node3D.new()
	var platforms: Array[Platform] = []
	SceneryBuilder.new(null, root)._climbable(c, platforms)
	var pieces := root.get_children().filter(func(n: Node) -> bool: return n is Sprite3D)
	check(pieces.size() >= 3, "the climbable is built from its pieces")
	for s: Sprite3D in pieces:
		check_eq(s.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % s.name)
	root.free()
