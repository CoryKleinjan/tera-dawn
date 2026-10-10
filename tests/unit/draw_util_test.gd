extends TestCase
## DrawUtil's filled shapes: a rounded box of any size the HUD draws (a bar at a sliver of
## fill, just after a level-up) is a polygon the renderer can triangulate, and anything
## smaller than a pixel or collapsed to a line is skipped rather than drawn.

func test_round_boxes_triangulate_at_any_drawn_size() -> void:
	for w in [1.0, 1.4, 2.0, 3.0, 7.5, 40.0, 300.0]:
		for h in [1.0, 2.0, 9.0, 22.0]:
			var r := Rect2(10, 20, w, h)
			check(DrawUtil.big_enough(r.size), "%s x %s is drawn" % [w, h])
			for rad in [0.0, 3.0, h / 2.0, 50.0]:
				var pts := DrawUtil.round_rect_points(r, rad)
				check(DrawUtil.fillable(pts) and not Geometry2D.triangulate_polygon(pts).is_empty(),
					"a %s x %s box with radius %s triangulates: %s" % [w, h, rad, pts])

func test_slivers_and_collapsed_shapes_are_skipped() -> void:
	for size in [Vector2(0.3, 10), Vector2(0, 10), Vector2(10, 0.5), Vector2(-2, 10)]:
		check(not DrawUtil.big_enough(size), "%s is too small to fill" % size)
	check(not DrawUtil.fillable(PackedVector2Array([Vector2(1, 1), Vector2(1, 1), Vector2(1, 1), Vector2(1, 1)])), "all one point")
	check(not DrawUtil.fillable(PackedVector2Array([Vector2(1, 1), Vector2(5, 1), Vector2(1, 1)])), "two points")
	check(not DrawUtil.fillable(PackedVector2Array()), "no points")
	check(DrawUtil.fillable(PackedVector2Array([Vector2(1, 1), Vector2(5, 1), Vector2(1, 4)])), "a triangle")

func test_drawing_a_sliver_draws_nothing() -> void:
	var c := Control.new()
	add_child(c)
	var drew := [false]
	c.draw.connect(func() -> void:
		DrawUtil.round_rect(c, Rect2(0, 0, 0.3, 10), 5.0, Color.WHITE)
		DrawUtil.ellipse(c, Vector2(5, 5), 0.2, 4.0, Color.WHITE)
		drew[0] = true)
	c.queue_redraw()
	await get_tree().process_frame
	check(drew[0], "the draw ran past the sliver")
	c.queue_free()
