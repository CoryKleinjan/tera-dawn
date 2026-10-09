class_name TDWorldFx
extends RefCounted
## How TDWorld shows the server's events: swings, projectiles, damage numbers, monster
## shots and deaths, level-ups and other effects. Everything it spawns goes on the
## world's fx layer.

var world: TDWorld

func _init(w: TDWorld) -> void:
	world = w

## Someone used a skill: their swing (yours already showed), then the damage on each
## monster hit. `lines` is [[mob index, [[damage, kind], ...]], ...].
func show_skill(peer: int, skill: SkillDef, at: Vector2, face: int, lines: Array) -> void:
	if skill == null:
		return
	var who := world.actor(peer)
	if who is TDAvatar:
		(who as TDAvatar).play_skill(skill)
		add_effect(skill.effect, at + Vector2(0, -40), face)
	var views := world.mobs()
	var from := at + Vector2(face * 20, -42)
	if skill.projectile and lines.is_empty():
		# nothing in range: it flies off and fades
		for i in skill.hits:
			world.fx_layer.add_child(TDProjectile.create(world, skill.projectile, from, from + Vector2(face * skill.projectile.max_range, 0), i * 7, null, Callable()))
	for line in lines:
		var m: TDMob = views[line[0]] if line[0] < views.size() else null
		if m == null:
			continue
		var hits: Array = line[1]
		if skill.projectile == null:
			_show_hits(skill, m, hits, face)
			continue
		# each hit lands with its own projectile
		for i in hits.size():
			m.incoming += 1
			var land := func() -> void:
				m.incoming -= 1
				_show_hits(skill, m, [hits[i]], face, i)
			world.fx_layer.add_child(TDProjectile.create(world, skill.projectile, from, Vector2.ZERO, i * 7, m, land))

## Damage numbers and hit effects for `hits` on monster `m` (`first` stacks numbers above
## earlier ones).
func _show_hits(skill: SkillDef, m: TDMob, hits: Array, face: int, first := 0) -> void:
	var mid := m.body_position() + Vector2(0, -m.def.size.y / 2.0)
	for i in hits.size():
		var kind: String = hits[i][1]
		add_number(m.body_position() + Vector2(0, -m.def.size.y - 10 - (first + i) * 30), hits[i][0], kind)
		if kind == "crit":
			add_effect(Content.effect(&"critical"), mid, face)
	add_effect(skill.hit_effect, mid, face)

## Monster `index` fired its shot at the point `aim`.
func show_mob_shot(index: int, aim: Vector2) -> void:
	var views := world.mobs()
	if index >= views.size() or views[index].def.shot == null:
		return
	var m := views[index]
	m.dir = -1 if aim.x < m.position.x else 1
	var from := m.body_position() + Vector2(m.dir * m.def.size.x * 0.4, -m.def.size.y * 0.55)
	world.fx_layer.add_child(TDProjectile.create(world, m.def.shot, from, aim, 0, null, Callable()))

func show_mob_death(index: int) -> void:
	var views := world.mobs()
	if index < views.size():
		var m := views[index]
		m.kill()
		add_effect(Content.effect(&"monster_poof"), m.body_position() + Vector2(0, -m.def.size.y / 2.0), 1)

func show_level_up(peer: int, _level: int) -> void:
	var who := world.actor(peer)
	if who == null:
		return
	add_effect(Content.effect(&"level_up"), who.position, 1, who)
	if who == world.player:
		world.player.level_up()

## A small "+9 EXP" or "+8 Dawnshards" rising over your hero; gains that arrive together
## stack upwards instead of covering each other.
func show_gain(kind: StringName, amount: int) -> void:
	var young := 0
	for f in world.fx_layer.get_children():
		if f is TDFloatText and (f as TDFloatText).is_gain() and f.t < TDFloatText.GAIN_STACK_TICKS:
			young += 1
	var n := TDFloatText.new()
	n.world = world
	n.position = world.player.position + Vector2(0, -96 - young * 14)
	n.value = amount
	n.kind = String(kind)
	world.fx_layer.add_child(n)

func add_number(pos: Vector2, value: int, kind: String) -> void:
	var n := TDFloatText.new()
	n.world = world
	n.position = pos
	n.value = value
	n.kind = kind
	world.fx_layer.add_child(n)

## Plays an effect. Effects that follow someone (heal, level up) follow `follow`, or you.
func add_effect(def: EffectDef, pos: Vector2, face: int, follow: Node2D = null) -> void:
	if def == null:
		return
	if def.follow_player and follow == null:
		follow = world.player
	world.fx_layer.add_child(TDEffect.create(world, def, pos, face, follow))
