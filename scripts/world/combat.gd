class_name Combat
extends RefCounted
## Damage rules in one place, so balance changes don't mean hunting through actors.
## The character's side of the numbers (damage range, crit) comes from
## CharacterStats.

const CRIT_MULTIPLIER := 1.6

## One damage line from a character's skill against a monster. Returns {damage, crit}.
static func player_hit(skill: SkillDef, _target: MonsterDef, ch: Character) -> Dictionary:
	var multiplier := skill.damage_at(ch.skills.level(skill))
	var crit := randf() < CharacterStats.crit_rate(ch.stats)
	var spread := ch.damage_range()
	var dmg := maxi(1, roundi(randi_range(spread.x, spread.y) * multiplier
		* CharacterStats.damage_bonus(ch.stats, skill.is_ranged())
		* (CRIT_MULTIPLIER if crit else 1.0)))
	return {"damage": dmg, "crit": crit}

## A monster move at least this strong (MonsterMove.power) from a boss is a big hit.
const BIG_HIT_POWER := 1.2

## Hearts a character loses to a monster's touch or one of its moves (`power`, see
## MonsterMove): one, or two from a boss's big hit. No dodging and no armor (yet): every hit
## lands, so fights are about not being touched.
static func monster_hit(monster: MonsterDef, _ch: Character, power := 1.0) -> int:
	return 2 if monster.boss and power >= BIG_HIT_POWER else 1
