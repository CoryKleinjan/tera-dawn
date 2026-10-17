class_name QuestLog
extends RefCounted
## A character's quests: which are in progress (with kill and visit counts) and which are
## done. Collect objectives count what's in the bag, so they're never stored.
## The rules for taking and handing in quests live here; TDServer calls them.

enum Status { LOCKED, AVAILABLE, ACTIVE, READY, DONE }

## quest id -> Array of counts, one per objective (KILL and VISIT use theirs)
var active := {}
## quest id -> times handed in
var done := {}

func status(q: QuestDef, c: Character) -> Status:
	if active.has(q.id):
		return Status.READY if is_ready(q, c) else Status.ACTIVE
	if done.has(q.id) and not q.repeatable:
		return Status.DONE
	return Status.AVAILABLE if can_take(q, c) else Status.LOCKED

func can_take(q: QuestDef, c: Character) -> bool:
	if not q.jobs.is_empty() and not c.job.id in q.jobs:
		return false
	for r in q.requires:
		if not done.has(r):
			return false
	if not q.requires_any.is_empty() and not q.requires_any.any(func(r: StringName) -> bool: return done.has(r)):
		return false
	for m in q.requires_beaten:
		if m and c.book.kills(m) <= 0:
			return false
	return true

## How far along objective `i` is.
func progress(q: QuestDef, i: int, c: Character) -> int:
	var o := q.objectives[i]
	if o.kind == QuestObjective.Kind.COLLECT:
		return mini(o.count, c.inventory.count_of(o.item))
	var counts: Array = active.get(q.id, [])
	return mini(o.count, counts[i]) if i < counts.size() else 0

func is_ready(q: QuestDef, c: Character) -> bool:
	if not active.has(q.id):
		return false
	for i in q.objectives.size():
		if progress(q, i, c) < q.objectives[i].count:
			return false
	return true

func accept(q: QuestDef) -> void:
	var counts := []
	counts.resize(q.objectives.size())
	counts.fill(0)
	active[q.id] = counts

func forfeit(q: QuestDef) -> void:
	active.erase(q.id)

## The quests worth showing on the tracker while on map `m`, at most `limit`: ready to hand
## in first, then those with something left to do here, then the rest, each group in the
## order they were taken.
func tracked(c: Character, m: MapDef, limit: int) -> Array[QuestDef]:
	var ready: Array[QuestDef] = []
	var here: Array[QuestDef] = []
	var rest: Array[QuestDef] = []
	for id in active:
		var q: QuestDef = Content.quests.get(id)
		if q == null:
			continue
		if is_ready(q, c):
			ready.append(q)
		elif m and _to_do_on(q, c, m):
			here.append(q)
		else:
			rest.append(q)
	ready.append_array(here)
	ready.append_array(rest)
	return ready.slice(0, limit)

## Whether quest `q` has an unfinished objective that can be worked on at `m`.
func _to_do_on(q: QuestDef, c: Character, m: MapDef) -> bool:
	for i in q.objectives.size():
		if progress(q, i, c) < q.objectives[i].count and q.objectives[i].can_do_on(m):
			return true
	return false

## Counts a defeated monster toward every quest that wants it. Returns the quests it moved on.
func record_kill(monster: MonsterDef) -> Array[QuestDef]:
	return _bump(func(o: QuestObjective) -> bool: return o.kind == QuestObjective.Kind.KILL and o.monster == monster)

## Counts standing on platform `platform` of map `map_id`. Returns the quests it moved on.
func record_reach(map_id: StringName, platform: int) -> Array[QuestDef]:
	return _bump(func(o: QuestObjective) -> bool: return o.kind == QuestObjective.Kind.REACH and o.map == map_id and o.platform == platform)

## Whether a quest in progress still wants `c` to reach a spot on map `map_id`.
func wants_reach(map_id: StringName) -> bool:
	for id in active:
		var q: QuestDef = Content.quests.get(id)
		if q == null:
			continue
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o.kind == QuestObjective.Kind.REACH and o.map == map_id and active[id][i] < o.count:
				return true
	return false

## Counts arriving on a map. Returns the quests it moved on.
func record_visit(map_id: StringName) -> Array[QuestDef]:
	return _bump(func(o: QuestObjective) -> bool: return o.kind == QuestObjective.Kind.VISIT and o.map == map_id)

func _bump(matches: Callable) -> Array[QuestDef]:
	var moved: Array[QuestDef] = []
	for id in active:
		var q: QuestDef = Content.quests.get(id)
		if q == null:
			continue
		var counts: Array = active[id]
		for i in q.objectives.size():
			if matches.call(q.objectives[i]) and counts[i] < q.objectives[i].count:
				counts[i] += 1
				if not q in moved:
					moved.append(q)
	return moved

## Quest items `monster` should drop for this character right now: [[item, chance], ...].
func quest_drops(monster: MonsterDef, c: Character) -> Array:
	var out := []
	for id in active:
		var q: QuestDef = Content.quests.get(id)
		if q == null:
			continue
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o.kind == QuestObjective.Kind.COLLECT and o.drop_from == monster and progress(q, i, c) < o.count:
				out.append([o.item, o.drop_chance])
	return out

## Hands the quest in: takes the collected items, pays the Dawnshard and item rewards and
## marks it done (Dawn Essence goes through TDServer.give_essence so the gain is shown).
## Returns why it couldn't, or "".
func complete(q: QuestDef, c: Character) -> String:
	if not is_ready(q, c):
		return "You haven't finished %s yet." % q.title
	var full := c.inventory.tab_without_room(q.reward_items.map(func(r: DropEntry) -> Array: return [r.item, r.min_amount]))
	if full >= 0:
		return "Make room in your %s inventory first." % ItemDef.TAB_NAMES[full]
	for o in q.objectives:
		if o.kind == QuestObjective.Kind.COLLECT and not o.keep:
			c.inventory.remove(o.item, o.count)
	active.erase(q.id)
	done[q.id] = int(done.get(q.id, 0)) + 1
	c.shards += q.reward_shards
	for r in q.reward_items:
		if r.item:
			c.inventory.add_stack(ItemStack.unrolled(r.item, r.min_amount))
	return ""


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "done": done.duplicate()}

func load_dict(data: Dictionary) -> void:
	active.clear()
	done.clear()
	var a: Variant = data.get("active", {})
	if a is Dictionary:
		for id in a:
			var q: QuestDef = Content.quests.get(StringName(id))
			if q and a[id] is Array:
				var counts: Array = a[id].map(func(n: Variant) -> int: return int(n))
				counts.resize(q.objectives.size())
				active[q.id] = counts.map(func(n: Variant) -> int: return 0 if n == null else n)
	var d: Variant = data.get("done", {})
	if d is Dictionary:
		for id in d:
			done[StringName(id)] = int(d[id])
