class_name TDWorld
extends Node2D
## Owns the current map: terrain, monsters, drops, effects, camera and combat rules.
## The game logic steps once per physics tick (60 Hz), matching the web prototype.

const VIEW := Vector2(960, 540)

var map_id := ""
var map: Dictionary = {}
var colors: Dictionary = {}
var plats: Array[Plat] = []
var ropes: Array[Dictionary] = []
var started := false
var tick := 0
var cam := Vector2.ZERO
var banner_text := ""
var banner_t := 0
var log_lines: Array[Dictionary] = []

var player: TDPlayer
var camera: Camera2D
var mob_layer: Node2D
var drop_layer: Node2D
var fx_layer: Node2D
var hud: TDHud

func _ready() -> void:
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var bg := TDBackground.new()
	bg.world = self
	bg_layer.add_child(bg)
	mob_layer = Node2D.new()
	add_child(mob_layer)
	drop_layer = Node2D.new()
	add_child(drop_layer)
	player = TDPlayer.new()
	player.world = self
	add_child(player)
	fx_layer = Node2D.new()
	add_child(fx_layer)
	hud = TDHud.new()
	hud.world = self
	add_child(hud)
	load_map(Game.map_id, 200.0 if Game.map_id == "meadow" else 90.0)

func start() -> void:
	started = true
	show_banner(map["name"])

