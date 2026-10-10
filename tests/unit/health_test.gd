extends TestCase
## Health: damage never goes below zero and reports what was really lost, `died` fires
## once, healing stops at the maximum and can't wake the fainted, and changing the
## maximum never heals.

var hp: Health
var changes := 0
var deaths := 0

func before_each() -> void:
	hp = Health.new(100)
	changes = 0
	deaths = 0
	hp.changed.connect(func() -> void: changes += 1)
	hp.died.connect(func() -> void: deaths += 1)

func test_starts_full() -> void:
	check_eq(hp.max_hp, 100, "max")
	check_eq(hp.hp, 100, "full")
	check_near(hp.fraction(), 1.0, "fraction")
	check(not hp.is_dead(), "alive")

func test_damage_returns_what_was_lost() -> void:
	check_eq(hp.damage(30), 30, "lost 30")
	check_eq(hp.hp, 70, "70 left")
	check_eq(hp.damage(500), 70, "only what was left")
	check_eq(hp.hp, 0, "never below 0")
	check_eq(changes, 2, "changed each time")

func test_dying_fires_once() -> void:
	hp.damage(100)
	check(hp.is_dead(), "dead at 0")
	check_eq(deaths, 1, "died once")
	check_eq(hp.damage(10), 0, "no more damage")
	check_eq(deaths, 1, "not again")

func test_heal_stops_at_the_maximum() -> void:
	hp.damage(30)
	hp.heal(10)
	check_eq(hp.hp, 80, "healed 10")
	hp.heal(1000)
	check_eq(hp.hp, 100, "stops at max")

func test_heal_doesnt_wake_the_fainted() -> void:
	hp.damage(100)
	hp.heal(50)
	check_eq(hp.hp, 0, "still 0")
	check(hp.is_dead(), "still down")

func test_set_max_never_heals() -> void:
	hp.damage(50)
	hp.set_max(200)
	check_eq(hp.max_hp, 200, "new max")
	check_eq(hp.hp, 50, "same hp")
	hp.set_max(20)
	check_eq(hp.hp, 20, "cut down to the new max")
	hp.set_max(0)
	check_eq(hp.max_hp, 1, "max is at least 1")
	check_eq(hp.hp, 1, "and hp follows")

func test_reset_refills_and_can_change_the_maximum() -> void:
	hp.damage(100)
	hp.reset()
	check_eq(hp.hp, 100, "full again")
	check(not hp.is_dead(), "up again")
	hp.reset(150)
	check_eq(hp.max_hp, 150, "new max")
	check_eq(hp.hp, 150, "full at the new max")

func test_set_hp_is_kept_in_range() -> void:
	hp.set_hp(40)
	check_eq(hp.hp, 40, "set")
	hp.set_hp(-5)
	check_eq(hp.hp, 0, "not below 0")
	hp.set_hp(999)
	check_eq(hp.hp, 100, "not above max")

func test_fraction() -> void:
	hp.damage(25)
	check_near(hp.fraction(), 0.75, "three quarters")
