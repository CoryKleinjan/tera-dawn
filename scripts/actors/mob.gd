class_name TDMob
extends Node2D
## A monster. Its MonsterDef says what it is; this node runs it: it patrols its platform,
## chases the player for a while after being hit, hurts the player on touch, and comes
## back some time after it is defeated. Flying monsters do the same in the air.

var world: TDWorld
var def: MonsterDef
var plat: Platform
var health := Health.new()
var hurtbox: Hitbox

var dir := 1
var walk_t := 0     # ticks until the next change of direction
var kx := 0.0       # knockback speed
var hurt_t := 0
var aggro := 0      # ticks left chasing the player
var dead := false
var death_t := 0
var respawn := 0
var phase := 0.0
var show_hp := 0    # ticks left showing the HP bar
var z := 0.0

var rig: SpriteRig
var _last_x := 0.0

static func create(w: TDWorld, d: MonsterDef, p: Platform) -> TDMob:
	var m := TDMob.new()
	m.world = w
	m.def = d
	m.plat = p
	m.hurtbox = Hitbox.new(d.size)
	m._reset()
	return m

func _reset() -> void:
	var half := def.size.x / 2.0
	health.reset(def.max_hp)
	position = Vector2(randf_range(plat.x + half, plat.x + plat.w - half), plat.y)
	_last_x = position.x
	dir = -1 if randf() < 0.5 else 1
	walk_t = randi_range(60, 200)
	kx = 0.0
	hurt_t = 0
	aggro = 0
	dead = false
	death_t = 0
	show_hp = 0
	phase = randf() * 6.0

func hurt(from_face: int) -> void:
	hurt_t = 14
	kx = from_face * 3.2
	aggro = 600
	show_hp = 240

func die() -> void:
	dead = true
	death_t = 40
	respawn = randi_range(def.respawn_ticks.x, def.respawn_ticks.y)

## Feet position including the hover height of flying monsters.
func body_position() -> Vector2:
	if def.flying:
		return position + Vector2(0, -def.hover_height + sin(phase * 1.5) * 6.0)
	return position

func step() -> void:
	phase += 0.08
	if dead:
		if death_t > 0:
			death_t -= 1
		else:
			respawn -= 1
			if respawn <= 0:
				_reset()
		return
	if show_hp > 0:
		show_hp -= 1
	if aggro > 0:
		aggro -= 1
	var half := def.size.x / 2.0
	var p := world.player
	if hurt_t > 0:
		hurt_t -= 1
		position.x += kx
		kx *= 0.82
	else:
		var same_plat := not p.fainted() and absf(p.position.y - plat.y) < 6 \
			and p.position.x > plat.x and p.position.x < plat.x + plat.w
		if aggro > 0 and same_plat:
			dir = -1 if p.position.x < position.x else 1
			position.x += dir * def.speed * 1.3
		else:
			walk_t -= 1
			if walk_t <= 0:
				walk_t = randi_range(60, 220)
				dir = 0 if randf() < 0.3 else (-1 if randf() < 0.5 else 1)
			position.x += dir * def.speed
	if position.x < plat.x + half:
		position.x = plat.x + half
		if dir < 0:
			dir = 1
	if position.x > plat.x + plat.w - half:
		position.x = plat.x + plat.w - half
		if dir > 0:
			dir = -1
	if hurtbox.rect_at(body_position()).intersects(p.hurtbox.rect_at(p.position)):
		world.hurt_player(def.attack, position.x)

# ---------- HD-2D visuals ----------

func _ready() -> void:
	z = TDStage.Z_MONSTER + randf() * TDStage.Z_MONSTER_SPREAD
	rig = SpriteRig.new()
	rig.setup(def.sprite_frames, def.texture, TDStage.TEXEL * def.sprite_scale, def.size.x * 1.1)
	add_child(rig)
	if def.light_color.a > 0.0:
		rig.add_light(def.light_color, def.light_energy, def.size.y)
	if def.aura_color.a > 0.0:
		rig.add_aura(def.aura_color, def.size.y * 0.8)

func _process(_delta: float) -> void:
	if rig == null or world == null:
		return
	var alpha := clampf(death_t / 30.0, 0.0, 1.0) if dead else 1.0
	rig.set_opacity(alpha)
	rig.set_flash(hurt_t > 0 and hurt_t % 4 < 2)
	var facing := dir
	if facing == 0:
		facing = -1 if world.player.position.x < position.x else 1
	rig.face(facing)
	var moving := absf(position.x - _last_x) > 0.01
	_last_x = position.x
	if dead:
		rig.play(&"die")
	elif hurt_t > 0:
		rig.play(&"hurt")
	elif aggro > 0 and moving:
		rig.play(&"attack")
	elif moving:
		rig.play(&"move")
	else:
		rig.play(&"idle")
	rig.place(body_position(), z, NAN if dead else plat.y)

## Name tag and HP bar, drawn by the overlay at this monster's projected screen position.
func draw_tag(ci: CanvasItem, at: Vector2, top: Vector2) -> void:
	if dead:
		return
	var label := "Lv.%d %s" % [def.level, def.display_name]
	UiSkin.draw_name_tag(ci, at + Vector2(0, 4), label, Palette.MIST, Palette.EMBER if def.boss else Color.TRANSPARENT)
	if show_hp > 0 or def.boss:
		UiSkin.draw_monster_hp(ci, top + Vector2(0, -16), maxf(54.0, def.size.x * (1.6 if def.boss else 1.1)), health.fraction())
