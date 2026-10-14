extends TestCase
## The town rules in docs/game-rules.md ("Towns" and "Making a town") that data can show:
## every NPC is one person with their own name, NPCs stand in the middle of their plank,
## each building picture belongs to one town, and every town has what a town needs.

const Scan := preload("res://tests/content/content_scan.gd")

## Least room (game px) between an NPC's feet and the end of the platform they stand on.
const NPC_EDGE := 40.0
## Least buildings in a town (its store and job hall among them).
const MIN_BUILDINGS := 5
## Towns made before the town kit that are short of a rule below, and what they're short of.
## Each one is Cory's call; take a town off once it's fixed. New towns never go on this list.
const BEFORE_KIT := {
	"dawnrise_village": ["buildings", "storage keeper"],
}

func _towns() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m: MapDef in Content.maps.values():
		if m.town and not m.interior:
			out.append(m)
	return out

## The town map plus the rooms its doors lead into.
func _town_maps(m: MapDef) -> Array[MapDef]:
	var out: Array[MapDef] = [m]
	for p in m.portals:
		if p.door and Content.maps.has(p.target_map):
			out.append(Content.map(p.target_map))
	return out

func _short(m: MapDef, rule: String) -> bool:
	return BEFORE_KIT.get(String(m.id), []).has(rule)

## Two different NPCs never share the last word of their names ("Old Dace" and "Dace"). A
## character who travels is one person: the same name, even when each place has its own file.
func test_every_npc_has_their_own_name() -> void:
	var seen := {}
	for n: NpcDef in Content.npcs.values():
		var words := n.display_name.strip_edges().to_lower().split(" ", false)
		if words.is_empty():
			continue
		var key: String = words[-1]
		var name := n.display_name.strip_edges()
		check(not seen.has(key) or seen[key][0] == name, "%s (%s) and %s (%s) share the name \"%s\"" % [name, n.id, seen.get(key, ["", ""])[0], seen.get(key, ["", ""])[1], key])
		seen[key] = [name, n.id]

func test_town_npcs_stand_in_the_middle_of_their_platform() -> void:
	for town in _towns():
		for m in _town_maps(town):
			var layout := MapLayout.new(m)
			for p in m.npcs:
				if p == null or p.platform < 0 or p.platform >= layout.platforms.size():
					continue
				var pl: Platform = layout.platforms[p.platform]
				if p.platform == 0:
					continue  # the floor runs the whole map
				check(p.x - pl.x >= NPC_EDGE and pl.x + pl.w - p.x >= NPC_EDGE,
					"%s: %s stands %d px from the end of platform %d (want %d+)" % [Scan.where(m), p.npc.id if p.npc else "?", minf(p.x - pl.x, pl.x + pl.w - p.x), p.platform, NPC_EDGE])

## Every building in a town is its own picture, used once and only in that town.
func test_each_building_picture_belongs_to_one_town() -> void:
	var used := {}
	for town in _towns():
		for m in _town_maps(town):
			for b in m.buildings:
				if b.building == null or b.building.texture == null:
					continue
				var path := b.building.texture.resource_path
				check(not used.has(path), "%s: %s's picture is already used in %s" % [Scan.where(m), b.building.id, used.get(path, "")])
				used[path] = String(m.id)

func test_every_town_has_what_a_town_needs() -> void:
	check(BEFORE_KIT.size() <= _towns().size(), "the before-kit list only names towns")
	for town in _towns():
		var maps := _town_maps(town)
		var buildings := 0
		var keeper := false
		var shop := false
		for m in maps:
			buildings += m.buildings.size()
			for p in m.npcs:
				if p and p.npc:
					keeper = keeper or p.npc.storage
					shop = shop or p.npc.shop != null
		if not _short(town, "buildings"):
			check(buildings >= MIN_BUILDINGS, "%s: %d buildings (want %d+)" % [Scan.where(town), buildings, MIN_BUILDINGS])
		if not _short(town, "storage keeper"):
			check(keeper, "%s: no storage keeper" % Scan.where(town))
		if not _short(town, "shop"):
			check(shop, "%s: no shopkeeper" % Scan.where(town))
		if not _short(town, "store room"):
			check(maps.size() > 1, "%s: no doors into a store or hall" % Scan.where(town))
