extends TestCase
## MapLayout: the floor and one-way platforms, what's under the feet, where drops land,
## ropes and ladders in reach, and portals.

var layout: MapLayout

## A 1000-wide map with the floor at 600, a platform at y 400 from x 100 to 300, one above
## it at y 250 from x 150 to 250, a rope at x 500 from 300 to 600 and a portal on platform 1.
func before_each() -> void:
	var m := MapDef.new()
	m.id = &"t_map"
	m.width = 1000
	m.ground_y = 600
	for p in [[100.0, 400.0, 200.0], [150.0, 250.0, 100.0]]:
		var d := PlatformDef.new()
		d.x = p[0]
		d.y = p[1]
		d.width = p[2]
		m.platforms.append(d)
	var rope := ClimbableDef.new()
	rope.x = 500
	rope.top = 300
	rope.bottom = 600
	m.climbables.append(rope)
	var portal := PortalDef.new()
	portal.x = 200
	portal.platform = 1
	portal.target_map = &"elsewhere"
	m.portals.append(portal)
	layout = MapLayout.new(m)

func test_platform_zero_is_solid_floor() -> void:
	check_eq(layout.platforms.size(), 3, "floor plus two")
	var f := layout.platforms[0]
	check(f.solid, "solid")
	check_eq(Vector3(f.x, f.y, f.w), Vector3(0, 600, 1000), "covers the map")
	check(not layout.platforms[1].solid, "one-way")
	check_eq(layout.platforms[2].y, 250.0, "in order")

func test_ground_below_in_open_air_is_floor() -> void:
	check_eq(layout.ground_below(Vector2(700, 100)), 600.0, "nothing but floor")

func test_ground_below_picks_nearest_platform_below() -> void:
	check_eq(layout.ground_below(Vector2(200, 100)), 250.0, "top platform first")
	check_eq(layout.ground_below(Vector2(200, 300)), 400.0, "below the top one")
	check_eq(layout.ground_below(Vector2(120, 100)), 400.0, "outside the small one")
	check_eq(layout.ground_below(Vector2(200, 450)), 600.0, "under both")

func test_ground_below_standing_on_platform_counts_it() -> void:
	check_eq(layout.ground_below(Vector2(200, 400)), 400.0, "on it")
	check_eq(layout.ground_below(Vector2(200, 400.9)), 400.0, "within a pixel")
	check_eq(layout.ground_below(Vector2(200, 401.5)), 600.0, "fell through")

func test_platform_edges_are_inclusive() -> void:
	check_eq(layout.ground_below(Vector2(100, 300)), 400.0, "left edge")
	check_eq(layout.ground_below(Vector2(300, 300)), 400.0, "right edge")
	check_eq(layout.ground_below(Vector2(300.5, 300)), 600.0, "just past")

func test_platform_under_feet() -> void:
	check(layout.platform_under(Vector2(200, 400)) == layout.platforms[1], "on platform 1")
	check(layout.platform_under(Vector2(200, 250.5)) == layout.platforms[2], "on platform 2")
	check(layout.platform_under(Vector2(700, 600)) == layout.platforms[0], "on the floor")
	check(layout.platform_under(Vector2(200, 380)) == null, "in the air")
	check(layout.platform_under(Vector2(50, 400)) == null, "beside the platform")

func test_dropping_from_the_top_lands_on_the_highest_ground() -> void:
	check_eq(layout.ground_below(Vector2(200, 0)), 250.0, "drop above both")
	check_eq(layout.ground_below(Vector2(900, 0)), 600.0, "drop over floor")

func test_climbable_near() -> void:
	check(layout.climbable_near(Vector2(500, 450)) != null, "on the rope")
	check(layout.climbable_near(Vector2(515, 450)) != null, "within 16 px")
	check(layout.climbable_near(Vector2(516, 450)) == null, "too far sideways")
	check(layout.climbable_near(Vector2(500, 299)) != null, "just above the top")
	check(layout.climbable_near(Vector2(500, 297)) == null, "above the top")
	check(layout.climbable_near(Vector2(500, 602)) != null, "at the bottom")
	check(layout.climbable_near(Vector2(500, 603)) == null, "below the bottom")

func test_portal_at() -> void:
	check(layout.portal_at(Vector2(200, 400)) != null, "standing in it")
	check(layout.portal_at(Vector2(233, 403)) != null, "near edge")
	check(layout.portal_at(Vector2(234, 400)) == null, "too far sideways")
	check(layout.portal_at(Vector2(200, 600)) == null, "on the floor below it")
	check(layout.portal_at(Vector2(200, 395)) == null, "jumping above it")

func test_real_maps_have_floor_and_land_on_ground() -> void:
	for id in Content.maps:
		var m: MapDef = Content.maps[id]
		var l := MapLayout.new(m)
		check_eq(l.platforms.size(), m.platforms.size() + 1, "%s platforms" % id)
		check(l.ground_below(Vector2(m.start_x, -1000)) <= m.ground_y, "%s landing never below floor" % id)
