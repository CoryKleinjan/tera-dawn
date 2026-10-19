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

## Damage a character takes from a monster's touch (or a move `power` times as strong),
## or 0 if they dodge it.
static func monster_hit(monster: MonsterDef, ch: Character, power := 1.0) -> int:
	var dodge := clampf(ch.avoid() * 0.004, 0.0, 0.3)
	if randf() < dodge:
		return 0
	return maxi(1, roundi(monster.attack * power * randf_range(0.85, 1.15) - ch.stats.defense * 0.3))

## EXP (of what's toward the next level) lost when the player faints.
static func faint_penalty(xp: int) -> int:
	return int(xp * 0.1)
