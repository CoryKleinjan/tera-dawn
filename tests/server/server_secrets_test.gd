extends TestCase
## Secrets on the server: portals that land on a raised platform, shortcuts that stay shut
## until found from their open end, and chests and walls that break open after enough blows,
## once per character, spilling their loot for whoever broke them.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const LEDGE_Y := 420.0
const NEAR_X := 1800.0
const FAR_X := 1700.0
const CHEST_X := 400.0
const WALL_X := 1000.0

var h: ServerHarness
var p: SimPlayer
var c: Character
var potion: ItemDef

func before_each() -> void:
	h = ServerHarness.new()
	potion = Content.item(&"red_potion")
	# the field: a ledge up high, a chest and a wall on the floor, and the near end of a
	# shortcut that drops you into the town
	var field := ServerHarness.field_def()
	field.platforms.append(ServerHarness.platform(1500.0, LEDGE_Y, 400.0))
	field.portals.append(_portal(NEAR_X, ServerHarness.TOWN, 600.0, 0, &"", &"test_drop"))
	field.breakables.append(_breakable(&"test_chest", CHEST_X, 2, [ServerHarness.drop(potion, 3)]))
	field.breakables.append(_breakable(&"test_wall", WALL_X, 3, []))
	field.portals.append(_portal(WALL_X, ServerHarness.TOWN, 900.0, 0, &"test_wall"))
	h.add_map(field)
	# the town: the far end of the drop, up to the field's ledge, and a plain way back
	var town := ServerHarness.town_def()
	town.portals.append(_portal(FAR_X, ServerHarness.FIELD, 1600.0, 1, &"test_drop"))
	town.portals.append(_portal(200.0, ServerHarness.FIELD, 300.0))
	h.add_map(town)
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	c = p.character

func after_each() -> void:
	h.close()

func _portal(x: float, to: StringName, to_x: float, to_platform := 0, shortcut := &"", opens := &"") -> PortalDef:
	var d := PortalDef.new()
	d.x = x
	d.target_map = to
	d.target_x = to_x
	d.target_platform = to_platform
	d.shortcut = shortcut
	d.opens_shortcut = opens
	return d

func _breakable(id: StringName, x: float, hits: int, loot: Array) -> BreakableDef:
	var b := BreakableDef.new()
	b.id = id
	b.x = x
	b.hits = hits
	for e: DropEntry in loot:
		b.loot.append(e)
	return b

## `who` swings their basic attack where they stand, facing right, and the swing recovers.
func _hit(who: SimPlayer) -> void:
	who.face = 1
	h.ask(who.peer, &"req_skill", [&"basic_attack", who.position, who.face])
	h.step(60)

func _portal_from(who: SimPlayer, x: float, y := ServerHarness.GROUND) -> void:
	h.place(who, x, y)
	h.ask(who.peer, &"req_portal")

# ---------- arriving up high ----------

func test_a_portal_can_land_you_on_a_raised_platform() -> void:
	c.find_secret(&"test_drop")
	h.move_to(p, ServerHarness.TOWN, 600.0)
	_portal_from(p, FAR_X)
	check_eq(p.map.def.id, ServerHarness.FIELD, "back on the field")
	check_eq(p.position, Vector2(1600.0, LEDGE_Y), "standing on the ledge")
	check_eq(h.last(2, &"ev_enter_map")[3], 1, "the client is told which platform")

# ---------- shortcuts ----------

func test_a_shortcut_stays_shut_from_its_far_end_until_found() -> void:
	h.move_to(p, ServerHarness.TOWN, 600.0)
	_portal_from(p, FAR_X)
	check_eq(p.map.def.id, ServerHarness.TOWN, "the far end doesn't open")

func test_going_through_the_near_end_finds_the_shortcut() -> void:
	_portal_from(p, NEAR_X)
	check_eq(p.map.def.id, ServerHarness.TOWN, "dropped into the town")
	check(c.found_secret(&"test_drop"), "the shortcut is found")
	check(h.told(2, "You found a shortcut."), "told")
	h.clear()
	_portal_from(p, FAR_X)
	check_eq(p.map.def.id, ServerHarness.FIELD, "and its far end leads back now")

