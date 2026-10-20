extends TestCase
## Every image the game loads fits on the graphics card: Godot can't load a texture wider or
## taller than 16384 px and draws it black instead (Old Clawbeard's strip did, play test
## 2026-10-20). tools/art/slice_sheets.py wraps a long animation strip onto more rows.

const LIMIT := 16384

func _pngs(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_pngs(dir.path_join(d), out)

## A PNG's size, read from its header (bytes 16 to 23, big-endian width then height).
func _size(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	f.big_endian = true
	f.seek(16)
	return Vector2i(f.get_32(), f.get_32())

func test_no_texture_is_too_big_to_load() -> void:
	var pngs: Array[String] = []
	_pngs("res://assets", pngs)
	check(pngs.size() > 100, "the scan finds the game's images")
	for path in pngs:
		var s := _size(path)
		check(s.x <= LIMIT and s.y <= LIMIT, "%s is %dx%d, within %d px" % [path, s.x, s.y, LIMIT])
