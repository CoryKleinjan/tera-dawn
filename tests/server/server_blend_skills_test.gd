extends TestCase
## The second-tier (blend) skills through the server: hitting all round (Blade Storm), hexes
## (Hex, Starfall), roots (Wrath of the Grove), Elemental Edge's fire, ice and lightning,
## streaks (Lucky Streak), bouncing shots (Ricochet) and marks (Hunter's Mark).

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var mob_def: MonsterDef
var map: MapInstance
var ann: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

## `xs`: where each monster stands; Ann stands at 300 facing right.
func _setup(xs: Array, hp := 100000) -> void:
	mob_def = ServerHarness.monster(&"test_mob", hp, 10)
	mob_def.attack = 40
	map = h.field_with([ServerHarness.spawn(mob_def, xs.size())])
	for i in xs.size():
		map.mobs[i].position.x = xs[i]
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ann.face = 1
	ServerHarness.no_cards(ann, mob_def)

func _use(id: StringName, lvl := 1) -> void:
	ann.character.skills.learned[id] = lvl
	ann.character.mp = 999
	ann.cooldown = 0
	ann.recharge.clear()
	h.ask(ann.peer, &"req_skill", [id, ann.position, ann.face, Hitbox.Aim.AHEAD])

## {mob index: number of damage lines} in the last ev_skill.
func _lines() -> Dictionary:
	var out := {}
	for row: Array in h.last(2, &"ev_skill")[5]:
		out[row[0]] = (row[1] as Array).size()
	return out

func test_blade_storm_hits_on_both_sides() -> void:
	_setup([380.0, 220.0, 900.0])
	_use(&"blade_storm")
	var lines := _lines()
	check(lines.has(0), "the monster ahead")
	check(lines.has(1), "and the one behind")
	check(not lines.has(2), "but not one far away")
	check_eq(lines.get(1, 0), Content.skill(&"blade_storm").hits, "every hit lands on the one behind")

func test_hex_makes_monsters_take_more_damage() -> void:
	_setup([380.0])
	_use(&"hex", 10)
	var m := map.mobs[0]
	var hex := Content.skill(&"hex")
	check(m.hexed(), "hexed")
	check_eq(m.hex_t, hex.hex_ticks(10), "for its time")
	check_near(m.damage_taken(), 1.0 + hex.hex_at(10), "takes more damage")

func test_starfall_hits_a_hexed_monster_once_more() -> void:
	_setup([380.0, 420.0])
	map.mobs[0].hex(0.1, 600)
	_use(&"starfall")
	var lines := _lines()
	var star := Content.skill(&"starfall")
	check_eq(lines.get(0, 0), star.hits + star.hexed_extra_hits, "the hexed one takes an extra star")
	check_eq(lines.get(1, 0), star.hits, "the other the usual stars")

func test_wrath_of_the_grove_roots_what_it_hits() -> void:
	_setup([500.0, 120.0])
	_use(&"wrath_of_the_grove")
	for m in map.mobs:
		check_eq(m.root_t, Content.skill(&"wrath_of_the_grove").root_ticks(1), "rooted, ahead and behind")
	var x := map.mobs[0].position.x
	map.mobs[0].hurt_t = 0
	h.step(30)
	check_eq(map.mobs[0].position.x, x, "a rooted monster doesn't move")

func test_elemental_edge_cycles_fire_ice_lightning() -> void:
	_setup([380.0])
	var book := ann.character.skills
	_use(&"elemental_edge")
	check_eq(book.element, SkillBook.Element.FIRE, "the first cast is fire")
	_use(&"elemental_edge")
	check_eq(book.element, SkillBook.Element.ICE, "then ice")
	_use(&"elemental_edge")
	check_eq(book.element, SkillBook.Element.LIGHTNING, "then lightning")
	_use(&"elemental_edge")
	check_eq(book.element, SkillBook.Element.FIRE, "and round to fire")

func test_fire_edge_sets_monsters_burning() -> void:
	_setup([380.0])
	ann.character.base.strength = 400
	ann.character.recalc()
	_use(&"elemental_edge", 10)
	_use(&"sunfall_blade")
	var m := map.mobs[0]
	check(m.burn_t > 0 and m.burn_damage > 0, "burning")
	var hp := m.health.hp
	h.step(SimMob.BURN_EVERY)
	check_eq(m.health.hp, hp - m.burn_damage, "and the burn bites once a second")

func test_ice_edge_chills_what_it_hits() -> void:
	_setup([380.0])
	_use(&"elemental_edge")
	_use(&"elemental_edge")
	_use(&"sunfall_blade")
	check_eq(map.mobs[0].slow_t, Content.skill(&"elemental_edge").slow_ticks(1), "slowed")

func test_lightning_edge_sparks_to_one_more_monster() -> void:
	_setup([380.0, 560.0, 1200.0])
	for i in 3:
		_use(&"elemental_edge")
	_use(&"hunters_mark")
	var lines := _lines()
	check(lines.has(0), "the shot hits the nearest")
	check_eq(lines.get(1, 0), 1, "and a spark jumps to the next one")
	check(not lines.has(2), "but not across the map")

func test_ricochet_bounces_shots_on() -> void:
	_setup([380.0, 560.0])
	ann.character.skills.learned[&"ricochet"] = 1
	_use(&"hunters_mark")
	var lines := _lines()
	check(lines.has(0) and lines.has(1), "the shot bounces from the first to the second")
	ann.character.skills.learned.erase(&"ricochet")
	_use(&"hunters_mark")
	check(not _lines().has(1), "without Ricochet it doesn't")

func test_ricochet_leaves_melee_alone() -> void:
	_setup([380.0, 560.0])
	ann.character.skills.learned[&"ricochet"] = 10
	_use(&"blade_storm")
	check(not _lines().has(1), "a blow doesn't bounce")

func test_lucky_streak_builds_and_breaks() -> void:
	_setup([380.0])
	ann.character.skills.learned[&"lucky_streak"] = 1
	for i in SkillDef.STREAK_MAX + 3:
		_use(&"blade_storm")
	check_eq(ann.streak, SkillDef.STREAK_MAX, "the streak stops at its most")
	ann.inv = 0
	ann.dodge_t = 0
	map.hurt_player(ann, mob_def, 380.0)
	check_eq(ann.streak, 0, "getting hit starts it over")

func test_hunters_mark_hits_harder_and_jumps_on() -> void:
	_setup([380.0, 520.0], 100000)
	_use(&"hunters_mark", 10)
	var mark := Content.skill(&"hunters_mark")
	check_eq(ann.mark, map.mobs[0].index, "the nearest is marked")
	check_near(ann.mark_boost(map.mobs[0]), 1.0 + mark.mark_bonus_at(10) + mark.mark_close_at(10), "close up it hits hardest")
	check_near(ann.mark_boost(map.mobs[1]), 1.0, "an unmarked monster takes the usual")
	map.mobs[0].health.damage(map.mobs[0].health.hp)
	map.kill_mob(map.mobs[0], ann)
	check_eq(ann.mark, map.mobs[1].index, "the mark jumps to the next one when it falls")
