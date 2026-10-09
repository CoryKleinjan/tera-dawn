class_name CharacterStats
extends RefCounted
## MapleStory-style formulas that turn a character's stats into what they do in combat.
## Balance lives here (and in Combat), so tuning never means hunting through actors.

## MapleStory's damage formula times this, so numbers fit Tera Dawn's monsters.
const DAMAGE_SCALE := 2.0
const BASE_CRIT := 0.12

## Lowest and highest hit before skills, crits and monster level: the stats window's
## "Damage" line. max = (primary × 4 + secondary) × weapon attack / 100.
static func damage_range(job: JobDef, total: StatBlock) -> Vector2i:
	var primary := total.value(StringName(job.primary_stat))
	var secondary := total.value(StringName(job.secondary_stat))
	var top := maxi(1, roundi((primary * 4 + secondary) * total.attack / 100.0 * DAMAGE_SCALE))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

static func magic_attack(total: StatBlock) -> int:
	return total.magic_attack + total.intelligence

static func accuracy(total: StatBlock) -> int:
	return total.accuracy + roundi(total.dexterity * 0.8 + total.luck * 0.5)

static func avoid(total: StatBlock) -> int:
	return total.avoid + roundi(total.dexterity * 0.25 + total.luck * 0.5)

static func crit_rate(_total: StatBlock) -> float:
	return BASE_CRIT

## Movement multipliers from Speed and Jump, capped like MapleStory (140% and 123%).
static func speed_multiplier(total: StatBlock) -> float:
	return clampf(1.0 + total.speed / 100.0, 0.5, 1.4)

static func jump_multiplier(total: StatBlock) -> float:
	return clampf(1.0 + total.jump / 100.0, 0.5, 1.23)

static func max_hp(job: JobDef, level: int, total: StatBlock) -> int:
	return job.base_hp + level * job.hp_per_level + total.max_hp

static func max_mp(job: JobDef, level: int, total: StatBlock) -> int:
	return job.base_mp + level * job.mp_per_level + total.max_mp
