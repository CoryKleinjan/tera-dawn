extends Node
## Runs every test file and quits with exit code 1 if anything failed:
##   godot --headless --path . res://tests/run_tests.tscn
##   godot --headless --path . res://tests/run_tests.tscn -- inventory   (only files or tests whose name contains "inventory")

const DIRS := ["res://tests/unit", "res://tests/content", "res://tests/server", "res://tests/ui"]
## A test that takes longer than this (in seconds) has hung, usually on a script error.
const TEST_TIMEOUT := 120.0

## The test that's running, for the watchdog.
var _current := ""
var _current_started := 0

func _ready() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	if _current != "" and Time.get_ticks_msec() - _current_started > TEST_TIMEOUT * 1000.0:
		print("FAIL %s: still running after %ds; it probably hit a script error" % [_current, TEST_TIMEOUT])
		print("\nstopped: a test hung")
		get_tree().quit(1)
		_current = ""

func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("-"):
			only = a
	var passed := 0
	var failed: Array[String] = []
	var started := Time.get_ticks_msec()
	for path in _files():
		var script := load(path) as Script
		var case: TestCase = null
		if script and script.can_instantiate():
			case = script.new() as TestCase
		if case == null:
			failed.append("%s: not a TestCase" % path)
			continue
		var file := path.get_file().get_basename()
		add_child(case)
		for m in case.get_method_list():
			var test: String = m.name
			if not test.begins_with("test_"):
				continue
			if only != "" and not file.contains(only) and not test.contains(only):
				continue
			case.failures.clear()
			seed(12345) # every test sees the same random numbers
			_current = "%s.%s" % [file, test]
			_current_started = Time.get_ticks_msec()
			await case.before_each()
			await case.call(test)
			await case.after_each()
			if case.failures.is_empty():
				passed += 1
				print("PASS %s.%s" % [file, test])
			else:
				for f in case.failures:
					print("FAIL %s.%s: %s" % [file, test, f])
				failed.append("%s.%s" % [file, test])
		case.queue_free()
		await get_tree().process_frame
	_current = ""
	print("\n%d passed, %d failed in %.1fs" % [passed, failed.size(), (Time.get_ticks_msec() - started) / 1000.0])
	for f in failed:
		print("  failed: " + f)
	get_tree().quit(1 if not failed.is_empty() or passed == 0 else 0)

func _files() -> Array[String]:
	var out: Array[String] = []
	for dir in DIRS:
		_scan(dir, out)
	out.sort()
	return out

func _scan(dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with("_test.gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)
