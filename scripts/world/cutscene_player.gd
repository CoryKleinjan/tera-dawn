class_name TDCutscenePlayer
extends Node
## Plays a CutsceneDef on your screen: runs its steps one after another, once per physics
## tick, moving the camera (WorldCamera.scene_center), walking your hero (TDPlayer.auto_walk)
## and the NPCs, and drawing the black bars, fades and speech box (TDCutsceneOverlay).
## Your controls and the HUD are put away while it plays; holding the menu key skips it.
##
## A cutscene only changes what you see: when it ends, every NPC it moved, turned or hid
## goes back to where it stood, and the camera returns to your hero. Your hero stays where
## it walked them. The server hears it ended (req_scene_done) and won't send it again.

## Hold the menu key this many ticks to skip.
const SKIP_HOLD := 45
## A walking NPC or hero is there once this close to the spot, in game pixels.
const ARRIVED := 3.0
## How close the camera follows someone each tick (0..1 of the way there).
const FOLLOW_EASE := 0.12

var world: TDWorld
var overlay: TDCutsceneOverlay
var def: CutsceneDef
## The step running now (its index in def.steps), and ticks spent on it.
var index := -1
var t := 0
## Ticks the menu key has been held, toward SKIP_HOLD.
var skip_t := 0

## Camera glide: from, to and how far along (CAMERA steps), or who it follows.
var _cam_from := Vector2.ZERO
var _cam_to := Vector2.ZERO
var _cam_t := 0
var _cam_ticks := 0
var _cam_follow: StringName = &""
## Fade and bars: where they started, where they're going, and how far along.
var _fade := Vector3.ZERO # from, to, ticks
var _fade_t := 0
var _bars := Vector3.ZERO
var _bars_t := 0
## who -> [x, speed] for everyone walking.
var _walks := {}
## TDNpc -> [x, face, visible] as they stood before the cutscene touched them.
var _saved := {}
## The music playing before a MUSIC step changed it ("" if none did).
var _music_before: StringName = &""
var _music_changed := false

func _ready() -> void:
	var layer := CanvasLayer.new()
	# above the HUD (TDHud.layer)
	layer.layer = 11
	add_child(layer)
	overlay = TDCutsceneOverlay.new()
	overlay.scenes = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

func playing() -> bool:
	return def != null

## Starts `scene` from its first step (ending any cutscene still playing, unseen).
func play(scene: CutsceneDef) -> void:
	stop()
	if scene == null or scene.steps.is_empty():
		return
	def = scene
	index = -1
	skip_t = 0
	_saved.clear()
	_walks.clear()
	_cam_follow = &""
	_music_changed = false
	world.hud.visible = false
	world.hud.windows["dialogue"].visible = false
	overlay.begin()
	_next()

## Ends the cutscene now without telling the server (a map change, leaving the game).
func stop() -> void:
	if def == null:
		return
	_restore()
	def = null

## Skips to the end, as if it had played through.
func skip() -> void:
	if def and def.skippable:
		_finish()

## One physics tick: the running step, walks, the camera glide, the fade and the bars.
func step() -> void:
	if def == null:
		return
	if def.skippable and Input.is_action_pressed("pause"):
		skip_t += 1
		if skip_t >= SKIP_HOLD:
			_finish()
			return
	else:
		skip_t = 0
	_step_walks()
	_step_camera()
	_step_fades()
	if index < def.steps.size() and _done(def.steps[index]):
		_next()
	else:
		t += 1

## Presses on (a key or a click): shows the rest of a line still appearing, or moves past it.
func advance() -> void:
	if def == null or index >= def.steps.size():
		return
	if def.steps[index].kind != CutsceneStep.Kind.SAY:
		return
	if overlay.typing():
		overlay.finish_typing()
	else:
		_next()

