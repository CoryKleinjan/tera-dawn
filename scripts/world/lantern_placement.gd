class_name LanternPlacement
extends RefCounted
## Where a map's lanterns stand along the floor: a few, spread evenly, each in open ground
## clear of everything else standing on or hanging over the floor (buildings, portals,
## ropes and ladders, props, NPCs and low platforms), so a lantern never shows in front of
## or behind another piece of the scene. Worked out from the MapDef alone, so it needs no
## scene, and tests can check every map.
## SceneryBuilder stands the posts here and keeps the floor's scattered trees, bushes and
## rocks and a town's background houses off them (keep_clear).

## How far apart lanterns stand when a map leaves `MapDef.lantern_spacing` at -1.
const TOWN_SPACING := 900.0
const FIELD_SPACING := 1400.0
## Open ground kept on each side of a lantern, in game pixels.
const CLEAR := 24.0
## How far in from the map's ends lanterns stand.
const EDGE := 160.0
## Half the width an NPC, a portal and a rope or ladder take up, in game pixels.
const NPC_HALF := 30.0
const PORTAL_HALF := 34.0
const CLIMB_HALF := 16.0
## How tall an NPC and a portal stand, for ones on a platform just above the floor.
const NPC_HEIGHT := 90.0
const PORTAL_HEIGHT := 110.0

## How far apart the map's lanterns stand (0 for none).
static func spacing(map: MapDef) -> float:
	if map.interior:
		return 0.0
	if map.lantern_spacing >= 0.0:
		return map.lantern_spacing
	return TOWN_SPACING if map.town else FIELD_SPACING

## The lantern post's size, in game pixels.
static func post_size(map: MapDef) -> Vector2:
	return TDStage.art_size(map.biome.lantern) if map.biome and map.biome.lantern else Vector2.ZERO

## The x of each lantern, left to right. One per `spacing` of the map's width, each as near
## its even share of the floor as open ground allows; a share with no open ground near it
## gets none.
static func slots(map: MapDef) -> Array[float]:
	var out: Array[float] = []
	var gap := spacing(map)
	if gap <= 0.0 or post_size(map) == Vector2.ZERO:
		return out
	var half := post_size(map).x * 0.5 + CLEAR
	var open := open_spans(map, blocked(map), half)
	var n := maxi(1, roundi(map.width / gap))
	for i in n:
		var want := map.width * (i + 0.5) / n
		var x: Variant = _nearest(open, want)
		if x == null or absf(x - want) > gap * 0.5:
			continue
		if not out.is_empty() and x - out[-1] < gap * 0.5:
			continue
		out.append(x)
	return out

## The ground each lantern keeps to itself (left and right edges as x and y), which the
## floor's scattered decor stays out of.
static func keep_clear(map: MapDef) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var half := post_size(map).x * 0.5 + CLEAR
	for x in slots(map):
		out.append(Vector2(x - half, x + half))
	return out

## The stretches of floor (left and right edges as x and y) where something already stands
## in the band a lantern post would fill.
static func blocked(map: MapDef) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var floor_y := float(map.ground_y)
	var band_top := floor_y - post_size(map).y - CLEAR
	var hits := func(top: float, bottom: float) -> bool: return bottom > band_top and top < floor_y
	var surface := func(platform: int) -> float:
		return floor_y if platform == 0 else map.platforms[platform - 1].y
	for b in map.buildings:
		var y: float = surface.call(b.platform)
		var h := b.building.height * b.scale if b.building else 0.0
		if hits.call(y - h, y):
			out.append(b.span())
	for p in map.portals:
		var y: float = surface.call(p.platform)
		if hits.call(y - PORTAL_HEIGHT, y):
			out.append(Vector2(p.x - PORTAL_HALF, p.x + PORTAL_HALF))
	for n in map.npcs:
		var y: float = surface.call(n.platform)
		if hits.call(y - NPC_HEIGHT, y):
			out.append(Vector2(n.x - NPC_HALF, n.x + NPC_HALF))
	for c in map.climbables:
		if hits.call(c.top, c.bottom):
			out.append(Vector2(c.x - CLIMB_HALF, c.x + CLIMB_HALF))
	for p in map.props:
		if p.texture == null:
			continue
		var size := TDStage.art_size(p.texture, TDStage.TEXEL * p.scale)
		var y := p.y if p.y >= 0.0 else floor_y
		if hits.call(y - size.y, y):
			out.append(Vector2(p.x - size.x * 0.5, p.x + size.x * 0.5))
	for d in map.platforms:
		var r := platform_rect(d, map.biome)
		if hits.call(r.position.y, r.end.y):
			out.append(Vector2(r.position.x, r.end.x))
	return out

## The area a platform's land art covers, in game pixels.
static func platform_rect(d: PlatformDef, biome: BiomeDef) -> Rect2:
	if d.look:
		var w := d.width / PlatformDef.LOOK_SPAN
		var top := d.y - d.look_grass()
		return Rect2(d.x + d.width * 0.5 - w * 0.5, top, w, d.look.get_height() * d.look_texel())
	if biome and biome.platform_middle:
		var span := PlatformSkin.span(biome, d.y)
		return Rect2(d.x, span.x, d.width, span.y - span.x)
	return Rect2(d.x, d.y, d.width, 40.0)

## Where a lantern's middle may stand (left and right ends as x and y): inside the map's
## edges and at least `half` from anything in `taken`.
static func open_spans(map: MapDef, taken: Array[Vector2], half: float) -> Array[Vector2]:
	var spans := taken.duplicate()
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[Vector2] = []
	var x := EDGE + half
	var end := map.width - EDGE - half
	for s in spans:
		if s.x - half > x:
			out.append(Vector2(x, minf(s.x - half, end)))
		x = maxf(x, s.y + half)
	if x < end:
		out.append(Vector2(x, end))
	return out.filter(func(o: Vector2) -> bool: return o.y >= o.x)

## The x in `open` nearest `want`, or null if there is none.
static func _nearest(open: Array[Vector2], want: float) -> Variant:
	var best: Variant = null
	for o in open:
		var x := clampf(want, o.x, o.y)
		if best == null or absf(x - want) < absf(best - want):
			best = x
	return best
