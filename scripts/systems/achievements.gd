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
		"stats": return c.ap.spent()
		"job": return 0 if c.job.advances_from == &"" else 1
		"quests": return c.quests.done.size()
		"maps": return c.visited.size()
		"shards": return c.shards
		"fame": return c.fame
		"guild": return 0 if c.guild == "" else 1
		"boss_kinds": return boss_kinds(c)
		"zones_explored": return zones_explored(c)
	return int(c.counters.get(kind, 0))

## The achievements `c` has just reached, which are added to its list.
static func check(c: Character) -> Array[AchievementDef]:
	var out: Array[AchievementDef] = []
	for a in all():
		if not c.achievements.has(String(a.id)) and measure(c, a.kind) >= a.goal:
			c.achievements.append(String(a.id))
			out.append(a)
	return out

## How many different bosses `c` has defeated.
static func boss_kinds(c: Character) -> int:
	var n := 0
	for m: MonsterDef in Content.monsters.values():
		if m.boss and c.book.kills(m) > 0:
			n += 1
	return n

## The bosses that stand on a map (the ones "every boss" means).
static func bosses_on_maps() -> int:
	var seen := {}
	for m: MapDef in Content.maps.values():
		for s in m.spawns:
			if s and s.monster and s.monster.boss and not s.from_tear:
				seen[s.monster.id] = true
	return seen.size()

## How many regions `c` has visited every map of (every one on the world map).
static func zones_explored(c: Character) -> int:
	var n := 0
	for r: RegionDef in Content.regions.values():
		var all_seen := true
		for m: MapDef in Content.maps.values():
			if m.region == r.id and not m.interior and m.world_pos != Vector2.ZERO and not c.visited.has(String(m.id)):
				all_seen = false
				break
		if all_seen:
			n += 1
	return n
