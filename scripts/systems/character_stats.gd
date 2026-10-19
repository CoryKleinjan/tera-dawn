class_name CharacterStats
extends RefCounted
## Formulas that turn a character's gear and hearts into what they do in combat. There are no
## levels (Cory Oct 19, Hollow Knight style): damage comes from the weapon and its tier.
## Balance lives here (and in Combat), so tuning never means hunting through actors.

const BASE_CRIT := 0.12
## The top of a hit is the weapon's attack (Weapon or Magic Attack, whichever is bigger, with
## its tier and runes) times this; the bottom is MASTERY of the top.
const DAMAGE_PER_ATTACK := 2.0
const MASTERY := 0.7

## Lowest and highest hit before the attack's own multiplier and crits: the stats window's
## "Damage" line.
static func damage_range(total: StatBlock) -> Vector2i:
	var top := maxi(1, roundi(main_attack(total) * DAMAGE_PER_ATTACK))
	return Vector2i(maxi(1, roundi(top * MASTERY)), top)

## What the weapon hits with: its Weapon Attack, or Magic Attack for a wand.
static func main_attack(total: StatBlock) -> int:
	return maxi(total.attack, total.magic_attack)

static func accuracy(total: StatBlock) -> int:
	return total.accuracy

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

## Health is hearts (Cory Oct 19): everyone starts with BASE_HEARTS, and every
## HEART_SHARDS_PER_HEART Heart Shards found add one more. A monster's hit takes a heart or
## two (Combat.monster_hit).
const BASE_HEARTS := 5
const HEART_SHARDS_PER_HEART := 4
## Mana fills as you hit monsters (MANA_PER_HIT for each one an attack lands on) and never
## comes back by itself. HEAL_COST of it heals a heart; it also pays for spells. Every
## MANA_SHARDS_PER_ORB Mana Shards found make the orb hold MANA_PER_ORB more.
const BASE_MANA := 99
const MANA_PER_HIT := 11
const HEAL_COST := 33
const MANA_SHARDS_PER_ORB := 3
const MANA_PER_ORB := 33

static func max_hp(heart_shards: int) -> int:
	return BASE_HEARTS + maxi(0, heart_shards) / HEART_SHARDS_PER_HEART

static func max_mp(mana_shards: int) -> int:
	return BASE_MANA + maxi(0, mana_shards) / MANA_SHARDS_PER_ORB * MANA_PER_ORB
