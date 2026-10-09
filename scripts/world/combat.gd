class_name Combat
extends RefCounted
## Damage rules in one place, so balance changes don't mean hunting through actors.
## The character's side of the numbers (damage range, accuracy, avoid) comes from
## CharacterStats.

const CRIT_MULTIPLIER := 1.6

## One damage line from the player's skill against a monster. Returns {damage, crit, miss}.
static func player_hit(skill: SkillDef, target: MonsterDef) -> Dictionary:
	# monsters above the player's level can dodge; accuracy wins that back
	var miss_chance := clampf((target.level - Game.level) * 0.06 - CharacterStats.accuracy(Game.stats) * 0.004, 0.0, 0.6)
	if randf() < miss_chance:
		return {"damage": 0, "crit": false, "miss": true}
	var crit := randf() < CharacterStats.crit_rate(Game.stats)
	var spread := Game.damage_range()
	var dmg := roundi(randi_range(spread.x, spread.y) * skill.damage_multiplier
		* (CRIT_MULTIPLIER if crit else 1.0))
	# higher-level monsters shrug off some damage
	dmg = maxi(1, dmg - maxi(0, target.level - Game.level) * 2)
	return {"damage": dmg, "crit": crit, "miss": false}

## Damage the player takes from a monster's touch, or 0 if the player dodges it.
static func monster_hit(monster: MonsterDef) -> int:
	var dodge := clampf(CharacterStats.avoid(Game.stats) * 0.004 - (monster.level - Game.level) * 0.02, 0.0, 0.3)
	if randf() < dodge:
		return 0
	return maxi(1, roundi(monster.attack * randf_range(0.85, 1.15) - Game.level * 0.6 - Game.stats.defense * 0.3))

## EXP lost when the player faints.
static func faint_penalty(xp: int) -> int:
	return int(xp * 0.1)
