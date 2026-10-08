class_name TDMob
extends Node2D
## A monster that patrols one platform and chases the player after being hit.

var world: TDWorld
var type := ""
var d: Dictionary = {}
var plat: Plat
var hp := 0
var dir := 1
var walk_t := 0
var kx := 0.0
var hurt_t := 0
var aggro := 0
var dead := false
var death_t := 0
var respawn := 0
var phase := 0.0
var show_hp := 0

func setup(t: String, p: Plat) -> void:
	type = t
	d = GameData.MOBS[t]
	plat = p
	_reset()

func _reset() -> void:
	var w := float(d["w"])
	hp = int(d["hp"])
	position = Vector2(randf_range(plat.x + w, plat.x + plat.w - w), plat.y)
	dir = -1 if randf() < 0.5 else 1
	walk_t = randi_range(60, 200)
	kx = 0.0
	hurt_t = 0
	aggro = 0
	dead = false
	death_t = 0
	show_hp = 0
	phase = randf() * 6.0
	modulate.a = 1.0

func hurt(from_face: int) -> void:
	hurt_t = 14
	kx = from_face * 3.2
	aggro = 600
	show_hp = 240

func die() -> void:
	dead = true
	death_t = 30
	respawn = randi_range(360, 540)

func step() -> void:
	phase += 0.08
	queue_redraw()
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
	var half := float(d["w"]) / 2.0
	var speed := float(d["speed"])
	var p := world.player
	if hurt_t > 0:
		hurt_t -= 1
		position.x += kx
		kx *= 0.82
	else:
		var same_plat := p.dead == 0 and absf(p.position.y - plat.y) < 6 and p.position.x > plat.x and p.position.x < plat.x + plat.w
		if aggro > 0 and same_plat:
			dir = -1 if p.position.x < position.x else 1
			position.x += dir * speed * 1.3
		else:
			walk_t -= 1
			if walk_t <= 0:
				walk_t = randi_range(60, 220)
				dir = 0 if randf() < 0.3 else (-1 if randf() < 0.5 else 1)
			position.x += dir * speed
	if position.x < plat.x + half:
		position.x = plat.x + half
		if dir < 0:
			dir = 1
	if position.x > plat.x + plat.w - half:
		position.x = plat.x + plat.w - half
		if dir > 0:
			dir = -1
	if absf(position.x - p.position.x) < half + 10 and p.position.y > position.y - float(d["h"]) - 4 and p.position.y - 56 < position.y:
		world.hurt_player(int(d["atk"]), position.x)

# ---------- drawing (placeholder art) ----------

func _draw() -> void:
	var alpha := 1.0
	if dead:
		alpha = death_t / 30.0
	if hurt_t > 0 and hurt_t % 4 < 2:
		alpha *= 0.6
	modulate.a = alpha
	if alpha <= 0.0:
		return
	var facing := dir
	if facing == 0:
		facing = -1 if world.player.position.x < position.x else 1
	var bob := sin(phase * 2.0)
	DrawUtil.ellipse(self, Vector2.ZERO, float(d["w"]) * 0.45, 5, Color(0, 0, 0, 0.2))
	var flip := Transform2D(0, Vector2(facing, 1), 0, Vector2.ZERO)
	match type:
		"dewling":
			var sq := 1.0 + bob * 0.08
			draw_set_transform_matrix(flip * Transform2D(0, Vector2(1.0 / sq, sq), 0, Vector2.ZERO))
			var body := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				var a := PI + t * PI
				body.append(Vector2(cos(a) * 18, sin(a) * 30 * (1.0 - 0.15 * absf(cos(a)))))
			var cols := PackedColorArray()
			for pt in body:
				cols.append(Color("a8f0e6").lerp(Color("3fb3b0"), (pt.y + 30) / 30.0))
			draw_polygon(body, cols)
			DrawUtil.ellipse(self, Vector2(-6, -20), 4, 6, Color(1, 1, 1, 0.6))
			draw_circle(Vector2(4, -13), 2.6, GameData.NIGHT)
			draw_circle(Vector2(11, -13), 2.6, GameData.NIGHT)
		"sproutcap":
			draw_set_transform_matrix(flip * Transform2D(0, Vector2(0, -maxf(0, bob) * 4)))
			DrawUtil.round_rect(self, Rect2(-12, -22, 24, 22), 8, Color("f2dcc0"))
			draw_circle(Vector2(2, -12), 2.4, GameData.NIGHT)
			draw_circle(Vector2(9, -12), 2.4, GameData.NIGHT)
			draw_colored_polygon(DrawUtil.ellipse_points(Vector2(0, -24), 22, 15, PI, TAU, 16), Color("e8566b"))
			draw_circle(Vector2(-9, -31), 3.5, GameData.MIST)
			draw_circle(Vector2(7, -34), 3, GameData.MIST)
			draw_circle(Vector2(14, -27), 2.5, GameData.MIST)
			draw_line(Vector2(0, -38), Vector2(0, -46), Color("4f9a4a"), 2.5)
			DrawUtil.ellipse(self, Vector2(-5, -47), 6, 3, Color("7ccf5f"))
			DrawUtil.ellipse(self, Vector2(5, -47), 6, 3, Color("7ccf5f"))
		_:
			draw_set_transform_matrix(flip)
			var stride := sin(phase * 3.0) * 3.0
			draw_rect(Rect2(-20 + stride, -12, 7, 12), Color("4a2c22"))
			draw_rect(Rect2(12 - stride, -12, 7, 12), Color("4a2c22"))
			DrawUtil.ellipse(self, Vector2(0, -22), 30, 17, Color("7a4a34"))
			for i in 5:
				var flick := sin(world.tick * 0.2 + i) * 4.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(-14 + i * 8, -36), Vector2(-10 + i * 8, -48 - flick), Vector2(-6 + i * 8, -36)]), GameData.EMBER)
			DrawUtil.ellipse(self, Vector2(26, -18), 10, 9, Color("8f5a40"))
			draw_colored_polygon(PackedVector2Array([Vector2(30, -12), Vector2(36, -22), Vector2(33, -11)]), GameData.MIST)
			draw_circle(Vector2(22, -24), 2.4, GameData.NIGHT)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if dead:
		return
	var label := "Lv.%d %s" % [int(d["lvl"]), d["name"]]
	var w := DrawUtil.text_width(Game.ui_font, label, 11) + 12
	DrawUtil.round_rect(self, Rect2(-w / 2, 4, w, 16), 4, Color(0.1, 0.07, 0.19, 0.6))
	DrawUtil.text(self, Game.ui_font, Vector2(0, 16), label, 11, GameData.MIST)
	if show_hp > 0:
		var bw := maxf(40.0, float(d["w"]))
		var top := -float(d["h"]) - 14
		draw_rect(Rect2(-bw / 2, top, bw, 6), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-bw / 2 + 1, top + 1, (bw - 2) * maxf(0, float(hp) / float(d["hp"])), 4), GameData.HP)
