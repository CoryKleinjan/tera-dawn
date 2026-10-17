extends TestCase
## Quests run through the server: taking one from its NPC, kill, collect and visit
## objectives, quest items that only drop while wanted, handing in for rewards, giving up.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const GIVER_X := 400.0
const TAKER_X := 1000.0

var h: ServerHarness
var p: SimPlayer
var c: Character
var quarry: MonsterDef
var token: ItemDef
var field: MapInstance
var q_kill: QuestDef
var q_collect: QuestDef
var q_visit: QuestDef

func before_each() -> void:
	h = ServerHarness.new()
	var town := ServerHarness.town_def()
	ServerHarness.npc(town, &"test_giver", GIVER_X)
	ServerHarness.npc(town, &"test_taker", TAKER_X)
	h.add_map(town)
	quarry = ServerHarness.monster(&"quarry", 1, 1)
	field = h.field_with([ServerHarness.spawn(quarry, 2)])
	for m in field.mobs:
		m.position.x = 340.0
	token = ItemDef.new()
	token.id = &"test_token"
	token.display_name = "Token"
	token.quest_item = true
	h.add_item(token)

	q_kill = _quest(&"test_q_kill")
	q_kill.objectives.append(_objective(QuestObjective.Kind.KILL, 2))
	q_kill.reward_essence = 5
	q_kill.reward_shards = 50
	q_kill.reward_items.append(ServerHarness.drop(Content.item(&"red_potion"), 3))

	q_collect = _quest(&"test_q_collect")
	q_collect.turn_in = &"test_taker"
	var o := _objective(QuestObjective.Kind.COLLECT, 2)
	o.item = token
	o.drop_from = quarry
	o.drop_chance = 1.0
	q_collect.objectives.append(o)

	q_visit = _quest(&"test_q_visit")
	var v := _objective(QuestObjective.Kind.VISIT, 1)
	v.map = ServerHarness.FIELD
	q_visit.objectives.append(v)

	p = h.join(2, "Ann", ServerHarness.TOWN, GIVER_X)
	c = p.character
	ServerHarness.no_cards(p, quarry)

func after_each() -> void:
	h.close()

func _quest(id: StringName) -> QuestDef:
	var q := QuestDef.new()
	q.id = id
	q.title = String(id).capitalize()
	q.giver = &"test_giver"
	return h.add_quest(q)

func _objective(kind: QuestObjective.Kind, n: int) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = kind
	o.count = n
	o.monster = quarry
	return o

## Goes to the field and defeats both quarries, then comes back to `x` in town.
func _hunt(back_x := GIVER_X) -> void:
	h.move_to(p, ServerHarness.FIELD, 300.0)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	h.step(30)
	h.place(p, 340.0)
	h.ask(2, &"req_loot")
	h.place(p, 300.0)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	h.step(30)
	h.place(p, 340.0)
	h.ask(2, &"req_loot")
	h.move_to(p, ServerHarness.TOWN, back_x)

func test_taking_a_quest_from_its_npc() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	check(c.quests.active.has(q_kill.id), "in progress")
	check(h.told(2, "New quest: Test Q Kill"), "told")

func test_quests_are_only_taken_standing_by_the_giver() -> void:
	h.place(p, GIVER_X + 200.0)
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	check(not c.quests.active.has(q_kill.id), "too far")
	h.place(p, TAKER_X)
	h.ask(2, &"req_quest_accept", [&"test_taker", q_kill.id])
	check(not c.quests.active.has(q_kill.id), "the wrong NPC")

func test_kills_count_toward_the_quest() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	h.move_to(p, ServerHarness.FIELD, 300.0)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check_eq(c.quests.active[q_kill.id], [1], "one down")
	check(h.told(2, "Test Q Kill: Defeat 2 Quarry 1/2"), "progress shown")

func test_handing_in_pays_every_reward() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	_hunt()
	check(h.told(2, "Test Q Kill is ready to hand in."), "told it's ready")
	var essence := c.essence
	var reds := c.inventory.count_of(Content.item(&"red_potion"))
	h.ask(2, &"req_quest_complete", [&"test_giver", q_kill.id])
	check(not c.quests.active.has(q_kill.id), "no longer active")
	check_eq(c.quests.done.get(q_kill.id), 1, "done once")
	check_eq(c.essence, essence + 5, "Dawn Essence reward")
	check_has(h.events(2, &"ev_gain"), [&"essence", 5], "essence shown rising over the player")
	check_has(h.events(2, &"ev_gain"), [&"exp", 5], "and as much EXP")
	check_eq(c.shards, 50, "Dawnshard reward")
	check_eq(c.inventory.count_of(Content.item(&"red_potion")), reds + 3, "item reward")
	check(h.told(2, "Quest complete: Test Q Kill"), "told")

