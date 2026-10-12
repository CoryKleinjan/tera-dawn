extends TestCase
## Monsters and levels across the zones (Cory, 2026-10-12): a map has at most three kinds of
## monster; each kind lives in one region (major zone) only; and the walk between towns stays
## easy, so every border field (a field with a portal into another region) is Lv. 10 or below;
## and every monster a map spawns (or that splits off one) is inside the map's level range.

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
			if s and s.monster:
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
				var r := Scan.level_range(m.level_text)
				check(r.y <= BORDER_MAX_LEVEL, "%s: leads into %s, so it's on the way between towns; %s is above Lv. %d" % [Scan.where(m), to.region, m.level_text, BORDER_MAX_LEVEL])
				var top := 0
				for s in m.spawns:
					if s and s.monster:
						top = maxi(top, s.monster.level)
				check(top <= BORDER_MAX_LEVEL, "%s: a level %d monster on the way between towns" % [Scan.where(m), top])

func test_monsters_stay_inside_their_maps_level_range() -> void:
	# what a map spawns, and what those split into, is inside its level_text (Cory, 2026-10-12)
	for m: MapDef in Content.maps.values():
		var r := Scan.level_range(m.level_text)
		if r.x < 0:
			continue
		for s in m.spawns:
			var mon: MonsterDef = s.monster if s else null
			while mon:
				check(mon.level >= r.x and mon.level <= r.y, "%s: %s is level %d, outside %s" % [Scan.where(m), mon.id, mon.level, m.level_text])
				mon = mon.splits_into
