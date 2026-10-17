extends TestCase
## Monsters across the zones (Cory, 2026-10-12): a map has at most three kinds of monster;
## each kind lives in one region (major zone) only; and the walk between towns stays easy, so
## every border field (a field with a portal into another region) spawns only monsters of
## tuning tier (MonsterDef.level) 10 or below.

const Scan := preload("res://tests/content/content_scan.gd")

const MAX_KINDS_PER_MAP := 3
const BORDER_MAX_LEVEL := 10
## Regions still borrowing their neighbours' monsters until they get their own (Cory, 2026-10-12:
## Dawnharbor gets monsters of its own later). Take a region off once it has them.
const BORROWING_REGIONS: Array[StringName] = [&"dawnharbor"]

func test_maps_have_at_most_three_kinds_of_monster() -> void:
	for m: MapDef in Content.maps.values():
		var kinds := {}
		for s in m.spawns:
			if s and s.monster:
				kinds[s.monster.id] = true
		check(kinds.size() <= MAX_KINDS_PER_MAP, "%s: %d kinds of monster %s, keep it to %d" % [Scan.where(m), kinds.size(), kinds.keys(), MAX_KINDS_PER_MAP])

func test_each_monster_lives_in_one_region() -> void:
	var regions_of := {}
	for m: MapDef in Content.maps.values():
		if m.region in BORROWING_REGIONS:
			continue
		for s in m.spawns:
			# what steps out of a job test's tear is the same in every job town (Cory)
			if s and s.monster and not s.from_tear:
				if not regions_of.has(s.monster.id):
					regions_of[s.monster.id] = {}
				regions_of[s.monster.id][m.region] = true
	for id in regions_of:
		check(regions_of[id].size() == 1, "%s spawns in %s; a monster belongs to one region" % [id, regions_of[id].keys()])

func test_border_fields_are_easy() -> void:
	for m: MapDef in Content.maps.values():
		if m.town or m.interior:
			continue
		for p in m.portals:
			var to: MapDef = Content.maps.get(p.target_map)
			if to and not to.interior and to.region != m.region:
				var top := 0
				for s in m.spawns:
					if s and s.monster:
						top = maxi(top, s.monster.level)
				check(top <= BORDER_MAX_LEVEL, "%s: leads into %s, so it's on the way between towns, but spawns a tier %d monster" % [Scan.where(m), to.region, top])
