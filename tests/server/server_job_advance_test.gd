extends TestCase
## Choosing a job at an instructor, through the server (req_advance): who may advance and
## where, the gifts that come with it, a full bag holding it back, switching between first
## jobs (the skills that go and their essence back, free the second time), and the
## new job being announced and saved. The smoke test covers the happy path through the
## dialogue window; these cover the refusals.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const INSTRUCTOR_X := 900.0
const MERCHANT_X := 400.0
const WARRIOR_TUTOR_X := 1700.0

var h: ServerHarness
var p: SimPlayer
var c: Character
var mage: JobDef
var wand: ItemDef
var blue: ItemDef

func before_each() -> void:
	h = ServerHarness.new()
	mage = Content.job(&"mage")
	wand = Content.item(&"apprentice_wand")
	blue = Content.item(&"blue_potion")
	var town := ServerHarness.town_def()
	ServerHarness.npc(town, &"test_instructor", INSTRUCTOR_X).instructs = [&"mage"]
	ServerHarness.npc(town, &"test_merchant", MERCHANT_X)
	ServerHarness.npc(town, &"test_warrior_tutor", WARRIOR_TUTOR_X).instructs = [&"warrior"]
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.TOWN, INSTRUCTOR_X)
	c = p.character

func after_each() -> void:
	h.close()

## A Beginner who has passed the Magician's Job Test.
func _ready_for_mage() -> void:
	c.quests.done[mage.advance_quest.id] = true

## A Warrior (passed) who bought Power Strike, with no essence left over.
func _as_warrior() -> SkillDef:
	c.job = Content.job(&"warrior")
	c.jobs_passed.assign(["warrior"])
	c.recalc()
	var strike := Content.skill(&"power_strike")
	c.essence = c.skills.price()
	check_eq(c.skills.learn(strike), "", "Power Strike bought")
	check_eq(c.essence, 0, "nothing left over")
	return strike

func _advance(npc := &"test_instructor", job := &"mage") -> void:
	h.ask(2, &"req_advance", [npc, job])

func test_advancing_changes_the_job_and_hands_out_the_gifts() -> void:
	_ready_for_mage()
	c.essence = 50
	_advance()
	check_eq(c.job, mage, "a Magician now")
	check_eq(c.essence, 50, "no essence given or taken")
	check_eq(c.gear.weapon(), wand, "the wand, worn at once")
	check_eq(c.inventory.count_of(blue), 30, "the mana potions")
	check(h.told(2, "You are now a Magician!"), "told")
	check(h.told(2, "Your instructor hands you: Apprentice Wand, 30 Blue Potion."), "told what was handed over")

func test_every_job_gets_its_basic_weapon_worn() -> void:
	for job in JobDef.paths_from(Character.START_JOB):
		var who := Character.create("Gift" + String(job.id), Character.START_JOB)
		who.quests.done[job.advance_quest.id] = true
		var old := who.gear.weapon()
		check_eq(who.advance(job), "", "%s: advanced" % job.id)
		var w := who.gear.weapon()
		if not check(w != null and job.family in w.jobs, "%s: wears a %s weapon, not %s" % [job.id, job.family, w.id if w else "nothing"]):
			continue
		check_eq(w, job.advance_gifts[0].item, "%s: the first gift is the weapon worn" % job.id)
		if old:
			check(who.inventory.count_of(old) == 1, "%s: the old weapon goes to the bag" % job.id)

func test_advancing_is_celebrated_and_sent_to_the_player() -> void:
	_ready_for_mage()
	_advance()
	var fx := h.last(2, &"ev_effect")
	check(not fx.is_empty() and fx[0] == EffectDef.CELEBRATE, "everyone on the map sees the celebration")
	h.step()
	var sent := h.last(2, &"ev_character")
	check(not sent.is_empty() and sent[0]["job"] == "mage", "the client is sent the new job")

func test_the_new_job_is_saved_at_once() -> void:
	_ready_for_mage()
	_advance()
	var saved := h.saved("Ann")
	check(saved != null and saved.job.id == &"mage", "saved as a Magician")

func test_the_job_test_is_needed_but_no_stats() -> void:
	_advance()
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "Pass the Job Test first."), "told why")
	_ready_for_mage()
	_advance()
	check_eq(c.job, mage, "the Job Test is enough, on a Beginner's starting stats")

func test_advancing_needs_you_by_the_instructor() -> void:
	_ready_for_mage()
	h.place(p, INSTRUCTOR_X + 400.0)
	_advance()
	check_eq(c.job.id, &"beginner", "too far away")
	check_eq(h.count(2, &"ev_log"), 0, "nothing said")

func test_only_an_instructor_of_that_job_can_advance_you() -> void:
	_ready_for_mage()
	h.place(p, MERCHANT_X)
	_advance(&"test_merchant")
	check_eq(c.job.id, &"beginner", "a merchant doesn't teach jobs")
	h.place(p, INSTRUCTOR_X)
	c.quests.done[Content.job(&"warrior").advance_quest.id] = true
	_advance(&"test_instructor", &"warrior")
	check_eq(c.job.id, &"beginner", "this instructor doesn't teach Warriors")
	_advance(&"test_instructor", &"no_such_job")
	check_eq(c.job.id, &"beginner", "unknown jobs are ignored")