func test_a_shortcut_is_only_found_once() -> void:
	_portal_from(p, NEAR_X)
	h.move_to(p, ServerHarness.FIELD, 300.0)
	h.clear()
	_portal_from(p, NEAR_X)
	check(not h.told(2, "You found a shortcut."), "not told twice")

# ---------- chests and walls ----------

func test_a_chest_shakes_until_its_last_blow_breaks_it_open() -> void:
	h.place(p, CHEST_X - 40.0)
	_hit(p)
	check_eq(h.last(2, &"ev_struck"), [0, false], "the first blow shakes it")
	check(not c.found_secret(&"test_chest"), "still shut")
	_hit(p)
	check_eq(h.last(2, &"ev_struck"), [0, true], "the second breaks it")
	check(c.found_secret(&"test_chest"), "opened for good")

func test_a_broken_chest_spills_its_loot_for_whoever_broke_it() -> void:
	h.place(p, CHEST_X - 40.0)
	_hit(p)
	_hit(p)
	var drops: Array = p.map.drops.values()
	check_eq(drops.size(), 1, "one drop")
	check_eq([drops[0].item, drops[0].amount, drops[0].owner], [potion, 3, 2], "three potions, Ann's")

func test_a_broken_chest_takes_no_more_blows() -> void:
	c.find_secret(&"test_chest")
	h.place(p, CHEST_X - 40.0)
	_hit(p)
	check_eq(h.count(2, &"ev_struck"), 0, "nothing to hit")
	check(p.map.drops.is_empty(), "and nothing spills")

func test_a_chest_card_spills_until_the_page_is_complete() -> void:
	var boar := Content.monster(&"bramble_boar")
	p.map.def.breakables[0].card = boar
	h.place(p, CHEST_X - 40.0)
	_hit(p)
	_hit(p)
	check(p.map.drops.values().any(func(d: SimDrop) -> bool: return d.item == Content.card(boar)), "its Monster Book card spills")
	p.map.def.breakables[0].card = null

func test_breaking_a_wall_opens_its_shortcut() -> void:
	h.place(p, WALL_X - 40.0)
	for i in 2:
		_hit(p)
	check(not p.map.def.portals[1].open_to(c), "the way behind it is still shut")
	_hit(p)
	check(c.found_secret(&"test_wall"), "the wall is broken")
	check(p.map.def.portals[1].open_to(c), "the way behind it opens")
	check(h.told(2, "You found a shortcut."), "told")

func test_everyone_breaks_their_own() -> void:
	var bob := h.join(3, "Bob", ServerHarness.FIELD, CHEST_X - 40.0)
	h.place(p, CHEST_X - 40.0)
	_hit(p)
	_hit(bob)
	check_eq(h.last(3, &"ev_struck"), [0, false], "Ann's blow doesn't count for Bob")
	_hit(p)
	check(c.found_secret(&"test_chest") and not bob.character.found_secret(&"test_chest"), "only Ann's is open")
	check_eq(h.count(3, &"ev_struck"), 1, "Bob doesn't see Ann's break")

func test_blows_are_forgotten_when_you_leave_the_map() -> void:
	h.place(p, CHEST_X - 40.0)
	_hit(p)
	h.move_to(p, ServerHarness.TOWN, 600.0)
	h.move_to(p, ServerHarness.FIELD, 300.0)
	h.place(p, CHEST_X - 40.0)
	h.clear()
	_hit(p)
	check_eq(h.last(2, &"ev_struck"), [0, false], "it takes both blows again")

func test_secrets_are_saved_with_the_character() -> void:
	c.find_secret(&"test_chest")
	var copy := Character.new()
	copy.load_dict(c.to_dict())
	check(copy.found_secret(&"test_chest"), "still found after a save and load")
	check(not copy.found_secret(&"test_wall"), "and nothing else")
