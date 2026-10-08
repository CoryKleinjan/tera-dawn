class_name Combat
extends RefCounted
## Damage rules in one place, so balance changes don't mean hunting through actors.

const CRIT_CHANCE := 0.12
const CRIT_MULTIPLIER := 1.6

## One damage line from the player's skill against a monster. Returns {damage, crit}.
static func player_hit(skill: SkillDef, target: MonsterDef) -> Dictionary:
	var crit := randf() < CRIT_CHANCE
	var dmg := roundi(Game.attack_power() * skill.damage_multiplier * randf_range(0.85, 1.15)
		* (CRIT_MULTIPLIER if crit else 1.0))
	# higher-level monsters shrug off some damage
	dmg = maxi(1, dmg - maxi(0, target.level - Game.level) * 2)
	return {"damage": dmg, "crit": crit}

## Damage the player takes from a monster's touch.
static func monster_hit(attack: int) -> int:
	return maxi(1, roundi(attack * randf_range(0.85, 1.15) - Game.level * 0.6))

## EXP lost when the player faints.
static func faint_penalty(xp: int) -> int:
	return int(xp * 0.1)
