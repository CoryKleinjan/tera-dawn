extends TestCase
## TravelRoute fares (free coaches for Beginners ready for their first job) and how the
## dialogue window labels a trip: where it goes, who it's for and what it costs.

var fx: UnitHelpers
var beginner: JobDef
var route: TravelRoute
var dest: MapDef

func before_each() -> void:
	fx = UnitHelpers.new()
	beginner = Content.job(Character.START_JOB)
	route = TravelRoute.new()
	route.by = "Coach"
	route.price = 400
	dest = MapDef.new()
	dest.display_name = "Greenbough"

func after_each() -> void:
	fx.cleanup()

func _beginner(lvl: int) -> Character:
	var c := fx.character(beginner)
	c.level = lvl
	return c

func test_first_advance_level_is_the_lowest_job_level() -> void:
	var lowest := 1 << 30
	for j in JobDef.paths_from(Character.START_JOB):
		lowest = mini(lowest, j.advance_level)
	check_eq(JobDef.first_advance_level(Character.START_JOB), lowest, "Beginner")
	check_eq(lowest, 10, "Lv 10 in the game's data")
	check(JobDef.first_advance_level(&"t_nothing_from_here") > Character.MAX_LEVEL, "no path: never")

func test_a_plain_route_charges_everyone() -> void:
	check_eq(route.fare_for(_beginner(10)), 400, "a Beginner at 10")

func test_free_for_beginners_from_the_first_job_level() -> void:
	route.free_for_beginners = true
	var lvl := JobDef.first_advance_level(Character.START_JOB)
	check_eq(route.fare_for(_beginner(lvl - 1)), 400, "too early")
	check_eq(route.fare_for(_beginner(lvl)), 0, "ready for a job")
	check_eq(route.fare_for(_beginner(lvl + 5)), 0, "still a Beginner later on")
	var warrior := fx.character(Content.job(&"warrior"))
	warrior.level = 12
	check_eq(route.fare_for(warrior), 400, "someone with a job pays")

func test_label_names_the_trip_the_level_range_and_the_fare() -> void:
	dest.level_text = "Lv. 7-12"
	check_eq(TDDialogueWindow.travel_label(route, dest, _beginner(3)), "Coach to Greenbough (Lv. 7-12, 400 Dawnshards)", "with a level range")
	dest.level_text = ""
	check_eq(TDDialogueWindow.travel_label(route, dest, _beginner(3)), "Coach to Greenbough (400 Dawnshards)", "without one")

func test_label_leaves_out_a_town_and_says_free() -> void:
	dest.level_text = "Town"
	dest.town = true
	route.free_for_beginners = true
	check_eq(TDDialogueWindow.travel_label(route, dest, _beginner(10)), "Coach to Greenbough (free)", "a town, free")
	route.price = 0
	check_eq(TDDialogueWindow.travel_label(route, dest, fx.character()), "Coach to Greenbough (free)", "a free trip")

func test_rooks_coaches_to_the_job_towns_are_free_for_beginners() -> void:
	var instructed := {}
	for m: MapDef in Content.maps.values():
		for at in m.npcs:
			if not at.npc.instructs.is_empty():
				instructed[m.outside()] = true
	var rook: NpcDef = Content.npcs[&"harbor_taxi"]
	check(not rook.travel.is_empty(), "Rook drives")
	for r in rook.travel:
		check(instructed.has(r.target_map), "%s has a job instructor" % r.target_map)
		check(r.free_for_beginners, "the coach to %s is free for Beginners" % r.target_map)

func test_every_trip_to_a_field_shows_its_level_range() -> void:
	for n: NpcDef in Content.npcs.values():
		for r in n.travel:
			var m := Content.map(r.target_map)
			if m and not m.town and m.level_text != "":
				check(TDDialogueWindow.travel_label(r, m, fx.character()).contains(m.level_text + ","), "%s: trip to %s shows %s" % [n.id, m.id, m.level_text])
