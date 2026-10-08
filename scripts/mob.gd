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

# ---------- HD-2D visuals ----------

var body: Sprite3D
var glow: Sprite3D
var flame_light: OmniLight3D
var shadow: Sprite3D
var z := 0.0
var last_x := 0.0

func _ready() -> void:
	z = randf_range(0.15, 0.32)
	body = TDStage.sprite(TDStage.tex(type), 4)
	add_child(body)
	if type == "emberboar":
		glow = TDStage.glow_sprite(TDStage.tex("emberboar_glow"), Color(2.4, 1.5, 0.8), 4)
		glow.offset = body.offset
		add_child(glow)
		flame_light = TDStage.light(Color("ff8a4a"), 1.6, 3.5)
		add_child(flame_light)
	shadow = TDStage.sprite(TDStage.tex("blob_shadow"), 1, false)
	shadow.offset = Vector2.ZERO
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = TDStage.PIXEL * float(d["w"]) / 40.0
	shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

func _process(_delta: float) -> void:
	if body == null or world == null:
		return
	var alpha := 1.0
	if dead:
		alpha = death_t / 30.0
	body.visible = alpha > 0.0
	body.transparency = 1.0 - alpha
	body.modulate = Color(2.2, 1.0, 1.0) if hurt_t > 0 and hurt_t % 4 < 2 else Color.WHITE
	var facing := dir
	if facing == 0:
		facing = -1 if world.player.position.x < position.x else 1
	var moving := absf(position.x - last_x) > 0.01
	last_x = position.x
	var frame := int(phase * 1.2) % 4
	if type == "emberboar":
		frame = int(phase * 2.0) % 4 if moving or hurt_t > 0 else 0
	body.frame = frame
	body.flip_h = facing < 0
	var p := TDStage.to3d(position, z)
	body.position = p
	shadow.position = TDStage.to3d(position, -0.25) + Vector3(0, 0.02, 0) # on the platform top, behind its front edge
	shadow.visible = not dead
	if glow:
		glow.frame = frame
		glow.flip_h = body.flip_h
		glow.position = p + Vector3(0, 0, 0.01)
		glow.visible = body.visible
		glow.transparency = body.transparency
		flame_light.position = p + Vector3(0, 1.4, 0.4)
		flame_light.light_energy = (1.4 + sin(phase * 5.0) * 0.3) * alpha

## Name tag and HP bar, drawn by the overlay at this monster's projected screen position.
func draw_tag(ci: CanvasItem, at: Vector2) -> void:
	if dead:
		return
	var label := "Lv.%d %s" % [int(d["lvl"]), d["name"]]
	var w := DrawUtil.text_width(Game.ui_font, label, 11) + 12
	DrawUtil.round_rect(ci, Rect2(at.x - w / 2, at.y + 4, w, 16), 4, Color(0.1, 0.07, 0.19, 0.6))
	DrawUtil.text(ci, Game.ui_font, at + Vector2(0, 16), label, 11, GameData.MIST)
	if show_hp > 0:
		var bw := maxf(40.0, float(d["w"]))
		var top := at.y - float(d["h"]) - 14
		ci.draw_rect(Rect2(at.x - bw / 2, top, bw, 6), Color(0, 0, 0, 0.55))
		ci.draw_rect(Rect2(at.x - bw / 2 + 1, top + 1, (bw - 2) * maxf(0, float(hp) / float(d["hp"])), 4), GameData.HP)
