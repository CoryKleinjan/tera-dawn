extends TestCase
## Every .tres under data/: it loads, it's the Def class its folder holds, its id is
## snake_case, unique and matches its file name, it has a name, every file it points at
## exists, and Content indexes exactly the files in its folders.

const Scan := preload("res://tests/content/content_scan.gd")
const SNAKE := "^[a-z][a-z0-9]*(_[a-z0-9]+)*$"

var _all := {}

func before_each() -> void:
	if _all.is_empty():
		_all = Scan.load_all()

func test_data_folder_has_files() -> void:
	check(_all.size() >= 400, "data/ holds %d .tres files, expected hundreds" % _all.size())

func test_every_file_loads() -> void:
	for path in _all:
		check(_all[path] != null, "%s: failed to load" % path)

func test_every_file_is_the_def_class_its_folder_holds() -> void:
	for path: String in _all:
		var want := Scan.expected_classes(path)
		if want.is_empty():
			fail("%s: folder data/%s is not one the content tests know; add it to content_scan.gd EXPECTED" % [path, Scan.folder(path)])
			continue
		var got := Scan.class_of(_all[path])
		check(got in want, "%s: is a %s, files in data/%s must be %s" % [path, got, Scan.folder(path), " or ".join(want)])

func test_plain_etc_items_are_plain_item_defs() -> void:
	# data/items/etc and the top of data/items hold Etc items, not gear that would land in the wrong tab
	for path: String in _all:
		var f := Scan.folder(path)
		if f == "items/etc" or f == "items":
			var got := Scan.class_of(_all[path])
			check(got == "ItemDef", "%s: is a %s, expected a plain ItemDef (Etc tab)" % [path, got])

func test_every_def_with_an_id_has_one() -> void:
	for path: String in _all:
		var res: Resource = _all[path]
		if res and "id" in res:
			check(String(res.get("id")) != "", "%s: field id is empty" % path)

func test_ids_are_snake_case() -> void:
	var re := RegEx.create_from_string(SNAKE)
	for path: String in _all:
		var res: Resource = _all[path]
		if res and "id" in res:
			var id := String(res.get("id"))
			check(re.search(id) != null, "%s: id %s is not snake_case" % [path, id])

func test_ids_match_file_names() -> void:
	for path: String in _all:
		var res: Resource = _all[path]
		if res and "id" in res:
			check_eq(String(res.get("id")), path.get_file().get_basename(), "%s: field id" % path)

func test_ids_are_unique_per_kind() -> void:
	# a kind is a top-level folder (items/ and its subfolders share one table)
	var seen := {}
	for path: String in _all:
		var res: Resource = _all[path]
		if res == null or not "id" in res:
			continue
		var kind := Scan.folder(path).get_slice("/", 0)
		var key := "%s/%s" % [kind, res.get("id")]
		if seen.has(key):
			fail("%s: id %s is also used by %s" % [path, res.get("id"), seen[key]])
		seen[key] = path

func test_monster_book_cards_do_not_clash_with_item_ids() -> void:
	for path: String in _all:
		if Scan.folder(path).begins_with("items") and String(_all[path].get("id")).begins_with("card_"):
			fail("%s: item ids starting with card_ are kept for Monster Book cards" % path)

func test_named_defs_have_names() -> void:
	for path: String in _all:
		var res: Resource = _all[path]
		if res == null:
			continue
		for field in ["display_name", "title"]:
			if field in res and not (res is MapDef and field == "title"):
				check(String(res.get(field)).strip_edges() != "", "%s: %s is empty" % [path, field])

func test_items_skills_and_jobs_have_descriptions() -> void:
	for path: String in _all:
		var res: Resource = _all[path]
		if res is SkillDef or res is JobDef or res is EquipDef or res is UseDef:
			if res is JobDef and (res as JobDef).advances_from == &"":
				continue # the Beginner is never offered by an instructor
			check(String(res.get("description")).strip_edges() != "", "%s: description is empty" % path)

func test_every_referenced_file_exists() -> void:
	var re := RegEx.create_from_string("\\[ext_resource [^\\]]*path=\"([^\"]+)\"")
	for path: String in _all:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var dep := m.get_string(1)
			check(ResourceLoader.exists(dep), "%s: points at %s, which doesn't exist" % [path, dep])

func test_every_referenced_file_has_the_declared_type() -> void:
	# a texture slot pointing at a .tres (or the reverse) would load as the wrong thing
	var re := RegEx.create_from_string("\\[ext_resource type=\"(\\w+)\"[^\\]]*path=\"([^\"]+)\"")
	for path: String in _all:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var type := m.get_string(1)
			var dep := m.get_string(2)
			if type == "Texture2D":
				check(dep.get_extension() in ["png", "svg", "webp", "jpg"], "%s: Texture2D %s is not an image" % [path, dep])
			elif type == "Script":
				check(dep.begins_with("res://scripts/data/"), "%s: uses script %s from outside scripts/data/" % [path, dep])

func test_content_indexes_every_file_in_its_folders() -> void:
	for kind: String in Content.FOLDERS:
		var table: Dictionary = Content.get(kind)
		for path in Scan.files(Content.FOLDERS[kind]):
			var res: Resource = _all.get(path)
			if res == null:
				continue
			var id: StringName = res.get("id")
			if not table.has(id):
				fail("%s: Content.%s has no entry %s" % [path, kind, id])
			elif table[id].resource_path != path:
				fail("%s: Content.%s[%s] is %s instead" % [path, kind, id, table[id].resource_path])

func test_content_has_nothing_without_a_file() -> void:
	for kind: String in Content.FOLDERS:
		var table: Dictionary = Content.get(kind)
		for id in table:
			var res: Resource = table[id]
			if res is CardDef:
				continue # made at startup for every monster
			if kind == "items" and id in Content.extra_items:
				continue # the tests' own gear
			check(res.resource_path.begins_with(Content.FOLDERS[kind] + "/"),
				"Content.%s[%s]: comes from %s, not a file in %s" % [kind, id, res.resource_path, Content.FOLDERS[kind]])

func test_every_monster_has_a_monster_book_card() -> void:
	for id in Content.monsters:
		var m: MonsterDef = Content.monsters[id]
		var card := Content.card(m)
		if check(card != null, "%s: Content has no card_%s" % [Scan.where(m), id]):
			check(card.monster == m and card.icon != null and card.display_name != "", "%s: card_%s is incomplete" % [Scan.where(m), id])
	var cards := Content.items.values().filter(func(i: ItemDef) -> bool: return i is CardDef)
	check_eq(cards.size(), Content.monsters.size(), "Monster Book cards, one per monster")