func _unhandled_input(event: InputEvent) -> void:
	if def == null or event.is_action_pressed("toggle_fullscreen"):
		return
	if event.is_echo():
		return
	if event.is_action_pressed("jump") or event.is_action_pressed("move_up") or event.is_action_pressed("chat") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		advance()
	# nothing else reaches the game while a cutscene plays (the menu key is held to skip)
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()

# ---------- steps ----------

func _next() -> void:
	index += 1
	t = 0
	while index < def.steps.size():
		var s := def.steps[index]
		_start(s)
		if not _done(s):
			return
		index += 1
	_finish()

## Starts step `s`. Steps that take no time are done at once.
func _start(s: CutsceneStep) -> void:
	overlay.hide_speech()
	match s.kind:
		CutsceneStep.Kind.FADE:
			_fade = Vector3(overlay.fade, s.amount, s.ticks)
			_fade_t = 0
		CutsceneStep.Kind.BARS:
			_bars = Vector3(overlay.bars, s.amount, s.ticks)
			_bars_t = 0
		CutsceneStep.Kind.CAMERA:
			_cam_follow = &""
			_cam_from = world.camera.center()
			_cam_to = s.at
			_cam_t = 0
			_cam_ticks = s.ticks
			world.camera.scene_center = _cam_from
		CutsceneStep.Kind.CAMERA_FOLLOW:
			_cam_follow = s.who
			_cam_ticks = 0
			if world.camera.scene_center == null:
				world.camera.scene_center = world.camera.center()
		CutsceneStep.Kind.CAMERA_BACK:
			_cam_follow = &""
			_cam_ticks = 0
			world.camera.scene_center = null
		CutsceneStep.Kind.SAY:
			overlay.say(_speaker_name(s), _portrait(s), s.text)
		CutsceneStep.Kind.MOVE:
			var who := _body(s.who)
			if who:
				_save(s.who)
				_walks[s.who] = [s.x, s.speed]
		CutsceneStep.Kind.FACE:
			if s.who == CutsceneStep.HERO:
				world.player.face = s.face
			else:
				var npc := _npc(s.who)
				if npc:
					_save(s.who)
					npc.face = s.face
		CutsceneStep.Kind.SHOW:
			var npc := _npc(s.who)
			if npc:
				_save(s.who)
				npc.visible = s.shown
				npc.rig.visible = s.shown
		CutsceneStep.Kind.MUSIC:
			if not _music_changed:
				_music_before = Sound.current_music
				_music_changed = true
			Sound.music(s.sound)
		CutsceneStep.Kind.SOUND:
			Sound.play(s.sound)
		CutsceneStep.Kind.POSE:
			if s.who == CutsceneStep.HERO:
				world.player.scene_pose = s.pose
			else:
				var npc := _npc(s.who)
				if npc:
					_save(s.who)
					if s.pose == &"":
						npc.rig.hold_still()
					elif npc.rig.has_animation(s.pose):
						npc.rig.play(s.pose)
		CutsceneStep.Kind.PLACE:
			world.show_for_me()

## Whether step `s` is over, so the next can start.
func _done(s: CutsceneStep) -> bool:
	match s.kind:
		CutsceneStep.Kind.WAIT:
			return t >= s.ticks
		CutsceneStep.Kind.FADE:
			return not s.wait or _fade_t >= int(_fade.z)
		CutsceneStep.Kind.BARS:
			return not s.wait or _bars_t >= int(_bars.z)
		CutsceneStep.Kind.CAMERA:
			return not s.wait or _cam_t >= _cam_ticks
		CutsceneStep.Kind.CAMERA_BACK:
			return t >= s.ticks
		CutsceneStep.Kind.SAY:
			return false # until the player presses on (advance)
		CutsceneStep.Kind.MOVE:
			return not s.wait or not _walks.has(s.who)
	return true

