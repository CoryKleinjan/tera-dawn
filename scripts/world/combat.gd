class_name Combat
extends RefCounted
## Damage rules in one place, so balance changes don't mean hunting through actors.
## The character's side of the numbers (damage range, accuracy, avoid) comes from
## CharacterStats.

const CRIT_MULTIPLIER := 1.6

## One damage line from a character's skill against a monster, with `extra_crit` added to
## their Critical Rate (a streak, as a share: 0.05 is 5%). Returns {damage, crit, miss}.
static func player_hit(skill: SkillDef, target: MonsterDef, ch: Character, extra_crit := 0.0) -> Dictionary:
	var multiplier := skill.damage_at(ch.skills.level(skill))
	# monsters above the player's level can dodge; accuracy wins that back
	var miss_chance := clampf((target.level - ch.level) * 0.06 - CharacterStats.accuracy(ch.stats) * 0.004, 0.0, 0.6)
	if randf() < miss_chance:
		return {"damage": 0, "crit": false, "miss": true}
	var crit := randf() < CharacterStats.crit_rate(ch.stats) + extra_crit
	var spread := ch.magic_range() if skill.magic else ch.damage_range()
	var dmg := roundi(randi_range(spread.x, spread.y) * multiplier
		* CharacterStats.damage_bonus(ch.stats, skill.is_ranged())
		* (CRIT_MULTIPLIER if crit else 1.0))
	# higher-level monsters shrug off some damage
	dmg = maxi(1, dmg - maxi(0, target.level - ch.level) * 2)
	return {"damage": dmg, "crit": crit, "miss": false}

## Damage a character takes from a monster's touch (or a move `power` times as strong),
## or 0 if they dodge it.
static func monster_hit(monster: MonsterDef, ch: Character, power := 1.0) -> int:
	var dodge := clampf(CharacterStats.avoid(ch.stats) * 0.004 - (monster.level - ch.level) * 0.02, 0.0, 0.3)
	if randf() < dodge:
		return 0
	return maxi(1, roundi(monster.attack * power * randf_range(0.85, 1.15) - ch.level * 0.6 - ch.stats.defense * 0.3))

## EXP lost when the player faints.
static func faint_penalty(xp: int) -> int:
	return int(xp * 0.1)
