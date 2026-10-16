class_name MonsterStrength
extends RefCounted
## How strong a monster is on a map. Each kind's own numbers (MonsterDef max_hp, attack,
## essence) are what it is on the map nearest a town that it lives on; on every map farther
## from the nearest town than that it is PER_MAP stronger (HP, attack and Dawn Essence
## alike). Bosses keep their own numbers wherever they are.

const PER_MAP := 0.15

## The multiplier for `m` on map `map_id`. `steps` is WorldRoutes.steps_from_town(), passed
## in when working out many monsters at once.
static func on_map(m: MonsterDef, map_id: StringName, steps: Dictionary = {}) -> float:
	if m == null or m.boss:
		return 1.0
	if steps.is_empty():
		steps = WorldRoutes.steps_from_town()
	if not steps.has(map_id):
		return 1.0
	var farther: int = steps[map_id] - home_steps(m, steps)
	return pow(1.0 + PER_MAP, maxi(0, farther))

## How far from a town the nearest map `m` lives on is (where its own numbers apply): the
## fewest steps among the maps that spawn it, or spawn the monster that splits into it.
static func home_steps(m: MonsterDef, steps: Dictionary) -> int:
	var best := -1
	for map: MapDef in Content.maps.values():
		if not steps.has(map.id):
			continue
		for s in map.spawns:
			if s.monster and (s.monster == m or s.monster.splits_into == m):
				var d: int = steps[map.id]
				if best < 0 or d < best:
					best = d
	return maxi(0, best)

## `amount` (HP, attack or essence) made `strength` times as strong, at least 1.
static func scaled(amount: int, strength: float) -> int:
	return maxi(1, roundi(amount * strength))