func _step_walks() -> void:
	world.player.auto_walk = 0
	for who: StringName in _walks.keys():
		var goal: float = _walks[who][0]
		if who == CutsceneStep.HERO:
			var dx := goal - world.player.position.x
			if absf(dx) <= ARRIVED:
				_walks.erase(who)
			else:
				world.player.auto_walk = 1 if dx > 0 else -1
			continue
		var npc := _npc(who)
		if npc == null:
			_walks.erase(who)
			continue
		var dx := goal - npc.position.x
		var stride: float = _walks[who][1]
		if absf(dx) <= maxf(ARRIVED, stride):
			npc.position.x = goal
			_walks.erase(who)
			if npc.rig.has_animation(&"walk"):
				npc.rig.hold_still()
		else:
			npc.face = 1 if dx > 0 else -1
			npc.position.x += signf(dx) * stride
			if npc.rig.has_animation(&"walk"):
				npc.rig.play(&"walk")

func _step_camera() -> void:
	if _cam_follow != &"":
		var who := _body(_cam_follow)
		if who and world.camera.scene_center is Vector2:
			var at: Vector2 = world.camera.scene_center
			world.camera.scene_center = at.lerp(who.position + Vector2(0, -TDWorld.world_view().y * 0.12), FOLLOW_EASE)
	elif _cam_ticks > 0 and _cam_t < _cam_ticks:
		_cam_t += 1
		var k := smoothstep(0.0, 1.0, float(_cam_t) / _cam_ticks)
		world.camera.scene_center = _cam_from.lerp(_cam_to, k)

func _step_fades() -> void:
	if _fade.z > 0 and _fade_t < int(_fade.z):
		_fade_t += 1
		overlay.fade = lerpf(_fade.x, _fade.y, float(_fade_t) / _fade.z)
	if _bars.z > 0 and _bars_t < int(_bars.z):
		_bars_t += 1
		overlay.bars = lerpf(_bars.x, _bars.y, smoothstep(0.0, 1.0, float(_bars_t) / _bars.z))

## The cutscene played through (or was skipped): put everything back and tell the server.
func _finish() -> void:
	var id := def.id
	_restore()
	def = null
	Net.ask(&"req_scene_done", [id])

func _restore() -> void:
	for npc: TDNpc in _saved:
		if is_instance_valid(npc):
			npc.position.x = _saved[npc][0]
			npc.face = _saved[npc][1]
			npc.visible = _saved[npc][2]
			npc.rig.visible = _saved[npc][2]
			npc.rig.hold_still()
	_saved.clear()
	_walks.clear()
	_cam_follow = &""
	_cam_ticks = 0
	_fade = Vector3.ZERO
	_bars = Vector3.ZERO
	world.player.auto_walk = 0
	world.player.scene_pose = &""
	world.camera.scene_center = null
	if _music_changed:
		Sound.music(_music_before)
		_music_changed = false
	overlay.end()
	world.hud.visible = true
	index = -1
	# quests the cutscene's lines finished can change who stands here
	world.show_for_me()

# ---------- who's who ----------

## Your hero or the NPC with this id on the map (null if they aren't here).
func _body(who: StringName) -> Node2D:
	if who == CutsceneStep.HERO:
		return world.player
	return _npc(who)

func _npc(id: StringName) -> TDNpc:
	for n in world.npcs():
		if n.def.id == id:
			return n
	return null

## Remembers how an NPC stood before the cutscene first changed them.
func _save(id: StringName) -> void:
	var npc := _npc(id)
	if npc and not _saved.has(npc):
		_saved[npc] = [npc.position.x, npc.face, npc.visible]

func _speaker_name(s: CutsceneStep) -> String:
	if s.speaker_name != "":
		return s.speaker_name
	if s.speaker == CutsceneStep.HERO:
		return Game.me.name
	var npc: NpcDef = Content.npcs.get(s.speaker)
	return npc.display_name if npc else ""

func _portrait(s: CutsceneStep) -> Texture2D:
	var placed := _npc(s.speaker)
	if placed:
		return placed.portrait()
	return null
