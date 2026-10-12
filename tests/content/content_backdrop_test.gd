extends TestCase
## Scenery meets the ground with no seam, wherever the camera is on every map: the nearest
## backdrop strip's painted ground runs on down behind the floor (or past the bottom of the
## view), so no bare edge or empty band shows above the floor, and every building's base
## stands on the walking line, so the land's front hides no more of it than the grass lip.

const Scan := preload("res://tests/content/content_scan.gd")

## The most of a building's base (game pixels) that may show below the walking line, hidden
## by the floor's front, at any camera height: about a doorstep.
const MAX_TUCK := 6.0

## The camera heights to check: the middle of the view at its highest, middle and lowest.
func _centers(m: MapDef) -> Array[float]:
	var r := TDStage.view_center_range(m.height)
	return [r.x, (r.x + r.y) / 2.0, r.y]

## Where the top of the floor's painted edge stands, in game y.
func _floor_top(m: MapDef) -> float:
	if m.look().platform_middle == null:
		return float(m.ground_y)
	return PlatformSkin.span(m.look(), m.ground_y).x

## The strip or picture layer nearest the camera (its bottom shows lowest), or null.
func _nearest_strip(b: BiomeDef) -> BackdropLayerDef:
	var near: BackdropLayerDef = null
	for layer in b.backdrop:
		if layer.mode != BackdropLayerDef.Mode.SCATTER and not layer.textures.is_empty():
			if near == null or layer.depth < near.depth:
				near = layer
	return near

func test_nearest_backdrop_reaches_the_floor() -> void:
	for m: MapDef in Content.maps.values():
		var near := _nearest_strip(m.look())
		if near == null:
			continue
		var bottom := BackdropBuilder.strip_edges(m, near).y
		var floor_top := TDStage.to3d(Vector2(0, _floor_top(m))).y
		for c in _centers(m):
			var strip_frac := TDStage.screen_frac_at(bottom, -near.depth, c)
			var floor_frac := TDStage.screen_frac_at(floor_top, TDStage.LAND_FRONT, c)
			check(strip_frac >= minf(floor_frac, 1.0),
					"%s: with the view centred at y %d the nearest backdrop strip ends %.0f%% down the screen, above the floor (%.0f%%)" % [Scan.where(m), c, strip_frac * 100.0, floor_frac * 100.0])

## A picture backdrop fills the whole view: its top edge never shows below the top of the
## screen, it is wide enough for both ends of the map, and the camera sees that far.
func test_backdrop_pictures_cover_the_view() -> void:
	for m: MapDef in Content.maps.values():
		for layer in m.look().backdrop:
			if layer.mode != BackdropLayerDef.Mode.PICTURE or layer.textures.is_empty():
				continue
			check(layer.depth + TDStage.view_distance() < TDStage.FAR - 10.0, "%s: the backdrop picture stands past the camera's far end" % Scan.where(m))
			var top := BackdropBuilder.strip_edges(m, layer).x
			for c in _centers(m):
				var frac := TDStage.screen_frac_at(top, -layer.depth, c)
				check(frac <= 0.0, "%s: with the view centred at y %d the backdrop picture's top shows %.0f%% down the screen" % [Scan.where(m), c, frac * 100.0])
			var span := BackdropBuilder.span_at(m, -layer.depth)
			var w := layer.textures[0].get_width() * BackdropBuilder.layer_pixel_size(m, layer)
			check(w >= span.y - span.x - 0.01, "%s: the backdrop picture is narrower than the view sweeps" % Scan.where(m))

func test_buildings_stand_on_the_walking_line() -> void:
	for m: MapDef in Content.maps.values():
		if m.buildings.is_empty():
			continue
		var layout := MapLayout.new(m)
		var view_h := TDWorld.world_view().y
		for b in m.buildings:
			var pl := layout.platforms[b.platform]
			var s := SceneryBuilder.building_sprite(b, pl.y)
			var top := TerrainBuilder.skin_span(m.platforms[b.platform - 1], m.look()).x if b.platform > 0 else _floor_top(m)
			for c in _centers(m):
				var base := TDStage.screen_frac_at(s.position.y, s.position.z, c)
				var walk := TDStage.screen_frac_at(TDStage.to3d(Vector2(0, pl.y)).y, TDStage.LAND_FRONT, c)
				var edge := TDStage.screen_frac_at(TDStage.to3d(Vector2(0, top)).y, TDStage.LAND_FRONT, c)
				var tuck := (base - walk) * view_h
				check(tuck <= MAX_TUCK, "%s: %s's base sinks %.1f px below the walking line with the view centred at y %d (want %d at most)" % [Scan.where(m), b.building.id, tuck, c, MAX_TUCK])
				check((base - edge) * view_h >= -0.5, "%s: %s's base shows above the land's top edge with the view centred at y %d" % [Scan.where(m), b.building.id, c])
			s.free()
