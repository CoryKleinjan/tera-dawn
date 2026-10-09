class_name CharacterStore
extends RefCounted
## Saves and loads characters on the server, one JSON file per character name. Names are
## unique on a server (whispers, buddies and guilds go by name). Which account owns a
## character is kept by AccountStore; deleted characters are moved to `deleted/`, where
## the server's owner can put them back by hand.

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
## multiplayer), named `char_name` or, if that's "", the name saved in the file. Null if
## it's missing or unreadable.
static func load_file(path: String, char_name: String) -> Character:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if not data is Dictionary:
		return null
	if char_name == "":
		char_name = CharacterStore.clean_name(str(data.get("name", "")))
	var c := Character.create(char_name)
	c.load_dict(data)
	c.name = char_name
	return c

## The name of every character saved here.
func saved_names() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(".json"):
			var c := load_file(folder.path_join(f), "")
			if c and c.name != "":
				out.append(c.name)
	return out

## Moves a character's save to `deleted/` (replacing an older deleted one of that name).
func remove(char_name: String) -> void:
	var gone := folder.path_join("deleted")
	DirAccess.make_dir_recursive_absolute(gone)
	var to := gone.path_join(_path(char_name).get_file())
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	DirAccess.rename_absolute(_path(char_name), to)

func save(c: Character) -> void:
	var f := FileAccess.open(_path(c.name), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(c.to_dict()))
