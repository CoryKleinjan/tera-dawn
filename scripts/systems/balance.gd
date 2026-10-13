class_name Balance
extends RefCounted
## Numbers for tuning: a typical character of a job and level (stats spent on the job's
## main stat, the best gear they could wear from the game's items), and how many hits of
## their main attack a monster takes. tests/balance_report.tscn prints the whole table;
## the smoke test keeps every job inside BAND against monsters of its level.

## Hits a level-matched monster should take with the main attack, low to high.
const BAND := Vector2(1.5, 9.0)
## The job you are at `level` along each line (Beginners advance at 10).
const LINES := [&"warrior", &"archer", &"mage", &"thief", &"pirate"]

## A character of `job_id` at `level`, as a player who spent their points sensibly would have.
static func typical(job_id: StringName, level: int) -> Character:
	# everyone starts as a Beginner and takes their job at 10
	var c := Character.create("Balance")
	if level >= 10:
		c.job = Content.job(job_id)
	c.level = level
	var j := c.job
	var points := (level - 1) * j.ap_per_level
	c.base.set(StringName(j.primary_stat), c.base.value(StringName(j.primary_stat)) + points)
	c.recalc()
	# the best of each kind of gear they could wear (by the stat their attack uses)
	var best := {}
	for item in Content.items.values():
		var e := item as EquipDef
		if e == null or e.stats == null or c.gear.equip_problem(e) != "":
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

## The attack this character would mostly use: the strongest attack skill they could have
## (at the level their SP allows), or the basic attack.
static func main_attack(c: Character) -> Array:
	var best: SkillDef = c.skills.basic_attack()
	var best_level := 1
	for s: SkillDef in Content.skills.values():
		if s.kind != SkillDef.Kind.ATTACK or s.innate or not c.job_line().has(s.job):
			continue
		# about one point a level since the job was taken goes into the main attack
		var lvl := clampi(c.level - (9 if s.job != &"beginner" else 0), 1, s.max_level)
		if s.weapons.size() > 0 and (c.gear.weapon() == null or not s.weapons.has(c.gear.weapon().weapon_kind)):
			continue
		if _average(c, s, lvl) * s.hits > _average(c, best, best_level) * best.hits:
			best = s
			best_level = lvl
	return [best, best_level]

static func _average(c: Character, s: SkillDef, lvl: int) -> float:
	var spread := c.magic_range() if s.magic else c.damage_range()
	var crit := CharacterStats.crit_rate(c.stats)
	return (spread.x + spread.y) / 2.0 * s.damage_at(lvl) * (1.0 + crit * (Combat.CRIT_MULTIPLIER - 1.0))

## Average hits of the main attack it takes to beat `m` (each cast's hits count separately).
static func hits_to_kill(c: Character, m: MonsterDef) -> float:
	var attack: Array = main_attack(c)
	var per_hit := maxf(1.0, _average(c, attack[0], attack[1]) - maxi(0, m.level - c.level) * 2)
	return m.max_hp / per_hit / float(attack[0].hits)

## Kills of a level-matched monster needed for one level.
static func kills_per_level(level: int, m: MonsterDef) -> float:
	var c := Character.new()
	c.level = level
	return c.xp_need() / float(maxi(1, m.exp_reward))
