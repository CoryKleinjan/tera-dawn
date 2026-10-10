class_name Achievements
extends RefCounted
## Milestones a character can reach. The server checks them after anything that could earn
## one and tells the player; the client unlocks the matching Steam achievement (its
## `steam` id must exist in the Steamworks app). Each is reached when what `kind` measures
## (see `measure`) is at least `goal`.

const LIST := [
	{"id": "first_hunt", "steam": "ACH_FIRST_HUNT", "title": "First Hunt", "text": "Defeat a monster.", "kind": "kills", "goal": 1},
	{"id": "hunter", "steam": "ACH_HUNTER", "title": "Hunter", "text": "Defeat 500 monsters.", "kind": "kills", "goal": 500},
	{"id": "slayer", "steam": "ACH_SLAYER", "title": "Slayer", "text": "Defeat 5,000 monsters.", "kind": "kills", "goal": 5000},
	{"id": "boss_breaker", "steam": "ACH_BOSS_BREAKER", "title": "Boss Breaker", "text": "Defeat a boss.", "kind": "bosses", "goal": 1},
	{"id": "boss_hunter", "steam": "ACH_BOSS_HUNTER", "title": "Boss Hunter", "text": "Defeat 25 bosses.", "kind": "bosses", "goal": 25},
	{"id": "level_5", "steam": "REACH_LEVEL_5", "title": "Growing Up", "text": "Reach level 5.", "kind": "level", "goal": 5},
	{"id": "level_10", "steam": "ACH_LEVEL_10", "title": "Finding Your Feet", "text": "Reach level 10.", "kind": "level", "goal": 10},
	{"id": "level_30", "steam": "ACH_LEVEL_30", "title": "Seasoned", "text": "Reach level 30.", "kind": "level", "goal": 30},
	# id and Steam name kept from when the cap was 50 (saved characters and Steamworks use them)
	{"id": "level_50", "steam": "ACH_LEVEL_50", "title": "Hero of Tera", "text": "Reach level 35, the highest level.", "kind": "level", "goal": 35},
	{"id": "first_job", "steam": "ACH_FIRST_JOB", "title": "A Calling", "text": "Take up a job.", "kind": "job", "goal": 1},
	{"id": "helper", "steam": "ACH_HELPER", "title": "Helping Hand", "text": "Finish 10 quests.", "kind": "quests", "goal": 10},
	{"id": "hero_for_hire", "steam": "ACH_HERO_FOR_HIRE", "title": "Hero for Hire", "text": "Finish 30 quests.", "kind": "quests", "goal": 30},
	{"id": "wanderer", "steam": "ACH_WANDERER", "title": "Wanderer", "text": "Visit 20 maps.", "kind": "maps", "goal": 20},
	{"id": "cartographer", "steam": "ACH_CARTOGRAPHER", "title": "Cartographer", "text": "Visit 40 maps.", "kind": "maps", "goal": 40},
	{"id": "collector", "steam": "ACH_COLLECTOR", "title": "Collector", "text": "Find 10 Monster Book cards.", "kind": "cards", "goal": 10},
	{"id": "first_page", "steam": "ACH_FIRST_PAGE", "title": "First Page", "text": "Complete a Monster Book page.", "kind": "pages", "goal": 1},
	{"id": "scholar", "steam": "ACH_SCHOLAR", "title": "Monster Scholar", "text": "Complete 15 Monster Book pages.", "kind": "pages", "goal": 15},
	{"id": "lucky_scroll", "steam": "ACH_LUCKY_SCROLL", "title": "Lucky Scroll", "text": "Have an upgrade scroll work.", "kind": "scrolls", "goal": 1},
	{"id": "nest_egg", "steam": "ACH_NEST_EGG", "title": "Nest Egg", "text": "Hold 100,000 Dawnshards.", "kind": "shards", "goal": 100000},
	{"id": "take_a_seat", "steam": "ACH_TAKE_A_SEAT", "title": "Take a Seat", "text": "Sit on a chair.", "kind": "sat", "goal": 1},
	{"id": "best_friend", "steam": "ACH_BEST_FRIEND", "title": "Best Friend", "text": "Bring out a pet.", "kind": "pets", "goal": 1},
	{"id": "well_liked", "steam": "ACH_WELL_LIKED", "title": "Well Liked", "text": "Reach 10 fame.", "kind": "fame", "goal": 10},
	{"id": "guildmate", "steam": "ACH_GUILDMATE", "title": "Guildmate", "text": "Join a guild.", "kind": "guild", "goal": 1},
	{"id": "dealmaker", "steam": "ACH_DEALMAKER", "title": "Dealmaker", "text": "Finish a trade or a shop sale.", "kind": "deals", "goal": 1},
]

static func find(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}

## How far a character is along what `kind` measures.
static func measure(c: Character, kind: String) -> int:
	match kind:
		"kills": return c.book.total_kills()
		"cards": return c.book.total_cards()
		"pages": return c.book.completed()
		"level": return c.level
		"job": return 0 if c.job.advances_from == &"" else 1
		"quests": return c.quests.done.size()
		"maps": return c.visited.size()
		"shards": return c.shards
		"fame": return c.fame
		"guild": return 0 if c.guild == "" else 1
	return int(c.counters.get(kind, 0))

## The achievements `c` has just reached, which are added to its list.
static func check(c: Character) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in LIST:
		if not c.achievements.has(a["id"]) and measure(c, a["kind"]) >= a["goal"]:
			c.achievements.append(a["id"])
			out.append(a)
	return out
