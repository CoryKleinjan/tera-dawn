extends TestCase
## Developer test characters (TestCharacters): one per job, in the best gear the job can wear
## up to the gear tier and able to wear all of it, with Dawnshards to spare; they're kept in
## their own folder apart from the player's own characters, only the missing ones are made
## unless asked to rebuild, and each is put back in its job's town.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var store: CharacterStore

func before_each() -> void:
	h = ServerHarness.new()
	store = CharacterStore.new(h.dir.path_join(TestCharacters.FOLDER))

func after_each() -> void:
	h.close()

# ---------- the characters ----------

func test_every_job_gets_a_character_in_gear_it_can_wear() -> void:
	for job in TestCharacters.jobs():
		var c := TestCharacters.build(TestCharacters.name_for(job), job)
		check_eq(c.job, job, "%s: the job" % job.id)
		check_eq(c.shards, TestCharacters.SHARDS, "%s: Dawnshards" % job.id)
		check(c.gear.weapon() != null, "%s: holds a weapon" % job.id)
		for place: StringName in c.equipment.worn:
			var e := c.equipment.at(place).equip_def()
			check_eq(c.gear.equip_problem(e), "", "%s can wear the %s" % [job.id, e.id])
		check_eq(c.health.hp, c.max_hp(), "%s: every heart" % job.id)

func test_the_gear_is_the_best_the_job_can_wear() -> void:
	for job in TestCharacters.jobs():
		var c := TestCharacters.build("Gear", job)
		for it: ItemDef in Content.items.values():
			var e := it as EquipDef
			if e == null or not c.gear.can_use(e.jobs) or e.required_level > TestCharacters.GEAR_TIER:
				continue
			var worn := c.equipment.at(c.equipment.place_for(e))
			if e.slot == EquipDef.Slot.WEAPON:
				worn = c.equipment.at(&"weapon")
				if worn.equip_def().weapon_kind != e.weapon_kind:
					continue
			if e.slot == EquipDef.Slot.SHIELD and worn and worn.equip_def().offhand_kind != e.offhand_kind:
				continue
			check(worn != null and worn.equip_def().required_level >= e.required_level,
				"%s wears nothing below the %s's gear tier" % [job.id, e.id])

func test_a_job_with_two_weapon_kinds_wields_its_first_and_carries_the_other() -> void:
	for job in TestCharacters.jobs():
		var weapons := TestCharacters.best_weapons(job, TestCharacters.GEAR_TIER)
		if weapons.size() < 2:
			continue
		var c := TestCharacters.build("Arms", job)
		check_eq(c.gear.weapon(), weapons[0], "%s wields its main kind" % job.id)
		for e in weapons.slice(1):
			check(c.inventory.find(e) >= 0, "%s carries the %s" % [job.id, e.id])

func test_each_starts_in_its_job_town() -> void:
	for job in TestCharacters.jobs():
		var c := TestCharacters.build("Home", job)
		var town := TestCharacters.home_town(job)
		check_eq(c.map_id, town, "%s starts at home" % job.id)
		check(Content.map(town).town, "%s: %s is a town" % [job.id, town])
		if job.id == Character.START_JOB:
			check_eq(town, Character.START_MAP, "the starting job starts where everyone does")
			continue
		check(town != Character.START_MAP, "%s has its own town" % job.id)
		var teaches := false
		for m: MapDef in Content.maps.values():
			for n in m.npcs:
				teaches = teaches or (m.return_town() == town and n.npc and TestCharacters.path_to(job)[0].id in n.npc.instructs)
		check(teaches, "%s: its instructor is in %s" % [job.id, town])

func test_every_job_is_listed_starting_job_first() -> void:
	var jobs := TestCharacters.jobs()
	check_eq(jobs.size(), Content.jobs.size(), "every job")
	check_eq(jobs[0].id, Character.START_JOB, "the starting job first")

# ---------- the test characters' folder ----------

func test_one_character_per_job_in_its_own_folder() -> void:
	var own := CharacterStore.new(h.dir)
	own.create("Mine", NewCharacter.new())
	TestCharacters.prepare(store, false)
	check_eq(store.names().size(), Content.jobs.size(), "one per job")
	check_eq(store.slots().size(), mini(Content.jobs.size(), CharacterStore.MAX_CHARACTERS), "character select lists them")
	check_eq(own.names(), ["Mine"] as Array[String], "the player's own characters are untouched")

func test_they_are_kept_until_rebuilt() -> void:
	TestCharacters.prepare(store, false)
	var first: String = store.names()[0]
	var c := store.load_character(first)
	c.shards = 7
	store.save(c)
	TestCharacters.prepare(store, false)
	check_eq(store.load_character(first).shards, 7, "kept as played")
	for n in store.names():
		var kept := store.load_character(n)
		kept.map_id = &"nowhere"
		store.save(kept)
	TestCharacters.prepare(store, false)
	for n in store.names():
		var kept := store.load_character(n)
		check_eq(kept.map_id, TestCharacters.home_town(kept.job), "%s back in its town" % n)
	TestCharacters.prepare(store, true)
	check_eq(store.load_character(first).shards, TestCharacters.SHARDS, "made fresh")
	check_eq(store.names().size(), Content.jobs.size(), "still one per job")

func test_a_taken_name_gets_a_number() -> void:
	var job := TestCharacters.jobs()[1]
	store.save(Character.create(TestCharacters.name_for(job)))
	TestCharacters.prepare(store, false)
	check_eq(store.load_character(TestCharacters.name_for(job)).job.id, Character.START_JOB, "a Beginner with that name isn't taken over")
	var named := ""
	for n in store.names():
		if store.load_character(n).job == job:
			named = n
	check(named.begins_with(TestCharacters.name_for(job).substr(0, 8)) and named != TestCharacters.name_for(job), "the job's one gets a number (%s)" % named)
