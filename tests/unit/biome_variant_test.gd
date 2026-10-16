extends TestCase
## BiomeVariantDef: a sub zone changes only what it sets, on a copy of its region's look. Land
## painted with its own grass can leave out the region's edge tufts and platform plants, and a
## sub zone can hang leaves in the screen's top corners.

var base: BiomeDef

func before_each() -> void:
	base = load("res://data/biomes/greenwood.tres")

func test_an_empty_variant_keeps_the_region_look() -> void:
	var b := BiomeVariantDef.new().apply(base)
	check(b != base, "the variant works on a copy")
	check_eq(b.edge_grass.size(), base.edge_grass.size(), "edge tufts kept")
	check_eq(b.platform_decor.size(), base.platform_decor.size(), "platform plants kept")
	check(b.frame_left == null and b.frame_right == null, "no corner leaves unless set")

func test_painted_land_can_leave_out_tufts_and_platform_plants() -> void:
	check(not base.edge_grass.is_empty() and not base.platform_decor.is_empty(), "the region has both")
	var v := BiomeVariantDef.new()
	v.hide_edge_grass = true
	v.hide_platform_decor = true
	var b := v.apply(base)
	check(b.edge_grass.is_empty(), "no edge tufts")
	check(b.platform_decor.is_empty(), "no platform plants")
	check(not base.edge_grass.is_empty() and not base.platform_decor.is_empty(), "the region's own look is unchanged")

func test_a_variant_hangs_leaves_in_the_top_corners() -> void:
	var v := BiomeVariantDef.new()
	v.frame_left = PlaceholderTexture2D.new()
	v.frame_right = PlaceholderTexture2D.new()
	var b := v.apply(base)
	check(b.frame_left == v.frame_left and b.frame_right == v.frame_right, "both corners set")
	check(base.frame_left == null, "the region's own look is unchanged")

func test_corner_leaves_fill_the_screen_height_in_their_corners() -> void:
	var f := CornerFrame.new()
	add_child(f)
	var b := BiomeDef.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(1200, 1350)
	b.frame_left = tex
	b.frame_right = tex
	f.show_for(b)
	check(f.visible, "shown when the look has leaves")
	var view := f.get_viewport().get_visible_rect().size
	var rects := f.get_children()
	check_eq(rects.size(), 2, "one picture per corner")
	var left: TextureRect = rects[0]
	var right: TextureRect = rects[1]
	check_near(left.size.y, view.y, "as tall as the screen")
	check_near(left.size.x, view.y * 1200.0 / 1350.0, "keeps its shape")
	check_eq(left.position, Vector2.ZERO, "left leaves in the top left corner")
	check_near(right.position.x + right.size.x, view.x, "right leaves reach the right edge")
	check_near(right.position.y, 0.0, "right leaves at the top")
	f.show_for(BiomeDef.new())
	check(not f.visible, "hidden on a look without leaves")
	f.free()
