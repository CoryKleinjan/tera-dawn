class_name Balance
extends RefCounted
## Numbers for tuning: a typical character of a job at a tier of progress (the best gear made
## for their job, raised to the gear tier players have by then), and how many hits of their
## attack a monster takes. A monster's tier is its MonsterDef.level (players have no levels,
## Cory Oct 19: a tier is only how far along they are). tests/balance_report.tscn prints the
## whole table; the smoke test keeps every job inside BAND against monsters of its tier.

## Hits a tier-matched monster should take with the main attack, low to high.
const BAND := Vector2(1.5, 9.0)
## Players take their first job at this tier; before it they fight bare-handed.
const JOB_TIER := 10
## The tier by which players have raised their gear to the top gear tier.
const TOP_TIER := 31

## The first jobs (each a line a Beginner takes at JOB_TIER), from the game's jobs.
static func lines() -> Array[StringName]:
	var out: Array[StringName] = []
	for j in JobDef.paths_from(Character.START_JOB):
		out.append(j.id)
	return out

## The gear tier (GearTierDef.rank) players have raised their gear to by `tier`: the first
## at JOB_TIER, the top one at TOP_TIER, evenly between.
static func gear_rank(tier: int) -> int:
	var top := Content.top_gear_tier()
	var t := clampf(float(tier - JOB_TIER) / (TOP_TIER - JOB_TIER), 0.0, 1.0)
	return clampi(1 + floori(t * (top - 1) + 0.0001), 1, top)

## A character of `job_id` at `tier`, wearing the best gear their job can wear at
## gear_rank(tier).
static func typical(job_id: StringName, tier: int) -> Character:
	# everyone starts as a Beginner and takes their job at JOB_TIER
	var c := Character.create("Balance")
	if tier >= JOB_TIER:
		c.job = Content.job(job_id)
	c.recalc()
	var best := {}
	for item in Content.items.values():
		var e := item as EquipDef
		# only the game's own gear (tests add their own, Content.extra_items)
		if e == null or e.stats == null or e.id in Content.extra_items or e.required_level > tier or c.gear.equip_problem(e) != "":
			continue
		var place := c.equipment.place_for(e)
		var score := _score(e)
		if not best.has(place) or score > best[place][0]:
			best[place] = [score, e]
	for place in best:
		var stack := ItemStack.exact(best[place][1])
		stack.tier = gear_rank(tier)
		c.equipment.put(place, stack)
	c.recalc()
	return c

static func _score(e: EquipDef) -> int:
	var s := e.stats
	return maxi(s.attack, s.magic_attack) * 3 + s.defense / 4

## The attack this character uses: their weapon's own (a bow shoots) or the plain swing.
static func main_attack(c: Character) -> SkillDef:
	return c.skills.basic_attack()

## Average damage of one of `s`'s hits.
static func average_hit(c: Character, s: SkillDef) -> float:
	var spread := c.damage_range()
	var crit := CharacterStats.crit_rate(c.stats)
	return (spread.x + spread.y) / 2.0 * s.damage_at(1) * (1.0 + crit * (Combat.CRIT_MULTIPLIER - 1.0))

## Average damage of one use of the main attack (all its hits).
static func swing_damage(c: Character) -> float:
	var attack := main_attack(c)
	return average_hit(c, attack) * attack.hits

## Average uses of the main attack it takes to beat `m`.
static func hits_to_kill(c: Character, m: MonsterDef) -> float:
	return m.max_hp / maxf(1.0, swing_damage(c))
