class_name CharacterStats
extends RefCounted
## MapleStory-style formulas that turn a character's level, job and stats into what they do in
## combat.
## Balance lives here (and in Combat), so tuning never means hunting through actors.

## MapleStory's damage formula times this, so numbers fit the game's monsters.
const DAMAGE_SCALE := 2.0
const BASE_CRIT := 0.12

## What a point of power (`power`) is worth in the damage formula.
const MAIN_STAT_WEIGHT := 3.6
## Power gained every level, on top of the job's `JobDef.base_power`.
const POWER_PER_LEVEL := 5
## Avoidability everyone has before gear, and the job's `JobDef.avoid_growth` a level on top.
const BASE_AVOID := 3

## Dawn Essence prices for skill levels: SKILL_PRICE × (1 + bought / SKILL_STEP) ^ PRICE_GROWTH,
## counted across every skill level bought. The pace bot should retune them.
const SKILL_PRICE := 17.0
const SKILL_STEP := 3.0
const PRICE_GROWTH := 2.1
## The EXP curve (xp_need): up to JOB_LEVEL a level takes XP_SCALE × level^XP_GROWTH EXP; after
## it, the Lv JOB_LEVEL amount times (level / JOB_LEVEL)^XP_JOB_GROWTH. Tuned with the pace bot
## (playtest/pace-run-3.md in the project files) at scale 55: about 1.5-2 hours to Lv 10, then
## halved so every level needs half the EXP. Quest EXP is set against it; change them together.
const XP_SCALE := 27.5
const XP_GROWTH := 3.0
const JOB_LEVEL := 10
const XP_JOB_GROWTH := 1.8

## What a `job` character's damage grows from at `level`: the job's base power plus
## POWER_PER_LEVEL a level (Character.power adds the Monster Book's).
static func power(job: JobDef, level: int) -> int:
	return job.base_power + POWER_PER_LEVEL * (maxi(1, level) - 1)

## Lowest and highest hit before skills, crits and monster level: the stats window's
## "Damage" line. max = power × MAIN_STAT_WEIGHT × weapon attack / 100.
static func damage_range(job: JobDef, power: int, total: StatBlock) -> Vector2i:
	var top := maxi(1, roundi(power * MAIN_STAT_WEIGHT * total.attack / 100.0 * DAMAGE_SCALE))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

## Lowest and highest spell hit before the spell's own multiplier, from Magic Attack (which
## includes power): (M² / 120) + M. The square keeps spells growing as fast as weapon damage,
## which grows with both power and Weapon Attack.
static func magic_range(job: JobDef, power: int, total: StatBlock) -> Vector2i:
	var m := magic_attack(total, power)
	var top := maxi(1, roundi(m * m / 120.0 + m))
	return Vector2i(maxi(1, roundi(top * job.mastery)), top)

## Magic Attack plus power.
static func magic_attack(total: StatBlock, power: int) -> int:
	return total.magic_attack + power

static func accuracy(total: StatBlock) -> int:
	return total.accuracy

## Avoidability: gear's, BASE_AVOID, and the job's avoid_growth for every level past the first.
static func avoid(job: JobDef, level: int, total: StatBlock) -> int:
	return total.avoid + BASE_AVOID + roundi(job.avoid_growth * (maxi(1, level) - 1))

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

## EXP needed to go from `level` to the next (see XP_SCALE).
static func xp_need(level: int) -> int:
	var lvl := maxi(1, level)
	if lvl <= JOB_LEVEL:
		return int(floor(XP_SCALE * pow(lvl, XP_GROWTH)))
	return int(floor(XP_SCALE * pow(JOB_LEVEL, XP_GROWTH) * pow(float(lvl) / JOB_LEVEL, XP_JOB_GROWTH)))

static func max_hp(job: JobDef, level: int, total: StatBlock) -> int:
	return job.base_hp + maxi(1, level) * job.hp_growth + total.max_hp

static func max_mp(job: JobDef, level: int, total: StatBlock) -> int:
	return job.base_mp + maxi(1, level) * job.mp_growth + total.max_mp

## Dawn Essence for the next skill level, with `bought` skill levels bought already.
static func skill_price(bought: int) -> int:
	return roundi(SKILL_PRICE * pow(1.0 + maxi(0, bought) / SKILL_STEP, PRICE_GROWTH))
