extends RefCounted
## Shared by the content tests: finds every .tres under data/ by walking the folders (so a
## file Content doesn't index is still checked), says which Def class each folder holds,
## and names a resource by its file for failure messages.

const DATA := "res://data"

## Folder (under data/) -> the classes a file there may be. The most specific folder wins.
const EXPECTED := {
	"monsters": ["MonsterDef"],
	"monster_moves": ["MonsterMove"],
	"npcs": ["NpcDef"],
	"items": ["ItemDef"],
	"items/equips": ["EquipDef"],
	"items/use": ["UseDef"],
	"items/etc": ["ItemDef"],
	"items/scrolls": ["ScrollDef"],
	"items/setup": ["ChairDef", "PetDef"],
	"skills": ["SkillDef"],
	"effects": ["EffectDef"],
	"maps": ["MapDef"],
	"jobs": ["JobDef"],
	"shops": ["ShopDef"],
	"quests": ["QuestDef"],
	"regions": ["RegionDef"],
	"biomes": ["BiomeDef"],
	"buildings": ["BuildingDef"],
	"climb_styles": ["ClimbStyleDef"],
	"projectiles": ["ProjectileDef"],
	"achievements": ["AchievementDef"],
	"cutscenes": ["CutsceneDef"],
	"hero": ["HeroLookDef"],
}

## Every .tres file under `dir`, sorted.
static func files(dir := DATA) -> Array[String]:
	var out: Array[String] = []
	_walk(dir, out)
	out.sort()
	return out

static func _walk(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(sub), out)
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres") or f.ends_with(".res"):
			out.append(dir.path_join(f))

## The folder of `path` relative to data/ ("items/equips").
static func folder(path: String) -> String:
	return path.get_base_dir().trim_prefix(DATA + "/").trim_prefix(DATA)

## The classes a file in `path`'s folder may be, or [] for a folder nobody expects.
static func expected_classes(path: String) -> Array:
	var f := folder(path)
	while f != "":
		if EXPECTED.has(f):
			return EXPECTED[f]
		f = f.get_base_dir() if f.contains("/") else ""
	return []

## The script class name of a resource ("MonsterDef"), or its engine class.
static func class_of(res: Resource) -> String:
	if res == null:
		return "null"
	var s: Script = res.get_script()
	while s:
		if s.get_global_name() != &"":
			return s.get_global_name()
		s = s.get_base_script()
	return res.get_class()

## "data/maps/meadow.tres" for failure messages (or the id for made-up resources).
static func where(res: Resource) -> String:
	if res == null:
		return "<null>"
	if res.resource_path != "":
		return res.resource_path.trim_prefix("res://")
	var id: Variant = res.get("id")
	return "<%s %s>" % [class_of(res), id]

## Every loaded resource under data/, path -> Resource.
static func load_all() -> Dictionary:
	var out := {}
	for p in files():
		out[p] = load(p)
	return out

## The Content tables, kind -> {id: Resource}.
static func tables() -> Dictionary:
	var out := {}
	for kind in Content.FOLDERS:
		out[kind] = Content.get(kind)
	return out

## "Lv. 10-14" -> Vector2i(10, 14); anything else (Town, "") -> Vector2i(-1, -1).
static func level_range(text: String) -> Vector2i:
	var re := RegEx.create_from_string("^Lv\\. (\\d+)-(\\d+)$")
	var m := re.search(text)
	if m == null:
		return Vector2i(-1, -1)
	return Vector2i(int(m.get_string(1)), int(m.get_string(2)))

## Monsters that live somewhere: every map's roster (spawns and what they split into).
static func spawned_monsters() -> Dictionary:
	var out := {}
	for m: MapDef in Content.maps.values():
		for s in m.spawns:
			if s and s.monster:
				out[s.monster.id] = s.monster
				var child := s.monster.splits_into
				while child and not out.has(child.id):
					out[child.id] = child
					child = child.splits_into
	return out

## Every NPC standing on a map, id -> [MapDef, ...].
static func placed_npcs() -> Dictionary:
	var out := {}
	for m: MapDef in Content.maps.values():
		for p in m.npcs:
			if p and p.npc:
				var list: Array = out.get(p.npc.id, [])
				list.append(m)
				out[p.npc.id] = list
	return out
