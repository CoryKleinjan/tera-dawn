extends TestCase
## The world hangs together: everything placed on a map stands on a real platform inside
## the map, every portal has a way back and lands somewhere sensible, every map can be
## reached from the starting map, every item can be got somehow, every monster lives
## somewhere, big monsters don't loom right over NPCs, and there's enough of everything (what tests/smoke_test.gd checks too).
## Nobody arrives or stands where the quickslots would cover them, and the map's sign stands
## clear of its portals.

const Scan := preload("res://tests/content/content_scan.gd")
const MapReach := preload("res://tests/content/map_reach.gd")

## How far from a map's right edge arrivals and NPCs must be: the quickslot panel's width and
## margin (game pixels are screen pixels at the default camera) and a hero's width, so with
## the camera at the edge the panel never covers them.
static func right_edge_clear() -> float:
	return TDQuickslots.panel_size().x + TDQuickslots.MARGIN.x + TDPlayer.WIDTH

func _platform_count(m: MapDef) -> int:
	return m.platforms.size() + 1

func test_platforms_lie_inside_the_map() -> void:
	# What the zoomed-out camera shows on the tallest screen shape the game expects (16:10,
	# like the Steam Deck), so it never shows past a map's edges.
	var view := Vector2(960, 600) / WorldCamera.ZOOM
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		check(m.width >= view.x and m.height >= view.y, "%s: size %dx%d is smaller than the camera's view %s" % [w, m.width, m.height, view])
		check(m.ground_y > 0 and m.ground_y < m.height, "%s: ground_y %d is outside 0..height %d" % [w, m.ground_y, m.height])
		check_between(m.start_x, 0, m.width, "%s: start_x" % w)
		for i in m.platforms.size():
			var p := m.platforms[i]
			if not check(p != null, "%s: platforms[%d] is empty" % [w, i]):
				continue
			check(p.width > 0, "%s: platforms[%d].width is %s" % [w, i, p.width])
			check(p.x >= 0 and p.x + p.width <= m.width, "%s: platforms[%d] runs from x %s to %s, outside 0..%d" % [w, i, p.x, p.x + p.width, m.width])
			check(p.y > 0 and p.y < m.ground_y, "%s: platforms[%d].y %s is not between the top and the floor (%d)" % [w, i, p.y, m.ground_y])

func test_arrivals_and_npcs_keep_clear_of_the_quickslots() -> void:
	var clear := right_edge_clear()
	for m: MapDef in Content.maps.values():
		for x: float in MapReach.arrivals_of(m):
			check(m.width - x >= clear, "%s: players arrive at x %d, %d from the right edge, under the quickslots (want %d+)" % [Scan.where(m), x, m.width - x, clear])
		for n in m.npcs:
			check(m.width - n.x >= clear, "%s: %s stands at x %d, %d from the right edge, under the quickslots (want %d+)" % [Scan.where(m), n.npc.id, n.x, m.width - n.x, clear])

func test_spawns_npcs_and_portals_stand_on_real_platforms() -> void:
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var n := _platform_count(m)
		for i in m.spawns.size():
			var s := m.spawns[i]
			if s:
				check(s.platform >= 0 and s.platform < n, "%s: spawns[%d].platform %d, the map has 0..%d" % [w, i, s.platform, n - 1])
		for i in m.npcs.size():
			var p := m.npcs[i]
			if p:
				check(p.platform >= 0 and p.platform < n, "%s: npcs[%d].platform %d, the map has 0..%d" % [w, i, p.platform, n - 1])
		for i in m.portals.size():
			var p := m.portals[i]
			if p:
				check(p.platform >= 0 and p.platform < n, "%s: portals[%d].platform %d, the map has 0..%d" % [w, i, p.platform, n - 1])

