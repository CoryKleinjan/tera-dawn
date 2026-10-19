extends TestCase
## Choosing a job at an instructor, through the server (req_advance): who may advance and
## where, the gifts that come with it, a full bag holding it back, switching between first
## jobs (free the second time, with no gifts again), and the new job being announced and
## saved. The smoke test covers the happy path through the dialogue window; these cover the
## refusals.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const INSTRUCTOR_X := 900.0
const MERCHANT_X := 400.0
const WARRIOR_TUTOR_X := 1700.0

var h: ServerHarness
var p: SimPlayer
var c: Character
var mage: JobDef
var wand: ItemDef
var scroll: ItemDef
var _old_gifts: Array[DropEntry]

func before_each() -> void:
	h = ServerHarness.new()
	mage = Content.job(&"mage")
	wand = Content.item(&"novice_wand")
	scroll = Content.item(&"return_scroll")
	# the Magician's gifts for these tests: a wand and three scrolls
	_old_gifts = mage.advance_gifts
	mage.advance_gifts = [ServerHarness.drop(wand), ServerHarness.drop(scroll, 3)] as Array[DropEntry]
	var town := ServerHarness.town_def()
	ServerHarness.npc(town, &"test_instructor", INSTRUCTOR_X).instructs = [&"mage"]
	ServerHarness.npc(town, &"test_merchant", MERCHANT_X)
	ServerHarness.npc(town, &"test_warrior_tutor", WARRIOR_TUTOR_X).instructs = [&"warrior"]
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.TOWN, INSTRUCTOR_X)
	c = p.character

func after_each() -> void:
	h.close()
	mage.advance_gifts = _old_gifts

## A Beginner who has passed the Magician's Job Test.
func _ready_for_mage() -> void:
	c.quests.done[mage.advance_quest.id] = true

## A Warrior who has passed the Warrior's Job Test.
func _as_warrior() -> void:
	c.job = Content.job(&"warrior")
	c.jobs_passed.assign(["warrior"])
	c.recalc()

func _advance(npc := &"test_instructor", job := &"mage") -> void:
	h.ask(2, &"req_advance", [npc, job])

func test_advancing_changes_the_job_and_hands_out_the_gifts() -> void:
	_ready_for_mage()
	_advance()
	check_eq(c.job, mage, "a Magician now")
	check_eq(c.gear.weapon(), wand, "the wand, worn at once")
	check_eq(c.inventory.count_of(scroll), 3, "the scrolls")
	check(h.told(2, "You are now a Magician!"), "told")
	check(h.told(2, "Your instructor hands you: Novice Wand, 3 Return Scroll."), "told what was handed over")

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
	check_eq(c.inventory.count_of(scroll), 0, "no scrolls either")

func test_a_full_use_tab_holds_the_advance_back() -> void:
	_ready_for_mage()
	var snack := Content.item(&"pet_snack")
	c.inventory.add(snack, Inventory.SLOTS * snack.stack_size())
	_advance()
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "Make room in your Use inventory first."), "told which tab")
	check_eq(c.inventory.count_of(wand), 0, "the wand isn't handed out alone")

func test_a_job_can_only_be_chosen_once() -> void:
	_ready_for_mage()
	_advance()
	_advance()
	check_eq(c.gear.weapon(), wand, "the first wand is worn")
	check_eq(c.inventory.count_of(wand), 0, "no second wand")
	check(h.told(2, "You're already a Magician."), "told")

func test_switching_jobs_needs_the_new_job_test() -> void:
	_as_warrior()
	_advance()
	check_eq(c.job.id, &"warrior", "the Magician's Job Test first")
	check(h.told(2, "Pass the Job Test first."), "told why")
	c.quests.done[mage.advance_quest.id] = true
	_advance()
	check_eq(c.job, mage, "a Magician now")
	check(h.told(2, "You are now a Magician!"), "told")
	check(h.told(2, "Your instructor hands you: Novice Wand, 3 Return Scroll."), "the first time, the gifts")
	check(c.has_passed(mage), "passed")
	var saved := h.saved("Ann")
	check(saved != null and saved.has_passed(mage) and saved.has_passed(Content.job(&"warrior")), "both jobs saved as passed")

func test_switching_back_is_free_and_gives_nothing_again() -> void:
	_as_warrior()
	_ready_for_mage()
	_advance()
	check_eq(c.job, mage, "a Magician")
	var scrolls := c.inventory.count_of(scroll)
	var wands := c.inventory.count_of(wand)
	h.clear()
	h.place(p, WARRIOR_TUTOR_X)
	_advance(&"test_warrior_tutor", &"warrior")
	check_eq(c.job.id, &"warrior", "a Warrior again, with no Job Test")
	check(h.told(2, "You are a Warrior again!"), "told")
	h.clear()
	h.place(p, INSTRUCTOR_X)
	_advance()
	check_eq(c.job, mage, "and a Magician again, free")
	check(h.told(2, "You are a Magician again!"), "told")
	check(not h.told(2, "Your instructor hands you"), "no gifts the second time")
	check_eq(c.inventory.count_of(scroll), scrolls, "no more scrolls")
	check_eq(c.inventory.count_of(wand), wands, "no second wand")

func test_unknown_players_are_ignored() -> void:
	h.ask(9, &"req_advance", [&"test_instructor", &"mage"])
	check_eq(h.count(9, &"ev_log"), 0, "nothing sent")

func test_job_names_take_a_or_an() -> void:
	check_eq(ServerJobs.with_article("Archer"), "an Archer", "an before a vowel")
	check_eq(ServerJobs.with_article("Magician"), "a Magician", "a before a consonant")
