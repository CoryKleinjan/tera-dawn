class_name TDWorldFx
extends RefCounted
## How TDWorld shows the server's events: swings, projectiles, damage numbers, monster
## shots and deaths, level-ups and other effects. Everything it spawns goes on the
## world's fx layer.

var world: TDWorld

func _init(w: TDWorld) -> void:
	world = w

## Someone used a skill aimed `aim`: their swing (yours already showed), then the damage
## on each monster hit. `lines` is [[mob index, [[damage, kind], ...]], ...].
func show_skill(peer: int, skill: SkillDef, at: Vector2, face: int, lines: Array, aim := Hitbox.Aim.AHEAD) -> void:
	if skill == null:
		return
	var who := world.actor(peer)
	if who is TDAvatar:
		(who as TDAvatar).play_skill(skill)
		add_effect(skill.effect, TDWorldFx.swing_point(at, face, aim), face, null, aim)
		world.sound_at(skill.cast_sound(), at)
		if skill.move and skill.ambush > 0.0:
			# an ambush: `at` is where they landed, the avatar is still where they left
			TDMoveFx.play(world, skill.move, (who as TDAvatar).position, at, who)
		elif skill.move:
			var to := skill.move.blink_to(at, face, aim, 1, float(world.map.width), float(world.map.ground_y))
			TDMoveFx.play(world, skill.move, at, to, who)
	var views := world.mobs()
	var mine := who == world.player
	var way := Hitbox.aim_direction(face, aim)
	var from := at + Vector2(0, -TDPlayer.CHEST) + way * 20 + Vector2(0, -2)
	if skill.projectile and lines.is_empty():
		# nothing in range: it flies off and fades
		for i in skill.hits:
			world.fx_layer.add_child(TDProjectile.create(world, skill.projectile, from, from + way * skill.projectile.max_range, i * 7, null, Callable()))
	for line in lines:
		var m: TDMob = views[line[0]] if line[0] < views.size() else null
		if m == null:
			continue
		var hits: Array = line[1]
		if skill.projectile == null:
			_show_hits(skill, m, hits, face, mine)
			if mine:
				_melee_hit[m.index] = world.tick
			continue
		# each hit lands with its own projectile
		for i in hits.size():
			m.incoming += 1
			var land := func() -> void:
				m.incoming -= 1
				_show_hits(skill, m, [hits[i]], face, mine)
			world.fx_layer.add_child(TDProjectile.create(world, skill.projectile, from, Vector2.ZERO, i * 7, m, land))

## Hit-stop: how many ticks a blow freezes the monster, plain and critical.
## Melee blows hold longer than shots, so they feel heavy.
const HIT_STOP := 3
const CRIT_STOP := 6
const MELEE_HIT_STOP := 5
const MELEE_CRIT_STOP := 9
## Screen shake for a critical shot, a critical melee blow, and a monster your melee blow
## just finished off (within KILL_KICK_TICKS of the blow).
const CRIT_SHAKE := 0.35
const MELEE_CRIT_SHAKE := 0.5
const KILL_KICK := 0.4
const KILL_KICK_TICKS := 30

## Monster index -> the world tick your last melee blow landed on it (see KILL_KICK).
var _melee_hit := {}
## Damage numbers on one monster closer together in time than this stack above each other,
## NUMBER_STEP apart, so a flurry of hits never piles up in one spot.
const NUMBER_STACK_TICKS := 24
const NUMBER_STEP := 36.0
## Monster index -> [world tick of its newest number, how many are stacked].
var _numbers := {}

## Where a swing's effect is drawn for someone standing at `feet`: at their chest, or above
## their head or below their middle when aimed up or down.
static func swing_point(feet: Vector2, face: int, aim: Hitbox.Aim) -> Vector2:
	var chest := feet + Vector2(0, -TDPlayer.CHEST)
	match aim:
		Hitbox.Aim.UP:
			return chest + Vector2(0, -TDPlayer.CHEST)
		Hitbox.Aim.DOWN:
			return chest + Vector2(0, TDPlayer.CHEST)
	return chest