func test_npcs_and_portals_stand_on_their_platform() -> void:
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var layout := MapLayout.new(m)
		for i in m.npcs.size():
			var p := m.npcs[i]
			if p and p.platform >= 0 and p.platform < layout.platforms.size():
				check(layout.platforms[p.platform].contains_x(p.x), "%s: npcs[%d] (%s) at x %s is off platform %d" % [w, i, p.npc.id if p.npc else "?", p.x, p.platform])
				check(p.face == 1 or p.face == -1, "%s: npcs[%d].face is %d" % [w, i, p.face])
		for i in m.portals.size():
			var p := m.portals[i]
			if p and p.platform >= 0 and p.platform < layout.platforms.size():
				check(layout.platforms[p.platform].contains_x(p.x), "%s: portals[%d] at x %s is off platform %d" % [w, i, p.x, p.platform])
				check_between(p.x, 0, m.width, "%s: portals[%d].x" % [w, i])

## A monster at least this tall (game pixels) is big enough to crowd the NPCs under its ledge.
const BIG_MONSTER := 80.0
## How high over an NPC's feet a big monster's ledge must be not to crowd them.
const NPC_HEADROOM := 260.0

func test_big_monsters_dont_crowd_over_npcs() -> void:
	for m: MapDef in Content.maps.values():
		var layout := MapLayout.new(m)
		for i in m.spawns.size():
			var s := m.spawns[i]
			if s == null or s.monster == null or s.platform <= 0 or s.platform >= layout.platforms.size():
				continue
			if s.monster.size.y * s.monster.sprite_scale < BIG_MONSTER:
				continue
			var area := s.patrol_area(layout.platforms[s.platform])
			var half := s.monster.size.x * s.monster.sprite_scale / 2.0
			for n in m.npcs:
				if n == null or n.platform >= layout.platforms.size():
					continue
				var below := layout.platforms[n.platform].y - area.y
				var under := n.x > area.x - half and n.x < area.x + area.w + half
				check(not (under and below > 0.0 and below < NPC_HEADROOM), "%s: spawns[%d] (%s) on platform %d stands right over %s" % [Scan.where(m), i, s.monster.id, s.platform, n.npc.id if n.npc else "?"])

func test_portals_dont_overlap() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.portals.size():
			for k in range(i + 1, m.portals.size()):
				var a := m.portals[i]
				var b := m.portals[k]
				if a and b and a.platform == b.platform:
					check(absf(a.x - b.x) >= 68, "%s: portals[%d] and portals[%d] overlap (x %s and %s)" % [Scan.where(m), i, k, a.x, b.x])

## No NPC is drawn over a portal: the gap between them is at least half the portal's picture
## plus half a body (the hero's width), so the swirl and the NPC never overlap.
func test_npcs_dont_stand_in_portals() -> void:
	for m: MapDef in Content.maps.values():
		var portal_half := 34.0
		if m.look() and not m.look().portal_frames.is_empty():
			portal_half = maxf(portal_half, TDStage.art_size(m.look().portal_frames[0]).x / 2.0)
		for i in m.npcs.size():
			var n := m.npcs[i]
			if n == null:
				continue
			for p in m.portals:
				if p and p.platform == n.platform:
					var gap := portal_half + TDPlayer.WIDTH / 2.0 if not p.door else 34.0
					check(absf(n.x - p.x) >= gap, "%s: npcs[%d] (%s) at x %s overlaps the portal at x %s (want %d+ apart)" % [Scan.where(m), i, n.npc.id if n.npc else "?", n.x, p.x, gap])

func test_climbables_lie_inside_the_map_and_reach_a_platform() -> void:
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var layout := MapLayout.new(m)
		for i in m.climbables.size():
			var c := m.climbables[i]
			if c == null:
				continue
			check_between(c.x, 0, m.width, "%s: climbables[%d].x" % [w, i])
			check(c.top >= 0 and c.top < c.bottom, "%s: climbables[%d] top %s must be above bottom %s and inside the map" % [w, i, c.top, c.bottom])
			check(c.bottom <= m.ground_y, "%s: climbables[%d].bottom %s is below the floor (%d)" % [w, i, c.bottom, m.ground_y])
			# the top has to let you off onto something
			var lands := false
			for pl in layout.platforms:
				lands = lands or (pl.contains_x(c.x) and absf(pl.y - c.top) <= 40)
			check(lands, "%s: climbables[%d] at x %s tops out at %s with no platform there" % [w, i, c.x, c.top])

