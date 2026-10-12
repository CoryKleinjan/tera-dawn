extends TestCase
## TravelRoute fares and how the dialogue window labels a trip: where it goes, who it's for
## and what it costs.

var route: TravelRoute
var dest: MapDef

func before_each() -> void:
	route = TravelRoute.new()
	route.by = "Coach"
	route.price = 400
	dest = MapDef.new()
	dest.display_name = "Greenbough"

func test_label_names_the_trip_the_level_range_and_the_fare() -> void:
	dest.level_text = "Lv. 7-12"
	check_eq(TDDialogueWindow.travel_label(route, dest), "Coach to Greenbough (Lv. 7-12, 400 Dawnshards)", "with a level range")
	dest.level_text = ""
	check_eq(TDDialogueWindow.travel_label(route, dest), "Coach to Greenbough (400 Dawnshards)", "without one")

func test_label_leaves_out_a_town_and_says_free() -> void:
	dest.level_text = "Town"
	dest.town = true
	check_eq(TDDialogueWindow.travel_label(route, dest), "Coach to Greenbough (400 Dawnshards)", "a town")
	route.price = 0
	check_eq(TDDialogueWindow.travel_label(route, dest), "Coach to Greenbough (free)", "a free trip")

func test_rooks_coaches_to_the_job_towns_cost_a_fare() -> void:
	var instructed := {}
	for m: MapDef in Content.maps.values():
		for at in m.npcs:
			if not at.npc.instructs.is_empty():
				instructed[m.outside()] = true
	var rook: NpcDef = Content.npcs[&"harbor_taxi"]
	check(not rook.travel.is_empty(), "Rook drives")
	for r in rook.travel:
		check(instructed.has(r.target_map), "%s has a job instructor" % r.target_map)
		check(r.price > 0, "the coach to %s costs Dawnshards" % r.target_map)

func test_every_trip_to_a_field_shows_its_level_range() -> void:
	for n: NpcDef in Content.npcs.values():
		for r in n.travel:
			var m := Content.map(r.target_map)
			if m and not m.town and m.level_text != "":
				check(TDDialogueWindow.travel_label(r, m).contains(m.level_text + ","), "%s: trip to %s shows %s" % [n.id, m.id, m.level_text])
