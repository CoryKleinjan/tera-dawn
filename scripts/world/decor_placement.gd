class_name DecorPlacement
extends RefCounted
## Where a map's scattered scenery stands: the biome's trees, bushes, rocks and flowers
## (BiomeDef.ground_decor and platform_decor), and a town's scattered houses when it has no
## buildings (town_decor). Worked out from the MapDef alone, so it needs no scene, and tests
## can check every map. SceneryBuilder stands the sprites where this puts them.
##
## Every piece:
## - sits wholly on the land it stands on: inside the map's floor, or inside its platform's
##   ends;
## - keeps clear of what stands on that land (buildings, portals, NPCs, ropes and ladders,
##   props, lanterns), so it never shows in front of or behind them. Pieces far back (the
##   tree line, a field's distant houses) only keep clear of buildings and lanterns;
## - never overlaps another piece from the same rule;
## - stands `density` as often as its DecorDef asks (wider gaps between slots).

## How often the biome's scenery stands, as a share of what its DecorDefs ask for, when a
## map leaves `MapDef.decor_density` at -1. Every biome's rules are spaced for 1.0.
const DENSITY := 0.7
## Open ground kept between a piece and anything it keeps clear of, in game pixels.
const GAP := 8.0
## Rules whose nearest depth is at or behind this stand far back (see the class notes).
const BACK_DEPTH := -5.0

## One piece of scenery: what it shows and where.
class Piece:
	var rule: DecorDef
	var texture: Texture2D
	## Bottom centre, in game pixels.
	var x: float
	var y: float
	## Game pixels per art pixel.
	var texel: float
	## Content depth (0 at the land's front, negative is further back).
	var depth: float
	var flip: bool
	## The part of the picture that isn't see-through, left and right edges as x and y.
	func span() -> Vector2:
		return DecorPlacement.visible_span(texture, texel, flip) + Vector2(x, x)

## How often this map's scenery stands (0 for none).
static func density(map: MapDef) -> float:
	return DENSITY if map.decor_density < 0.0 else map.decor_density

## The floor's scenery (ground_decor), then a building-less town's houses (town_decor), in
## the order they are drawn.
static func floor_pieces(map: MapDef, rng: RandomNumberGenerator) -> Array[Piece]:
	var out: Array[Piece] = []
	if map.biome == null:
		return out
	var land := Vector2(0.0, map.width)
	var lanterns := LanternPlacement.keep_clear(map)
	var near := standing_on(map, 0)
	near.append_array(lanterns)
	var back := building_spans(map, 0)
	back.append_array(lanterns)
	for rule in map.biome.ground_decor:
		out.append_array(scatter(rule, land, map.ground_y, rng, back if is_back(rule) else near, density(map)))
	if map.town and map.buildings.is_empty():
		for rule in map.biome.town_decor:
			out.append_array(scatter(rule, land, map.ground_y, rng, back, 1.0))
	return out

## The scenery along each floating platform (platform_decor), platform by platform.
static func platform_pieces(map: MapDef, rng: RandomNumberGenerator) -> Array[Piece]:
	var out: Array[Piece] = []
	if map.biome == null:
		return out
	for i in map.platforms.size():
		var d := map.platforms[i]
		var avoid := standing_on(map, i + 1)
		for rule in map.biome.platform_decor:
			out.append_array(scatter(rule, Vector2(d.x, d.x + d.width), d.y, rng, avoid, density(map)))
	return out

## Whether a rule stands far back (the tree line), behind everything on the land.
static func is_back(rule: DecorDef) -> bool:
	return rule.depth.y <= BACK_DEPTH

