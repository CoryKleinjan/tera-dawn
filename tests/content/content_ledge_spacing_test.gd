extends TestCase
## Hollow Knight style rooms (Cory, 2026-10-19): ledges never pile into a wall. No ledge
## hangs over another closer than its own painted depth (less a little for the shelf's
## rounded underside), unless the lower one is a wide ledge at least twice as wide and the
## upper one a step standing on it. A step never tucks under a wider ledge's shelf, except
## the few listed below where the room's top ledge has no other way up to it.
## Zones join this list as their rooms are laid out again.
const Scan := preload("res://tests/content/content_scan.gd")
const LAID_OUT: Array[StringName] = [&"lumewood"]
const TUCK := 20.0
const SLACK := 30.0
## map id -> the steps (x, y) allowed under a wider ledge's shelf
const TUCKED := {
	&"arcane_spire": [Vector2(1240, 416), Vector2(1520, 384)],
	&"crystal_caves": [Vector2(250, 441), Vector2(530, 357)],
	&"glowcap_hollow": [Vector2(1530, 775)],
}

func test_ledges_never_pile_up() -> void:
	for m: MapDef in Content.maps.values():
		if m.region not in LAID_OUT or m.town or m.solo or m.music != &"":
			continue
		var w := Scan.where(m)
		var tucked: Array = TUCKED.get(m.id, [])
		for a in m.platforms:
			var ra := LanternPlacement.platform_rect(a, m.look())
			for b in m.platforms:
				var gap := b.y - a.y
				if a == b or gap <= 0.0 or gap >= ra.size.y - TUCK: continue
				var rb := LanternPlacement.platform_rect(b, m.look())
				if minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x) <= SLACK: continue
				var step_on := b.width >= a.width * 2.0
				var known := a.width >= b.width * 2.0 and Vector2(b.x, b.y) in tucked
				check(step_on or known, "%s: the ledge at x %d, y %d piles onto the one at x %d, y %d" % [w, a.x, a.y, b.x, b.y])
