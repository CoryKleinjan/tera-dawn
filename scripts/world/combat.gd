class_name Combat
extends RefCounted
## Damage rules in one place, so balance changes don't mean hunting through actors.
## The character's side of the numbers (damage range, accuracy, avoid) comes from
## CharacterStats.

const CRIT_MULTIPLIER := 1.6

## One damage line from a character's skill against a monster. Returns {damage, crit, miss}.
static func player_hit(skill: SkillDef, _target: MonsterDef, ch: Character) -> Dictionary:
	var multiplier := skill.damage_at(ch.skills.level(skill))
	var crit := randf() < CharacterStats.crit_rate(ch.stats)
	var spread := ch.magic_range() if skill.magic else ch.damage_range()
	var dmg := maxi(1, roundi(randi_range(spread.x, spread.y) * multiplier
		* CharacterStats.damage_bonus(ch.stats, skill.is_ranged())
		* (CRIT_MULTIPLIER if crit else 1.0)))
	return {"damage": dmg, "crit": crit, "miss": false}

## A hit as strong as this (a monster's attack times its move's power and its strength on
## the map) costs two hearts instead of one: the hardest hitters and the bosses' big moves.
const TWO_HEART_HIT := 100.0
## Chance to block a hit for each point of Weapon and Magic Defense, and the most it reaches.
const BLOCK_PER_DEFENSE := 0.02
const MAX_BLOCK := 0.3

## Hearts a character loses to a monster's touch (or a hit `power` times as strong: its move's
## power times its strength on the map), or 0 if they dodge or block it.
static func monster_hit(monster: MonsterDef, ch: Character, power := 1.0) -> int:
	var dodge := clampf(ch.avoid() * 0.004, 0.0, 0.3)
	if randf() < dodge or randf() < block_chance(ch.stats):
		return 0
	return hearts_for(monster.attack * power)

## Hearts a hit of `strength` (attack x power) costs.
static func hearts_for(strength: float) -> int:
	return 2 if strength >= TWO_HEART_HIT else 1

## The chance that Weapon and Magic Defense block a hit entirely.
static func block_chance(total: StatBlock) -> float:
	return minf(MAX_BLOCK, (total.defense + total.magic_defense) * BLOCK_PER_DEFENSE)

## Share of max MP a guard (Magic Guard) spends to soak one heart of a hit.
const GUARD_MP_SHARE := 0.1

## MP a guard spends to soak a heart for `ch`.
static func guard_mp(ch: Character) -> int:
	return maxi(1, roundi(ch.max_mp() * GUARD_MP_SHARE))

## EXP (of what's toward the next level) lost when the player faints.
static func faint_penalty(xp: int) -> int:
	return int(xp * 0.1)