## Drops pieces from `rule` along `land` (left and right ends as x and y) on the surface at
## `y`: one slot every spacing / `dens`, each filled by the rule's chance, leaving out any
## piece that would hang off the land, overlap a stretch in `avoid` or overlap a piece
## already dropped by this rule.
static func scatter(rule: DecorDef, land: Vector2, y: float, rng: RandomNumberGenerator, avoid: Array[Vector2], dens: float) -> Array[Piece]:
	var out: Array[Piece] = []
	if rule.textures.is_empty() or dens <= 0.0:
		return out
	var taken := avoid.duplicate()
	var x := land.x + rng.randf_range(0.0, rule.spacing.x / dens)
	while x < land.y:
		if rng.randf() < rule.chance:
			var p := Piece.new()
			p.rule = rule
			p.texture = rule.textures[rng.randi() % rule.textures.size()]
			p.texel = rule.texel * rng.randf_range(rule.scale.x, rule.scale.y)
			p.depth = rng.randf_range(rule.depth.x, rule.depth.y)
			p.flip = rng.randf() < 0.5
			p.x = x
			p.y = y
			var s := p.span()
			if s.x >= land.x and s.y <= land.y and not _hits(s, taken):
				taken.append(s)
				out.append(p)
		x += rng.randf_range(rule.spacing.x, rule.spacing.y) / dens
	return out

## The stretches (left and right edges as x and y) taken by what stands on platform
## `platform` (0 is the floor): buildings, portals, NPCs, ropes and ladders that reach it
## from above or below, and props.
static func standing_on(map: MapDef, platform: int) -> Array[Vector2]:
	var out := building_spans(map, platform)
	var y := surface(map, platform)
	for p in map.portals:
		if p.platform == platform:
			out.append(Vector2(p.x - LanternPlacement.PORTAL_HALF, p.x + LanternPlacement.PORTAL_HALF))
	for n in map.npcs:
		if n.platform == platform:
			var r := LanternPlacement.npc_rect(n)
			out.append(Vector2(n.x + r.position.x, n.x + r.end.x))
	for c in map.climbables:
		if c.top < y + 4.0 and c.bottom > y - 4.0 and _on(map, platform, c.x):
			out.append(Vector2(c.x - LanternPlacement.CLIMB_HALF, c.x + LanternPlacement.CLIMB_HALF))
	for p in map.props:
		if p.texture == null:
			continue
		var base := p.y if p.y >= 0.0 else float(map.ground_y)
		if absf(base - y) <= 4.0 and _on(map, platform, p.x):
			var half := TDStage.art_size(p.texture, TDStage.TEXEL * p.scale).x * 0.5
			out.append(Vector2(p.x - half, p.x + half))
	return out

## The stretches taken by buildings on platform `platform` (0 is the floor).
static func building_spans(map: MapDef, platform: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for b in map.buildings:
		if b.platform == platform:
			out.append(b.span())
	return out

## The top edge of platform `platform` (0 is the floor), in game pixels.
static func surface(map: MapDef, platform: int) -> float:
	return float(map.ground_y) if platform == 0 else map.platforms[platform - 1].y

## Whether x lies along platform `platform` (the floor runs the whole map).
static func _on(map: MapDef, platform: int, x: float) -> bool:
	if platform == 0:
		return true
	var d := map.platforms[platform - 1]
	return x >= d.x and x <= d.x + d.width

static func _hits(s: Vector2, taken: Array[Vector2]) -> bool:
	return taken.any(func(a: Vector2) -> bool: return s.y + GAP > a.x and s.x - GAP < a.y)

static var _used := {}

## The part of `texture` that isn't see-through, as left and right edges in game pixels from
## its bottom centre, drawn `texel` game pixels per art pixel (mirrored when `flip`).
static func visible_span(texture: Texture2D, texel: float, flip: bool) -> Vector2:
	var key := texture.resource_path if texture.resource_path else str(texture.get_instance_id())
	if not _used.has(key):
		var img := texture.get_image()
		if img and img.is_compressed():
			img.decompress()
		var used := img.get_used_rect() if img else Rect2i(Vector2i.ZERO, texture.get_size())
		var w := texture.get_width() * 0.5
		_used[key] = Vector2(used.position.x - w, used.end.x - w) / TDStage.art_density(texture)
	var s: Vector2 = _used[key] * texel
	return Vector2(-s.y, -s.x) if flip else s
