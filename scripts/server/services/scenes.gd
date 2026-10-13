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

## Their game finished (or skipped) scene `id`: it won't play again.
func on_scene_done(peer: int, id: StringName) -> void:
	var p := player_of(peer)
	if p == null or p.scene == &"" or p.scene != id:
		return
	p.scene = &""
	p.character.saw(id)
	p.dirty_character = true
	server.save(p)

## Stops a scene without noting it as seen (they left the map, or attacked, so it isn't playing).
func stop(p: SimPlayer) -> void:
	p.scene = &""
	p.scene_t = 0

## One server tick for one player: a scene that ran far too long stops.
func step(p: SimPlayer) -> void:
	if p.scene == &"":
		return
	p.scene_t -= 1
	if p.scene_t <= 0:
		stop(p)
