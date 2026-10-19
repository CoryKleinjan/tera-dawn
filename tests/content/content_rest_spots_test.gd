extends TestCase
## Rest spots, the Hollow Knight way (Cory, 2026-10-19; MapDef.rest_spots): each zone drawn to
## shape has two, one midway and one in the room before its boss, and each shows its region's
## bench. A bench stands on its ledge, clear of ways out and doors, and its room's monsters
## keep off it, so you can sit there in peace.

const Scan := preload("res://tests/content/content_scan.gd")

## Every rest spot, as [map, spot].
func _spots() -> Array:
	var out := []
	for m: MapDef in Content.maps.values():
		for r in m.rest_spots:
			out.append([m, r])
	return out

func test_every_shaped_zone_has_two_rest_spots() -> void:
	for r: RegionDef in Content.regions.values():
		if not r.shaped_zone:
			continue
		var n := _spots().filter(func(s: Array) -> bool: return s[0].region == r.id).size()
		check_eq(n, 2, "%s has two rest spots" % r.id)

func test_rest_spots_stand_in_fields_of_a_region_with_a_bench() -> void:
	for s in _spots():
		var m: MapDef = s[0]
		var r: RegionDef = Content.regions.get(m.region)
		check(not m.town and not m.interior, "%s: a rest spot stands out in the fields" % Scan.where(m))
		check(r != null and r.bench != null, "%s: its region has a bench to show" % Scan.where(m))

func test_benches_stand_on_their_ledge() -> void:
	for s in _spots():
		var m: MapDef = s[0]
		var spot: Vector2i = s[1]
		if not check(spot.y >= 0 and spot.y <= m.platforms.size(), "%s: the rest spot at %d stands on platform %d, which isn't there" % [Scan.where(m), spot.x, spot.y]):
			continue
		var r: RegionDef = Content.regions.get(m.region)
		var half := TDStage.art_size(r.bench).x / 2.0 if r and r.bench else 0.0
		var pl := MapLayout.new(m).platforms[spot.y]
		check(pl.contains_x(spot.x - half) and pl.contains_x(spot.x + half), "%s: the bench at %d hangs off platform %d" % [Scan.where(m), spot.x, spot.y])

func test_benches_keep_clear_of_ways_and_doors() -> void:
	for s in _spots():
		var m: MapDef = s[0]
		var spot: Vector2i = s[1]
		for p in m.portals:
			if p.platform == spot.y:
				check(absf(p.x - spot.x) > MapLayout.REST_REACH + LanternPlacement.PORTAL_HALF, "%s: the bench at %d stands in the way to %s" % [Scan.where(m), spot.x, p.target_map])

func test_monsters_keep_off_benches() -> void:
	for s in _spots():
		var m: MapDef = s[0]
		var spot: Vector2i = s[1]
		var layout := MapLayout.new(m)
		for sp in m.spawns:
			if sp.platform != spot.y or sp.from_tear:
				continue
			var a := sp.patrol_area(layout.platforms[sp.platform])
			var clear := a.x + a.w <= spot.x - MapLayout.REST_REACH or a.x >= spot.x + MapLayout.REST_REACH
			check(clear, "%s: %s walk over the bench at %d" % [Scan.where(m), sp.monster.id, spot.x])
