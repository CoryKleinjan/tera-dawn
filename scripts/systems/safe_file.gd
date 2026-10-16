class_name SafeFile
extends RefCounted
## Writing save files so a crash or power cut mid-write can't lose them: the new text goes
## to a temporary file first and is swapped in only once it's fully written, and the last
## good copy is kept beside it as `<file>.bak`. Reading falls back to that copy when the
## file itself is missing or unreadable.

const TEMP := ".tmp"
const BACKUP := ".bak"

## Writes `text` to `path`. False if it couldn't be written (the old file is untouched).
static func write_text(path: String, text: String) -> bool:
	var temp := path + TEMP
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if f.get_error() != OK or not FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + BACKUP):
			DirAccess.remove_absolute(path + BACKUP)
		DirAccess.rename_absolute(path, path + BACKUP)
	return DirAccess.rename_absolute(temp, path) == OK

## The JSON in `path` (or, if that's missing or broken, in its backup), or null.
static func read_json(path: String) -> Variant:
	for p in [path, path + BACKUP]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
		if data != null:
			return data
	return null

## Whether `path` or its backup exists.
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BACKUP)
