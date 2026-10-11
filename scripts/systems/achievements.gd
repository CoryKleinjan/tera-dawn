class_name Achievements
extends RefCounted
## Milestones a character can reach: one AchievementDef per file in data/achievements/,
## loaded by Content. The server checks them after anything that could earn one and tells
## the player; the client unlocks the matching Steam achievement (its `steam` id must exist
## in the Steamworks app). Each is reached when what `kind` measures (see `measure`) is at
## least `goal`.

## Every achievement, in `order`: as the collection window lists them and the server awards them.
static func all() -> Array[AchievementDef]:
	var out: Array[AchievementDef] = []
	out.assign(Content.achievements.values())
	out.sort_custom(func(a: AchievementDef, b: AchievementDef) -> bool: return a.order < b.order or (a.order == b.order and a.id < b.id))
	return out

## The achievement with this id, or null.
static func find(id: String) -> AchievementDef:
	return Content.achievements.get(StringName(id))

## How far a character is along what `kind` measures. Kinds not listed here are tallies the
## game keeps with Character.count (see Counters).
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
static func check(c: Character) -> Array[AchievementDef]:
	var out: Array[AchievementDef] = []
	for a in all():
		if not c.achievements.has(String(a.id)) and measure(c, a.kind) >= a.goal:
			c.achievements.append(String(a.id))
			out.append(a)
	return out
