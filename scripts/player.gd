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
	queue_redraw()
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

# ---------- drawing (placeholder art) ----------

func _draw() -> void:
	if dead > 0:
		DrawUtil.round_rect(self, Rect2(-14, -30, 28, 30), 6, Color("c9b8d9"))
		DrawUtil.text(self, Game.ui_font, Vector2(0, -11), "RIP", 11, Color("5b4682"))
		return
	modulate.a = 0.55 if inv > 0 and inv % 8 < 4 else 1.0
	var climbing := is_climbing()
	if on_ground:
		DrawUtil.ellipse(self, Vector2.ZERO, 14, 4, Color(0, 0, 0, 0.22))
	var f := 1.0 if climbing else float(face)
	var flip := Transform2D(0, Vector2(f, 1), 0, Vector2.ZERO)
	draw_set_transform_matrix(flip)
	var walking := on_ground and absf(vel.x) > 0.3
	var stride := sin(anim * 0.35) * 5.0 if walking else 0.0
	var cstep := sin(position.y * 0.25) * 4.0 if climbing else 0.0
	# legs and boots
	draw_rect(Rect2(-7 + stride * 0.6, -16 + cstep, 6, 16), Color("3d2c5e"))
	draw_rect(Rect2(2 - stride * 0.6, -16 - cstep, 6, 16), Color("3d2c5e"))
	draw_rect(Rect2(-8 + stride * 0.6, -3, 8, 3), Color("2a1b3d"))
	draw_rect(Rect2(1 - stride * 0.6, -3, 8, 3), Color("2a1b3d"))
	# tunic
	var tunic := DrawUtil.round_rect_points(Rect2(-10, -38, 20, 24), 6)
	var tcols := PackedColorArray()
	for pt in tunic:
		tcols.append(Color("ff9a6b").lerp(Color("e0603f"), (pt.y + 38) / 24.0))
	draw_polygon(tunic, tcols)
	draw_rect(Rect2(-10, -20, 20, 3), GameData.SUN)
	# arm and sword
	var swing := 1.0 - float(atk_t) / (22.0 if skill_t > 0 else 16.0) if atk_t > 0 else -1.0
	var ang := -2.2 if climbing else 0.5
	if swing >= 0:
		ang = -2.0 + swing * 3.4
	draw_set_transform_matrix(flip * Transform2D(ang, Vector2(4, -32)))
	draw_rect(Rect2(-3, 0, 6, 13), Color("ffd9b8"))
	if not climbing:
		draw_rect(Rect2(-2, 12, 4, 6), Color("6b4433"))
		draw_rect(Rect2(-6, 17, 12, 3), GameData.SUN)
		var blade := PackedVector2Array([Vector2(-3, 20), Vector2(3, 20), Vector2(2, 50), Vector2(0, 55), Vector2(-2, 50)])
		draw_polygon(blade, PackedColorArray([Color("f4f1ff"), Color("f4f1ff"), Color("a9b7ff"), Color("a9b7ff"), Color("a9b7ff")]))
	draw_set_transform_matrix(flip)
	# head and hair
	draw_circle(Vector2(0, -52), 15, Color("ffd9b8"))
	var hair := Color("ff9a3c")
	draw_colored_polygon(DrawUtil.ellipse_points(Vector2(-1, -56), 16, 16, PI * 1.02, PI * 2.05, 16), hair)
	draw_colored_polygon(PackedVector2Array([Vector2(-16, -56), Vector2(-20, -40), Vector2(-9, -50)]), hair)
	if climbing:
		draw_circle(Vector2(0, -52), 14, hair)
	else:
		draw_rect(Rect2(4, -53, 3, 6), Color("2a1b3d"))
		draw_rect(Rect2(10, -53, 3, 6), Color("2a1b3d"))
		draw_circle(Vector2(11, -45), 3, Color(1, 0.47, 0.47, 0.4))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# name tag
	DrawUtil.round_rect(self, Rect2(-30, 4, 60, 16), 4, Color(0.1, 0.07, 0.19, 0.7))
	DrawUtil.text(self, Game.ui_font, Vector2(0, 16), "Dawnling", 11, GameData.SUN)
