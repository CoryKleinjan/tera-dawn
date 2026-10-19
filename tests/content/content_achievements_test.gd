extends TestCase
## Achievements (data/achievements/, through Content): every file loads as a complete
## AchievementDef, ids and Steam ids are unique, they're the 20 the game shipped with and kept (saves
## and Steamworks know them by id and Steam name), every kind is something
## Achievements.measure or a Counters tally actually tracks, goals are reachable numbers, and
## find() returns each one.

const Scan := preload("res://tests/content/content_scan.gd")

## The achievements as they were when they lived in code, in order. Saved characters keep
## these ids and Steamworks these Steam names, so none may change. Three were made solo goals
## when the game became single player first (Cory, 2026-10-16): level_50 (now every boss),
## well_liked (a boss untouched) and dealmaker (every map of a zone). lucky_scroll went with
## the upgrade scrolls (Cory, 2026-10-17), and level_5, level_10 and level_30 with player
## levels (Cory, 2026-10-19).
const SHIPPED := [
	{"id": "first_hunt", "steam": "ACH_FIRST_HUNT", "title": "First Hunt", "text": "Defeat a monster.", "kind": "kills", "goal": 1},
	{"id": "hunter", "steam": "ACH_HUNTER", "title": "Hunter", "text": "Defeat 500 monsters.", "kind": "kills", "goal": 500},
	{"id": "slayer", "steam": "ACH_SLAYER", "title": "Slayer", "text": "Defeat 5,000 monsters.", "kind": "kills", "goal": 5000},
	{"id": "boss_breaker", "steam": "ACH_BOSS_BREAKER", "title": "Boss Breaker", "text": "Defeat a boss.", "kind": "bosses", "goal": 1},
	{"id": "boss_hunter", "steam": "ACH_BOSS_HUNTER", "title": "Boss Hunter", "text": "Defeat 25 bosses.", "kind": "bosses", "goal": 25},
	{"id": "level_50", "steam": "ACH_LEVEL_50", "title": "Hero of Tera", "text": "Defeat every boss in Tera.", "kind": "boss_kinds", "goal": 8},
	{"id": "first_job", "steam": "ACH_FIRST_JOB", "title": "A Calling", "text": "Take up a job.", "kind": "job", "goal": 1},
	{"id": "helper", "steam": "ACH_HELPER", "title": "Helping Hand", "text": "Finish 10 quests.", "kind": "quests", "goal": 10},
	{"id": "hero_for_hire", "steam": "ACH_HERO_FOR_HIRE", "title": "Hero for Hire", "text": "Finish 30 quests.", "kind": "quests", "goal": 30},
	{"id": "wanderer", "steam": "ACH_WANDERER", "title": "Wanderer", "text": "Visit 20 maps.", "kind": "maps", "goal": 20},
	{"id": "cartographer", "steam": "ACH_CARTOGRAPHER", "title": "Cartographer", "text": "Visit 40 maps.", "kind": "maps", "goal": 40},
	{"id": "collector", "steam": "ACH_COLLECTOR", "title": "Collector", "text": "Find 10 Monster Book cards.", "kind": "cards", "goal": 10},
	{"id": "first_page", "steam": "ACH_FIRST_PAGE", "title": "First Page", "text": "Complete a Monster Book page.", "kind": "pages", "goal": 1},
	{"id": "scholar", "steam": "ACH_SCHOLAR", "title": "Monster Scholar", "text": "Complete 15 Monster Book pages.", "kind": "pages", "goal": 15},
	{"id": "nest_egg", "steam": "ACH_NEST_EGG", "title": "Nest Egg", "text": "Hold 100,000 Dawnshards.", "kind": "shards", "goal": 100000},
	{"id": "take_a_seat", "steam": "ACH_TAKE_A_SEAT", "title": "Take a Seat", "text": "Sit down for a rest.", "kind": "sat", "goal": 1},
	{"id": "best_friend", "steam": "ACH_BEST_FRIEND", "title": "Best Friend", "text": "Bring out a pet.", "kind": "pets", "goal": 1},
	{"id": "well_liked", "steam": "ACH_WELL_LIKED", "title": "Untouchable", "text": "Defeat a boss without taking a hit on its map.", "kind": "clean_bosses", "goal": 1},
	{"id": "guildmate", "steam": "ACH_GUILDMATE", "title": "Guildmate", "text": "Join a guild.", "kind": "guild", "goal": 1},
	{"id": "dealmaker", "steam": "ACH_DEALMAKER", "title": "Seen It All", "text": "Visit every map of a zone.", "kind": "zones_explored", "goal": 1},
]

const DIR := "res://data/achievements"

## Kinds measure() reads straight from the Character, from the source of achievements.gd,
## plus the tallies game code counts with Character.count (Counters).
func _known_kinds() -> Dictionary:
	var out := {}
	var re_measure := RegEx.create_from_string("\"(\\w+)\":\\s*return")
	for m in re_measure.search_all(FileAccess.get_file_as_string("res://scripts/systems/achievements.gd")):
		out[m.get_string(1)] = "measured"
	for k in Counters.ALL:
		out[k] = "counted"
	return out

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out