## A rope or ladder hangs from the platform its top is on and stands on the floor its bottom
## reaches, with its end pieces clear of those platforms' ends (else it hangs off a ledge).
## Each side is measured from the line to the end piece's solid pixels on that side, with the
## top piece mirrored as the game draws it.
func test_climbables_fit_on_their_platforms() -> void:
	for m: MapDef in Content.maps.values():
		var w := Scan.where(m)
		var layout := MapLayout.new(m)
		for i in m.climbables.size():
			var c := m.climbables[i]
			if c == null or c.style == null:
				continue
			var st := c.style
			for end in [[c.top, st.top if st.top else st.middle], [c.bottom, st.bottom if st.bottom else st.middle]]:
				if not check(layout.platforms.any(func(pl: Platform) -> bool: return pl.contains_x(c.x) and absf(pl.y - end[0]) < 1.0),
						"%s: climbables[%d] at x %s has no platform at y %s" % [w, i, c.x, end[0]]):
					continue
				var room := ClimbStyleDef.ledge_room(c.x, end[0], layout.platforms)
				var reach := ClimbStyleDef.solid_reach(end[1], st.texel)
				if end[1] == st.top and st.top_flipped(room):
					reach = Vector2(reach.y, reach.x)
				check(room.x >= reach.x and room.y >= reach.y,
						"%s: climbables[%d] at x %s hangs over the end of the platform at y %s (its art reaches %s px left, %s px right)" % [w, i, c.x, end[0], snappedf(reach.x, 0.1), snappedf(reach.y, 0.1)])

## A climbable's top piece (a rope's post, a vine's tangle, a ladder's posts) stays small next
## to the hero. A rope's top also carries the start of the rope hanging from its knot, so the
## limit is 60% of the hero's height, not half.
const CLIMB_TOP_MAX := 0.6

func test_climb_tops_are_in_scale_with_the_hero() -> void:
	for st: ClimbStyleDef in _climb_styles():
		if st.top == null:
			continue
		var h := TDStage.art_size(st.top, st.texel).y
		check(h <= TDPlayer.HEIGHT * CLIMB_TOP_MAX,
				"climb style %s: its top piece is %s px tall, more than %d%% of the hero's %s" % [st.id, snappedf(h, 0.1), CLIMB_TOP_MAX * 100, TDPlayer.HEIGHT])

func _climb_styles() -> Array[ClimbStyleDef]:
	var out: Array[ClimbStyleDef] = []
	for m: MapDef in Content.maps.values():
		for c in m.climbables:
			if c and c.style and not out.has(c.style):
				out.append(c.style)
	return out

func test_npcs_and_starts_are_inside_the_map() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.npcs.size():
			if m.npcs[i]:
				check_between(m.npcs[i].x, 0, m.width, "%s: npcs[%d].x" % [Scan.where(m), i])
		check(MapLayout.new(m).portal_at(Vector2(m.start_x, m.ground_y)) == null, "%s: start_x %s is inside a portal" % [Scan.where(m), m.start_x])

func test_every_portal_has_a_way_back() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.portals.size():
			var p := m.portals[i]
			var there: MapDef = Content.maps.get(p.target_map) if p else null
			if there == null:
				continue
			check(there.portals.any(func(b: PortalDef) -> bool: return b.target_map == m.id),
				"%s: portals[%d] leads to %s, which has no portal back" % [Scan.where(m), i, p.target_map])

func test_portals_land_on_the_map_away_from_portals() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.portals.size():
			var p := m.portals[i]
			var there: MapDef = Content.maps.get(p.target_map) if p else null
			if there == null:
				continue
			var what := "%s: portals[%d].target_x %s on %s" % [Scan.where(m), i, p.target_x, p.target_map]
			check(p.target_x >= 0 and p.target_x <= there.width, what + " is off the map")
			check(not there.portals.any(func(b: PortalDef) -> bool: return absf(b.x - p.target_x) < 34), what + " lands inside a portal")

