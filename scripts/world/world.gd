class_name TDWorld
extends Node2D
## What the player sees: the map they're on, drawn as a lit diorama by TDStage, with
## their own hero, the monsters, other players, NPCs, drops and effects, plus the camera
## and the HUD. The server decides what happens (see TDServer); this shows its events
## (through Net) and runs your own movement so it feels instant.
## Logic steps once per physics tick (60 Hz) in 2D game pixels (y down). The camera is a
## WorldCamera, and the server's snapshots, player info and drops go through SnapshotSync.

## The size of the game's canvas in game pixels. The height is always at least 540 and the
## width at least 960; a wider or taller window (16:10 like the Steam Deck, ultrawide) shows
## more of the world instead of black bars (see _on_resized).
static var VIEW := Vector2(960, 540)
## Picking up more of an item within this many ticks of the last time adds to its log line
## ("Picked up 3 Moss Tuft") instead of writing another.
const PICKUP_MERGE_TICKS := 120
## How long the map-name banner shows, and how long it waits first (so it arrives after the
## fade into a new map).
const BANNER_TICKS := 150
const BANNER_DELAY := 16
## The title screen's track (Sound.music id).
const TITLE_MUSIC := &"title"
## Sounds in the world are full volume within SOUND_NEAR game pixels of your hero, fade out
## to nothing at SOUND_FAR, and come SOUND_FADE_DB quieter just before that.
const SOUND_NEAR := 200.0
const SOUND_FAR := 900.0
const SOUND_FADE_DB := -18.0

var map: MapDef
## How far the world has declined on this map (TearState): the stage shows its light and fog.
var decline := 0
var layout: MapLayout
var platforms: Array[Platform] = []
var started := false
var tick := 0
## Follows your hero (see WorldCamera).
var camera: WorldCamera
## The top left of what the camera shows, in game pixels.
var cam: Vector2:
	get:
		return camera.pos
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
## Plays cutscenes the server sends (see TDCutscenePlayer).
var scenes: TDCutscenePlayer
var hud: TDHud
## Keeps the monsters, other players and drops in step with the server (see SnapshotSync).
var sync: SnapshotSync
## drop id -> TDDrop
var drops: Dictionary:
	get:
		return sync.drops
## peer id -> TDAvatar
var avatars: Dictionary:
	get:
		return sync.avatars
## peer id -> another player's info (see SnapshotSync.player_infos).
var player_infos: Dictionary:
	get:
		return sync.player_infos

func _ready() -> void:
	Net.world = self
	camera = WorldCamera.new(self)
	sync = SnapshotSync.new(self)
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
	scenes = TDCutscenePlayer.new()
	scenes.world = self
	add_child(scenes)
	Game.character_changed.connect(func() -> void:
		if not scenes.playing():
			show_for_me())
	# the title screen shows the meadow until the server puts the player somewhere
	load_map(Character.START_MAP)
	player.place(map.start_x, platforms[0].y)
	snap_camera()
	Sound.music(TITLE_MUSIC)

func _exit_tree() -> void:
	if Net.world == self:
		Net.world = null

func _layer() -> Node2D:
	var n := Node2D.new()
	add_child(n)
	return n

func start() -> void:
	started = true
	# no music change here: the map still loaded is the title screen's, and the server
	# sends the real one (enter_map) right after, which starts its track

## Stops showing the game. Also leaves the server and logs out, unless `stay_connected`
## (going back to character select).
func stop(stay_connected := false) -> void:
	started = false
	scenes.stop()
	if not stay_connected:
		Net.stop()
	sync.clear_avatars()
	Game.social = {}
	hud.invites.clear()
	hud.chat.clear()
	hud.prompt.answer(false)
	for w: TDWindow in hud.windows.values():
		w.visible = false
	Sound.music(TITLE_MUSIC)

## The server put the player on a map, at `x` on platform `platform`: build it and show
## what's on it.
func enter_map(id: StringName, x: float, state: Dictionary, platform := 0) -> void:
	# a cutscene belongs to the map it started on (the server stops it too)
	scenes.stop()
	hud.windows["player"].visible = false
	load_map(id, state.get("decline", 0))
	player.place(x, platforms[platform].y)
	var mob_states: Array = state.get("mobs", [])
	var views := mobs()
	for i in mini(mob_states.size(), views.size()):
		views[i].apply(mob_states[i])
	for d in state.get("drops", []):
		add_drop(d)
	stage.show_tears(state.get("tear", false))
	snap_camera()
	# the new map fades in from dark (the portal faded the old one out)
	stage.set_faded(1.0)
	stage.fade_to(0.0)
	if started:
		show_banner(map.display_name)
		Sound.music(map.music_id())

