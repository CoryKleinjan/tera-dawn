extends TestCase
## Painted skill effects: a buff's aura loops round the player for as long as the buff
## lasts, and shots loop their painted frames in flight.

func _aura(lasts: int) -> TDEffect:
	var def: EffectDef = (load("res://data/skills/war_cry.tres") as SkillDef).aura
	var e := TDEffect.create(null, def, Vector2(100, 200), 1)
	e.lasts = lasts
	e._ready()
	return e

func test_every_timed_buff_has_an_aura() -> void:
	for s: SkillDef in Content.skills.values():
		if s.kind == SkillDef.Kind.BUFF and s.duration_ticks(1) > 0:
			check(s.aura != null, "%s lasts a while but shows no aura" % s.id)

func test_an_aura_loops_its_frames_until_the_buff_ends() -> void:
	var e := _aura(300)
	var seen := {}
	for i in 299:
		e.step()
		seen[e.sprite.texture] = true
	check(not e.is_queued_for_deletion(), "still showing while the buff lasts")
	check_eq(seen.size(), e.def.frames.size(), "every frame came round")
	check(e.sprite.transparency > 0.9, "faded out at the end")
	e.step()
	e.step()
	check(e.is_queued_for_deletion(), "gone once the buff ends")
	e.free()

func test_casting_again_fades_the_old_aura() -> void:
	var e := _aura(3000)
	for i in 20:
		e.step()
	e.fade()
	for i in TDEffect.AURA_FADE_OUT + 1:
		e.step()
	check(e.is_queued_for_deletion(), "the old aura made way")
	e.free()

func test_a_shot_loops_its_painted_frames() -> void:
	var def: ProjectileDef = (load("res://data/skills/fire_burst.tres") as SkillDef).projectile
	check(def.frames.size() > 1, "the fireball is painted as frames")
	var p := TDProjectile.create(null, def, Vector2.ZERO, Vector2(100000, 0), 0, null, Callable())
	p._ready()
	var seen := {}
	for i in 60:
		p.step()
		seen[p.sprite.texture] = true
	check_eq(seen.size(), def.frames.size(), "every frame came round in a second of flight")
	p.free()
