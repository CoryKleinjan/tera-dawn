class_name TDWorld
extends Node2D
## What the player sees: the map they're on, drawn as an HD-2D diorama by TDStage, with
## their own hero, the monsters, other players, NPCs, drops and effects, plus the camera
## and the HUD. The server decides what happens (see TDServer); this shows its events
## (through Net) and runs your own movement so it feels instant.
## Logic steps once per physics tick (60 Hz) in 2D game pixels (y down).

const VIEW := Vector2(960, 540)
## Picking up more of an item within this many ticks of the last time adds to its log line
## ("Picked up 3 Moss Tuft") instead of writing another.
const PICKUP_MERGE_TICKS := 120

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
## Shows the server's events: swings, damage numbers, shots and effects.
var fx: TDWorldFx
var hud: TDHud
## drop id -> TDDrop
var drops := {}
## peer id -> TDAvatar
var avatars := {}
## peer id -> another player's info (name, level, look...; see MapInstance.send_player_info),
## kept so an avatar made after it arrived still gets it.
var player_infos := {}

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
	fx = TDWorldFx.new(self)
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

## Stops showing the game. Also leaves the server and logs out, unless `stay_connected`
## (going back to character select).
func stop(stay_connected := false) -> void:
	started = false
	if not stay_connected:
		Net.stop()
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	player_infos.clear()
	player.rig.visible = false
	Game.social = {}
	hud.invites.clear()
	hud.chat.clear()
	hud.prompt.answer(false)
	for w: TDWindow in hud.windows.values():
		w.visible = false

## The server put the player on a map: build it and show what's on it.
func enter_map(id: StringName, x: float, state: Dictionary) -> void:
	for w in ["player", "player_shop"]:
		hud.windows[w].visible = false
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
	player_infos.clear()
	# same order as the server's MapInstance, so index i is the same monster on both sides
	for r in map.roster():
		mob_layer.add_child(TDMob.create(self, mob_layer.get_child_count(), r[0], platforms[r[1]]))
	for p in map.npcs:
		npc_layer.add_child(TDNpc.create(self, p, platforms[p.platform]))
	cam = _camera_target()
	stage.build()

func show_banner(text: String) -> void:
	banner_text = text
	banner_t = 180

## You reached an achievement: pop up its toast, and unlock it on Steam.
func show_achievement(id: String) -> void:
	var a := Achievements.find(id)
	if a.is_empty():
		return
	hud.banners.achievement(a)
	SteamService.unlock_achievement(a["steam"])

## Adds a line to the message log (the last six show, each for five seconds). The same
## text twice in a row just keeps the line up longer.
func add_log(text: String, col: Color) -> void:
	if not log_lines.is_empty() and log_lines[-1]["text"] == text:
		log_lines[-1]["t"] = 300
		return
	log_lines.append({"text": text, "color": col, "t": 300})
	if log_lines.size() > 6:
		log_lines.pop_front()

## You picked something up: one log line per item, adding to the last one when you pick up
## the same item again within PICKUP_MERGE_TICKS.
func show_pickup(item: ItemDef, amount: int) -> void:
	for i in log_lines.size():
		var line := log_lines[i]
		if line.get("item") == item.id and tick - int(line["at"]) <= PICKUP_MERGE_TICKS:
			log_lines.remove_at(i)
			_log_pickup(item, int(line["count"]) + amount)
			return
	_log_pickup(item, amount)

func _log_pickup(item: ItemDef, count: int) -> void:
	add_log("Picked up %s" % MapInstance.amount_name(item, count), Palette.MIST)
	log_lines[-1].merge({"item": item.id, "count": count, "at": tick}, true)

## EXP or Dawnshards you just gained, as a small number rising over you.
func show_gain(kind: StringName, amount: int) -> void:
	fx.show_gain(kind, amount)

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

## The other player drawn under a screen point, or null.
func avatar_at(screen_pos: Vector2) -> TDAvatar:
	for a: TDAvatar in avatars.values():
		var feet := stage.screen(a.position, TDStage.Z_OTHER_PLAYER)
		if Rect2(feet + Vector2(-24, -78), Vector2(48, 82)).has_point(screen_pos):
			return a
	return null

## Clicking another player: their shop if they're minding one, otherwise what you can do with them.
func click_avatar(a: TDAvatar) -> void:
	if a.shop_title != "":
		Net.ask(&"req_shop_view", [a.peer])
	else:
		hud.windows["player"].open(a)

## Keys don't move the player while they type or mind a shop.
func input_blocked() -> bool:
	return hud.typing() or hud.selling()

## A chat line arrived; map chat also shows in a bubble over the speaker.
func show_chat(kind: String, from: String, text: String, from_peer: int) -> void:
	hud.chat.add(kind, from, text)
	if kind == "pet":
		var owner := actor(from_peer)
		if owner and owner.get(&"companion"):
			(owner.get(&"companion") as TDCompanion).say(text)
	if kind == "all":
		var who := actor(from_peer)
		if who:
			who.set(&"speech", text)
			who.set(&"speech_t", 300)

func _camera_target() -> Vector2:
	return Vector2(
		clampf(player.position.x - VIEW.x / 2.0, 0, float(map.width) - VIEW.x),
		clampf(player.position.y - VIEW.y * 0.62, 0, float(map.height) - VIEW.y))

# ---------- loop ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Settings.video.toggle_fullscreen()
		Settings.apply(Settings.video)
		Settings.save()
	elif started and not hud.title.visible and event.is_action_pressed("chat") and not hud.typing():
		hud.chat.open()
		get_viewport().set_input_as_handled()
	elif started and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var a := avatar_at(event.position)
		if a:
			click_avatar(a)
	elif event.is_action_pressed("pause"):
		hud.escape()
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

## Where the monsters and other players are now (SnapshotCodec.decode). Monsters left out
## of it haven't changed.
func apply_snapshot(snap: Dictionary) -> void:
	var views := mobs()
	for row: Array in snap.get("mobs", []):
		if row[0] < views.size():
			views[row[0]].apply(row[1])
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
			if player_infos.has(peer):
				avatars[peer].apply_info(player_infos[peer])
		avatars[peer].apply(state)
	for peer in avatars.keys():
		if not seen.has(peer):
			remove_avatar(peer)

## Another player's name, level, look and the like changed.
func set_player_info(peer: int, info: Array) -> void:
	player_infos[peer] = info
	if avatars.has(peer):
		avatars[peer].apply_info(info)

func remove_avatar(peer: int) -> void:
	var a: TDAvatar = avatars.get(peer)
	player_infos.erase(peer)
	if a:
		avatars.erase(peer)
		a.queue_free()

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

# ---------- presentation (see TDWorldFx) ----------

func show_skill(peer: int, skill: SkillDef, at: Vector2, face: int, lines: Array) -> void:
	fx.show_skill(peer, skill, at, face, lines)

func show_mob_shot(index: int, aim: Vector2) -> void:
	fx.show_mob_shot(index, aim)

func show_mob_death(index: int) -> void:
	fx.show_mob_death(index)

func show_level_up(peer: int, level: int) -> void:
	fx.show_level_up(peer, level)

func add_number(pos: Vector2, value: int, kind: String) -> void:
	fx.add_number(pos, value, kind)

## Plays an effect. Effects that follow someone (heal, level up) follow `follow`, or you.
func add_effect(def: EffectDef, pos: Vector2, face: int, follow: Node2D = null) -> void:
	fx.add_effect(def, pos, face, follow)
