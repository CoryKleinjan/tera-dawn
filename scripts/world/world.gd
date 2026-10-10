class_name TDWorld
extends Node2D
## What the player sees: the map they're on, drawn as an HD-2D diorama by TDStage, with
## their own hero, the monsters, other players, NPCs, drops and effects, plus the camera
## and the HUD. The server decides what happens (see TDServer); this shows its events
## (through Net) and runs your own movement so it feels instant.
## Logic steps once per physics tick (60 Hz) in 2D game pixels (y down).

## The size of the game's canvas in game pixels. The height is always at least 540 and the
## width at least 960; a wider or taller window (16:10 like the Steam Deck, ultrawide) shows
## more of the world instead of black bars (see _on_resized).
static var VIEW := Vector2(960, 540)
## How far ahead of the hero the camera looks in the direction they walk, in game pixels.
const LOOK_AHEAD := 70.0
## The camera only follows a jump once the hero is this far above or below where they last stood.
const CAM_DEAD_ZONE := 90.0
## Picking up more of an item within this many ticks of the last time adds to its log line
## ("Picked up 3 Moss Tuft") instead of writing another.
const PICKUP_MERGE_TICKS := 120
## How long the map-name banner shows, and how long it waits first (so it arrives after the
## fade into a new map).
const BANNER_TICKS := 150
const BANNER_DELAY := 16

var map: MapDef
var layout: MapLayout
var platforms: Array[Platform] = []
var started := false
var tick := 0
var cam := Vector2.ZERO
var _cam_prev := Vector2.ZERO
var _look := 0.0
var _cam_floor := 0.0
## Screen shake strength (0..1); it fades by itself (see shake()).
var _shake := 0.0
## node -> where it was at the last tick, for drawing between ticks (see drawn()).
var _prev := {}
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
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
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
	snap_camera()
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
	snap_camera()
	# the new map fades in from dark (the portal faded the old one out)
	stage.set_faded(1.0)
	stage.fade_to(0.0)
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
	banner_t = BANNER_TICKS + BANNER_DELAY

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
		clampf(player.position.x + _look - VIEW.x / 2.0, 0, maxf(0.0, float(map.width) - VIEW.x)),
		clampf(_cam_floor - VIEW.y * 0.62, 0, maxf(0.0, float(map.height) - VIEW.y)))

## Puts the camera on the hero at once (a new map, a respawn), with nothing to glide from.
func snap_camera() -> void:
	_cam_floor = player.position.y
	_look = 0.0
	cam = _camera_target()
	_cam_prev = cam
	_prev.clear()
	stage.follow(cam)

## Moves the camera's aim one tick: a little ahead of the way the hero walks, and up or
## down only once they land somewhere new (or jump or fall well past where they stood).
func _aim_camera() -> void:
	if absf(player.vel.x) > 0.3:
		_look = move_toward(_look, player.face * LOOK_AHEAD, 1.6)
	var y := player.position.y
	if player.on_ground or player.is_climbing() or absf(y - _cam_floor) > CAM_DEAD_ZONE:
		_cam_floor += (y - _cam_floor) * (1.0 if absf(y - _cam_floor) > 400.0 else 0.25)

## Shakes the screen (a crit, a boss slam, getting hit): 0.3 is a nudge, 1 is a big hit.
## Off when the player turned screen shake off in the video settings.
func shake(amount: float) -> void:
	if Settings.video.screen_shake:
		_shake = minf(1.0, maxf(_shake, amount))

## Where a node that moves once per tick should be drawn this frame: between where it was at
## the last two ticks, so movement is smooth on any screen (120 Hz, 144 Hz, the Deck's 40 Hz).
func drawn(n: Node2D) -> Vector2:
	var before: Variant = _prev.get(n)
	if before == null or (before as Vector2).distance_to(n.position) > 64.0:
		return n.position  # new, or it jumped (a portal, a respawn): no gliding
	return (before as Vector2).lerp(n.position, Engine.get_physics_interpolation_fraction())

func _on_resized() -> void:
	fit_to(get_viewport().get_visible_rect().size)

## Lays the camera and HUD out for a screen of `size` (in UI pixels: 960 wide, taller on
## 16:10 screens like the Steam Deck's).
func fit_to(size: Vector2) -> void:
	VIEW = Vector2(maxf(960.0, size.x), maxf(540.0, size.y))
	if stage and stage.camera:
		stage.fit_view()
	if hud:
		hud.fit_view()

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
	_prev.clear()
	_prev[player] = player.position
	# the game carries on behind the menu (it's online), but you stand still
	if started and not hud.title.visible:
		player.step()
	for layer in [mob_layer, npc_layer, avatar_layer, drop_layer, fx_layer]:
		for c in layer.get_children():
			_prev[c] = c.position
			c.step()
	for i in range(log_lines.size() - 1, -1, -1):
		log_lines[i]["t"] -= 1
		if log_lines[i]["t"] <= 0:
			log_lines.remove_at(i)
	if banner_t > 0:
		banner_t -= 1
	_cam_prev = cam
	_aim_camera()
	cam += (_camera_target() - cam) * Vector2(0.12, 0.1)
	_shake = maxf(0.0, _shake - 0.04)

func _process(_delta: float) -> void:
	var at := _cam_prev.lerp(cam, Engine.get_physics_interpolation_fraction())
	if _shake > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		var k := _shake * _shake * 9.0
		at += Vector2(sin(t * 71.0), cos(t * 53.0)) * k
	stage.follow(at)

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
	var taker := actor(by) if by != 0 else null
	if taker:
		d.collect(taker)  # it flies to them, then sparkles
	elif by != 0:
		add_effect(d.item.pickup_effect, d.position + Vector2(0, -16), 1)
		d.queue_free()
	else:
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
