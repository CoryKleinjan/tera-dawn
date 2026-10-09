class_name AccountStore
extends RefCounted
## Saves and loads player accounts on the server, one JSON file per account in
## `<save folder>/accounts/`. An account is a username, a PasswordHash record (never the
## password) and the names of the characters it owns on this server:
##   {"username": "Rowan_7", "password": {...}, "characters": ["Rowan", "Mira"], "created": 1760000000}
## Accounts belong to the server they were made on; nothing here is shared with any other
## server, so neither accounts nor characters can move between servers.

const MIN_USERNAME := 3
const MAX_USERNAME := 16
const MIN_PASSWORD := 8
const MAX_PASSWORD := 64
## The account the player at the keyboard of a single-player or hosted game uses. The "~"
## can't be typed into a username, so nobody can register it or log in to it from outside.
const LOCAL := "~local"

var folder := ""

func _init(save_folder: String) -> void:
	folder = save_folder.path_join("accounts")
	DirAccess.make_dir_recursive_absolute(folder)

## Why `username` can't be used, or "" if it's fine.
static func username_problem(username: String) -> String:
	if username.length() < MIN_USERNAME or username.length() > MAX_USERNAME:
		return "Usernames are %d to %d characters long." % [MIN_USERNAME, MAX_USERNAME]
	for ch in username:
		if not (ch.is_valid_identifier() or ch.is_valid_int()):
			return "Usernames use only letters, numbers and _."
	return ""

## Why `password` can't be used, or "" if it's fine.
static func password_problem(password: String) -> String:
	if password.length() < MIN_PASSWORD:
		return "Passwords need at least %d characters." % MIN_PASSWORD
	if password.length() > MAX_PASSWORD:
		return "Passwords can be at most %d characters." % MAX_PASSWORD
	return ""

## The key an account is filed under: usernames aren't case sensitive.
static func key(username: String) -> String:
	return username.to_lower()

func _path(username: String) -> String:
	return folder.path_join(key(username) + ".json")

func exists(username: String) -> bool:
	return FileAccess.file_exists(_path(username))

## The saved account, or {} if there isn't one.
func load_account(username: String) -> Dictionary:
	var f := FileAccess.open(_path(username), FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if not data is Dictionary:
		return {}
	var names: Array[String] = []
	for n in data.get("characters", []):
		names.append(str(n))
	data["characters"] = names
	return data

## A new account (not saved yet). `password` is a PasswordHash record ({} for LOCAL).
static func make(username: String, password: Dictionary) -> Dictionary:
	var names: Array[String] = []
	return {"username": username, "password": password, "characters": names, "created": int(Time.get_unix_time_from_system())}

func save(account: Dictionary) -> void:
	var f := FileAccess.open(_path(account["username"]), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(account, "\t"))

## Every saved account (used to find characters no account owns yet).
func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(".json"):
			var a := load_account(f.get_basename())
			if not a.is_empty():
				out.append(a)
	return out

## Whether `account` owns a character called `char_name` (any case).
static func owns(account: Dictionary, char_name: String) -> bool:
	return index_of(account, char_name) >= 0

static func index_of(account: Dictionary, char_name: String) -> int:
	var names: Array = account.get("characters", [])
	for i in names.size():
		if String(names[i]).to_lower() == char_name.to_lower():
			return i
	return -1
