extends TestCase
## Cutscenes are sound: every one in data/cutscenes has no problems, the maps and quests that
## play one point at a file Content knows, and the NPCs a map's intro moves or lets speak
## stand on that map. Also keeps the main story's secret: no text the game shows (names,
## lines, quest and item text) mentions Tera's Dawn, the curse, the tears or the other dawns.

const Scan := preload("res://tests/content/content_scan.gd")

## Words that give the main story away. Story cutscenes are left out: Cory OKs their text.
const SECRETS := ["tera's dawn", "dawn curse", "white hole", "other dawn", "the tears"]

func test_every_cutscene_has_no_problems() -> void:
	for d: CutsceneDef in Content.cutscenes.values():
		check_eq(String(d.id), Scan.where(d).get_file().get_basename(), "%s: id matches the file name" % Scan.where(d))
		for p in d.problems():
			fail("%s: %s" % [Scan.where(d), p])

func _indexed(scene: CutsceneDef, what: String) -> void:
	if scene == null:
		return
	if check(Content.cutscenes.has(scene.id), "%s plays %s, which isn't in data/cutscenes" % [what, Scan.where(scene)]):
		check(Content.cutscenes[scene.id] == scene, "%s plays a copy of %s" % [what, Scan.where(scene)])

func test_maps_and_quests_play_cutscenes_content_knows() -> void:
	for m: MapDef in Content.maps.values():
		_indexed(m.intro_scene, "%s: intro_scene" % Scan.where(m))
		for s in m.scene_spots:
			_indexed(s.scene, "%s: a scene spot" % Scan.where(m))
			_indexed(s.then_scene, "%s: a scene spot's then_scene" % Scan.where(m))
	for q: QuestDef in Content.quests.values():
		_indexed(q.start_scene, "%s: start_scene" % Scan.where(q))
		_indexed(q.finish_scene, "%s: finish_scene" % Scan.where(q))

func test_a_maps_intro_only_uses_npcs_on_that_map() -> void:
	for m: MapDef in Content.maps.values():
		if m.intro_scene == null:
			continue
		var here := {}
		for p in m.npcs:
			if p and p.npc:
				here[p.npc.id] = true
		for id in m.intro_scene.npcs():
			check(here.has(id), "%s: its intro uses %s, who doesn't stand there" % [Scan.where(m), id])

## A scene spot's scenes only use NPCs standing where they play, it stands on a platform the
## map has, and it sends you to a map that exists.
func test_scene_spots_are_sound() -> void:
	for m: MapDef in Content.maps.values():
		for s in m.scene_spots:
			check(s.platform >= 0 and s.platform <= m.platforms.size(), "%s: a scene spot is on platform %d, which isn't there" % [Scan.where(m), s.platform])
			check(s.scene != null or s.then_map != &"" or s.glow != Vector2.ZERO, "%s: a scene spot does nothing" % Scan.where(m))
			if s.then_map != &"" and check(Content.maps.has(s.then_map), "%s: a scene spot sends you to %s, which isn't a map" % [Scan.where(m), s.then_map]):
				_npcs_on(s.then_scene, Content.maps[s.then_map], "%s: a scene spot's then_scene" % Scan.where(m))
			_npcs_on(s.scene, m, "%s: a scene spot" % Scan.where(m))

func _npcs_on(scene: CutsceneDef, m: MapDef, what: String) -> void:
	if scene == null:
		return
	var here := m.npcs.filter(func(p: NpcPlacement) -> bool: return p and p.npc).map(func(p: NpcPlacement) -> StringName: return p.npc.id)
	for id in scene.npcs():
		check(id in here, "%s uses %s, who doesn't stand on %s" % [what, id, m.id])

## Every bit of text a resource holds, as [field, text].
func _texts(res: Resource) -> Array:
	var out := []
	for prop in res.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var v: Variant = res.get(prop.name)
		if v is String or v is StringName:
			out.append([prop.name, String(v)])
		elif v is PackedStringArray:
			for line in v:
				out.append([prop.name, line])
	return out

func test_no_text_gives_the_story_away() -> void:
	var re := RegEx.create_from_string("\\b(%s)\\b" % "|".join(SECRETS).replace("'", "'?"))
	var tables := Scan.tables()
	tables.erase("cutscenes")
	for kind: String in tables:
		for res: Resource in tables[kind].values():
			for t: Array in _texts(res):
				var hit := re.search(String(t[1]).to_lower())
				check(hit == null, "%s: %s mentions \"%s\" (a story secret)" % [Scan.where(res), t[0], hit.get_string() if hit else ""])
