class_name TDWorld
extends Node2D
## What the player sees: the map they're on, drawn as an HD-2D diorama by TDStage, with
## their own hero, the monsters, other players, NPCs, drops and effects, plus the camera
## and the HUD. The server decides what happens (see TDServer); this shows its events
## (through Net) and runs your own movement so it feels instant.
## Logic steps once per physics tick (60 Hz) in 2D game pixels (y down).

const VIEW := Vector2(960, 540)

var map: MapDef
var layout: MapLayout
var platforms: Array[Platform] = []
var started := false
var tick := 0
var cam := Vector2.ZERO
var banner_text := ""
var banner_t := 0
var log_lines: Array[Dictionary] = []

var player: TDPlayer
var stage: TDStage
var mob_layer: Node2D
var npc_layer: Node2D
var drop_layer: Node2D
var avatar_layer: Node2D
var fx_layer: Node2D
var hud: TDHud
## drop id -> TDDrop
var drops := {}
## peer id -> TDAvatar
var avatars := {}

func _ready() -> void:
	Net.world = self
	stage = TDStage.new()
	stage.world = self
	add_child(stage)
	mob_layer = _layer()
	npc_layer = _layer()
	drop_layer = _layer()
	avatar_layer = _layer()
	player = TDPlayer.new()
	player.world = self
	add_child(player)
	fx_layer = _layer()
	hud = TDHud.new()
	hud.world = self
	add_child(hud)
	# the title screen shows the meadow until the server puts the player somewhere
	load_map(Character.START_MAP)
	player.place(map.start_x, platforms[0].y)
	player.rig.visible = false

func _exit_tree() -> void:
	if Net.world == self:
		Net.world = null

func _layer() -> Node2D:
	var n := Node2D.new()
	add_child(n)
	return n

func start() -> void:
	started = true
	player.rig.visible = true

## Leaves the game and goes back to the title screen.
func stop() -> void:
	started = false
	Net.stop()
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	player.rig.visible = false

## The server put the player on a map: build it and show what's on it.
func enter_map(id: StringName, x: float, state: Dictionary) -> void:
	load_map(id)
	player.place(x, platforms[0].y)
	var mob_states: Array = state.get("mobs", [])
	var views := mobs()
	for i in mini(mob_states.size(), views.size()):
		views[i].apply(mob_states[i])
	for d in state.get("drops", []):
		add_drop(d)
	cam = _camera_target()
	stage.follow(cam)
	if started:
		show_banner(map.display_name)

