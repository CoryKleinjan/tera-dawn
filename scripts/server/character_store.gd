class_name CharacterStore
extends RefCounted
## Saves and loads characters on the server, one JSON file per character name.
## (Accounts and passwords come later; for now a name is a character.)

const MAX_NAME := 12

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
	return FileAccess.file_exists(_path(char_name))

## The saved character with this name, or null if there isn't one.
func load_character(char_name: String) -> Character:
	return load_file(_path(char_name), char_name)

## Reads a character from any save file (also the single-player save from before
## multiplayer). Null if it's missing or unreadable.
static func load_file(path: String, char_name: String) -> Character:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if not data is Dictionary:
		return null
	var c := Character.create(char_name)
	c.load_dict(data)
	c.name = char_name
	return c

func save(c: Character) -> void:
	var f := FileAccess.open(_path(c.name), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(c.to_dict()))
