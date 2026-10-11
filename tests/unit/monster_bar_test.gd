extends TestCase
## The monster HP bar: drawn from its frame's end caps and middle only, so the emblem painted
## at the art's left end never shows, and its fill sits centred inside the frame at any width.

## The first texel column of monster_hp_1 right of the emblem.
const EMBLEM_END := 36.0

func test_bar_leaves_out_the_emblem() -> void:
	for part: Rect2 in [WorldSkin.MONSTER_CAP, WorldSkin.MONSTER_MID]:
		check(part.position.x >= EMBLEM_END, "the bar takes art from x %d on, right of the emblem" % part.position.x)
		check(Rect2(Vector2.ZERO, UiSkin.tex("monster_hp_1").get_size()).encloses(part), "%s lies inside the art" % part)

func test_bar_is_as_wide_as_asked_with_its_fill_centred() -> void:
	for width: float in [54.0, 80.0, 135.0, 243.0]:
		var scale := width / 135.0
		var frame := WorldSkin.monster_bar_rect(Vector2(10, 20), width, scale)
		check_eq(frame.size.x, width, "a bar asked %d px wide" % width)
		var groove := WorldSkin.monster_bar_groove(frame, scale)
		check(frame.encloses(groove), "the %d px bar's fill lies inside its frame" % width)
		check(is_equal_approx(groove.position.x - frame.position.x, frame.end.x - groove.end.x),
			"the %d px bar's fill has the same margin at both ends" % width)
