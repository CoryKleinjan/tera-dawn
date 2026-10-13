extends TestCase
## Every ladder, rope and vine in every map is built as the game draws it (SceneryBuilder), and
## its pieces line up: each stands straight up and down on one shared line (so none leans with
## the camera), each starts where the one above ends, and where two pieces join, the rails or
## strands of the lower one carry on from the upper one's, or run into a wider end piece (a
## ladder's posts, a vine's tangle).

const Scan := preload("res://tests/content/content_scan.gd")

## How far (game pixels) the middles of two joining strands may be apart, and how much wider
## one may be painted than the other (one art pixel).
const SIDE_TOL := 0.15
const WIDTH_TOL := 0.5
## How far (game pixels) a piece may start below the end of the one above.
const GAP_TOL := 0.01

## A built piece: its texture, whether it's mirrored, drawn size, centre x and top y (game px),
## and the height (3D units) its sides stay upright from.
func _piece(mi: MeshInstance3D) -> Dictionary:
	var q := mi.mesh as QuadMesh
	var m := q.material as ShaderMaterial
	var size := q.size * TDStage.PX
	return {
		"texture": m.get_shader_parameter(&"albedo_tex"),
		"flipped": m.get_shader_parameter(&"flip_h"),
		"shader": m.shader,
		"slant": float(m.get_shader_parameter(&"slant")) * TDStage.PX,
		"size": size,
		"x": mi.position.x * TDStage.PX,
		"top": -mi.position.y * TDStage.PX - size.y / 2.0,
		"upright": mi.position.y + float(m.get_shader_parameter(&"top")),
	}

## Where a built piece's sides are, game pixels from the map's left edge, along its bottom (or
## top) edge, as drawn.
func _sides(p: Dictionary, st: ClimbStyleDef, bottom_edge: bool) -> Vector2:
	var tex: Texture2D = p.texture
	var s := ClimbStyleDef.join_sides(tex, st.texel, bottom_edge)
	if p.flipped:
		s = Vector2(-s.y, -s.x)
	var x: float = p.x + (p.slant if bottom_edge else 0.0)
	return s * (p.size.x / TDStage.art_size(tex, st.texel).x) + Vector2(x, x)

func _joins(a: Vector2, b: Vector2) -> bool:
	if absf((a.x + a.y) - (b.x + b.y)) / 2.0 <= SIDE_TOL and absf((a.y - a.x) - (b.y - b.x)) <= WIDTH_TOL + 0.001:
		return true
	# one is an end piece the other's rails or strands run into
	return (a.x <= b.x + SIDE_TOL and a.y >= b.y - SIDE_TOL) or (b.x <= a.x + SIDE_TOL and b.y >= a.y - SIDE_TOL)

func test_ladders_and_ropes_line_up_in_every_map() -> void:
	var count := 0
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var layout := MapLayout.new(m)
		for i in m.climbables.size():
			var c := m.climbables[i]
			if c == null or c.style == null:
				continue
			var st := c.style
			var root := Node3D.new()
			SceneryBuilder.new(null, root)._climbable(c, layout.platforms)
			var pieces: Array[Dictionary] = []
			for n in root.get_children():
				if n is MeshInstance3D:
					pieces.append(_piece(n))
			root.free()
			var what := "%s: climbables[%d] (%s) at x %s" % [w, i, st.id, c.x]
			if not check(pieces.size() >= 1, "%s is built" % what):
				continue
			count += 1
			for j in pieces.size():
				var p := pieces[j]
				var name_: String = p.texture.resource_path.get_file()
				check(p.shader == SceneryBuilder.UPRIGHT_SPRITE, "%s: its %s stands straight up and down" % [what, name_])
				check_near(p.upright, pieces[0].upright, "%s: its %s stays upright from the same line as the top piece" % [what, name_])
				if j == 0:
					continue
				var above := pieces[j - 1]
				var gap: float = p.top - (above.top + above.size.y)
				check(gap <= GAP_TOL, "%s: a %s px gap above its %s" % [what, snappedf(gap, 0.01), name_])
				var a := _sides(above, st, true)
				var b := _sides(p, st, false)
				check(_joins(a, b), "%s: its %s (sides %s..%s px) doesn't line up with the %s above (%s..%s px)" % [
						what, name_, snappedf(b.x - c.x, 0.01), snappedf(b.y - c.x, 0.01),
						above.texture.resource_path.get_file(), snappedf(a.x - c.x, 0.01), snappedf(a.y - c.x, 0.01)])
	check(count > 0, "some map has a ladder or rope")