## Builds a map: its layout, the NPCs, a view for each of its monsters (shown once the
## server says where they are) and the stage.
func load_map(id: StringName) -> void:
	map = Content.map(id)
	layout = MapLayout.new(map)
	platforms = layout.platforms
	for layer in [mob_layer, npc_layer, drop_layer, avatar_layer, fx_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	drops.clear()
	avatars.clear()
	# same order as the server's MapInstance, so index i is the same monster on both sides
	for s in map.spawns:
		for i in s.count:
			mob_layer.add_child(TDMob.create(self, mob_layer.get_child_count(), s.monster, platforms[s.platform]))
	for p in map.npcs:
		npc_layer.add_child(TDNpc.create(self, p, platforms[p.platform]))
	cam = _camera_target()
	stage.build()

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

# ---------- queries ----------

func mobs() -> Array[TDMob]:
	var out: Array[TDMob] = []
	for c in mob_layer.get_children():
		out.append(c as TDMob)
	return out

func npcs() -> Array[TDNpc]:
	var out: Array[TDNpc] = []
	for c in npc_layer.get_children():
		out.append(c as TDNpc)
	return out

func npc_near(pos: Vector2) -> TDNpc:
	for n in npcs():
		if absf(pos.x - n.position.x) < 50 and absf(pos.y - n.position.y) < 8:
			return n
	return null

## Your own hero for your peer id, another player's avatar, or null.
func actor(peer: int) -> Node2D:
	if peer == multiplayer.get_unique_id():
		return player
	return avatars.get(peer)

func _camera_target() -> Vector2:
	return Vector2(
		clampf(player.position.x - VIEW.x / 2.0, 0, float(map.width) - VIEW.x),
		clampf(player.position.y - VIEW.y * 0.62, 0, float(map.height) - VIEW.y))

# ---------- loop ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("pause") and started:
		if not hud.close_top_window():
			hud.show_title(true)
	elif started and not hud.title.visible:
		for action in TDHud.WINDOW_ACTIONS:
			if event.is_action_pressed(action):
				hud.toggle_window(action)

func _physics_process(_delta: float) -> void:
	tick += 1
	# the game carries on behind the menu (it's online), but you stand still
	if started and not hud.title.visible:
		player.step()
	for layer in [mob_layer, npc_layer, avatar_layer, drop_layer, fx_layer]:
		for c in layer.get_children():
			c.step()
	for i in range(log_lines.size() - 1, -1, -1):
		log_lines[i]["t"] -= 1
		if log_lines[i]["t"] <= 0:
			log_lines.remove_at(i)
	if banner_t > 0:
		banner_t -= 1
	cam += (_camera_target() - cam) * Vector2(0.12, 0.1)
	stage.follow(cam)

# ---------- events from the server ----------

## Where the monsters and other players are now.
func apply_snapshot(snap: Dictionary) -> void:
	var views := mobs()
	var mob_states: Array = snap.get("mobs", [])
	for i in mini(mob_states.size(), views.size()):
		views[i].apply(mob_states[i])
	var me := multiplayer.get_unique_id()
	var seen := {}
	for state in snap.get("players", []):
		var peer: int = state[0]
		if peer == me:
			continue
		seen[peer] = true
		if not avatars.has(peer):
			avatars[peer] = TDAvatar.create(self, peer)
			avatar_layer.add_child(avatars[peer])
		avatars[peer].apply(state)
	for peer in avatars.keys():
		if not seen.has(peer):
			remove_avatar(peer)

func remove_avatar(peer: int) -> void:
	var a: TDAvatar = avatars.get(peer)
	if a:
		avatars.erase(peer)
		a.queue_free()

## Someone used a skill: their swing (yours already showed), then the damage on each
## monster hit. `lines` is [[mob index, [[damage, kind], ...]], ...].
func show_skill(peer: int, skill: SkillDef, at: Vector2, face: int, lines: Array) -> void:
	if skill == null:
		return
	var who := actor(peer)
	if who is TDAvatar:
		(who as TDAvatar).play_skill(skill)
		add_effect(skill.effect, at + Vector2(0, -40), face)
	var views := mobs()
	for line in lines:
		var m: TDMob = views[line[0]] if line[0] < views.size() else null
		if m == null:
			continue
		var mid := m.body_position() + Vector2(0, -m.def.size.y / 2.0)
		var hits: Array = line[1]
		for i in hits.size():
			var kind: String = hits[i][1]
			add_number(m.body_position() + Vector2(0, -m.def.size.y - 10 - i * 30), hits[i][0], kind)
			if kind == "crit":
				add_effect(Content.effect(&"critical"), mid, face)
		add_effect(skill.hit_effect, mid, face)

func show_mob_death(index: int) -> void:
	var views := mobs()
	if index < views.size():
		var m := views[index]
		m.kill()
		add_effect(Content.effect(&"monster_poof"), m.body_position() + Vector2(0, -m.def.size.y / 2.0), 1)

func show_level_up(peer: int, level: int) -> void:
	var who := actor(peer)
	if who == null:
		return
	add_effect(Content.effect(&"level_up"), who.position, 1, who)
	if who == player:
		player.level_up()
		if level >= 5:
			SteamService.unlock_achievement("REACH_LEVEL_5")

func add_drop(snap: Array) -> void:
	var d := TDDrop.create(self, snap)
	if d.item == null or drops.has(d.id):
		return
	drops[d.id] = d
	drop_layer.add_child(d)

## A drop was picked up (by peer `by`) or vanished (by 0).
func remove_drop(id: int, by: int) -> void:
	var d: TDDrop = drops.get(id)
	if d == null:
		return
	drops.erase(id)
	if by != 0:
		add_effect(d.item.pickup_effect, d.position + Vector2(0, -16), 1)
	d.queue_free()

func add_number(pos: Vector2, value: int, kind: String) -> void:
	var n := TDFloatText.new()
	n.world = self
	n.position = pos
	n.value = value
	n.kind = kind
	fx_layer.add_child(n)

## Plays an effect. Effects that follow someone (heal, level up) follow `follow`, or you.
func add_effect(def: EffectDef, pos: Vector2, face: int, follow: Node2D = null) -> void:
	if def == null:
		return
	if def.follow_player and follow == null:
		follow = player
	fx_layer.add_child(TDEffect.create(self, def, pos, face, follow))
