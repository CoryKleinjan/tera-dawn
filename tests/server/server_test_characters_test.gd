extends TestCase
## Developer test characters (TestCharacters): one per job at the level cap, in the best gear
## the job can wear and able to wear all of it, with every skill and the Dawnshards; the
## local login puts them on their own account, leaves the player's own alone, makes only the
## missing ones unless asked to rebuild, and nobody else can reach them.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var lobby: TDLobby

func before_each() -> void:
	h = ServerHarness.new()
	lobby = h.server.lobby
	h.server.local_player = true
	h.api.peers.append(1)

func after_each() -> void:
	h.close()

func _test_login(mode := TestCharacters.Mode.ON) -> Dictionary:
	h.ask(1, &"req_local_login", [mode])
	return lobby.account_of(1)

# ---------- the characters ----------

func test_every_job_gets_a_max_level_character_in_gear_it_can_wear() -> void:
	for job in TestCharacters.jobs():
		var c := TestCharacters.build(TestCharacters.name_for(job), job)
		check_eq(c.job, job, "%s: the job" % job.id)
		check_eq(c.level, Character.MAX_LEVEL, "%s: the level cap" % job.id)
		check_eq(c.shards, TestCharacters.SHARDS, "%s: Dawnshards" % job.id)
		check_eq(c.ap, 0, "%s: every Ability Point spent" % job.id)
		check(c.weapon() != null, "%s: holds a weapon" % job.id)
		for place: StringName in c.equipment.worn:
			var e := c.equipment.at(place).equip_def()
			check_eq(c.equip_problem(e), "", "%s can wear the %s" % [job.id, e.id])
		check_eq(c.health.hp, c.max_hp(), "%s: full HP" % job.id)
		for w in TestCharacters.best_weapons(job, c.level):
			if w.ammo != &"":
				var has_ammo := false
				for s in c.inventory.tabs[ItemDef.Tab.USE]:
					has_ammo = has_ammo or (s and s.item is AmmoDef and (s.item as AmmoDef).kind == w.ammo)
				check(has_ammo, "%s: carries ammo for the %s" % [job.id, w.id])

func test_the_gear_is_the_best_the_job_can_wear() -> void:
	for job in TestCharacters.jobs():
		var c := TestCharacters.build("Gear", job)
		for it: ItemDef in Content.items.values():
			var e := it as EquipDef
			if e == null or not c.can_use(e.jobs) or e.required_level > c.level:
				continue
			var worn := c.equipment.at(c.equipment.place_for(e))
			if e.slot == EquipDef.Slot.WEAPON:
				worn = c.equipment.at(&"weapon")
				if worn.equip_def().weapon_kind != e.weapon_kind:
					continue
			check(worn != null and worn.equip_def().required_level >= e.required_level,
				"%s wears nothing below the %s's level" % [job.id, e.id])

func test_a_job_with_two_weapon_kinds_wields_its_first_and_carries_the_other() -> void:
	for job in TestCharacters.jobs():
		var weapons := TestCharacters.best_weapons(job, Character.MAX_LEVEL)
		if weapons.size() < 2:
			continue
		var c := TestCharacters.build("Arms", job)
		check_eq(c.weapon(), weapons[0], "%s wields its main kind" % job.id)
		for e in weapons.slice(1):
			check(c.inventory.find(e) >= 0, "%s carries the %s" % [job.id, e.id])

func test_every_skill_is_at_its_highest_level() -> void:
	for job in TestCharacters.jobs():
		var c := TestCharacters.build("Skills", job)
		for s: SkillDef in Content.skills.values():
			if not s.innate and s.job in c.job_line():
				check_eq(c.skill_level(s), s.max_level, "%s: %s" % [job.id, s.id])

func test_every_job_is_listed_starting_job_first() -> void:
	var jobs := TestCharacters.jobs()
	check_eq(jobs.size(), Content.jobs.size(), "every job")
	check_eq(jobs[0].id, Character.START_JOB, "the starting job first")

# ---------- logging in ----------

func test_the_test_account_has_one_character_per_job_and_leaves_the_local_one_alone() -> void:
	h.ask(1, &"req_local_login")
	h.ask(1, &"req_create_character", ["Mine", ServerHarness.made()])
	lobby.dropped(1)
	var a := _test_login()
	check_eq(a["username"], TestCharacters.ACCOUNT, "on the test account")
	check_eq(a["characters"].size(), Content.jobs.size(), "one per job")
	check_eq(h.last(1, &"ev_logged_in")[1].size(), Content.jobs.size(), "character select lists them")
	check_eq(lobby.accounts.load_account(AccountStore.LOCAL)["characters"], ["Mine"], "the player's own account is untouched")
	lobby.dropped(1)
	h.ask(1, &"req_local_login", [TestCharacters.Mode.OFF])
	check_eq(lobby.account_of(1)["username"], AccountStore.LOCAL, "turned off: back on the own account")

func test_they_are_kept_until_rebuilt() -> void:
	var a := _test_login()
	var first: String = a["characters"][0]
	var c := h.server.store.load_character(first)
	c.shards = 7
	h.server.store.save(c)
	lobby.dropped(1)
	_test_login()
	check_eq(h.server.store.load_character(first).shards, 7, "kept as played")
	lobby.dropped(1)
	_test_login(TestCharacters.Mode.REBUILD)
	check_eq(h.server.store.load_character(first).shards, TestCharacters.SHARDS, "made fresh")
	check_eq(lobby.account_of(1)["characters"].size(), Content.jobs.size(), "still one per job")

func test_a_taken_name_gets_a_number() -> void:
	var job := TestCharacters.jobs()[0]
	h.server.store.save(Character.create(TestCharacters.name_for(job)))
	var a := _test_login()
	check(not TestCharacters.name_for(job) in a["characters"], "someone else's character isn't taken over")
	check_eq(h.server.store.load_character(TestCharacters.name_for(job)).level, 1, "and isn't touched")

func test_nobody_who_joined_can_reach_them() -> void:
	h.api.peers.append(2)
	h.ask(2, &"req_local_login", [TestCharacters.Mode.ON])
	check(lobby.account_of(2).is_empty(), "not for someone who joined")
	check(not lobby.accounts.exists(TestCharacters.ACCOUNT), "nothing made")
	h.server.local_player = false
	h.ask(1, &"req_local_login", [TestCharacters.Mode.ON])
	check(lobby.account_of(1).is_empty(), "not on a server without a local player")