func test_every_file_loads_with_a_unique_id_and_steam_id() -> void:
	var ids := {}
	var steam := {}
	var files := Scan.files(DIR)
	for path in files:
		var a := load(path) as AchievementDef
		check(a != null, "%s: not an AchievementDef" % path)
		if a == null:
			continue
		check_eq(String(a.id), path.get_file().get_basename(), "%s: id matches the file name" % path)
		check(not ids.has(a.id), "%s: id %s is also %s's" % [path, a.id, ids.get(a.id)])
		check(not steam.has(a.steam), "%s: Steam id %s is also %s's" % [path, a.steam, steam.get(a.steam)])
		ids[a.id] = path
		steam[a.steam] = path
	check_eq(files.size(), SHIPPED.size(), "achievement files")
	check_eq(Content.achievements.size(), SHIPPED.size(), "achievements in Content")

func test_they_are_the_shipped_achievements_in_order() -> void:
	var list := Achievements.all()
	check_eq(list.size(), SHIPPED.size(), "achievements")
	for i in mini(list.size(), SHIPPED.size()):
		var a := list[i]
		var have := {"id": String(a.id), "steam": a.steam, "title": a.title, "text": a.text, "kind": a.kind, "goal": a.goal}
		check_eq(have, SHIPPED[i], "achievement %d" % i)

func test_orders_are_unique() -> void:
	var seen := {}
	for a in Achievements.all():
		check(not seen.has(a.order), "achievement %s: order %d is also %s's" % [a.id, a.order, seen.get(a.order)])
		seen[a.order] = a.id

func test_every_achievement_is_complete() -> void:
	var list := Achievements.all()
	check(list.size() >= 10, "achievements: %d" % list.size())
	for a in list:
		for k in ["steam", "title", "text", "kind"]:
			check(String(a.get(k)).strip_edges() != "", "achievement %s: %s is empty" % [a.id, k])
		check(a.goal >= 1, "achievement %s: goal %d must be at least 1" % [a.id, a.goal])

func test_ids_are_unique_snake_case() -> void:
	var re := RegEx.create_from_string("^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
	var seen := {}
	for a in Achievements.all():
		check(re.search(String(a.id)) != null, "achievement %s: id is not snake_case" % a.id)
		check(not seen.has(a.id), "achievement %s: id listed twice" % a.id)
		seen[a.id] = true

func test_steam_ids_are_unique_upper_case() -> void:
	var re := RegEx.create_from_string("^[A-Z][A-Z0-9_]*$")
	var seen := {}
	for a in Achievements.all():
		check(re.search(a.steam) != null, "achievement %s: steam id %s isn't an upper-case Steam API name" % [a.id, a.steam])
		check(not seen.has(a.steam), "achievement %s: steam id %s is also used by %s" % [a.id, a.steam, seen.get(a.steam)])
		seen[a.steam] = a.id

func test_titles_are_unique() -> void:
	var seen := {}
	for a in Achievements.all():
		check(not seen.has(a.title), "achievement %s: title %s is also %s's" % [a.id, a.title, seen.get(a.title)])
		seen[a.title] = a.id

func test_every_kind_is_tracked() -> void:
	var known := _known_kinds()
	for a in Achievements.all():
		check(known.has(a.kind), "achievement %s: kind %s is neither measured by Achievements.measure nor a Counters tally" % [a.id, a.kind])

func test_tallies_are_counted_by_name() -> void:
	# Character.count takes a Counters name, never a loose string that could drift from it
	var re := RegEx.create_from_string("\\.count\\(\"")
	for path in _scripts("res://scripts"):
		check(re.search(FileAccess.get_file_as_string(path)) == null, "%s: counts a tally by a loose string instead of a Counters name" % path)

func test_goals_of_one_kind_climb() -> void:
	# two achievements of the same kind and goal would always unlock together
	var seen := {}
	for a in Achievements.all():
		var key := "%s/%d" % [a.kind, a.goal]
		check(not seen.has(key), "achievement %s: same kind and goal as %s" % [a.id, seen.get(key)])
		seen[key] = a.id

func test_goals_are_reachable() -> void:
	for a in Achievements.all():
		if a.kind == "maps":
			check(a.goal <= Content.maps.size(), "achievement %s: visit %d maps, but there are %d" % [a.id, a.goal, Content.maps.size()])
		if a.kind == "pages":
			check(a.goal <= Content.monsters.size(), "achievement %s: %d pages, but there are %d monsters" % [a.id, a.goal, Content.monsters.size()])
		if a.kind == "quests":
			check(a.goal <= Content.quests.size(), "achievement %s: finish %d quests, but there are %d" % [a.id, a.goal, Content.quests.size()])
		if a.kind == "boss_kinds":
			check_eq(a.goal, Achievements.bosses_on_maps(), "achievement %s: every boss means the bosses on maps" % a.id)
		if a.kind == "zones_explored":
			check(a.goal <= Content.regions.size(), "achievement %s: %d zones, but there are %d" % [a.id, a.goal, Content.regions.size()])

func test_find_returns_each_achievement() -> void:
	for a in Achievements.all():
		check(Achievements.find(String(a.id)) == a, "Achievements.find(%s)" % a.id)
	check(Achievements.find("no_such_achievement") == null, "find of an unknown id is null")

func test_a_new_character_has_reached_nothing() -> void:
	var c := Character.create("Fresh")
	for a in Achievements.all():
		check(Achievements.measure(c, a.kind) < a.goal, "achievement %s: a new character already has it" % a.id)
	check(Achievements.check(c).is_empty(), "a new character reaches no achievement")

func test_effects_fired_by_name_exist() -> void:
	for id in EffectDef.NAMED:
		check(Content.effects.has(id), "EffectDef names %s, but data/effects has no such effect" % id)
