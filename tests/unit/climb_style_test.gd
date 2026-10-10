extends TestCase
## ClimbStyleDef.pieces: a rope or ladder's pieces stacked edge to edge from its top to its
## bottom, with a whole number of evenly spaced middles.

var style: ClimbStyleDef

func _texture(w: int, h: int) -> Texture2D:
	return ImageTexture.create_from_image(Image.create(w, h, false, Image.FORMAT_RGBA8))

## Texel 1: a 20-tall top, 30-tall middles and a 10-tall bottom (game pixels).
func before_each() -> void:
	style = ClimbStyleDef.new()
	style.texel = 1.0
	style.top = _texture(16, 20)
	style.middle = _texture(16, 30)
	style.bottom = _texture(24, 10)

func _check_touching(pieces: Array[Dictionary]) -> void:
	for i in range(1, pieces.size()):
		var above: Dictionary = pieces[i - 1]
		check_near(pieces[i].y, above.y + above.height, "piece %d starts where piece %d ends" % [i, i - 1])

func test_pieces_run_from_top_to_bottom_touching() -> void:
	var p := style.pieces(100.0, 400.0)
	check_eq(p[0].texture, style.top, "top piece first")
	check_near(p[0].y, 100.0, "top piece hangs from the top")
	check_eq(p[-1].texture, style.bottom, "bottom piece last")
	check_near(p[-1].y + p[-1].height, 400.0 + ClimbStyleDef.BOTTOM_SINK, "bottom piece stands just into the floor")
	_check_touching(p)

func test_middles_are_a_whole_number_evenly_spaced() -> void:
	var p := style.pieces(100.0, 400.0)
	var middles := p.filter(func(d: Dictionary) -> bool: return d.texture == style.middle)
	# 302 - 20 - 10 = 272 between the ends: 9 middles of about 30.2 each
	check_eq(middles.size(), 9, "nine middles")
	for m: Dictionary in middles:
		check_near(m.height, 272.0 / 9.0, "evenly spaced")

func test_top_rise_lifts_the_top_piece_above_the_ledge() -> void:
	style.top_rise = 0.25
	var p := style.pieces(100.0, 400.0)
	check_near(p[0].y, 95.0, "a quarter of the 20-tall top rises above the ledge")
	_check_touching(p)

func test_short_climbable_still_joins() -> void:
	var p := style.pieces(100.0, 150.0)
	check_eq(p.size(), 3, "top, one squeezed middle, bottom")
	_check_touching(p)

func test_no_end_pieces() -> void:
	style.top = null
	style.bottom = null
	var p := style.pieces(0.0, 90.0)
	check_eq(p.size(), 3, "three middles fill it")
	check_near(p[-1].y + p[-1].height, 90.0 + ClimbStyleDef.BOTTOM_SINK, "down into the floor")
	_check_touching(p)

func test_top_piece_with_a_peg_to_one_side_flips_toward_the_wider_side() -> void:
	var img := Image.create(40, 10, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 24, 10), Color.WHITE)  # 20 px left of the line, 4 px right
	style.top = ImageTexture.create_from_image(img)
	check_eq(ClimbStyleDef.solid_reach(style.top, 1.0), Vector2(20, 4), "reaches 20 left, 4 right")
	check(not style.top_flipped(Vector2(30, 10)), "room on the left: as drawn")
	check(style.top_flipped(Vector2(10, 30)), "near the left end: mirrored")
	check(not style.top_flipped(Vector2(INF, INF)), "on the floor: as drawn")