## Damage numbers and hit effects for `hits` on monster `m` (numbers stack, see
## _number_slot). Your own hits also get hit-stop, and crits a little screen shake.
func _show_hits(skill: SkillDef, m: TDMob, hits: Array, face: int, mine: bool) -> void:
	var mid := m.body_position() + Vector2(0, -m.def.size.y / 2.0)
	var crit := false
	var landed := false
	for i in hits.size():
		var kind: String = hits[i][1]
		add_number(m.body_position() + Vector2(0, -m.def.size.y - 10 - _number_slot(m.index) * NUMBER_STEP), hits[i][0], kind)
		crit = crit or kind == "crit"
		landed = landed or kind != "miss"
		if kind == "crit":
			add_effect(Content.effect(EffectDef.CRITICAL), mid, face)
	if not landed:
		return
	var stop := 0
	if mine:
		if skill.is_ranged():
			stop = CRIT_STOP if crit else HIT_STOP
		else:
			stop = MELEE_CRIT_STOP if crit else MELEE_HIT_STOP
	m.hit_react(face, stop)
	if mine:
		if not skill.is_ranged():
			world.player.hit_stop(stop)
			world.player.recoil()
		if crit:
			world.shake(CRIT_SHAKE if skill.is_ranged() else MELEE_CRIT_SHAKE)
	burst(mid, m.def.aura_color if m.def.aura_color.a > 0.0 else Color(1.9, 1.5, 0.9), 8 if crit else 4, 0.6)
	add_effect(skill.hit_effect, mid, face)

## Which step up the next damage number on monster `index` goes: one above the last while
## they come quickly, back to the bottom after a pause.
func _number_slot(index: int) -> int:
	var last: Array = _numbers.get(index, [-NUMBER_STACK_TICKS - 1, -1])
	var slot: int = last[1] + 1 if world.tick - int(last[0]) <= NUMBER_STACK_TICKS else 0
	_numbers[index] = [world.tick, slot]
	return slot

## A quick spray of glowing sparks at a spot (hits, deaths, pickups). Colours may be HDR.
func burst(at: Vector2, col: Color, amount: int, speed := 1.0) -> void:
	var p := TDStage.particles(col, amount, 0.16)
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.6
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = 2.0 * speed
	p.initial_velocity_max = 4.5 * speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.position = TDStage.to3d(at, TDStage.Z_EFFECT)
	world.stage.map_root.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## A little puff of dust kicked up at someone's feet: landing (`dir` 0, both ways) or
