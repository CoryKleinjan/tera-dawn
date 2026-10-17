class_name Balance
extends RefCounted
## Numbers for tuning: a typical character of a job at a tier of progress (their level, stats
## bought in the job's main stat, the best gear made for that tier from the game's items), and
## how many hits of their main attack a monster takes. A player's tier is their level, and a
## monster's tier is its MonsterDef.level. tests/balance_report.tscn prints the whole table; the smoke test keeps
## every job inside BAND against monsters of its tier.

## Hits a tier-matched monster should take with the main attack, low to high.
const BAND := Vector2(1.5, 9.0)

## The first jobs (each a line a Beginner takes at tier 10), from the game's jobs. Second
## jobs join the checks once players are offered them.
static func lines() -> Array[StringName]:
	var out: Array[StringName] = []
	for j in JobDef.paths_from(Character.START_JOB):
		out.append(j.id)
	return out

## A character of `job_id` at `tier`, as a player who spent their essence sensibly would have.
static func typical(job_id: StringName, tier: int) -> Character:
	# everyone starts as a Beginner and takes their job at 10
	var c := Character.create("Balance")
	if tier >= 10:
		c.job = Content.job(job_id)
	var j := c.job
	c.level = clampi(tier, 1, Character.MAX_LEVEL)
	var points := (tier - 1) * CharacterStats.GROWTH_POINTS
	c.base.set(StringName(j.primary_stat), c.base.value(StringName(j.primary_stat)) + points)
	c.recalc()
	# the best of each kind of gear made for their tier (by the stat their attack uses)
	var best := {}
	for item in Content.items.values():
		var e := item as EquipDef
		if e == null or e.stats == null or e.required_level > tier or c.gear.equip_problem(e) != "":
			continue
		var place := c.equipment.place_for(e)
		if place == &"weapon" and e.jobs.is_empty() and c.job.advances_from != &"":
			continue # a job's own weapons are what its skills need
		var score := _score(c, e)
		if not best.has(place) or score > best[place][0]:
			best[place] = [score, e]
	for place in best:
		c.equipment.put(place, ItemStack.exact(best[place][1]))
	c.recalc()
	return c

static func _score(c: Character, e: EquipDef) -> int:
	var s := e.stats
	return (s.magic_attack + s.intelligence if c.job.primary_stat == "intelligence" else s.attack * 3) \
		+ s.value(StringName(c.job.primary_stat)) + s.defense / 4

## How far along `c` is (see the top): their level.
static func tier(c: Character) -> int:
	return c.level

## The attack this character would mostly use: the attack skill they could have (at the
## skill level their tier pays for) with the most damage per second, or the basic attack.
static func main_attack(c: Character) -> Array:
	var best: SkillDef = c.skills.basic_attack()
	var best_level := 1
	for s: SkillDef in Content.skills.values():
		if s.kind != SkillDef.Kind.ATTACK or s.innate or not c.job_line().has(s.job):
			continue
		# about one skill level a tier since the job was taken goes into the main attack
		var lvl := clampi(tier(c) - (9 if s.job != &"beginner" else 0), 1, s.max_level)
		if s.weapons.size() > 0 and (c.gear.weapon() == null or not s.weapons.has(c.gear.weapon().weapon_kind)):
			continue
		if s.offhand.size() > 0 and (c.gear.offhand() == null or not s.offhand.has(c.gear.offhand().offhand_kind)):
			continue
		if per_second(c, s, lvl) > per_second(c, best, best_level):
			best = s
			best_level = lvl
	return [best, best_level]

## Average damage per second using only `s` at `lvl`: a cast's hits over the time until it
## can be cast again (the shared cooldown, or its own recharge when that's longer).
static func per_second(c: Character, s: SkillDef, lvl: int) -> float:
	var ticks := maxi(1, maxi(s.cooldown, s.recharge_ticks(lvl)))
	return _average(c, s, lvl) * s.hits * 60.0 / ticks

static func _average(c: Character, s: SkillDef, lvl: int) -> float:
	var spread := c.magic_range() if s.magic else c.damage_range()
	var crit := CharacterStats.crit_rate(c.stats)
	return (spread.x + spread.y) / 2.0 * s.damage_at(lvl) * (1.0 + crit * (Combat.CRIT_MULTIPLIER - 1.0))

## Average hits of the main attack it takes to beat `m` (each cast's hits count separately).
static func hits_to_kill(c: Character, m: MonsterDef) -> float:
	var attack: Array = main_attack(c)
	var per_hit := maxf(1.0, _average(c, attack[0], attack[1]))
	return m.max_hp / per_hit / float(attack[0].hits)

## Kills of a tier-matched monster it takes to level up once from `tier` (a monster gives as
## much EXP as Dawn Essence).
static func kills_per_tier(tier: int, m: MonsterDef) -> float:
	return CharacterStats.xp_need(tier) / float(maxi(1, m.essence))
