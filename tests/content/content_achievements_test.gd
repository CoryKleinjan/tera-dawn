extends TestCase
## Achievements.LIST: every entry is complete, ids and Steam ids are unique, every kind is
## something Achievements.measure or Character.count actually tracks, goals are reachable
## numbers, and find() returns each one.

const KEYS := ["id", "steam", "title", "text", "kind", "goal"]

## Kinds measure() reads straight from the Character, from the source of achievements.gd,
## plus tallies some game code counts with Character.count("<kind>").
func _known_kinds() -> Dictionary:
	var out := {}
	var re_measure := RegEx.create_from_string("\"(\\w+)\":\\s*return")
	for m in re_measure.search_all(FileAccess.get_file_as_string("res://scripts/systems/achievements.gd")):
		out[m.get_string(1)] = "measured"
	var re_count := RegEx.create_from_string("\\.count\\(\"(\\w+)\"")
	for path in _scripts("res://scripts"):
		for m in re_count.search_all(FileAccess.get_file_as_string(path)):
			out[m.get_string(1)] = path
	return out

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out

func test_every_achievement_is_complete() -> void:
	check(Achievements.LIST.size() >= 10, "achievements: %d" % Achievements.LIST.size())
	for i in Achievements.LIST.size():
		var a: Dictionary = Achievements.LIST[i]
		for k in KEYS:
			check(a.has(k), "Achievements.LIST[%d] (%s): no %s" % [i, a.get("id", "?"), k])
		for k in ["id", "steam", "title", "text", "kind"]:
			check(a.get(k) is String and String(a.get(k, "")).strip_edges() != "", "Achievements.LIST[%d] (%s): %s is empty or not text" % [i, a.get("id", "?"), k])
		check(a.get("goal") is int and int(a.get("goal", 0)) >= 1, "Achievements.LIST[%d] (%s): goal %s must be a whole number of at least 1" % [i, a.get("id", "?"), a.get("goal")])

func test_ids_are_unique_snake_case() -> void:
	var re := RegEx.create_from_string("^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
	var seen := {}
	for i in Achievements.LIST.size():
		var id := str(Achievements.LIST[i].get("id", ""))
		check(re.search(id) != null, "Achievements.LIST[%d]: id %s is not snake_case" % [i, id])
		check(not seen.has(id), "Achievements.LIST[%d]: id %s is also LIST[%s]" % [i, id, seen.get(id)])
		seen[id] = i

func test_steam_ids_are_unique_upper_case() -> void:
	var re := RegEx.create_from_string("^[A-Z][A-Z0-9_]*$")
	var seen := {}
	for i in Achievements.LIST.size():
		var a: Dictionary = Achievements.LIST[i]
		var steam := str(a.get("steam", ""))
		check(re.search(steam) != null, "Achievements.LIST[%d] (%s): steam id %s isn't an upper-case Steam API name" % [i, a.get("id"), steam])
		check(not seen.has(steam), "Achievements.LIST[%d] (%s): steam id %s is also used by %s" % [i, a.get("id"), steam, seen.get(steam)])
		seen[steam] = a.get("id")

func test_titles_are_unique() -> void:
	var seen := {}
	for a: Dictionary in Achievements.LIST:
		check(not seen.has(a["title"]), "achievement %s: title %s is also %s's" % [a["id"], a["title"], seen.get(a["title"])])
		seen[a["title"]] = a["id"]

func test_every_kind_is_tracked() -> void:
	var known := _known_kinds()
	for a: Dictionary in Achievements.LIST:
		check(known.has(a["kind"]), "achievement %s: kind %s is neither measured by Achievements.measure nor counted with Character.count" % [a["id"], a["kind"]])

func test_goals_of_one_kind_climb() -> void:
	# two achievements of the same kind and goal would always unlock together
	var seen := {}
	for a: Dictionary in Achievements.LIST:
		var key := "%s/%d" % [a["kind"], a["goal"]]
		check(not seen.has(key), "achievement %s: same kind and goal as %s" % [a["id"], seen.get(key)])
		seen[key] = a["id"]

func test_goals_are_reachable() -> void:
	var c := Character.new()
	for a: Dictionary in Achievements.LIST:
		if a["kind"] == "level":
			check(c.xp_need(int(a["goal"])) > 0, "achievement %s: level %d has no EXP curve" % [a["id"], a["goal"]])
		if a["kind"] == "maps":
			check(int(a["goal"]) <= Content.maps.size(), "achievement %s: visit %d maps, but there are %d" % [a["id"], a["goal"], Content.maps.size()])
		if a["kind"] == "pages":
			check(int(a["goal"]) <= Content.monsters.size(), "achievement %s: %d pages, but there are %d monsters" % [a["id"], a["goal"], Content.monsters.size()])
		if a["kind"] == "quests":
			check(int(a["goal"]) <= Content.quests.size(), "achievement %s: finish %d quests, but there are %d" % [a["id"], a["goal"], Content.quests.size()])

func test_find_returns_each_achievement() -> void:
	for a: Dictionary in Achievements.LIST:
		check_eq(Achievements.find(a["id"]), a, "Achievements.find(%s)" % a["id"])
	check(Achievements.find("no_such_achievement").is_empty(), "find of an unknown id is empty")

func test_a_new_character_has_reached_nothing() -> void:
	var c := Character.create("Fresh")
	for a: Dictionary in Achievements.LIST:
		check(Achievements.measure(c, a["kind"]) < int(a["goal"]), "achievement %s: a new character already has it" % a["id"])
	check(Achievements.check(c).is_empty(), "a new character reaches no achievement")
