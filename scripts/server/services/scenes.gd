class_name ServerScenes
extends ServerPart
## Cutscenes on the server: it decides when one plays (the first time a character enters
## a map with an `intro_scene`, or takes or hands in a quest with a scene), sends it to that
## player alone (ev_scene), and notes it as seen when their game says it ended. While a
## scene plays, monsters leave the player alone. The scene itself plays on the client
## (TDCutscenePlayer).

## A scene that hasn't ended after this many ticks stops protecting the player (a client
## that never answered). Five minutes.
const MAX_TICKS := 60 * 60 * 5

## Plays `scene` for `p`, unless it's null, they've seen it, or another is playing.
func play(p: SimPlayer, scene: CutsceneDef) -> void:
	if scene == null or p.scene != &"" or p.character.has_seen(scene.id):
		return
	p.scene = scene.id
	p.scene_t = MAX_TICKS
	Net.send(p.peer, &"ev_scene", [scene.id])

## `p` stands on scene spot `s` (MapInstance.check_spots): its scene plays, and once it ends
## they're sent on. A spot whose scene they've seen sends them on right away.
func at_spot(p: SimPlayer, s: SceneSpot) -> void:
	play(p, s.scene)
	if p.in_scene():
		if s.then_map != &"":
			p.scene_then = s
	elif s.then_map != &"":
		_send_on(p, s)

## Sends `p` where scene spot `s` leads, and plays its arrival scene there.
func _send_on(p: SimPlayer, s: SceneSpot) -> void:
	if not Content.maps.has(s.then_map):
		return
	server.enter_map(p, s.then_map, s.then_x)
	play(p, s.then_scene)

## Their game finished (or skipped) scene `id`: it won't play again.
func on_scene_done(peer: int, id: StringName) -> void:
	var p := player_of(peer)
	if p == null or p.scene == &"" or p.scene != id:
		return
	p.scene = &""
	p.character.saw(id)
	p.dirty_character = true
	server.save(p)
	p.map.wake_tear(p)
	var spot := p.scene_then
	p.scene_then = null
	if spot:
		_send_on(p, spot)

## Stops a scene without noting it as seen (they left the map, or attacked, so it isn't playing).
func stop(p: SimPlayer) -> void:
	p.scene = &""
	p.scene_then = null
	p.scene_t = 0
	if p.map:
		p.map.wake_tear(p)

## One server tick for one player: a scene that ran far too long stops.
func step(p: SimPlayer) -> void:
	if p.scene == &"":
		return
	p.scene_t -= 1
	if p.scene_t <= 0:
		stop(p)
