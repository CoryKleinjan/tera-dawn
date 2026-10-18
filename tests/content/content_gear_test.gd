extends TestCase
## The game's own gear (not the test fixtures, Content.extra_items) against what needs it:
## every skill that needs a kind of weapon has a real one its job can hold. Tests hand
## characters fixture gear, so without this a skill no real weapon fits passes everywhere
## (as Riptide Combo did with the Pirate's scimitar).

const Scan := preload("res://tests/content/content_scan.gd")

func _real_weapons() -> Array[EquipDef]:
	var out: Array[EquipDef] = []
	for i: ItemDef in Content.items.values():
		var e := i as EquipDef
		if e and e.weapon_kind != &"" and not i.id in Content.extra_items:
			out.append(e)
	return out

func test_every_weapon_skill_has_a_real_weapon_its_job_can_hold() -> void:
	var weapons := _real_weapons()
	for s: SkillDef in Content.skills.values():
		if s.weapons.is_empty() or not s.is_active():
			continue
		# a skill of no job (a weapon's own attack) just needs that weapon to exist
		var job: JobDef = Content.jobs.get(s.job)
		var fits := weapons.filter(func(e: EquipDef) -> bool:
			return e.weapon_kind in s.weapons and (job == null or e.jobs.is_empty() or job.wear_families().any(func(f: StringName) -> bool: return f in e.jobs)))
		check(not fits.is_empty(), "%s: needs a %s, but no real weapon of that kind fits %s" % [Scan.where(s), " or ".join(s.weapons), job.display_name if job else "anyone"])

## Gear never drops (Cory, Oct 18): shops sell it, unlocked by progress or secrets.
func test_no_monster_zone_or_chest_drops_gear() -> void:
	for m: MonsterDef in Content.monsters.values():
		for d in m.drops:
			check(not (d and d.item is EquipDef), "%s: drops gear %s" % [Scan.where(m), d.item.id if d and d.item else &""])
	for r: RegionDef in Content.regions.values():
		for d in r.drops:
			check(not (d and d.item is EquipDef), "%s: its monsters drop gear %s" % [Scan.where(r), d.item.id if d and d.item else &""])
	for map: MapDef in Content.maps.values():
		for b in map.breakables:
			for d in (b.loot if b else []):
				check(not (d and d.item is EquipDef), "%s: a chest holds gear %s" % [Scan.where(map), d.item.id if d and d.item else &""])

func test_gear_tiers_run_from_one_without_gaps() -> void:
	check(Content.top_gear_tier() >= 2, "there are tiers to climb")
	var last := 0.0
	for rank in range(1, Content.top_gear_tier() + 1):
		var t := Content.gear_tier(rank)
		check(t != null, "tier %d exists" % rank)
		if t == null:
			continue
		check(t.display_name != "", "tier %d has a name" % rank)
		check(t.stat_scale > last, "tier %d is stronger than the one below" % rank)
		check(rank == 1 or t.fee > 0, "tier %d has a fee" % rank)
		last = t.stat_scale
	check_eq(Content.gear_tier(1).stat_scale, 1.0, "tier 1 is gear as listed")
