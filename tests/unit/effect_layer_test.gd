extends TestCase
## Skill effects play on the characters' plane: in front of the hero, with their solid parts
## recording depth so the depth of field keeps them sharp instead of blurring them into the
## scenery behind (TDStage.effect_sprite).

func test_skill_effect_plays_in_front_of_the_hero_and_records_depth() -> void:
	var skill: SkillDef = load("res://data/skills/power_strike.tres")
	for def: EffectDef in [skill.effect, skill.hit_effect]:
		var e := TDEffect.create(null, def, Vector2(100, 200), 1)
		e._ready()
		check(e.sprite.position.z > TDStage.Z_PLAYER, "%s draws in front of the hero" % def.id)
		check_eq(e.sprite.alpha_cut, SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "%s records its depth" % def.id)
		e.free()

func test_projectile_records_depth() -> void:
	var def: ProjectileDef = (load("res://data/skills/star_throw.tres") as SkillDef).projectile
	var p := TDProjectile.create(null, def, Vector2.ZERO, Vector2(100, 0), 0, null, Callable())
	p._ready()
	check_eq(p.sprite.alpha_cut, SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "the star records its depth")
	p.free()