## skidding round (`dir` the way it sprays, -1 or 1).
func dust(feet: Vector2, dir: int, amount: int) -> void:
	var p := TDStage.particles(DUST, amount, 0.22)
	(p.mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX  # dust doesn't glow
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.45
	p.direction = Vector3(dir, 0.6, 0).normalized() if dir != 0 else Vector3.UP
	p.spread = 35.0 if dir != 0 else 80.0
	p.gravity = Vector3(0, -1.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, DUST)
	fade.set_color(1, Color(DUST, 0.0))
	p.color_ramp = fade
	p.position = TDStage.to3d(feet + Vector2(0, -2), TDStage.Z_EFFECT)
	world.stage.map_root.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## Dust's colour: pale sandy brown, not glowing.
const DUST := Color(0.82, 0.74, 0.6, 0.6)

## Monster `index` fired its shot (move `move_index`) at the point `aim`.
func show_mob_shot(index: int, move_index: int, aim: Vector2) -> void:
	var views := world.mobs()
	if index >= views.size() or move_index >= views[index].def.moves.size():
		return
	var m := views[index]
	var shot := m.def.moves[move_index].projectile
	if shot == null:
		return
	m.dir = -1 if aim.x < m.position.x else 1
	var from := m.body_position() + Vector2(m.dir * m.def.size.x * 0.4, -m.def.size.y * 0.55)
	world.fx_layer.add_child(TDProjectile.create(world, shot, from, aim, 0, null, Callable()))
	world.sound_at(shot.sound, from)

## Monster `index`'s move did `what` at `at` (see Net.ev_mob_move): a slam's dust and
## shake, a landing's dust, a blink's puff of light, a boss's second wind.
func show_mob_move(index: int, what: StringName, at: Vector2) -> void:
	var views := world.mobs()
	var m: TDMob = views[index] if index < views.size() else null
	match what:
		&"slam":
			var reach := m.def.size.x if m else 60.0
			dust(at + Vector2(-reach * 0.5, 0), -1, 18)
			dust(at + Vector2(reach * 0.5, 0), 1, 18)
			if world.player and absf(world.player.position.x - at.x) < 500.0:
				world.shake(0.5 if m and m.def.boss else 0.25)
		&"land":
			dust(at, 0, 14 if m and m.def.boss else 8)
		&"blink":
			burst(at + Vector2(0, -30), Color(0.7, 0.6, 1.6), 16, 0.8)
		&"rage":
			burst(at + Vector2(0, -40), Color(2.0, 0.6, 0.3), 30, 1.2)
			flash(at + Vector2(0, -40), Color(1.0, 0.45, 0.25), 2.5)
			if m:
				m.rig.pulse(Color(1.0, 0.4, 0.3))

func show_mob_death(index: int) -> void:
	var views := world.mobs()
	if index < views.size():
		var m := views[index]
		m.kill()
		var mid := m.body_position() + Vector2(0, -m.def.size.y / 2.0)
		add_effect(Content.effect(EffectDef.MONSTER_POOF), mid, 1)
		# a pop of dawn-motes (the monster's spark going free) and a brief flash of light
		burst(mid, Color(2.2, 1.8, 1.0), 16 if m.def.boss else 10, 1.3 if m.def.boss else 1.0)
		flash(mid, Color(1.0, 0.85, 0.6), 4.0 if m.def.boss else 2.0)
		if m.def.boss:
			world.shake(0.8)
		elif world.tick - int(_melee_hit.get(index, -KILL_KICK_TICKS - 1)) <= KILL_KICK_TICKS:
			world.shake(KILL_KICK)
		_melee_hit.erase(index)

## A brief flash of light at a spot that fades by itself.
func flash(at: Vector2, col: Color, energy: float) -> void:
	var l := TDStage.light(col, energy, 5.0)
	l.position = TDStage.to3d(at, TDStage.Z_EFFECT + 0.6)
	world.stage.map_root.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)

## Plays over the music when you level up (Sound.jingle id).
const LEVEL_UP_JINGLE := &"jingle_levelup"

func show_level_up(peer: int, _level: int) -> void:
	var who := world.actor(peer)
	if who == null:
		return
	add_effect(Content.effect(EffectDef.LEVEL_UP), who.position, 1, who)
	if who == world.player:
		world.player.level_up()
		Sound.jingle(LEVEL_UP_JINGLE)

## A small "+9 EXP" or "+8 Dawnshards" rising over your hero; gains that arrive together
## stack upwards instead of covering each other.
func show_gain(kind: StringName, amount: int) -> void:
	var young := 0
	for f in world.fx_layer.get_children():
		if f is TDFloatText and (f as TDFloatText).is_gain() and f.t < TDFloatText.GAIN_STACK_TICKS:
			young += 1
	var n := TDFloatText.new()
	n.world = world
	n.position = world.player.position + Vector2(0, -TDPlayer.HEIGHT - 30 - young * 14)
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
## `aim` turns it to point up or down (aimed swings).
func add_effect(def: EffectDef, pos: Vector2, face: int, follow: Node2D = null, aim := Hitbox.Aim.AHEAD) -> void:
	if def == null:
		return
	if def.follow_player and follow == null:
		follow = world.player
	world.fx_layer.add_child(TDEffect.create(world, def, pos, face, follow, aim))
	world.sound_at(def.sound, follow.position if follow else pos)
