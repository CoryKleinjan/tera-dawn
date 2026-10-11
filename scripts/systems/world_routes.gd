class_name WorldRoutes
## How the world fits together, worked out from the maps' portals and the travel NPCs, so a
## new map or region joins the world map without being listed anywhere else.
##
## A **link** is two outdoor maps joined by a portal (each pair once, either direction).
## A **major route** joins two regions (major zones): on foot when a map of one has a portal
## into the other, or by a trip (a ship) to a region you can't walk to. Trips between regions
## that are walkable anyway (the coaches) are shortcuts, not routes.

## Two outdoor maps joined by a portal, as [a, b] with a < b. Doors into rooms aren't links.
static func links() -> Array:
	var seen := {}
	var out := []
	for m: MapDef in Content.maps.values():
		if m.interior:
			continue
		for p in m.portals:
			var to: MapDef = Content.maps.get(p.target_map)
			if to == null or to.interior or to.id == m.id:
				continue
			var pair := [m.id, to.id] if String(m.id) < String(to.id) else [to.id, m.id]
			var key := "%s|%s" % pair
			if not seen.has(key):
				seen[key] = true
				out.append(pair)
	return out

## The maps `id` has a portal link to (either direction), outdoor ones only.
static func linked(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for pair in links():
		if pair[0] == id:
			out.append(pair[1])
		elif pair[1] == id:
			out.append(pair[0])
	return out

## The major routes, each {"a": region id, "b": region id, "by": "Walk" or the trip's
## TravelRoute.by ("Ship")}, a < b, each pair of regions once. `crossings` (Array of map-id
## pairs) holds the links that cross between them on foot.
static func routes() -> Array:
	var by_pair := {}
	for pair in links():
		var a := _region_of(pair[0])
		var b := _region_of(pair[1])
		if a == &"" or b == &"" or a == b:
			continue
		var key := _pair_key(a, b)
		if not by_pair.has(key):
			by_pair[key] = _route(a, b, "Walk")
		by_pair[key].crossings.append(pair)
	for m: MapDef in Content.maps.values():
		for place in m.npcs:
			if place.npc == null:
				continue
			for trip in place.npc.travel:
				var a := _region_of(m.id)
				var b := _region_of(trip.target_map)
				if a == &"" or b == &"" or a == b or by_pair.has(_pair_key(a, b)) or _walkable(a, b, by_pair):
					continue
				by_pair[_pair_key(a, b)] = _route(a, b, trip.by)
	return by_pair.values()

## The routes that start or end in `region`.
static func routes_of(region: StringName) -> Array:
	return routes().filter(func(r: Dictionary) -> bool: return r.a == region or r.b == region)

## The region on the other end of `route` from `region`.
static func other_end(route: Dictionary, region: StringName) -> StringName:
	return route.b if route.a == region else route.a

## The region a map belongs to; a room counts as the town outside it.
static func _region_of(map_id: StringName) -> StringName:
	var m: MapDef = Content.maps.get(map_id)
	if m == null:
		return &""
	if m.interior:
		var outside: MapDef = Content.maps.get(m.outside())
		return outside.region if outside else m.region
	return m.region

static func _pair_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % ([a, b] if String(a) < String(b) else [b, a])

static func _route(a: StringName, b: StringName, by: String) -> Dictionary:
	var ends := [a, b] if String(a) < String(b) else [b, a]
	return {"a": ends[0], "b": ends[1], "by": by, "crossings": []}

## Whether regions `a` and `b` are joined on foot through other regions.
static func _walkable(a: StringName, b: StringName, by_pair: Dictionary) -> bool:
	var reached := {a: true}
	var todo: Array[StringName] = [a]
	while not todo.is_empty():
		var at: StringName = todo.pop_back()
		for r: Dictionary in by_pair.values():
			if r.by != "Walk" or not (r.a == at or r.b == at):
				continue
			var next: StringName = other_end(r, at)
			if not reached.has(next):
				reached[next] = true
				todo.append(next)
	return reached.has(b)
