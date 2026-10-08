class_name TDPlayer
extends Node2D
## The player character. position is the point between the feet.

var world: TDWorld
var vel := Vector2.ZERO
var face := 1
var on_ground := false
var plat: Plat = null
var climb: Dictionary = {}
var grab_cd := 0
var drop_from: Plat = null
var drop_t := 0
var atk_t := 0
var atk_cd := 0
var skill_t := 0
var inv := 0
var dead := 0
var anim := 0

func place(x: float, y: float) -> void:
	position = Vector2(x, y)
	vel = Vector2.ZERO
	climb = {}
	on_ground = true
	plat = world.plats[0]

func is_climbing() -> bool:
	return not climb.is_empty()

func step() -> void:
	anim += 1
	if dead > 0:
		dead -= 1
		if dead == 0:
			Game.hp = ceili(Game.max_hp() / 2.0)
			Game.mp = ceili(Game.max_mp() / 2.0)
			inv = 120
			world.load_map("meadow", 200)
		return
	for t in ["inv", "atk_t", "atk_cd", "skill_t", "grab_cd", "drop_t"]:
		if get(t) > 0:
			set(t, get(t) - 1)
	if world.tick % 120 == 0:
		Game.hp = mini(Game.max_hp(), Game.hp + 2 + Game.level / 3)
		Game.mp = mini(Game.max_mp(), Game.mp + 2 + Game.level / 4)

	_attacks()
	if _portals():
		return
	if is_climbing():
		_climb()
		return
	if _grab_rope():
		return
	_move()

func _attacks() -> void:
	if is_climbing() or atk_cd > 0:
		return
	if Input.is_action_just_pressed("attack"):
		atk_t = 16
		atk_cd = 24
		world.hit_mobs(78, 1, 1, 1.0)
		world.add_effect("swish", position + Vector2(0, -34), face)
	elif Input.is_action_just_pressed("skill"):
		if Game.mp >= 8:
			Game.mp -= 8
			atk_t = 22
			skill_t = 26
			atk_cd = 36
			world.hit_mobs(170, 4, 2, 1.25)
			world.add_effect("slash", position + Vector2(0, -34), face)
		else:
			world.add_log("Not enough MP for Dawn Slash.", Color("8cc6ff"))

func _portals() -> bool:
	if not (Input.is_action_just_pressed("move_up") and on_ground):
		return false
	for p in world.map["portals"]:
		if absf(position.x - float(p["x"])) < 34 and absf(position.y - world.plats[int(p["plat"])].y) < 4:
			world.load_map(p["to"], float(p["tx"]))
			return true
	return false

func _climb() -> void:
	vel = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		position.y -= 2.6
	if Input.is_action_pressed("move_down"):
		position.y += 2.6
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	if Input.is_action_just_pressed("jump") and (left or right):
		var dir := -1 if left else 1
		climb = {}
		grab_cd = 20
		vel = Vector2(3.0 * dir, -5.5)
		face = dir
	elif position.y <= climb["top"]:
		position.y = climb["top"]
		climb = {}
		on_ground = true
		grab_cd = 10
	elif position.y >= climb["bottom"]:
		position.y = climb["bottom"]
		climb = {}
		on_ground = true
		grab_cd = 10

func _grab_rope() -> bool:
	if grab_cd > 0:
		return false
	var r := world.rope_near(position)
	if r.is_empty():
		return false
	if Input.is_action_pressed("move_up") and position.y > float(r["top"]) + 1:
		climb = r
	elif Input.is_action_pressed("move_down") and on_ground and absf(position.y - float(r["top"])) < 3:
		climb = r
		position.y = float(r["top"]) + 8
	else:
		return false
	position.x = r["x"]
	vel = Vector2.ZERO
	on_ground = false
	return true

func _move() -> void:
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var rooted := atk_t > 0 and on_ground
	var acc := 0.8 if on_ground else 0.28
	var max_speed := 3.7
	if left and not right and not rooted:
		vel.x = maxf(-max_speed, vel.x - acc)
		face = -1
	elif right and not left and not rooted:
		vel.x = minf(max_speed, vel.x + acc)
		face = 1
	else:
		vel.x *= 0.7 if on_ground else 0.98
	if absf(vel.x) < 0.05:
		vel.x = 0

	if Input.is_action_just_pressed("jump") and on_ground:
		if Input.is_action_pressed("move_down") and plat != null and not plat.solid:
			drop_from = plat
			drop_t = 16
			vel.y = 1
		else:
			vel.y = -9.8
		on_ground = false

	vel.y = minf(vel.y + 0.5, 12.0)
	var prev_y := position.y
	position.x = clampf(position.x + vel.x, 14.0, float(world.map["w"]) - 14.0)
	position.y += vel.y
	on_ground = false
	if vel.y >= 0:
		for pl in world.plats:
			if pl == drop_from and drop_t > 0:
				continue
			if pl.contains_x(position.x) and prev_y <= pl.y and position.y >= pl.y:
				position.y = pl.y
				vel.y = 0
				on_ground = true
				plat = pl
				break
	if position.y > float(world.map["h"]):
		position.y = float(world.map["ground"])
		vel.y = 0

# ---------- HD-2D visuals ----------

const Z := 0.4 # in front of monsters standing at the same spot

var body: Sprite3D
var shadow: Sprite3D

func _ready() -> void:
	body = TDStage.sprite(TDStage.tex("hero"), 15)
	add_child(body)
	shadow = TDStage.sprite(TDStage.tex("blob_shadow"), 1, false)
	shadow.offset = Vector2.ZERO
	shadow.axis = Vector3.AXIS_Y
	shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

func _process(_delta: float) -> void:
	_sync_visuals()

## Frames in hero.png: 0-3 idle, 4-7 walk, 8 jump, 9-10 climb, 11-12 attack, 13 hurt, 14 fallen.
func _sync_visuals() -> void:
	if body == null or world == null:
		return
	var p := TDStage.to3d(position, Z)
	body.position = p
	shadow.position = TDStage.to3d(position, -0.25) + Vector3(0, 0.02, 0) # on the platform top, behind its front edge
	shadow.visible = on_ground and dead == 0
	body.visible = not (inv > 0 and inv % 8 < 4) or dead > 0
	var frame := 0
	if dead > 0:
		frame = 14
	elif is_climbing():
		frame = 9 + int(position.y / 14.0) % 2
	elif atk_t > 0:
		var dur := 22.0 if skill_t > 0 else 16.0
		frame = 11 + mini(1, int((1.0 - atk_t / dur) * 2.0))
	elif inv > 70 and inv <= 90: # just got hit (world.gd sets inv = 90)
		frame = 13
	elif not on_ground:
		frame = 8
	elif absf(vel.x) > 0.3:
		frame = 4 + (anim / 6) % 4
	else:
		frame = (anim / 15) % 4
	body.frame = frame
	body.flip_h = face < 0 and not is_climbing() and dead == 0
