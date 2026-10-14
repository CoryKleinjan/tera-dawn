extends TestCase
## Everywhere on a map can be walked to: every platform, rope, portal, NPC and monster
## spawn is reachable with the hero's own jump (see map_reach.gd) from where players
## arrive; land-shaped art is a real platform, never background scenery, and stands on the
## floor (no floating rock islands or arches); and no two exits of a map lead to the same place.

const Scan := preload("res://tests/content/content_scan.gd")
const MapReach := preload("res://tests/content/map_reach.gd")

func test_everything_on_every_map_can_be_reached() -> void:
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var reach := MapReach.new(m, MapReach.arrivals_of(m))
		for i in m.platforms.size():
			var p := m.platforms[i]
			check(reach.platform_reached(i + 1), "%s: platforms[%d] (x %d-%d, y %d) can't be reached" % [w, i, p.x, p.x + p.width, p.y])
		for i in m.climbables.size():
			var c := m.climbables[i]
			check(reach.climbable_reached(i), "%s: climbables[%d] (x %d, y %d-%d) can't be reached" % [w, i, c.x, c.top, c.bottom])
		for i in m.portals.size():
			check(reach.platform_reached(m.portals[i].platform), "%s: portals[%d] to %s can't be reached" % [w, i, m.portals[i].target_map])
		for i in m.npcs.size():
			check(reach.platform_reached(m.npcs[i].platform), "%s: npcs[%d] can't be reached" % [w, i])
		for i in m.spawns.size():
			check(reach.platform_reached(m.spawns[i].platform), "%s: spawns[%d] can't be reached" % [w, i])

func test_land_art_is_never_scenery() -> void:
	var land := {}
	for m: MapDef in Content.maps.values():
		for p in m.platforms:
			if p.look:
				land[p.look.resource_path] = true
	check(land.size() > 0, "no platform has a look")
	for m: MapDef in Content.maps.values():
		for i in m.props.size():
			var p := m.props[i]
			if p.texture:
				check(not land.has(p.texture.resource_path), "%s: props[%d] is land art (%s); make it a platform with that look" % [Scan.where(m), i, p.texture.resource_path.get_file()])

## Land art Cory removed (2026-10-11): it must not come back as an asset.
const REMOVED_LAND := ["arch", "floating_rock", "ledge_vines", "ledge_overhang", "ledge_roots"]

## A platform's `look` is a piece of land standing on the floor (a tall ledge); floating rock
## islands and arches are gone, so a floating platform uses the biome's plain platform front.
## Its picture reaches down to the floor, unless it hangs between two platforms (a bridge).
func test_land_art_stands_on_the_floor() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.platforms.size():
			var p := m.platforms[i]
			if p.look and p.hangs:
				for end in [p.x, p.x + p.width]:
					var held := m.platforms.any(func(o: PlatformDef) -> bool: return o != p and is_equal_approx(o.y, p.y) and end >= o.x - 4.0 and end <= o.x + o.width + 4.0)
					check(held, "%s: platforms[%d] (%s) hangs from nothing at x %d; a bridge's ends meet platforms at its height" % [Scan.where(m), i, p.look.resource_path.get_file(), end])
			elif p.look:
				var span := TerrainBuilder.skin_span(p, m.look())
				var gap := m.ground_y - span.y
				check(gap <= 4.0, "%s: platforms[%d] (%s) floats %d px above the floor; land art must stand on the ground" % [Scan.where(m), i, p.look.resource_path.get_file(), gap])

func test_removed_land_art_stays_gone() -> void:
	var tiles := "res://assets/sprites/tiles"
	for biome in DirAccess.get_directories_at(tiles):
		for file in DirAccess.get_files_at(tiles.path_join(biome)):
			check(not REMOVED_LAND.has(file.get_basename().get_basename()), "%s/%s is removed land art; Cory doesn't want it in the game" % [biome, file])

func test_no_two_exits_lead_to_the_same_map() -> void:
	for m: MapDef in Content.maps.values():
		var seen := {}
		for i in m.portals.size():
			var to := m.portals[i].target_map
			check(not seen.has(to), "%s: portals[%d] and portals[%s] both lead to %s" % [Scan.where(m), i, seen.get(to), to])
			seen[to] = i
