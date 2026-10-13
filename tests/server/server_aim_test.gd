extends TestCase
## Aimed attacks on the server: holding up hits a monster overhead, down (in the air) one
## below, and ahead stays ahead; buffs don't aim; melee blows knock harder than shots.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var map: MapInstance
var p: SimPlayer
var mob: SimMob

func before_each() -> void:
	h = ServerHarness.new()
	var d := ServerHarness.monster(&"test_mob", 100000)
	map = h.field_with([ServerHarness.spawn(d, 1)])
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(p, d)
	mob = map.mobs[0]

func after_each() -> void:
	h.close()

## Puts the monster `offset` from Ann's feet.
func _mob_at(offset: Vector2) -> void:
	mob.position = p.position + offset

func _attack(aim: Hitbox.Aim, skill := &"basic_attack") -> Array:
	p.cooldown = 0
	h.ask(2, &"req_skill", [skill, p.position, p.face, aim])
	return h.last(2, &"ev_skill")

func test_up_hits_a_monster_overhead() -> void:
	_mob_at(Vector2(0, -110))
	check_eq(_attack(Hitbox.Aim.AHEAD)[5], [], "a swing ahead misses it")
	var ev := _attack(Hitbox.Aim.UP)
	check_eq((ev[5] as Array).size(), 1, "an upward swing hits it")
	check_eq(ev[6], Hitbox.Aim.UP, "everyone is told it went up")

func test_down_hits_a_monster_below() -> void:
	_mob_at(Vector2(0, 70))
	check_eq(_attack(Hitbox.Aim.AHEAD)[5], [], "a swing ahead misses it")
	check_eq((_attack(Hitbox.Aim.DOWN)[5] as Array).size(), 1, "a downward swing hits it")

func test_up_misses_a_monster_ahead() -> void:
	_mob_at(Vector2(75, 0))
	check_eq((_attack(Hitbox.Aim.AHEAD)[5] as Array).size(), 1, "ahead hits it")
	check_eq(_attack(Hitbox.Aim.UP)[5], [], "up doesn't")

func test_a_buff_never_aims() -> void:
	var skill := Content.skill(&"quick_step")
	p.character.skills.learned[skill.id] = 1
	check_eq(_attack(Hitbox.Aim.UP, skill.id)[6], Hitbox.Aim.AHEAD, "shown ahead")

func test_a_nonsense_aim_counts_as_ahead() -> void:
	_mob_at(Vector2(60, 0))
	var ev := _attack(99 as Hitbox.Aim)
	check_eq(ev[6], Hitbox.Aim.DOWN, "kept to a real aim")
	check_eq(_attack(-5 as Hitbox.Aim)[6], Hitbox.Aim.AHEAD, "and from below")

func test_melee_knocks_harder_than_a_shot() -> void:
	_mob_at(Vector2(60, 0))
	_attack(Hitbox.Aim.AHEAD)
	var melee := absf(mob.kx)
	p.character.skills.learned[&"pebble_toss"] = 1
	p.character.mp = 999
	_attack(Hitbox.Aim.AHEAD, &"pebble_toss")
	check_near(absf(mob.kx), SimMob.KNOCKBACK, "a shot pushes the usual amount")
	check_near(melee, SimMob.KNOCKBACK * MapInstance.MELEE_KNOCKBACK, "a blow pushes harder")

func test_up_and_down_push_the_monster_away_from_you() -> void:
	_mob_at(Vector2(-10, -110))
	_attack(Hitbox.Aim.UP)
	check(mob.kx < 0.0, "pushed left, though Ann faces right")
