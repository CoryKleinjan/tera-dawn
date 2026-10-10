extends TestCase
## Choosing a job at an instructor, through the server (req_advance): who may advance and
## where, the gifts and Skill Points that come with it, a full bag holding it back, and the
## new job being announced and saved. The smoke test covers the happy path through the
## dialogue window; these cover the refusals.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const INSTRUCTOR_X := 900.0
const MERCHANT_X := 400.0

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
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.TOWN, INSTRUCTOR_X)
	c = p.character

func after_each() -> void:
	h.close()

## A Beginner who meets every Magician requirement.
func _ready_for_mage() -> void:
	c.level = mage.advance_level
	c.base.intelligence = mage.advance_requirements.intelligence
	c.recalc()

func _advance(npc := &"test_instructor", job := &"mage") -> void:
	h.ask(2, &"req_advance", [npc, job])

func test_advancing_changes_the_job_and_hands_out_the_gifts_and_sp() -> void:
	_ready_for_mage()
	var sp := c.sp
	_advance()
	check_eq(c.job, mage, "a Magician now")
	check_eq(c.sp, sp + mage.advance_sp, "the job's Skill Points")
	check_eq(c.inventory.count_of(wand), 1, "the wand")
	check_eq(c.inventory.count_of(blue), 30, "the mana potions")
	check(h.told(2, "You are now a Magician!"), "told")

func test_advancing_is_celebrated_and_sent_to_the_player() -> void:
	_ready_for_mage()
	_advance()
	var fx := h.last(2, &"ev_effect")
	check(not fx.is_empty() and fx[0] == &"celebrate", "everyone on the map sees the celebration")
	h.step()
	var sent := h.last(2, &"ev_character")
	check(not sent.is_empty() and sent[0]["job"] == "mage", "the client is sent the new job")

func test_the_new_job_is_saved_at_once() -> void:
	_ready_for_mage()
	_advance()
	var saved := h.server.store.load_character("Ann")
	check(saved != null and saved.job.id == &"mage", "saved as a Magician")

func test_too_low_a_level_is_refused_and_told() -> void:
	_ready_for_mage()
	c.level = mage.advance_level - 1
	_advance()
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "You need to be level %d to become a Magician." % mage.advance_level), "told why")
	check_eq(c.inventory.count_of(wand), 0, "no gift")

func test_missing_stats_are_refused_and_told() -> void:
	_ready_for_mage()
	c.base.intelligence = mage.advance_requirements.intelligence - 1
	_advance()
	check_eq(c.job.id, &"beginner", "still a Beginner")
	check(h.told(2, "INT to become a Magician."), "told which stat")

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
	c.base.strength = 35
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
	var sp := c.sp
	_advance()
	check_eq(c.sp, sp, "no second round of Skill Points")
	check_eq(c.inventory.count_of(wand), 1, "no second wand")
	check(h.told(2, "A Magician can't become a Magician."), "told")

func test_unknown_players_are_ignored() -> void:
	h.ask(9, &"req_advance", [&"test_instructor", &"mage"])
	check_eq(h.count(9, &"ev_log"), 0, "nothing sent")