func load_map(id: String, x: float) -> void:
	map_id = id
	Game.map_id = id
	map = GameData.MAPS[id]
	colors = GameData.THEMES[map["theme"]]
	plats.clear()
	plats.append(Plat.new(0, map["ground"], map["w"], true))
	for p in map["plats"]:
		plats.append(Plat.new(p[0], p[1], p[2]))
	ropes.clear()
	for r in map["ropes"]:
		ropes.append({"x": float(r[0]), "top": float(r[1]), "bottom": float(r[2]), "kind": r[3]})
	for layer in [mob_layer, drop_layer, fx_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	for s in map["spawns"]:
		for i in int(s[2]):
			var m := TDMob.new()
			m.world = self
			m.setup(s[0], plats[int(s[1])])
			mob_layer.add_child(m)
	player.place(x, plats[0].y)
	cam = _camera_target()
	camera.position = cam
	if started:
		show_banner(map["name"])
	Game.save_game()
	queue_redraw()

func show_banner(text: String) -> void:
	banner_text = text
	banner_t = 180

func add_log(text: String, col: Color) -> void:
	if not log_lines.is_empty() and log_lines[-1]["text"] == text:
		log_lines[-1]["t"] = 300
		return
	log_lines.append({"text": text, "color": col, "t": 300})
	if log_lines.size() > 6:
		log_lines.pop_front()

func rope_near(pos: Vector2) -> Dictionary:
	for r in ropes:
		if absf(pos.x - r["x"]) < 16 and pos.y > r["top"] - 2 and pos.y <= r["bottom"] + 2:
			return r
	return {}

func mobs() -> Array[TDMob]:
	var out: Array[TDMob] = []
	for c in mob_layer.get_children():
		out.append(c as TDMob)
	return out

func _camera_target() -> Vector2:
	return Vector2(
		clampf(player.position.x - VIEW.x / 2.0, 0, float(map["w"]) - VIEW.x),
		clampf(player.position.y - VIEW.y * 0.62, 0, float(map["h"]) - VIEW.y))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("pause") and started:
		started = false
		hud.show_title(true)

func _physics_process(_delta: float) -> void:
	tick += 1
	if started:
		player.step()
	for m in mobs():
		m.step()
	for d in drop_layer.get_children():
		(d as TDDrop).step()
	for f in fx_layer.get_children():
		f.step()
	for i in range(log_lines.size() - 1, -1, -1):
		log_lines[i]["t"] -= 1
		if log_lines[i]["t"] <= 0:
			log_lines.remove_at(i)
	if banner_t > 0:
		banner_t -= 1
	cam += (_camera_target() - cam) * Vector2(0.12, 0.1)
	camera.position = cam
	if tick % 300 == 0:
		Game.save_game()
	queue_redraw()

# ---------- combat ----------

func hit_mobs(reach: float, max_targets: int, lines: int, mult: float) -> int:
	var p := player.position
	var x0 := p.x - 10.0 if player.face > 0 else p.x - reach
	var x1 := p.x + reach if player.face > 0 else p.x + 10.0
	var targets: Array[TDMob] = []
	for m in mobs():
		var half: float = m.d["w"] / 2.0
		if not m.dead and m.position.x + half > x0 and m.position.x - half < x1 \
				and m.position.y > p.y - 90 and m.position.y - float(m.d["h"]) < p.y + 10:
			targets.append(m)
	targets.sort_custom(func(a: TDMob, b: TDMob) -> bool:
		return absf(a.position.x - p.x) < absf(b.position.x - p.x))
	if targets.size() > max_targets:
		targets.resize(max_targets)
	for m in targets:
		for i in lines:
			if m.dead:
				break
			var crit := randf() < 0.12
			var dmg := roundi(Game.attack_power() * mult * randf_range(0.85, 1.15) * (1.6 if crit else 1.0))
			dmg = maxi(1, dmg - maxi(0, int(m.d["lvl"]) - Game.level) * 2)
			m.hp -= dmg
			add_number(m.position + Vector2(0, -float(m.d["h"]) - 10 - i * 30), dmg, "crit" if crit else "hit")
			if m.hp <= 0:
				kill_mob(m)
		if not m.dead:
			m.hurt(player.face)
		add_effect("spark", m.position + Vector2(0, -float(m.d["h"]) / 2.0), 1)
	return targets.size()

func kill_mob(m: TDMob) -> void:
	m.die()
	var levels := Game.gain_xp(int(m.d["xp"]))
	add_log("+%d EXP" % int(m.d["xp"]), Color("ffe39a"))
	if levels > 0:
		add_effect("levelup", player.position, 1)
		add_log("Level up! You reached Lv. %d" % Game.level, GameData.SUN)
		if Game.level >= 5:
			SteamService.unlock_achievement("REACH_LEVEL_5")
	var count := 2 if randf() < 0.35 else 1
	var range_: Array = m.d["shards"]
	for i in count:
		var drop := TDDrop.new()
		drop.world = self
		drop.position = m.position + Vector2(0, -20)
		drop.vel = Vector2(randf_range(-1.6, 1.6), randf_range(-6, -4))
		drop.floor_y = m.plat.y
		drop.amount = randi_range(int(range_[0]), int(range_[1]))
		drop_layer.add_child(drop)

func hurt_player(base: int, from_x: float) -> void:
	if not started or player.inv > 0 or player.dead > 0:
		return
	var dmg := maxi(1, roundi(base * randf_range(0.85, 1.15) - Game.level * 0.6))
	Game.hp -= dmg
	player.inv = 90
	add_number(player.position + Vector2(0, -70), dmg, "taken")
	if not player.is_climbing():
		player.vel = Vector2(-3.5 if player.position.x < from_x else 3.5, -4.5)
		player.on_ground = false
	if Game.hp <= 0:
		Game.hp = 0
		player.dead = 150
		var lost := int(Game.xp * 0.1)
		Game.xp -= lost
		add_log("You fainted and lost %d EXP." % lost, Color("ff8a99"))

func add_number(pos: Vector2, value: int, kind: String) -> void:
	var n := TDFloatText.new()
	n.position = pos
	n.value = value
	n.kind = kind
	fx_layer.add_child(n)

func add_effect(kind: String, pos: Vector2, face: int) -> void:
	var e := TDEffect.new()
	e.world = self
	e.kind = kind
	e.position = pos
	e.face = face
	fx_layer.add_child(e)

# ---------- terrain drawing ----------

func _draw() -> void:
	var view := Rect2(cam, VIEW).grow(80)
	for pl in plats:
		if pl.x > view.end.x or pl.x + pl.w < view.position.x:
			continue
		_draw_platform(pl, view)
	for r in ropes:
		if r["x"] > view.position.x and r["x"] < view.end.x:
			_draw_rope(r)
	_draw_portals()
	_draw_sign()

func _draw_platform(pl: Plat, view: Rect2) -> void:
	var dirt: Color = colors["dirt"]
	var dirt_dark: Color = colors["dirt_dark"]
	var grass: Color = colors["grass"]
	if pl.solid:
		var x0 := maxf(pl.x, view.position.x)
		var x1 := minf(pl.x + pl.w, view.end.x)
		DrawUtil.vgradient_rect(self, Rect2(x0, pl.y, x1 - x0, 120), dirt, dirt_dark)
		draw_rect(Rect2(x0, pl.y + 120, x1 - x0, float(map["h"]) - pl.y), dirt_dark)
		var sx := floorf(x0 / 60.0) * 60.0
		while sx < x1:
			DrawUtil.ellipse(self, Vector2(sx + 20, pl.y + 40 + int(sx) % 7 * 4), 10, 5, Color(0, 0, 0, 0.12))
			sx += 60.0
	else:
		var body := DrawUtil.round_rect_points(Rect2(pl.x, pl.y, pl.w, 24), 8)
		var cols := PackedColorArray()
		for pt in body:
			cols.append(dirt.lerp(dirt_dark, (pt.y - pl.y) / 24.0))
		draw_polygon(body, cols)
	DrawUtil.round_rect(self, Rect2(pl.x - 2, pl.y - 3, pl.w + 4, 10), 4, grass)
	draw_rect(Rect2(pl.x + 4, pl.y - 2, pl.w - 8, 2), colors["grass_hi"])
	var gx := 6.0
	while gx < pl.w - 6:
		var tip := 12.0 + int(gx * 7) % 5
		draw_colored_polygon(PackedVector2Array([
			Vector2(pl.x + gx, pl.y + 6), Vector2(pl.x + gx + 5, pl.y + 6), Vector2(pl.x + gx + 2.5, pl.y + tip)]), grass)
		gx += 14.0

func _draw_rope(r: Dictionary) -> void:
	var x: float = r["x"]
	var t: float = r["top"]
	var b: float = r["bottom"]
	if r["kind"] == "ladder":
		draw_line(Vector2(x - 10, t - 6), Vector2(x - 10, b), Color("6b4433"), 4)
		draw_line(Vector2(x + 10, t - 6), Vector2(x + 10, b), Color("6b4433"), 4)
		var y := t + 6
		while y < b:
			draw_line(Vector2(x - 10, y), Vector2(x + 10, y), Color("a77a5a"), 3)
			y += 16
	else:
		draw_line(Vector2(x, t - 4), Vector2(x, b - 4), Color("c9a77a"), 4)
		var y := t + 10
		while y < b - 6:
			draw_circle(Vector2(x, y), 3.5, Color("8e6c4a"))
			y += 22

func _draw_portals() -> void:
	for p in map["portals"]:
		var base := Vector2(float(p["x"]), plats[int(p["plat"])].y)
		var c := base + Vector2(0, -46)
		DrawUtil.ellipse(self, c, 18, 38, Color(1, 0.94, 0.78, 0.25))
		for i in 3:
			var col := Color(1, 0.82, 0.4) if i == 1 else Color(0.67, 0.55, 1)
			col.a = 0.8 - i * 0.2
			var pts := DrawUtil.ellipse_points(c, 22 + i * 6 + sin(tick * 0.08 + i) * 3, 42 + i * 5)
			pts.append(pts[0])
			draw_polyline(pts, col, 5 - i, true)
		if absf(player.position.x - base.x) < 60:
			var label := "↑ to %s" % GameData.MAPS[p["to"]]["name"]
			var w := DrawUtil.text_width(Game.ui_font, label, 13) + 20
			DrawUtil.round_rect(self, Rect2(base.x - w / 2, base.y - 118, w, 22), 6, Color(0.1, 0.07, 0.19, 0.7))
			DrawUtil.text(self, Game.ui_font, base + Vector2(0, -102), label, 13, GameData.MIST)

func _draw_sign() -> void:
	if not map.has("sign"):
		return
	var s: Dictionary = map["sign"]
	var base := Vector2(float(s["x"]), float(map["ground"]))
	draw_rect(Rect2(base.x - 3, base.y - 60, 6, 60), Color("6b4433"))
	var w := DrawUtil.text_width(Game.ui_font, s["text"], 13) + 20
	DrawUtil.round_rect(self, Rect2(base.x - w / 2, base.y - 84, w, 28), 5, Color("a77a5a"))
	DrawUtil.text(self, Game.ui_font, base + Vector2(0, -65), s["text"], 13, Color("2b1a14"))
