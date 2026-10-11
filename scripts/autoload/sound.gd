extends Node
## Autoload "Sound": the game's music and sound effects.
##
## Sounds are files named by id, so adding one means adding a file, not code:
##   assets/audio/music/<id>.ogg   a looping track (`music`) or a short jingle (`jingle`)
##   assets/audio/sfx/<id>.ogg     a sound effect (`play`); <id>_1.ogg, <id>_2.ogg ... are
##                                 variants of one sound, picked at random each time
## Data names the ids: a region's town and field music (RegionDef, MapDef.music_id), an
## effect's sound (EffectDef.sound), a skill's or projectile's sound (SkillDef.cast_sound).
## An id with no file is silent, so nothing breaks while a sound is still being made.
##
## Music plays on the Music bus and effects on the Effects bus, so the settings sliders
## (AudioSettings) reach them. Every button in the game clicks by itself (see _on_node_added).

const MUSIC_DIR := "res://assets/audio/music"
const SFX_DIR := "res://assets/audio/sfx"
## How long one track takes to fade into the next, in seconds.
const CROSSFADE := 1.5
## How far the music dips while a jingle plays over it, and how long it takes to come back.
const DUCK_DB := -20.0
const DUCK_RETURN := 1.0
## Sound effects that can play at once; the oldest is cut off when they're all busy.
const VOICES := 16
## Each effect plays a little higher or lower each time (up to this share) so repeats don't
## sound mechanical.
const PITCH_JITTER := 0.06
## The quietest a track gets while fading, in dB.
const SILENT_DB := -60.0
## Buttons click with this sound (see _on_node_added).
const CLICK := &"click"

## The track playing (or fading in), or &"" for none.
var current_music: StringName = &""
## Two players so one track can fade out while the next fades in.
var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _jingle: AudioStreamPlayer
var _duck: Tween
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
## sfx id -> Array[AudioStream], its variants.
var _sfx := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		_music.append(_player(&"Music"))
	_jingle = _player(&"Music")
	_jingle.finished.connect(_unduck)
	for i in VOICES:
		_voices.append(_player(&"Effects"))
	_sfx = load_sfx(SFX_DIR)
	get_tree().node_added.connect(_on_node_added)

func _player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# ---------- music ----------

## Fades into track `id` (looping). Asking for the track already playing does nothing, so
## walking between maps of one region keeps the music going. &"" fades the music out.
func music(id: StringName) -> void:
	if id == current_music:
		return
	current_music = id
	var old := _music[_active]
	if old.playing:
		_fade(old, SILENT_DB, CROSSFADE).finished.connect(old.stop)
	var stream := music_stream(id)
	if stream == null:
		return
	_active = 1 - _active
	var p := _music[_active]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	_fade(p, 0.0, CROSSFADE)

## Plays the short piece `id` (level up, quest complete) once over the music, which dips
## while it plays.
func jingle(id: StringName) -> void:
	var stream := music_stream(id, false)
	if stream == null:
		return
	_jingle.stream = stream
	_jingle.play()
	if _duck:
		_duck.kill()
	for p in _music:
		if p.playing:
			p.volume_db = DUCK_DB

func _unduck() -> void:
	_duck = create_tween().set_parallel()
	for p in _music:
		if p.playing:
			_duck.tween_property(p, "volume_db", 0.0, DUCK_RETURN)

func _fade(p: AudioStreamPlayer, to_db: float, time: float) -> Tween:
	var t := create_tween()
	t.tween_property(p, "volume_db", to_db, time)
	return t

## The track `id`, set to loop (or not), or null if there's no file for it.
func music_stream(id: StringName, loop := true) -> AudioStream:
	if id == &"":
		return null
	var path := "%s/%s.ogg" % [MUSIC_DIR, id]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	return stream

func has_music(id: StringName) -> bool:
	return ResourceLoader.exists("%s/%s.ogg" % [MUSIC_DIR, id])

# ---------- sound effects ----------

## Plays sound effect `id` (a random variant), `volume_db` louder or quieter than its file.
func play(id: StringName, volume_db := 0.0) -> void:
	var variants: Array = _sfx.get(id, [])
	if variants.is_empty():
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = variants.pick_random()
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()

func has_sound(id: StringName) -> bool:
	return _sfx.has(id)

## Every sound effect in `dir`: id -> its variants. "hit.ogg" is the sound "hit", and
## "hit_1.ogg", "hit_2.ogg" are two variants of it.
static func load_sfx(dir: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		# exported games list "hit.ogg.import" (or .remap) rather than the file itself
		file = file.trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension() != "ogg":
			continue
		var stream: AudioStream = load(dir.path_join(file))
		if stream == null:
			continue
		var id := StringName(sfx_id(file.get_basename()))
		if not out.has(id):
			out[id] = []
		if not stream in out[id]:
			out[id].append(stream)
	return out

## The sound a file of that name belongs to: "hit_2" is a variant of "hit".
static func sfx_id(file_name: String) -> String:
	var cut := file_name.rfind("_")
	if cut > 0 and file_name.substr(cut + 1).is_valid_int():
		return file_name.left(cut)
	return file_name

## Every button clicks when pressed, wherever it was made.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind(CLICK))
