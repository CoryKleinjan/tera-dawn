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
