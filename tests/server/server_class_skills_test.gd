extends TestCase
## The first jobs' skills through the server: party buffs, skills with their own recharge,
## hiding (Dark Sight), MP shielding (Magic Guard), slowing (Ice Spike), bursts around a
## target (Fire Burst), attack speed (All Hands) and off-hand gear.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var mob_def: MonsterDef
var map: MapInstance
var ann: SimPlayer
var bob: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

func _setup(mobs := 1, x := 400.0) -> void:
	mob_def = ServerHarness.monster(&"test_mob", 1000, 10)
	mob_def.attack = 40
	map = h.field_with([ServerHarness.spawn(mob_def, mobs)])
	for i in map.mobs.size():
		map.mobs[i].position.x = x + i * 30.0
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	ServerHarness.no_cards(ann, mob_def)

func _use(p: SimPlayer, id: StringName, lvl := 1) -> void:
	p.character.skills.learned[id] = lvl
	p.character.mp = 999
	p.cooldown = 0
	h.ask(p.peer, &"req_skill", [id, p.position, p.face, Hitbox.Aim.AHEAD])

func _party(a: int, b: int) -> void:
	h.ask(a, &"req_social", [&"party", h.server.sessions[b].character.name])
	var inv := h.last(b, &"ev_invite")
	h.ask(b, &"req_invite_answer", [inv[0], true])

# ---------- party buffs ----------

func test_a_party_buff_reaches_party_members_nearby() -> void:
	_setup()
	bob = h.join(3, "Bob", ServerHarness.FIELD, 700.0)
	var cat := h.join(4, "Cat", ServerHarness.FIELD, 500.0)
	_party(2, 3)
	var attack := bob.character.stats.attack
	_use(ann, &"war_cry", 4)
	var cry := Content.skill(&"war_cry")
	check_eq(ann.character.skills.buffs.get(cry.id, [0])[0], 4, "Ann has it")
	check_eq(bob.character.skills.buffs.get(cry.id, [0])[0], 4, "Bob, in her party, gets it at her level")
	check_eq(bob.character.stats.attack, attack + cry.stats_at(4).attack, "and his Weapon Attack rises")
	check(not cat.character.skills.buffs.has(cry.id), "Cat isn't in the party")

func test_a_party_buff_misses_party_members_far_away() -> void:
	_setup()
	bob = h.join(3, "Bob", ServerHarness.FIELD, 300.0 + SkillDef.PARTY_REACH + 60.0)
	_party(2, 3)
	_use(ann, &"haste")
	check(ann.character.skills.buffs.has(&"haste"), "Ann has it")
	check(not bob.character.skills.buffs.has(&"haste"), "Bob is too far away")

func test_a_self_buff_stays_with_the_caster() -> void:
	_setup()
	bob = h.join(3, "Bob", ServerHarness.FIELD, 400.0)
	_party(2, 3)
	_use(ann, &"iron_body")
	check(ann.character.skills.steady(), "Ann can't be knocked back")
	check(not bob.character.skills.buffs.has(&"iron_body"), "Bob doesn't get it")

# ---------- recharge ----------

func test_first_aid_heals_then_waits_for_its_recharge() -> void:
	_setup()
	var c := ann.character
	c.health.damage(c.max_hp() - 1)
	_use(ann, &"first_aid")
	var aid := Content.skill(&"first_aid")
	check_eq(c.health.hp, 1 + roundi(c.max_hp() * aid.heal_at(1)), "healed")
	check(c.skills.buffs.is_empty(), "nothing lingers after the heal")
	h.step(aid.cooldown + 1)
	c.health.damage(c.health.hp - 1)
	_use(ann, &"first_aid")
	check_eq(c.health.hp, 1, "still recharging")
	h.step(aid.recharge_ticks(1))
	c.health.damage(c.health.hp - 1)
	_use(ann, &"first_aid")
	check_eq(c.health.hp, 1 + roundi(c.max_hp() * aid.heal_at(1)), "ready again")

# ---------- Dark Sight ----------

func test_dark_sight_hides_you_until_you_attack() -> void:
	_setup(1, 310.0)
	var mob: SimMob = map.mobs[0]
	_use(ann, &"dark_sight")
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

# ---------- Magic Guard ----------

func test_magic_guard_takes_part_of_a_hit_out_of_mp() -> void:
	_setup()
	_use(ann, &"magic_guard")
	var c := ann.character
	var guard := c.skills.mp_guard()
	check_near(guard, Content.skill(&"magic_guard").mp_guard_at(1), "guarding")
	c.base.avoid = -999
	c.recalc()
	c.mp = c.max_mp()
	var mp := c.mp
	var hp := c.health.hp
	map.hurt_player(ann, mob_def, 400.0)
	var lost_hp := hp - c.health.hp
	var lost_mp := mp - c.mp
	check(lost_mp > 0, "MP took some")
	check_eq(lost_mp, roundi((lost_hp + lost_mp) * guard), "its share")

func test_magic_guard_lets_hp_take_the_rest_once_mp_runs_out() -> void:
	_setup()
	_use(ann, &"magic_guard", 8)
	var c := ann.character
	c.mp = 0
	var hp := c.health.hp
	c.base.avoid = -999
	c.recalc()
	map.hurt_player(ann, mob_def, 400.0)
	check(c.health.hp < hp, "no MP, so HP takes it all")

# ---------- attacks ----------

func test_ice_spike_slows_what_it_hits() -> void:
	_setup()
	_use(ann, &"ice_spike")
	check(map.mobs[0].slow_t > 0, "slowed")
	check_eq(map.mobs[0].slow_t, Content.skill(&"ice_spike").slow_ticks(1), "for its time")

func test_fire_burst_hits_up_to_five_around_the_first() -> void:
	_setup(7, 400.0)
	var burst := Content.skill(&"fire_burst")
	map.mobs[6].position.x = 400.0 + burst.splash + 120.0
	_use(ann, &"fire_burst")
	var hit: Array = h.last(2, &"ev_skill")[5]
	check_eq(hit.size(), burst.max_targets, "five hit")
	check(not map.mobs[6].index in hit.map(func(e: Array) -> int: return e[0]), "not the one outside the burst")

func test_all_hands_makes_attacks_come_sooner() -> void:
	_setup()
	_use(ann, &"basic_attack")
	var plain := ann.cooldown
	_use(ann, &"all_hands", 8)
	_use(ann, &"basic_attack")
	check(ann.cooldown < plain, "shorter cooldown (%d < %d)" % [ann.cooldown, plain])

func test_an_off_hand_skill_needs_its_off_hand() -> void:
	_setup()
	_use(ann, &"star_scatter")
	check(h.told(2, "Star Scatter needs throwing stars in your off-hand slot."), "told what's missing")
	ann.character.equipment.put(&"shield", ItemStack.exact(Content.item(&"iron_star")))
	ann.character.recalc()
	ann.recharge.clear()
	_use(ann, &"star_scatter")
	check_eq(h.last(2, &"ev_skill")[1], &"star_scatter", "thrown with stars in the off-hand slot")
