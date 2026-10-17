class_name CharacterStore
extends RefCounted
## The characters saved on this computer, one JSON file per character name, in the order
## they were made (`order.json`). Each player keeps their own characters here and brings
## one along to whatever game they play: solo, hosting, or joining a friend's (see Net).
## Deleted characters are moved to `deleted/`, where they can be put back by hand. Saves
## are written through SafeFile, so each keeps a `.bak` of the last good save.

const MAX_NAME := 12
## How many characters character select has room for.
const MAX_CHARACTERS := 6
const ORDER_FILE := "order.json"

var folder := "user://characters"

func _init(dir := "user://characters") -> void:
	folder = dir
	DirAccess.make_dir_recursive_absolute(folder)

## A name with only the characters allowed in names, or "" if nothing usable is left.
static func clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.is_valid_identifier() or ch.is_valid_int() or ch == " ":
			out += ch
	return out.strip_edges().substr(0, MAX_NAME)

func _path(char_name: String) -> String:
	return folder.path_join(char_name.to_lower().replace(" ", "_") + ".json")

func exists(char_name: String) -> bool:
	return SafeFile.exists(_path(char_name))

## The saved character with this name (in any case), named as it was made, or null if
## there isn't one.
func load_character(char_name: String) -> Character:
	return load_file(_path(char_name), "")

## Reads a character from a save file, named `char_name` or, if that's "", the name saved
## in the file. Null if it's missing or unreadable.
static func load_file(path: String, char_name: String) -> Character:
	var data: Variant = SafeFile.read_json(path)
	if not data is Dictionary:
		return null
	return from_dict(data, char_name)

## A character from saved data, named `char_name` or, if that's "", the name in the data.
## The server uses this for the character a player brings into its game.
static func from_dict(data: Dictionary, char_name := "") -> Character:
	if char_name == "":
		char_name = CharacterStore.clean_name(str(data.get("name", "")))
	var c := Character.create(char_name)
	c.load_dict(data)
	c.name = char_name
	return c

## The name saved in the file `char_name` would use, or "" if there's none. Names that only
## differ in case or by a space for an _ share a file, so this may be spelled differently.
func saved_name(char_name: String) -> String:
	var c := load_file(_path(char_name), "")
	return c.name if c else ""

## Every character saved here.
func saved_characters() -> Array[Character]:
	var out: Array[Character] = []
	var files := DirAccess.get_files_at(folder)
	for f in files:
		# a save whose file was lost mid-write still has its backup
		if f.ends_with(".json" + SafeFile.BACKUP) and not files.has(f.trim_suffix(SafeFile.BACKUP)):
			f = f.trim_suffix(SafeFile.BACKUP)
		if f.ends_with(".json") and f != ORDER_FILE:
			var c := load_file(folder.path_join(f), "")
			if c and c.name != "":
				out.append(c)
	return out

## The name of every character saved here, in the order they were made (saves the order
## doesn't know yet, copied in by hand say, go at the end by name).
func names() -> Array[String]:
	var out: Array[String] = []
	var order: Variant = SafeFile.read_json(folder.path_join(ORDER_FILE))
	if order is Array:
		for n in order:
			var saved := saved_name(str(n))
			if saved != "" and not out.has(saved):
				out.append(saved)
	var rest: Array[String] = []
	for c in saved_characters():
		if not out.has(c.name):
			rest.append(c.name)
	rest.sort()
	out.append_array(rest)
	return out

func _save_order(list: Array[String]) -> void:
	SafeFile.write_text(folder.path_join(ORDER_FILE), JSON.stringify(list))

## The characters as character select shows them ({name, level, job}), at most
## MAX_CHARACTERS, in the order they were made.
func slots() -> Array:
	var out := []
	for n in names():
		var c := load_character(n)
		if c:
			out.append({"name": c.name, "level": c.level, "job": c.job.display_name})
		if out.size() >= MAX_CHARACTERS:
			break
	return out

## Why a new character can't be called `raw_name` here, or "".
func name_problem(raw_name: String) -> String:
	var char_name := clean_name(raw_name)
	if char_name == "":
		return "Please pick a name."
	if exists(char_name):
		# names that only differ in case are the same name; ones that share a save file
		# some other way (a space for an _) are too close
		var held := saved_name(char_name)
		if held != "" and held.to_lower() != char_name.to_lower():
			return "That name is too close to one you have."
		return "You already have a character called %s." % (held if held != "" else char_name)
	return ""

## Makes and saves a new character from the creator's choices. Returns "" or why not.
func create(raw_name: String, made: NewCharacter) -> String:
	if names().size() >= MAX_CHARACTERS:
		return "You can have up to %d characters." % MAX_CHARACTERS
	var why := name_problem(raw_name)
	if why != "":
		return why
	var c := Character.create(clean_name(raw_name), Character.START_JOB, made)
	save(c)
	return ""

## Moves a character's save to `deleted/` (replacing an older deleted one of that name).
func remove(char_name: String) -> void:
	var list := names()
	var gone := folder.path_join("deleted")
	DirAccess.make_dir_recursive_absolute(gone)
	var to := gone.path_join(_path(char_name).get_file())
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	DirAccess.rename_absolute(_path(char_name), to)
	# its backup goes too, so it doesn't come back
	if FileAccess.file_exists(_path(char_name) + SafeFile.BACKUP):
		if FileAccess.file_exists(to + SafeFile.BACKUP):
			DirAccess.remove_absolute(to + SafeFile.BACKUP)
		DirAccess.rename_absolute(_path(char_name) + SafeFile.BACKUP, to + SafeFile.BACKUP)
	for n in list.duplicate():
		if n.to_lower() == char_name.to_lower():
			list.erase(n)
	_save_order(list)

func save(c: Character) -> void:
	save_data(c.name, c.to_dict())

## Saves a character's data (Character.to_dict) under `char_name`, adding it to the end of
## the order if it's new.
func save_data(char_name: String, data: Dictionary) -> void:
	var fresh := not exists(char_name)
	SafeFile.write_text(_path(char_name), JSON.stringify(data))
	if fresh:
		var list := names()
		if not list.has(char_name):
			list.append(char_name)
		_save_order(list)
