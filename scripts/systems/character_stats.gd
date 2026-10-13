class_name CharacterStats
extends RefCounted
## MapleStory-style formulas that turn a character's stats into what they do in combat.
## Balance lives here (and in Combat), so tuning never means hunting through actors.

## MapleStory's damage formula times this, so numbers fit the game's monsters.
const DAMAGE_SCALE := 2.0
const BASE_CRIT := 0.12

## What the job's one stat (JobDef.damage_stat) is worth in the damage formula.
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

## Lowest and highest hit before skills, crits and monster level: the stats window's
## "Damage" line. max = main stat × MAIN_STAT_WEIGHT × weapon attack / 100, with the stat
## `JobDef.damage_stat` picks.
static func damage_range(job: JobDef, total: StatBlock) -> Vector2i:
	var main := total.value(job.damage_stat(total))
	var top := maxi(1, roundi(main * MAIN_STAT_WEIGHT * total.attack / 100.0 * DAMAGE_SCALE))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

## Lowest and highest spell hit before the spell's own multiplier, from Magic Attack (which
## includes INT): (M² / 120) + M. The square keeps spells growing as fast as weapon
## damage, which grows with both the main stat and Weapon Attack.
static func magic_range(job: JobDef, total: StatBlock) -> Vector2i:
	var m := magic_attack(total)
	var top := maxi(1, roundi(m * m / 120.0 + m))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

static func magic_attack(total: StatBlock) -> int:
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

static func max_hp(job: JobDef, level: int, total: StatBlock) -> int:
	return job.base_hp + level * job.hp_per_level + total.max_hp + roundi(total.strength * HP_PER_STR)

static func max_mp(job: JobDef, level: int, total: StatBlock) -> int:
	return job.base_mp + level * job.mp_per_level + total.max_mp + roundi(total.intelligence * MP_PER_INT)
