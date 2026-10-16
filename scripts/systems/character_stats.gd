class_name CharacterStats
extends RefCounted
## MapleStory-style formulas that turn a character's stats into what they do in combat.
## Balance lives here (and in Combat), so tuning never means hunting through actors.

## MapleStory's damage formula times this, so numbers fit the game's monsters.
const DAMAGE_SCALE := 2.0
const BASE_CRIT := 0.12

## What the job's damage stat (JobDef.damage_stat_value: one stat, or a blend's two added
## together) is worth in the damage formula.
const MAIN_STAT_WEIGHT := 3.6
## What the other stats give as they grow: Max HP per STR, Max MP per INT, Accuracy per
## DEX, Avoidability per LUK, and for CHA a shop discount and more Dawnshards per point.
const HP_PER_STR := 1.0
const MP_PER_INT := 1.0
const ACCURACY_PER_DEX := 0.8
const AVOID_PER_LUK := 0.75
const DISCOUNT_PER_CHA := 0.001
const MAX_DISCOUNT := 0.15
const SHARDS_PER_CHA := 0.002

## Dawn Essence prices. Each point in a stat costs more than the last point bought in that
## stat: STAT_PRICE × (1 + bought / STAT_STEP) ^ PRICE_GROWTH. Skill levels work the same way,
## counted across every skill level bought (SKILL_STEP). Set so the first hours take about as
## long as the old EXP curve did; the pace bot should retune them.
const STAT_PRICE := 17.0
const STAT_STEP := 5.0
const SKILL_PRICE := 17.0
const SKILL_STEP := 3.0
const PRICE_GROWTH := 2.1
## Max HP and MP grow by the job's hp_growth / mp_growth for every this many stat points
## bought (and once more from the start).
const GROWTH_POINTS := 5

## Lowest and highest hit before skills, crits and monster level: the stats window's
## "Damage" line. max = main stat × MAIN_STAT_WEIGHT × weapon attack / 100, with the stat
## (or a blend's two stats added together) `JobDef.damage_stat_value` gives.
static func damage_range(job: JobDef, total: StatBlock) -> Vector2i:
	var main := job.damage_stat_value(total)
	var top := maxi(1, roundi(main * MAIN_STAT_WEIGHT * total.attack / 100.0 * DAMAGE_SCALE))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

## Lowest and highest spell hit before the spell's own multiplier, from Magic Attack (which
## includes INT, or for a blend with INT both its stats): (M² / 120) + M. The square keeps
## spells growing as fast as weapon damage, which grows with both the main stat and Weapon
## Attack.
static func magic_range(job: JobDef, total: StatBlock) -> Vector2i:
	var m := magic_attack(total, job)
	var top := maxi(1, roundi(m * m / 120.0 + m))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

## Magic Attack plus INT. A blend whose stats include INT (a Spellblade's STR and INT) adds
## both its stats instead, so its spells grow with either.
static func magic_attack(total: StatBlock, job: JobDef = null) -> int:
	if job and job.secondary_stat != &"" and &"intelligence" in job.damage_stats():
		return total.magic_attack + job.damage_stat_value(total)
	return total.magic_attack + total.intelligence

static func accuracy(total: StatBlock) -> int:
	return total.accuracy + roundi(total.dexterity * ACCURACY_PER_DEX)

static func avoid(total: StatBlock) -> int:
	return total.avoid + roundi(total.luck * AVOID_PER_LUK)

## The share taken off shop prices for this much CHA (at most MAX_DISCOUNT).
static func shop_discount(total: StatBlock) -> float:
	return minf(MAX_DISCOUNT, maxi(0, total.charisma) * DISCOUNT_PER_CHA)

## Dawnshards picked up are multiplied by this for this much CHA.
static func shard_bonus(total: StatBlock) -> float:
	return 1.0 + maxi(0, total.charisma) * SHARDS_PER_CHA

static func crit_rate(total: StatBlock) -> float:
	return BASE_CRIT + total.crit / 100.0

## How many ticks an attack's cooldown or pose of `ticks` lasts with Attack Speed: 25% faster
## means it comes round in 1 / 1.25 of the time. Server and client both work it out here.
static func attack_ticks(ticks: int, total: StatBlock) -> int:
	return maxi(1, roundi(ticks / (1.0 + maxi(0, total.attack_speed) / 100.0)))

## Extra damage on a hit from Melee or Ranged Damage, as a multiplier.
static func damage_bonus(total: StatBlock, ranged: bool) -> float:
	return 1.0 + (total.ranged_damage if ranged else total.melee_damage) / 100.0

## Movement multipliers from Speed and Jump, capped like MapleStory (140% and 123%).
static func speed_multiplier(total: StatBlock) -> float:
	return clampf(1.0 + total.speed / 100.0, 0.5, 1.4)

static func jump_multiplier(total: StatBlock) -> float:
	return clampf(1.0 + total.jump / 100.0, 0.5, 1.23)

## How far a character has grown: 1, plus one for every GROWTH_POINTS stat points bought.
static func growth(bought: int) -> float:
	return 1.0 + float(maxi(0, bought)) / GROWTH_POINTS

static func max_hp(job: JobDef, bought: int, total: StatBlock) -> int:
	return job.base_hp + roundi(growth(bought) * job.hp_growth) + total.max_hp + roundi(total.strength * HP_PER_STR)

static func max_mp(job: JobDef, bought: int, total: StatBlock) -> int:
	return job.base_mp + roundi(growth(bought) * job.mp_growth) + total.max_mp + roundi(total.intelligence * MP_PER_INT)

## Dawn Essence for the next point of a stat that has had `bought` points bought already.
static func stat_price(bought: int) -> int:
	return roundi(STAT_PRICE * pow(1.0 + maxi(0, bought) / STAT_STEP, PRICE_GROWTH))

## Dawn Essence for the next skill level, with `bought` skill levels bought already.
static func skill_price(bought: int) -> int:
	return roundi(SKILL_PRICE * pow(1.0 + maxi(0, bought) / SKILL_STEP, PRICE_GROWTH))