## Builds a map: its layout, the NPCs, a view for each of its monsters (shown once the
## server says where they are) and the stage. `step`: how far the world has declined (TearState).
func load_map(id: StringName, step := 0) -> void:
	map = Content.map(id)
	decline = step
	layout = MapLayout.new(map)
	platforms = layout.platforms
	for layer in [mob_layer, npc_layer, drop_layer, avatar_layer, fx_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	sync.clear()
	# same order as the server's MapInstance, so index i is the same monster on both sides
	for r in map.roster():
		mob_layer.add_child(TDMob.create(self, mob_layer.get_child_count(), TearState.kind(r[0], decline),
			platforms[r[1]]))
	for p in map.npcs:
		npc_layer.add_child(TDNpc.create(self, p, platforms[p.platform]))
	camera.jump_to_target()
	stage.build()

## Shows the NPCs and portals that are there for you at this point of your quests (an NPC's
## NpcPlacement, a portal's opens_after). A cutscene calls it when it ends.
func show_for_me() -> void:
	for n: TDNpc in npc_layer.get_children():
		n.refresh()
	stage.show_open_portals(Game.me)
	stage.show_breakables(Game.me)

func show_banner(text: String) -> void:
	banner_text = text
	banner_t = BANNER_TICKS + BANNER_DELAY

## You reached an achievement: pop up its toast, and unlock it on Steam.
func show_achievement(id: String) -> void:
	var a := Achievements.find(id)
	if a == null:
		return
	hud.banners.achievement(a)
	SteamService.unlock_achievement(a.steam)

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

## The NPCs standing here for you (not ones your quests hide, see TDNpc.shown).
func npcs() -> Array[TDNpc]:
	var out: Array[TDNpc] = []
	for c: TDNpc in npc_layer.get_children():
		if c.shown:
			out.append(c)
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

## Clicking another player: what you can do with them.
func click_avatar(a: TDAvatar) -> void:
	hud.windows["player"].open(a)

## Keys don't move the player while they type or watch a cutscene.
func input_blocked() -> bool:
	return hud.holds_input() or scenes.playing()

## The server started cutscene `id` for you. One this game doesn't have is answered as
## finished, so the server doesn't wait on it.
## The map's tear just opened (MapDef.tear_platform).
func open_tear() -> void:
	stage.show_tears(true)

## Bright sparks where a blow lands on a chest or wall.
const STRUCK_SPARKS := Color(2.6, 2.2, 1.4)

## A chest or wall you hit shook, or broke open (`broke`): a hit flash on it, and when it
## breaks a burst of sparks and dust with the find sound. A fake wall you walked into just
## fades with the find sound.
func strike_breakable(i: int, broke: bool) -> void:
	if i < 0 or i >= map.breakables.size():
		return
	stage.strike_breakable(i, broke)
	var b := map.breakables[i]
	if b.walk_through:
		Sound.play(&"sparkle")
		return
	var foot := Vector2(b.x, platforms[b.platform].y)
	var middle := foot - Vector2(0, b.size().y / 2.0)
	add_effect(Content.effects.get(&"hit"), middle, 1)
	if broke:
		fx.burst(middle, STRUCK_SPARKS, 24, 1.2)
		fx.dust(foot, 0, 14)
		Sound.play(&"sparkle")

func play_scene(id: StringName) -> void:
	var def: CutsceneDef = Content.cutscenes.get(id)
	if def == null:
		Net.ask(&"req_scene_done", [id])
		return
	scenes.play(def)

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

## How much of the world the camera shows, in game pixels: the canvas, zoomed by WorldCamera.ZOOM.
static func world_view() -> Vector2:
	return VIEW / WorldCamera.ZOOM

## Puts the camera on the hero at once (a new map, a respawn), with nothing to glide from.
func snap_camera() -> void:
	_prev.clear()
	camera.snap()

## Shakes the screen (see WorldCamera.shake).
func shake(amount: float) -> void:
	camera.shake(amount)

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
	scenes.step()
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
	camera.step()

func _process(_delta: float) -> void:
	camera.draw()

# ---------- events from the server ----------

## Where the monsters and other players are now (see SnapshotSync).
func apply_snapshot(snap: Dictionary) -> void:
	sync.apply_snapshot(snap)

## Another player's name, look and the like changed.
func set_player_info(peer: int, info: Array) -> void:
	sync.set_player_info(peer, info)

func remove_avatar(peer: int) -> void:
	sync.remove_avatar(peer)

func add_drop(snap: Array) -> void:
	sync.add_drop(snap)

## A drop was picked up (by peer `by`) or vanished (by 0).
func remove_drop(id: int, by: int) -> void:
	sync.remove_drop(id, by)

# ---------- presentation (see TDWorldFx) ----------

func show_skill(peer: int, skill: SkillDef, at: Vector2, face: int, lines: Array, aim := 0) -> void:
	fx.show_skill(peer, skill, at, face, lines, aim as Hitbox.Aim)

func show_mob_shot(index: int, move_index: int, aim: Vector2) -> void:
	fx.show_mob_shot(index, move_index, aim)

func show_mob_death(index: int) -> void:
	fx.show_mob_death(index)

func fly_essence(from: Vector2, amount: int) -> void:
	fx.fly_essence(from, amount)

func show_level_up(peer: int, level: int) -> void:
	fx.show_level_up(peer, level)

func add_number(pos: Vector2, value: int, kind: String) -> void:
	fx.add_number(pos, value, kind)

## Plays sound effect `id` coming from `pos` in the world: quieter the further it is from
## your hero, and not at all beyond SOUND_FAR.
func sound_at(id: StringName, pos: Vector2) -> void:
	var d := pos.distance_to(player.position)
	if id == &"" or d >= SOUND_FAR:
		return
	var k := clampf((d - SOUND_NEAR) / (SOUND_FAR - SOUND_NEAR), 0.0, 1.0)
	Sound.play(id, SOUND_FADE_DB * k)

## Plays an effect. Effects that follow someone (heal, level up) follow `follow`, or you.
func add_effect(def: EffectDef, pos: Vector2, face: int, follow: Node2D = null, aim := Hitbox.Aim.AHEAD) -> void:
	fx.add_effect(def, pos, face, follow, aim)

## Shows buff `skill`'s aura round `who` for `ticks` (TDWorldFx.add_aura).
func add_aura(who: Node2D, skill: SkillDef, ticks: int) -> void:
	fx.add_aura(who, skill, ticks)
