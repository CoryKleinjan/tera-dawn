extends TestCase
## Music keeps playing through quick track changes and jingles (Sound.music, Sound.jingle,
## with time moved on by hand through Sound.advance).

const A := &"town_dawnrise"
const B := &"field_dawnrise"
const C := &"town_dawnharbor"
const JINGLE := &"jingle_levelup"

func before_each() -> void:
	_silence()

func after_each() -> void:
	_silence()

func _silence() -> void:
	Sound._jingle.stop()
	Sound.music(&"")
	_wait(Sound.CROSSFADE + Sound.DUCK_RETURN + 0.5)

## Moves the music on by `seconds`, a frame at a time.
func _wait(seconds: float) -> void:
	var step := 1.0 / 60.0
	var t := 0.0
	while t < seconds:
		Sound.advance(step)
		t += step

## The players playing `id`.
func _playing(id: StringName) -> Array:
	var path := "%s/%s.ogg" % [Sound.MUSIC_DIR, id]
	return Sound._music.filter(func(p: AudioStreamPlayer) -> bool: return p.playing and p.stream.resource_path == path)

func _volume(id: StringName) -> float:
	var players := _playing(id)
	return players[0].volume_db if players.size() == 1 else Sound.SILENT_DB

func test_a_track_fades_in_and_the_old_one_out() -> void:
	Sound.music(A)
	_wait(Sound.CROSSFADE + 0.1)
	check_near(_volume(A), 0.0, "the track is at full volume after the fade")
	Sound.music(B)
	_wait(Sound.CROSSFADE + 0.1)
	check_eq(_playing(A).size(), 0, "the old track stopped once faded out")
	check_near(_volume(B), 0.0, "the new track is at full volume")

func test_two_changes_inside_one_fade_keep_the_music_playing() -> void:
	# joining: the title track, then the preview map's, then the real map's, all at once
	Sound.music(A)
	_wait(0.2)
	Sound.music(B)
	_wait(0.05)
	Sound.music(C)
	_wait(Sound.CROSSFADE * 3)
	check_eq(_playing(C).size(), 1, "the last track asked for is still playing")
	check_near(_volume(C), 0.0, "and at full volume")
	check_eq(_playing(A).size() + _playing(B).size(), 0, "the others stopped")

func test_going_straight_back_fades_the_track_back_in() -> void:
	Sound.music(A)
	_wait(Sound.CROSSFADE + 0.1)
	Sound.music(B)
	_wait(0.3)
	Sound.music(A)
	_wait(Sound.CROSSFADE + 0.1)
	check_eq(_playing(A).size(), 1, "the first track is playing again")
	check_near(_volume(A), 0.0, "at full volume")
	check_eq(_playing(B).size(), 0, "the second one stopped")

func test_a_jingle_dips_the_music_gently_and_it_comes_back() -> void:
	Sound.music(A)
	_wait(Sound.CROSSFADE + 0.1)
	Sound.jingle(JINGLE)
	Sound.advance(1.0 / 60.0)
	check(_volume(A) > Sound.DUCK_DB / 2.0, "the music eases down instead of dropping at once")
	_wait(Sound.DUCK_DOWN + 0.1)
	check_near(_volume(A), Sound.DUCK_DB, "the music is dipped while the jingle plays")
	Sound._jingle.stop()
	_wait(Sound.DUCK_RETURN + 0.1)
	check_near(_volume(A), 0.0, "the music is back to full volume after the jingle")

func test_a_jingle_during_a_change_does_not_bring_the_old_track_back() -> void:
	Sound.music(A)
	_wait(Sound.CROSSFADE + 0.1)
	Sound.music(B)
	_wait(0.5)
	var fading := _volume(A)
	Sound.jingle(JINGLE)
	_wait(0.2)
	check(_volume(A) < fading, "the old track keeps fading out")
	Sound._jingle.stop()
	_wait(Sound.CROSSFADE + Sound.DUCK_RETURN)
	check_eq(_playing(A).size(), 0, "the old track stopped")
	check_near(_volume(B), 0.0, "the new track is at full volume")