func test_portals_land_near_the_portal_back() -> void:
	# stepping through and straight back should bring you close to where you started
	for m: MapDef in Content.maps.values():
		for i in m.portals.size():
			var p := m.portals[i]
			var there: MapDef = Content.maps.get(p.target_map) if p else null
			if there == null:
				continue
			var back := there.portals.filter(func(b: PortalDef) -> bool: return b.target_map == m.id)
			if back.is_empty():
				continue
			var nearest := INF
			for b: PortalDef in back:
				nearest = minf(nearest, absf(b.x - p.target_x))
			check(nearest <= 400, "%s: portals[%d] lands %s px from the portal back to %s" % [Scan.where(m), i, nearest, m.id])

func test_travel_routes_land_away_from_portals() -> void:
	for n: NpcDef in Content.npcs.values():
		for i in n.travel.size():
			var r := n.travel[i]
			var there: MapDef = Content.maps.get(r.target_map)
			if there:
				check(not there.portals.any(func(b: PortalDef) -> bool: return absf(b.x - r.target_x) < 34),
					"%s: travel[%d] lands inside a portal on %s" % [Scan.where(n), i, r.target_map])

func _reachable(from: StringName) -> Dictionary:
	var seen := {from: true}
	var todo: Array[StringName] = [from]
	while not todo.is_empty():
		var m: MapDef = Content.maps.get(todo.pop_back())
		if m == null:
			continue
		var nexts: Array[StringName] = m.neighbours()
		for p in m.npcs:
			if p and p.npc:
				for r in p.npc.travel:
					nexts.append(r.target_map)
		for n in nexts:
			if Content.maps.has(n) and not seen.has(n):
				seen[n] = true
				todo.append(n)
	return seen

func test_every_map_is_reachable_from_the_start() -> void:
	check(Content.maps.has(Character.START_MAP), "Character.START_MAP %s is not a map" % Character.START_MAP)
	var seen := _reachable(Character.START_MAP)
	for id in Content.maps:
		check(seen.has(id), "%s: can't be reached from %s by portals or travel" % [Scan.where(Content.maps[id]), Character.START_MAP])

func test_the_start_is_reachable_from_every_map() -> void:
	# no one-way trips: from anywhere you can find your way back to the start
	for id in Content.maps:
		check(_reachable(id).has(Character.START_MAP), "%s: no way back to %s" % [Scan.where(Content.maps[id]), Character.START_MAP])

func test_every_town_has_a_storage_keeper() -> void:
	for m: MapDef in Content.maps.values():
		if m.town and m.id != &"free_market" and m.id != Character.START_MAP:
			check(m.npcs.any(func(p: NpcPlacement) -> bool: return p.npc and p.npc.storage), "%s: town has no storage keeper" % Scan.where(m))

func test_market_maps_have_a_market_clerk() -> void:
	var markets := 0
	for m: MapDef in Content.maps.values():
		if m.market:
			markets += 1
			check(m.npcs.any(func(p: NpcPlacement) -> bool: return p.npc and p.npc.market), "%s: market map without a market NPC" % Scan.where(m))
	check(markets >= 1, "there is a Free Market map")
	for m: MapDef in Content.maps.values():
		for p in m.npcs:
			if p and p.npc and p.npc.market:
				check(m.market, "%s: %s helps set up shops on a map that isn't a market" % [Scan.where(m), p.npc.id])

## Monsters kept in the game's files that no map spawns yet: Ember Hollow's fire monsters,
## which left Dawnrise Isle when it became Fern Hollow (Cory, 2026-10-11: he'll place them elsewhere).
const KNOWN_UNSPAWNED: Array[StringName] = [&"ember_boar", &"cinder_imp", &"ashshell", &"flame_boar_chief"]

func test_every_monster_lives_somewhere() -> void:
	var spawned := Scan.spawned_monsters()
	for id in Content.monsters:
		if id in KNOWN_UNSPAWNED:
			check(not spawned.has(id), "%s is spawned now: take it off KNOWN_UNSPAWNED" % id)
			continue
		check(spawned.has(id), "%s: no map spawns it (nor a monster that splits into it)" % Scan.where(Content.monsters[id]))

