extends Node
## Autoload "Content": every monster, NPC, item, skill, effect, job, map, shop, quest,
## achievement and cutscene in data/, by id.
##
## Content is plain Godot resources (.tres) loaded from these folders at startup, so adding
## a monster or a map means adding a file, not code. Lookups by an unknown id push an error
## and return null.

const FOLDERS := {
	"monsters": "res://data/monsters",
	"npcs": "res://data/npcs",
	"items": "res://data/items",
	"skills": "res://data/skills",
	"effects": "res://data/effects",
	"maps": "res://data/maps",
	"jobs": "res://data/jobs",
	"shops": "res://data/shops",
	"quests": "res://data/quests",
	"regions": "res://data/regions",
	"achievements": "res://data/achievements",
	"cutscenes": "res://data/cutscenes",
}

var monsters := {}
var npcs := {}
var items := {}
## Items loaded by add_items_from rather than from data/ (the tests' own gear).
var extra_items: Array[StringName] = []
var skills := {}
var effects := {}
var maps := {}
var jobs := {}
var shops := {}
var quests := {}
var regions := {}
## AchievementDefs; Achievements lists them in order and measures them.
var achievements := {}
var cutscenes := {}

func _ready() -> void:
	for kind in FOLDERS:
		set(kind, _load_folder(FOLDERS[kind], {}))
	# every monster has a Monster Book card, made here rather than kept as files
	var art: Texture2D = load("res://assets/sprites/items/monster_card.png")
	for m in monsters.values():
		var card := CardDef.for_monster(m, art)
		items[card.id] = card

## Loads more items from a folder: the tests' own gear (tests/fixtures/gear), which they wear
## and trade (the game itself has only the starter sets).
## Their ids are kept in `extra_items`, so checks on the game's own content can leave them out.
func add_items_from(path: String) -> void:
	var more := _load_folder(path, {})
	for id: StringName in more:
		items[id] = more[id]
		extra_items.append(id)

## The Monster Book card of a monster.
func card(m: MonsterDef) -> CardDef:
	return items.get(StringName("card_%s" % m.id))

func monster(id: StringName) -> MonsterDef:
	return _lookup(monsters, id, "monster")

func npc(id: StringName) -> NpcDef:
	return _lookup(npcs, id, "NPC")

func item(id: StringName) -> ItemDef:
	return _lookup(items, id, "item")

func skill(id: StringName) -> SkillDef:
	return _lookup(skills, id, "skill")

func effect(id: StringName) -> EffectDef:
	return _lookup(effects, id, "effect")

func map(id: StringName) -> MapDef:
	return _lookup(maps, id, "map")

func job(id: StringName) -> JobDef:
	return _lookup(jobs, id, "job")

func shop(id: StringName) -> ShopDef:
	return _lookup(shops, id, "shop")

func quest(id: StringName) -> QuestDef:
	return _lookup(quests, id, "quest")

func cutscene(id: StringName) -> CutsceneDef:
	return _lookup(cutscenes, id, "cutscene")

## The quests an NPC gives or takes in, in the order they're defined.
func quests_of(npc_id: StringName) -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	for q: QuestDef in quests.values():
		if q.giver == npc_id or q.turn_in_npc() == npc_id:
			out.append(q)
	return out

func _lookup(table: Dictionary, id: StringName, what: String) -> Resource:
	if not table.has(id):
		push_error("Unknown %s id: %s" % [what, id])
		return null
	return table[id]

## Loads every resource in a folder and its subfolders into a dictionary keyed by its `id`.
func _load_folder(path: String, out: Dictionary) -> Dictionary:
	if not DirAccess.dir_exists_absolute(path):
		return out
	for sub in DirAccess.get_directories_at(path):
		_load_folder(path.path_join(sub), out)
	for file in DirAccess.get_files_at(path):
		# exported builds list text resources as "name.tres.remap"
		file = file.trim_suffix(".remap")
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(path.path_join(file))
		var id: StringName = res.get("id") if res else &""
		if id == &"":
			push_error("%s has no id" % path.path_join(file))
			continue
		if out.has(id):
			push_error("Two resources use the id %s in %s" % [id, path])
		out[id] = res
	return out