func test_unfinished_quests_cant_be_handed_in() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	h.ask(2, &"req_quest_complete", [&"test_giver", q_kill.id])
	check(c.quests.active.has(q_kill.id), "still active")
	check_eq(c.shards, 0, "no reward")
	check(h.told(2, "You haven't finished Test Q Kill yet."), "told why")

func test_finished_quests_cant_be_taken_again() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	_hunt()
	h.ask(2, &"req_quest_complete", [&"test_giver", q_kill.id])
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	check(not c.quests.active.has(q_kill.id), "not taken twice")

func test_quest_items_drop_only_while_the_quest_wants_them() -> void:
	h.move_to(p, ServerHarness.FIELD, 300.0)
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check(field.drops.is_empty(), "no token without the quest")
	h.move_to(p, ServerHarness.TOWN, GIVER_X)
	h.ask(2, &"req_quest_accept", [&"test_giver", q_collect.id])
	h.move_to(p, ServerHarness.FIELD, 300.0)
	field = h.server.maps[ServerHarness.FIELD] # loaded fresh, the first quarry back
	h.step(30) # past the swing's cooldown
	for m in field.mobs:
		m.position.x = 340.0
	h.ask(2, &"req_skill", [&"basic_attack", p.position, 1])
	check_eq(field.drops.size(), 1, "a token dropped")
	check_eq((field.drops.values()[0] as SimDrop).item.id, token.id, "the quest item")

func test_collected_items_are_taken_when_handed_in_elsewhere() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_collect.id])
	_hunt(TAKER_X)
	check_eq(c.inventory.count_of(token), 2, "two tokens collected")
	check(h.told(2, "Test Q Collect: Token 2/2"), "pickup progress shown")
	h.ask(2, &"req_quest_complete", [&"test_giver", q_collect.id])
	check(c.quests.active.has(q_collect.id), "the giver doesn't take it in")
	h.ask(2, &"req_quest_complete", [&"test_taker", q_collect.id])
	check(c.quests.done.has(q_collect.id), "handed in to the other NPC")
	check_eq(c.inventory.count_of(token), 0, "tokens taken")

func test_reaching_a_map_completes_a_visit_objective() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_visit.id])
	check_eq(c.quests.active[q_visit.id], [0], "not there yet")
	h.move_to(p, ServerHarness.FIELD)
	check_eq(c.quests.active[q_visit.id], [1], "visited")
	check(h.told(2, "Test Q Visit is ready to hand in."), "told")

func test_taking_a_visit_quest_on_its_map_counts_at_once() -> void:
	q_visit.objectives[0].map = ServerHarness.TOWN
	h.ask(2, &"req_quest_accept", [&"test_giver", q_visit.id])
	check_eq(c.quests.active[q_visit.id], [1], "already there")

func test_giving_up_a_quest() -> void:
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	h.ask(2, &"req_quest_forfeit", [q_kill.id])
	check(not c.quests.active.has(q_kill.id), "dropped")
	check(h.told(2, "Gave up on Test Q Kill."), "told")
	h.ask(2, &"req_quest_accept", [&"test_giver", q_kill.id])
	check(c.quests.active.has(q_kill.id), "can be taken again")

# ---------- real content ----------

## Puts the player beside NPC `npc_id` on the real map `map_id`, standing on its platform.
func _beside(map_id: StringName, npc_id: StringName) -> void:
	h.move_to(p, map_id)
	for at in Content.map(map_id).npcs:
		if at.npc.id == npc_id:
			h.place(p, at.x, p.map.layout.platforms[at.platform].y)
			return
	check(false, "%s isn't on %s" % [npc_id, map_id])

func test_choosing_a_path_is_handed_in_to_the_harbormaster_in_dawnharbor() -> void:
	var q: QuestDef = Content.quests[&"q07_choosing_a_path"]
	check_eq(q.turn_in_npc(), &"harbormaster", "handed in at the docks")
	_beside(&"dawnrise_village", q.giver)
	h.ask(2, &"req_quest_accept", [q.giver, q.id])
	if not check(c.quests.active.has(q.id), "taken from Sorrel"):
		return
	_beside(&"dawnharbor", &"harbormaster")
	check_eq(c.quests.status(q, c), QuestLog.Status.READY, "reaching Dawnharbor finishes it")
	h.ask(2, &"req_quest_complete", [&"harbormaster", q.id])
	check_eq(c.quests.done.get(q.id), 1, "handed in to Harbormaster Ines")
	check(h.told(2, "Quest complete: Choosing a Path"), "told")

func test_choosing_a_path_is_not_handed_in_back_on_the_isle() -> void:
	var q: QuestDef = Content.quests[&"q07_choosing_a_path"]
	_beside(&"dawnrise_village", q.giver)
	h.ask(2, &"req_quest_accept", [q.giver, q.id])
	_beside(&"dawnharbor", &"harbormaster")
	_beside(&"dawnrise_village", q.giver)
	h.ask(2, &"req_quest_complete", [q.giver, q.id])
	check(c.quests.active.has(q.id), "Sorrel doesn't take it back")