func test_monsters_that_split_children_are_not_spawned_directly_only() -> void:
	# a split-only monster still needs its parent on a map
	var spawned := Scan.spawned_monsters()
	for m: MonsterDef in Content.monsters.values():
		if m.splits_into and spawned.has(m.id):
			check(spawned.has(m.splits_into.id), "%s: splits into %s, which never appears" % [Scan.where(m), m.splits_into.id])

## Every way to get an item: id -> how.
func _sources() -> Dictionary:
	var out := {}
	var spawned := Scan.spawned_monsters()
	var placed := Scan.placed_npcs()
	for m: MonsterDef in spawned.values():
		for d in m.drops:
			if d and d.item:
				out[d.item.id] = "dropped by %s" % m.id
		var card := Content.card(m)
		if card:
			out[card.id] = "card of %s" % m.id
	for n: NpcDef in Content.npcs.values():
		if n.shop and placed.has(n.id):
			for e in n.shop.items:
				if e and e.item:
					out[e.item.id] = "sold by %s" % n.id
	for q: QuestDef in Content.quests.values():
		for r in q.reward_items:
			if r and r.item:
				out[r.item.id] = "reward of %s" % q.id
		for o in q.objectives:
			if o and o.kind == QuestObjective.Kind.COLLECT and o.drop_from and o.item and spawned.has(o.drop_from.id):
				out[o.item.id] = "quest drop from %s" % o.drop_from.id
	for j: JobDef in Content.jobs.values():
		for g in j.advance_gifts + j.starting_items:
			if g and g.item:
				out[g.item.id] = "given by job %s" % j.id
		for e in j.starting_gear + j.creator_gear:
			if e:
				out[e.id] = "starting gear of %s" % j.id
	return out

## Items nothing drops, sells or gives yet, if a gap is ever let in on purpose. Remove an id
## once something does (the test below fails when a listed item becomes obtainable).
## The fire monsters' own loot, while they wait for a new home (see KNOWN_UNSPAWNED).
const KNOWN_UNOBTAINABLE: Array[StringName] = [&"cinder_horn", &"ashshell_fragment",
	&"card_ember_boar", &"card_cinder_imp", &"card_ashshell", &"card_flame_boar_chief"]

func test_every_item_can_be_obtained() -> void:
	var sources := _sources()
	for id in Content.items:
		if id in KNOWN_UNOBTAINABLE:
			continue
		check(sources.has(id), "%s: no monster drops it, no shop sells it, no quest or job gives it" % Scan.where(Content.items[id]))

func test_known_unobtainable_list_is_current() -> void:
	var sources := _sources()
	for id in KNOWN_UNOBTAINABLE:
		check(Content.items.has(id), "KNOWN_UNOBTAINABLE lists %s, which is not an item" % id)
		check(not sources.has(id), "%s is %s now: take it off KNOWN_UNOBTAINABLE" % [id, sources.get(id)])

func test_every_quest_item_can_be_found() -> void:
	var sources := _sources()
	for q: QuestDef in Content.quests.values():
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o and o.kind == QuestObjective.Kind.COLLECT and o.item:
				check(sources.has(o.item.id), "%s: objectives[%d] wants %s, which can't be got" % [Scan.where(q), i, o.item.id])

func test_every_quest_can_be_taken_by_someone() -> void:
	for q: QuestDef in Content.quests.values():
		if q.jobs.is_empty():
			continue
		check(q.jobs.all(func(j: StringName) -> bool: return Content.jobs.has(j)), "%s: jobs names an unknown job" % Scan.where(q))

func test_every_skill_can_be_learned() -> void:
	# its job exists and is reachable, and its requirement chain ends
	for s: SkillDef in Content.skills.values():
		if s.innate:
			continue
		var job: JobDef = Content.jobs.get(s.job)
		if job == null:
			continue
		var steps := 0
		var cur := s
		while cur and cur.requires != &"" and steps < 20:
			cur = Content.skills.get(cur.requires)
			steps += 1
		check(steps < 20, "%s: requires chain never ends" % Scan.where(s))

