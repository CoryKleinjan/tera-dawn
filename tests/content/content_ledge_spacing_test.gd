extends TestCase
## Hollow Knight style rooms (Cory, 2026-10-19): ledges never pile into a wall. Where one
## ledge hangs over another closer than its own painted depth, at least two thirds of the
## upper shelf still shows above the lower one, unless the lower one is a wide landing the
## upper one stands on as a step (at least twice as wide). Rooms join this list as they are
## laid out again.

const Scan := preload("res://tests/content/content_scan.gd")

const LAID_OUT: Array[StringName] = [&"glowcap_hollow"]
## Sideways overlap (game pixels) small enough to ignore: the shelf ends are rounded.
const SLACK := 30.0

func test_ledges_never_pile_up() -> void:
	for id in LAID_OUT:
		var m: MapDef = Content.maps[id]
		var w := Scan.where(m)
		for a in m.platforms:
			var ra := LanternPlacement.platform_rect(a, m.look())
			for b in m.platforms:
				var gap := b.y - a.y
				if a == b or gap <= 0.0 or gap >= ra.size.y:
					continue
				var rb := LanternPlacement.platform_rect(b, m.look())
				if minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x) <= SLACK:
					continue
				var landing := b.width >= a.width * 2.0
				check(landing or gap >= ra.size.y * 2.0 / 3.0,
					"%s: the ledge at x %d, y %d piles onto the one at x %d, y %d" % [w, a.x, a.y, b.x, b.y])
