extends TestCase
## Skill machinery through the server, with skills made for the test: party buffs, skills with
## their own recharge, hiding, slowing, bursts around a target, attack speed and off-hand
## gear.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var u := UnitHelpers.new()
var mob_def: MonsterDef
var map: MapInstance
var ann: SimPlayer
var bob: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()
	u.cleanup()

func _setup(mobs := 1, x := 400.0) -> void:
	mob_def = ServerHarness.monster(&"test_mob", 1000)
	mob_def.attack = 40
	map = h.field_with([ServerHarness.spawn(mob_def, mobs)])
	for i in map.mobs.size():
		map.mobs[i].position.x = x + i * 30.0
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(ann, mob_def)

## A buff made for the test, cast with the spell motion and lasting `seconds`.
func _buff(id: StringName, seconds := 60.0) -> SkillDef:
	var s := u.skill(id, SkillDef.Kind.BUFF)
	s.animation = SkillDef.SPELL
	s.duration = seconds
	return s

## A ranged attack made for the test.
func _shot(id: StringName) -> SkillDef:
	var s := u.skill(id)
	s.reach = 340.0
	s.projectile = ProjectileDef.new()
	return s

func _use(p: SimPlayer, id: StringName, lvl := 1) -> void:
	p.character.skills.learned[id] = lvl
	p.character.mp = p.character.max_mp()
	p.cooldown = 0
	h.ask(p.peer, &"req_skill", [id, p.position, p.face, Hitbox.Aim.AHEAD])

func _party(a: int, b: int) -> void:
	h.ask(a, &"req_social", [&"party", h.server.sessions[b].character.name])
	var inv := h.last(b, &"ev_invite")
	h.ask(b, &"req_invite_answer", [inv[0], true])

# ---------- party buffs ----------

func test_a_party_buff_reaches_party_members_nearby() -> void:
	_setup()
	var cry := _buff(&"t_cry")
	cry.party = true
	cry.stats = UnitHelpers.stats({"attack": 6})
	cry.stats_per_level = UnitHelpers.stats({"attack": 2})
	bob = h.join(3, "Bob", ServerHarness.FIELD, 700.0)
	var cat := h.join(4, "Cat", ServerHarness.FIELD, 500.0)
	_party(2, 3)
	var attack := bob.character.stats.attack
	_use(ann, cry.id, 4)
	check_eq(ann.character.skills.buffs.get(cry.id, [0])[0], 4, "Ann has it")
	check_eq(bob.character.skills.buffs.get(cry.id, [0])[0], 4, "Bob, in her party, gets it at her level")
	check_eq(bob.character.stats.attack, attack + cry.stats_at(4).attack, "and his Weapon Attack rises")
	check(not cat.character.skills.buffs.has(cry.id), "Cat isn't in the party")

func test_a_party_buff_misses_party_members_far_away() -> void:
	_setup()
	var haste := _buff(&"t_haste")
	haste.party = true
	bob = h.join(3, "Bob", ServerHarness.FIELD, 300.0 + SkillDef.PARTY_REACH + 60.0)
	_party(2, 3)
	_use(ann, haste.id)
	check(ann.character.skills.buffs.has(haste.id), "Ann has it")
	check(not bob.character.skills.buffs.has(haste.id), "Bob is too far away")

func test_a_self_buff_stays_with_the_caster() -> void:
	_setup()
	var iron := _buff(&"t_iron")
	iron.steady = true
	bob = h.join(3, "Bob", ServerHarness.FIELD, 400.0)
	_party(2, 3)
	_use(ann, iron.id)
	check(ann.character.skills.steady(), "Ann can't be knocked back")
	check(not bob.character.skills.buffs.has(iron.id), "Bob doesn't get it")

# ---------- recharge ----------

func test_a_heal_waits_for_its_recharge() -> void:
	_setup()
	var aid := _buff(&"t_aid", 0.0)
	aid.heal = 0.5
	aid.recharge = 60.0
	var c := ann.character
	c.health.damage(c.max_hp() - 1)
	_use(ann, aid.id)
	check_eq(c.health.hp, 1 + roundi(c.max_hp() * aid.heal_at(1)), "healed")
	check(c.skills.buffs.is_empty(), "nothing lingers after the heal")
	h.step(aid.cooldown + 1)
	c.health.damage(c.health.hp - 1)
	_use(ann, aid.id)
	check_eq(c.health.hp, 1, "still recharging")
	h.step(aid.recharge_ticks(1))
	c.health.damage(c.health.hp - 1)
	_use(ann, aid.id)
	check_eq(c.health.hp, 1 + roundi(c.max_hp() * aid.heal_at(1)), "ready again")

# ---------- hiding ----------

func test_a_hiding_buff_hides_you_until_you_attack() -> void:
	_setup(1, 310.0)
	var sight := _buff(&"t_sight", 3.0)
	sight.hide = true
	var mob: SimMob = map.mobs[0]
	_use(ann, sight.id)
	check(ann.hidden(), "hidden")
	check(ann.motion()[5] & SnapshotFlags.PLAYER_HIDDEN, "others are told")
	check(not mob.can_target(ann), "monsters can't see Ann")
	var hp := ann.character.health.hp
	map.hurt_player(ann, mob_def, mob.position.x)
	check_eq(ann.character.health.hp, hp, "or touch her")
	h.step(30)
	_use(ann, &"basic_attack")
	check(not ann.hidden(), "attacking gives her away")
	check(mob.can_target(ann), "seen again")

# ---------- attacks ----------

func test_a_slowing_shot_slows_what_it_hits() -> void:
	_setup()
	var spike := _shot(&"t_spike")
	spike.slow = 1.0
	_use(ann, spike.id)
	check(map.mobs[0].slow_t > 0, "slowed")
	check_eq(map.mobs[0].slow_t, spike.slow_ticks(1), "for its time")

func test_a_burst_hits_up_to_its_targets_around_the_first() -> void:
	_setup(7, 400.0)
	var burst := _shot(&"t_burst")
	burst.max_targets = 5
	burst.splash = 140.0
	map.mobs[6].position.x = 400.0 + burst.splash + 120.0
	_use(ann, burst.id)
	var hit: Array = h.last(2, &"ev_skill")[5]
	check_eq(hit.size(), burst.max_targets, "five hit")
	check(not map.mobs[6].index in hit.map(func(e: Array) -> int: return e[0]), "not the one outside the burst")

func test_attack_speed_makes_attacks_come_sooner() -> void:
	_setup()
	var hands := _buff(&"t_hands")
	hands.stats = UnitHelpers.stats({"attack_speed": 25})
	_use(ann, &"basic_attack")
	var plain := ann.cooldown
	_use(ann, hands.id)
	_use(ann, &"basic_attack")
	check(ann.cooldown < plain, "shorter cooldown (%d < %d)" % [ann.cooldown, plain])

func test_throwing_stars_need_nothing_but_the_skill() -> void:
	_setup()
	var scatter := _shot(&"t_scatter")
	_use(ann, scatter.id)
	check_eq(h.last(2, &"ev_skill")[1], scatter.id, "thrown with no off-hand (there is none) and no ammo")
