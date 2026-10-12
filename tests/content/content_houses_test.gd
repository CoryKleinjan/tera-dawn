extends TestCase
## Houses only stand at their proper size, and only in towns. A map that isn't a town has no
## buildings unless it is marked `MapDef.houses_allowed` (a quest needs the house, or Cory
## asked for one), and scattered scenery never uses a building picture: it stands far back at
## a random size, which makes a house look tiny. Placed buildings keep their full size.

const Scan := preload("res://tests/content/content_scan.gd")

## The least a building stands on screen, in game pixels (the hero is about 105; a market
## stall is about 2 heroes, a house 2.5).
const MIN_HEIGHT := 200.0
## The furthest back a building stands (BuildingPlacement.depth): further back looks smaller.
const MIN_DEPTH := -3.0

## Every picture a building uses: each BuildingDef's, and the biomes' house pictures
## (`building_*.png`), which are kept but no longer scattered.
func _building_pictures() -> Dictionary:
	var out := {}
	for path in Scan.files(Scan.DATA.path_join("buildings")):
		var b := load(path) as BuildingDef
		if b and b.texture:
			out[b.texture.resource_path] = true
	for tex in _scenery_textures():
		if tex.resource_path.get_file().begins_with("building_"):
			out[tex.resource_path] = true
	return out

## Every texture a biome or map scatters as scenery.
func _scenery_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for rule in _rules().values():
		for d: DecorDef in rule:
			out.append_array(d.textures)
	return out

## Every scenery rule, by where it comes from.
func _rules() -> Dictionary:
	var out := {}
	for path in Scan.files(Scan.DATA.path_join("biomes")):
		var b := load(path) as BiomeDef
		if b:
			for group in ["ground_decor", "platform_decor", "town_decor"]:
				out["%s: %s" % [path, group]] = b.get(group)
	for m: MapDef in Content.maps.values():
		if m.variant:
			out["%s: variant.more_ground_decor" % Scan.where(m)] = m.variant.more_ground_decor
	return out

func test_scenery_never_scatters_houses() -> void:
	var houses := _building_pictures()
	check(not houses.is_empty(), "found the building pictures")
	var rules := _rules()
	for where in rules:
		for d: DecorDef in rules[where]:
			for tex in d.textures:
				check(tex == null or not houses.has(tex.resource_path), "%s scatters the house %s; houses only stand as placed buildings" % [where, tex.resource_path.get_file()])

func test_only_towns_have_houses() -> void:
	var houses := _building_pictures()
	for m: MapDef in Content.maps.values():
		if m.town or m.houses_allowed:
			continue
		check(m.buildings.is_empty(), "%s: not a town but has %d buildings (set houses_allowed if a quest needs one)" % [Scan.where(m), m.buildings.size()])
		for p in m.props:
			if p and p.texture:
				check(not houses.has(p.texture.resource_path), "%s: a prop shows the house %s (set houses_allowed if a quest needs one)" % [Scan.where(m), p.texture.resource_path.get_file()])

func test_buildings_stand_at_full_size() -> void:
	for path in Scan.files(Scan.DATA.path_join("buildings")):
		var b := load(path) as BuildingDef
		if b:
			check(b.height >= MIN_HEIGHT, "%s stands %d px tall (want %d+)" % [path, b.height, MIN_HEIGHT])
	for m: MapDef in Content.maps.values():
		for b in m.buildings:
			if b == null or b.building == null:
				continue
			var h := b.building.height * b.scale
			check(h >= MIN_HEIGHT, "%s: %s stands %d px tall at scale %s (want %d+)" % [Scan.where(m), b.building.id, h, b.scale, MIN_HEIGHT])
			check(b.depth >= MIN_DEPTH, "%s: %s stands at depth %s, too far back (want %s or nearer)" % [Scan.where(m), b.building.id, b.depth, MIN_DEPTH])
