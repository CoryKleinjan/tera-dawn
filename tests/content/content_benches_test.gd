extends TestCase
## Rest spots are safe: no monster walks on the ledge a bench stands on, or close by on land
## at about its height (the floor just under a low bench ledge), so sitting to heal or waking
## there after fainting doesn't start with hits (play test 2026-10-20: Deep Canopy's and
## Elder's Root's benches had monsters on their ledges).

const Scan := preload("res://tests/content/content_scan.gd")

## How close a monster's walk may come to a bench, on land within NEAR_HEIGHT of the bench's.
const CLEAR := 300.0
const NEAR_HEIGHT := 100.0

## Platform `i`'s left end, top and width (0 is the floor).
func _span(m: MapDef, i: int) -> Vector3:
	if i == 0:
		return Vector3(0, m.ground_y, m.width)
	var p := m.platforms[i - 1]
	return Vector3(p.x, p.y, p.width)

func test_no_monster_walks_by_a_bench() -> void:
	for path in Scan.files("res://data/maps"):
		var m: MapDef = load(path)
		for r in m.rest_spots:
			var bench := _span(m, r.y)
			for s in m.spawns:
				check(s.platform != r.y, "%s: %s spawns on the bench's ledge (platform %d)" % [m.id, s.monster.id, r.y])
				var land := _span(m, s.platform)
				if absf(land.y - bench.y) > NEAR_HEIGHT:
					continue
				var from := land.x if s.patrol_from < 0 else s.patrol_from
				var to := land.x + land.z if s.patrol_to < 0 else s.patrol_to
				var gap := maxf(from - r.x, r.x - to)
				check(gap >= CLEAR, "%s: %s walks %d px from the bench at x %d (keep %d)" % [m.id, s.monster.id, gap, r.x, CLEAR])
