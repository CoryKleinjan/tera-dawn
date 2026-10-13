extends TestCase
## Movement skills on the server: a Charge shoves monsters aside without hurting them, a
## Blink puts the player where it lands, a roll keeps them from being hit, and all of them
## cost MP and show on everyone's screen.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var map: MapInstance
var p: SimPlayer
var mob: SimMob

func before_each() -> void:
	h = ServerHarness.new()
	var d := ServerHarness.monster(&"test_mob", 1000)
	map = h.field_with([ServerHarness.spawn(d, 1)])
	p = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(p, d)
	mob = map.mobs[0]
	mob.position = p.position + Vector2(400, 0)

func after_each() -> void:
	h.close()

func _use(id: StringName, aim := Hitbox.Aim.AHEAD) -> void:
	p.character.skills.learned[id] = 1
	p.character.mp = 999
	p.cooldown = 0
	h.ask(2, &"req_skill", [id, p.position, p.face, aim])

func test_charge_shoves_without_damage() -> void:
	mob.position = p.position + Vector2(60, 0)
	_use(&"charge")
	check_eq(mob.health.hp, 1000, "no damage")
	check(mob.kx > SimMob.KNOCKBACK, "shoved away, harder than a hit")
	check_eq(p.character.mp, 999 - Content.skill(&"charge").mp_at(1), "MP paid")
	check_eq(h.last(2, &"ev_skill")[5], [], "no damage shown")

func test_charge_leaves_monsters_behind_alone() -> void:
	mob.position = p.position + Vector2(-80, 0)
	_use(&"charge")
	check_eq(mob.kx, 0.0, "not shoved")

func test_blink_puts_you_where_it_lands() -> void:
	var from := p.position
	_use(&"blink", Hitbox.Aim.UP)
	var want := Content.skill(&"blink").move.blink_to(from, 1, Hitbox.Aim.UP, 1, float(map.def.width), float(map.def.ground_y))
	check_eq(p.position, want, "up where the client lands")
	h.step(3)
	h.ask(2, &"req_move", [want + Vector2(0, 3), 1, &"fall", false])
	check_eq(p.position, want + Vector2(0, 3), "and the next report from there is fine")

func test_a_roll_cannot_be_hit() -> void:
	_use(&"rolling_dash")
	var hp := p.character.health.hp
	map.hurt_player(p, mob.def, mob.position.x)
	check_eq(p.character.health.hp, hp, "not hurt mid-roll")
	h.step(Content.skill(&"rolling_dash").move.ticks)
	map.hurt_player(p, mob.def, mob.position.x)
	check(p.character.health.hp < hp or p.inv > 0, "hit again once it's over")

func test_everyone_sees_a_move() -> void:
	h.join(3, "Bob", ServerHarness.FIELD, 900.0)
	_use(&"flash_jump")
	check_eq(h.count(3, &"ev_skill"), 1, "Bob is told")