func test_a_full_equip_tab_holds_the_advance_back() -> void:
	_ready_for_mage()
	for i in Inventory.SLOTS:
		c.inventory.add_stack(ItemStack.unrolled(wand, 1))
	_advance()
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "Make room in your Equip inventory first."), "told which tab")
	check_eq(c.inventory.count_of(wand), Inventory.SLOTS, "nothing added")
	check_eq(c.inventory.count_of(blue), 0, "no potions either")

func test_a_full_use_tab_holds_the_advance_back() -> void:
	_ready_for_mage()
	var red := Content.item(&"red_potion")
	c.inventory.add(red, Inventory.SLOTS * red.stack_size())
	_advance()
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "Make room in your Use inventory first."), "told which tab")
	check_eq(c.inventory.count_of(wand), 0, "the wand isn't handed out alone")

func test_a_job_can_only_be_chosen_once() -> void:
	_ready_for_mage()
	_advance()
	c.essence = 50
	_advance()
	check_eq(c.essence, 50, "nothing given a second time")
	check_eq(c.gear.weapon(), wand, "the first wand is worn")
	check_eq(c.inventory.count_of(wand), 0, "no second wand")
	check(h.told(2, "You're already a Magician."), "told")

func test_switching_jobs_drops_the_old_skills_and_hands_back_their_essence() -> void:
	var strike := _as_warrior()
	var paid := int(c.skills.paid[strike.id])
	var level := c.level
	check(c.quickslot_of(&"skill", strike.id) >= 0, "Power Strike on a quickslot")
	_advance()
	check_eq(c.job.id, &"warrior", "the Magician's Job Test first")
	check(h.told(2, "Pass the Job Test first."), "told why")
	check_eq(c.skills.level(strike), 1, "skills kept until then")
	c.quests.done[mage.advance_quest.id] = true
	_advance()
	check_eq(c.job, mage, "a Magician now")
	check_eq(c.skills.level(strike), 0, "Power Strike forgotten")
	check_eq(c.essence, paid, "exactly what it cost comes back")
	check_eq(c.quickslot_of(&"skill", strike.id), -1, "its quickslot empties")
	check_eq(c.level, level, "the level stays")
	check(h.told(2, "You are now a Magician!"), "told")
	check(h.told(2, "You forget Power Strike, and %d Dawn Essence comes back to you." % paid), "told what went and what came back")
	check(h.told(2, "Your instructor hands you: Apprentice Wand, 30 Blue Potion."), "the first time, the gifts")
	check(c.has_passed(mage), "passed")
	var saved := h.saved("Ann")
	check(saved != null and saved.has_passed(mage) and saved.has_passed(Content.job(&"warrior")), "both jobs saved as passed")

func test_switching_back_is_free_and_gives_nothing_again() -> void:
	_as_warrior()
	_ready_for_mage()
	_advance()
	check_eq(c.job, mage, "a Magician")
	var spike := Content.skill(&"ice_spike")
	c.essence += c.skills.price()
	check_eq(c.skills.learn(spike), "", "a Magician skill bought")
	var paid := int(c.skills.paid[spike.id])
	var essence := c.essence
	var blues := c.inventory.count_of(blue)
	var reds := c.inventory.count_of(Content.item(&"red_potion"))
	h.clear()
	h.place(p, WARRIOR_TUTOR_X)
	_advance(&"test_warrior_tutor", &"warrior")
	check_eq(c.job.id, &"warrior", "a Warrior again, with no Job Test")
	check(h.told(2, "You are a Warrior again!"), "told")
	check(not h.told(2, "Your instructor hands you"), "no gifts the second time")
	check_eq(c.inventory.count_of(blue), blues, "no more Blue Potions")
	check_eq(c.inventory.count_of(Content.item(&"red_potion")), reds, "no more Red Potions")
	check_eq(c.skills.level(spike), 0, "the Magician skill goes")
	check_eq(c.essence, essence + paid, "and its essence comes back")
	check(h.told(2, "You forget Ice Spike, and %d Dawn Essence comes back to you." % paid), "told")
	h.clear()
	h.place(p, INSTRUCTOR_X)
	_advance()
	check_eq(c.job, mage, "and a Magician again, free")
	check(h.told(2, "You are a Magician again!"), "told")
	check(not h.told(2, "You forget"), "nothing to forget")

func test_unknown_players_are_ignored() -> void:
	h.ask(9, &"req_advance", [&"test_instructor", &"mage"])
	check_eq(h.count(9, &"ev_log"), 0, "nothing sent")

func test_job_names_take_a_or_an() -> void:
	check_eq(ServerJobs.with_article("Archer"), "an Archer", "an before a vowel")
	check_eq(ServerJobs.with_article("Magician"), "a Magician", "a before a consonant")
