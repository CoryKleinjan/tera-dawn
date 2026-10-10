extends TestCase
## Putting skills and items on quickslots through the server (req_set_quickslot): what is
## kept, what is ignored, moving something that is already on a slot, and clearing a slot.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var p: SimPlayer
var c: Character

func before_each() -> void:
	h = ServerHarness.new()
	p = h.join(2, "Ann")
	c = p.character
	for i in Character.QUICKSLOTS:
		c.quickslots[i] = []

func after_each() -> void:
	h.close()

func _slot(i: int, kind: StringName, id: StringName) -> void:
	h.ask(2, &"req_set_quickslot", [i, kind, id])

func test_a_skill_goes_on_its_slot_and_is_sent_back() -> void:
	_slot(3, &"skill", &"power_strike")
	check_eq(c.quickslots[3], [&"skill", &"power_strike"], "on slot 3")
	h.step()
	var sent := h.last(2, &"ev_character")
	check(not sent.is_empty() and sent[0]["quickslots"][3] == ["skill", "power_strike"], "the client is sent the change")

func test_an_item_goes_on_its_slot() -> void:
	_slot(0, &"item", &"red_potion")
	check_eq(c.quickslots[0], [&"item", &"red_potion"], "on slot 0")

func test_unknown_skills_and_items_are_ignored() -> void:
	_slot(0, &"skill", &"no_such_skill")
	_slot(1, &"item", &"no_such_item")
	check_eq(c.quickslots[0], [], "no unknown skill")
	check_eq(c.quickslots[1], [], "no unknown item")

func test_an_unknown_kind_is_ignored() -> void:
	_slot(0, &"emote", &"red_potion")
	check_eq(c.quickslots[0], [], "nothing set")

func test_a_skill_id_sent_as_an_item_is_ignored() -> void:
	_slot(0, &"item", &"power_strike")
	check_eq(c.quickslots[0], [], "a skill isn't an item")

func test_slots_outside_the_bar_are_ignored() -> void:
	_slot(-1, &"item", &"red_potion")
	_slot(Character.QUICKSLOTS, &"item", &"red_potion")
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "the bar keeps its size")
	for i in Character.QUICKSLOTS:
		check_eq(c.quickslots[i], [], "slot %d still empty" % i)

func test_placing_something_already_on_the_bar_swaps_the_two_slots() -> void:
	_slot(0, &"item", &"red_potion")
	_slot(1, &"skill", &"power_strike")
	_slot(1, &"item", &"red_potion")
	check_eq(c.quickslots[1], [&"item", &"red_potion"], "moved to slot 1")
	check_eq(c.quickslots[0], [&"skill", &"power_strike"], "what was there takes its old slot")

func test_an_empty_kind_clears_the_slot() -> void:
	_slot(2, &"item", &"red_potion")
	_slot(2, &"", &"")
	check_eq(c.quickslots[2], [], "cleared")

func test_quickslots_are_saved() -> void:
	_slot(5, &"skill", &"power_strike")
	h.leave(2)
	var saved := h.server.store.load_character("Ann")
	check(saved != null and saved.quickslots[5] == [&"skill", &"power_strike"], "kept after leaving")

func test_unknown_players_are_ignored() -> void:
	h.ask(9, &"req_set_quickslot", [0, &"item", &"red_potion"])
	check_eq(c.quickslots[0], [], "Ann's bar untouched")
