extends TestCase
## Every sound the game asks for has a file: each map's music, each effect's, skill's and
## projectile's sound, and the ones code names (Sound plays an id with no file as silence,
## so a missing file would otherwise go unnoticed). And sound files are named the way
## Sound expects.

func _music_ids() -> Array[StringName]:
	var out: Array[StringName] = [TDWorld.TITLE_MUSIC]
	for m: MapDef in Content.maps.values():
		out.append(m.music_id())
	return out

func _jingle_ids() -> Array[StringName]:
	return [TDWorldFx.LEVEL_UP_JINGLE, TDPlayer.FAINT_JINGLE, ServerQuests.QUEST_JINGLE, ServerJobs.ADVANCE_JINGLE]

func _sound_ids() -> Dictionary:
	var out := {}  # id -> where it's named
	for e: EffectDef in Content.effects.values():
		if e.sound != &"":
			out[e.sound] = "effect %s" % e.id
	for s: SkillDef in Content.skills.values():
		if s.cast_sound() != &"":
			out[s.cast_sound()] = "skill %s" % s.id
	for m: MonsterDef in Content.monsters.values():
		if m.shot and m.shot.sound != &"":
			out[m.shot.sound] = "monster %s" % m.id
	for id in [Sound.CLICK, TDWindow.OPEN_SOUND, TDWindow.CLOSE_SOUND, TDPlayer.HURT_SOUND, TDPlayer.PORTAL_SOUND]:
		out[id] = "code"
	return out

## The zone, boss and dungeon tracks are being remade (docs/zone-vibes.md): the old ones are
## gone and the new ones land a few at a time, so a map's track may have no file yet and the
## map is silent. Set this back to true once every map's track is in.
const MAP_MUSIC_COMPLETE := false

func test_every_map_has_music() -> void:
	for m: MapDef in Content.maps.values():
		var id := m.music_id()
		if check(id != &"", "%s plays no music: give its region town_music and field_music, or the map its own" % m.id) and MAP_MUSIC_COMPLETE:
			check(Sound.has_music(id), "%s plays %s, but assets/audio/music/%s.ogg is missing" % [m.id, id, id])
	check(Sound.has_music(TDWorld.TITLE_MUSIC), "the title music is missing")

func test_every_jingle_has_a_file() -> void:
	for id in _jingle_ids():
		check(Sound.has_music(id), "jingle %s: assets/audio/music/%s.ogg is missing" % [id, id])

func test_every_sound_has_a_file() -> void:
	var ids := _sound_ids()
	for id in ids:
		check(Sound.has_sound(id), "%s (%s): assets/audio/sfx/%s.ogg is missing" % [id, ids[id], id])

func test_music_loops_and_jingles_do_not() -> void:
	for id in _music_ids():
		var s := Sound.music_stream(id)
		if s is AudioStreamOggVorbis:
			check((s as AudioStreamOggVorbis).loop, "%s loops" % id)
	for id in _jingle_ids():
		var s := Sound.music_stream(id, false)
		if s is AudioStreamOggVorbis:
			check(not (s as AudioStreamOggVorbis).loop, "%s plays once" % id)
			check(s.get_length() < 15.0, "jingle %s is short (%.1f s)" % [id, s.get_length()])

func test_sound_files_are_ogg() -> void:
	for dir in [Sound.MUSIC_DIR, Sound.SFX_DIR]:
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() in ["import", "md"]:
				continue
			check(file.get_extension() == "ogg", "%s/%s: sounds are .ogg files" % [dir, file])

func test_variants_belong_to_one_sound() -> void:
	check_eq(Sound.sfx_id("hit"), "hit", "a plain name is its own sound")
	check_eq(Sound.sfx_id("hit_2"), "hit", "a numbered name is a variant")
	check_eq(Sound.sfx_id("magic_hit"), "magic_hit", "an underscore alone isn't a variant")
	check_eq(Sound.sfx_id("magic_hit_10"), "magic_hit", "variants can go past 9")