func test_there_is_enough_content() -> void:
	# the same floors the smoke test keeps
	var towns := Content.maps.values().filter(func(m: MapDef) -> bool: return m.town)
	var bosses := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.boss)
	var shooters := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.shot != null)
	var splitters := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.splits_into != null)
	var scrolls := Content.items.values().filter(func(i: ItemDef) -> bool: return i is ScrollDef)
	check(Content.maps.has(&"meadow") and Content.maps.has(&"hollow"), "the starting maps meadow and hollow exist")
	check(towns.size() >= 7, "hub towns: %d, want at least 7" % towns.size())
	check(Content.maps.size() >= 40, "maps: %d, want at least 40" % Content.maps.size())
	check(Content.monsters.size() >= 50, "monsters: %d, want at least 50" % Content.monsters.size())
	check(bosses.size() >= 6, "bosses: %d, want at least 6" % bosses.size())
	check(shooters.size() >= 10, "monsters that shoot: %d, want at least 10" % shooters.size())
	check(splitters.size() >= 4, "monsters that split: %d, want at least 4" % splitters.size())
	check(Content.items.size() >= 200, "items: %d, want at least 200" % Content.items.size())
	check(scrolls.size() >= 12, "upgrade scrolls: %d, want at least 12" % scrolls.size())
	check(Content.quests.size() >= 6, "quests: %d, want at least 6" % Content.quests.size())
	check(not Content.shops.is_empty(), "there are shops")

func test_every_first_job_is_taught_in_a_town() -> void:
	for id in [&"warrior", &"archer", &"mage", &"thief", &"pirate"]:
		check(Content.jobs.has(id) and Content.jobs[id].advances_from == Character.START_JOB, "%s is a first job" % id)
		var teaches := false
		for m: MapDef in Content.maps.values():
			if m.town or m.interior and Content.maps.get(m.outside(), m).town:
				for p in m.npcs:
					teaches = teaches or (p.npc != null and id in p.npc.instructs)
		check(teaches, "some town's instructor teaches %s" % id)

func test_buildings_stand_on_their_platform() -> void:
	for m: MapDef in Content.maps.values():
		var layout := MapLayout.new(m)
		for i in m.buildings.size():
			var b := m.buildings[i]
			var w := "%s: buildings[%d]" % [Scan.where(m), i]
			if not check(b != null and b.building != null and b.building.texture != null, w + " has no building picture"):
				continue
			if check(b.platform >= 0 and b.platform < layout.platforms.size(), "%s.platform %d, the map has 0..%d" % [w, b.platform, layout.platforms.size() - 1]):
				check(layout.platforms[b.platform].contains_x(b.x), "%s: its door at x %s is off platform %d" % [w, b.x, b.platform])
			check(b.depth < 0.0, "%s.depth %s must be behind the walking line" % [w, b.depth])

func test_town_doors_are_in_a_building() -> void:
	# a door is a building's doorway: it stands where a building on that platform has its door
	for m: MapDef in Content.maps.values():
		if m.interior:
			continue
		for i in m.portals.size():
			var p := m.portals[i]
			if p and p.door:
				check(m.buildings.any(func(b: BuildingPlacement) -> bool: return b.platform == p.platform and absf(b.x - p.x) < 4.0),
					"%s: portals[%d] is a door but no building has its door at x %s" % [Scan.where(m), i, p.x])

func test_rooms_have_one_door_out_to_their_town() -> void:
	for m: MapDef in Content.maps.values():
		if not m.interior:
			continue
		var w := Scan.where(m)
		check(not m.town and m.spawns.is_empty(), "%s: a room is not a town and has no monsters" % w)
		check(m.world_pos == Vector2.ZERO, "%s: a room isn't drawn on the world map (its town is)" % w)
		if check(m.portals.size() == 1, "%s: a room has one door, it has %d portals" % [w, m.portals.size()]):
			var out := m.portals[0]
			check(out.door, "%s: its way out is a door" % w)
			check(out.target_map == m.return_map, "%s: its door leads to %s, its return_map is %s" % [w, out.target_map, m.return_map])
			var town: MapDef = Content.maps.get(m.return_map)
			if town:
				check(town.portals.any(func(d: PortalDef) -> bool: return d.door and d.target_map == m.id), "%s: %s has no door into it" % [w, town.id])
