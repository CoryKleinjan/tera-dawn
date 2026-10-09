extends TestCase
## Fails on any error the HUD and content tests print. A script error doesn't fail a test
## by itself: GDScript prints it, abandons the function and carries on, so a window whose
## draw breaks halfway (or a test that breaks halfway) would still pass. This runs those
## suites again in a child Godot, reads its output, and turns every SCRIPT ERROR / ERROR
## printed while one of them ran into a failure naming the test and the line.

## Passed to the child so its copy of this test doesn't start another one.
const CHILD_FLAG := "--error-scan-child"
## Run-test filters for the suites to scan, and the folders their files live in.
const SUITES := {"hud_": "res://tests/ui", "content_": "res://tests/content"}
## Errors from the headless dummy renderer, not from the game.
const IGNORED_SOURCES := ["servers/rendering/dummy/"]

func test_window_and_data_suites_print_no_errors() -> void:
	if CHILD_FLAG in OS.get_cmdline_user_args():
		return
	for suite: String in SUITES:
		var out := []
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/run_tests.tscn", "--", suite, CHILD_FLAG]
		OS.execute(OS.get_executable_path(), args, out, true)
		var text := "\n".join(out)
		if not check(RegEx.create_from_string("(?m)^\\d+ passed, \\d+ failed").search(text) != null, "the %s suites ran to the end in a child Godot:\n%s" % [suite, text.right(2000)]):
			continue
		for problem in errors_by_test(text, SUITES[suite]):
			fail(problem)

## "<test>: <error> (<where>)" for every error printed while a test from a file in `dir`
## ran. An error belongs to the next PASS / FAIL line, the test that was running.
static func errors_by_test(output: String, dir: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = []
	var lines := output.split("\n")
	var error_re := RegEx.create_from_string("^(USER )?(SCRIPT )?ERROR: (.*)$")
	var result_re := RegEx.create_from_string("^(PASS|FAIL) ([A-Za-z0-9_]+)\\.([A-Za-z0-9_]+)")
	for i in lines.size():
		var line := lines[i].strip_edges(false, true)
		if RegEx.create_from_string("^\\d+ passed, \\d+ failed").search(line):
			break
		var e := error_re.search(line)
		if e:
			var where := lines[i + 1].strip_edges() if i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:") else ""
			if not IGNORED_SOURCES.any(func(s: String) -> bool: return where.contains(s)):
				pending.append("%s (%s)" % [e.get_string(3), where.trim_prefix("at: ")])
			continue
		var r := result_re.search(line)
		if r:
			var file := r.get_string(2)
			if ResourceLoader.exists(dir.path_join(file + ".gd")):
				for p in pending:
					out.append("%s.%s printed an error: %s" % [file, r.get_string(3), p])
			pending.clear()
	return out

func test_error_scan_reads_runner_output() -> void:
	# the parser itself, on output shaped like the runner's
	var sample := "\n".join([
		"Godot Engine v4.3",
		"ERROR: Parameter \"m\" is null.",
		"   at: mesh_get_surface_count (servers/rendering/dummy/storage/mesh_storage.h:120)",
		"SCRIPT ERROR: Invalid call. Nonexistent function 'x' in base 'Nil'.",
		"          at: _draw_body (res://scripts/ui/windows/stats_window.gd:12)",
		"PASS hud_windows_test.test_one",
		"PASS hud_windows_test.test_two",
		"ERROR: something else",
		"   at: push_error (core/variant/variant_utility.cpp:1092)",
		"FAIL someone_elses_test.test_three: nope",
		"USER SCRIPT ERROR: boom",
		"   at: f (res://x.gd:1)",
		"PASS hud_windows_test.test_four",
		"",
		"3 passed, 1 failed in 0.1s",
		"ERROR: 297 resources still in use at exit (run with --verbose for details).",
	])
	var got := errors_by_test(sample, "res://tests/ui")
	check_eq(got.size(), 2, "errors found in tests from tests/ui: %s" % [got])
	if got.size() == 2:
		check(got[0].begins_with("hud_windows_test.test_one printed an error: Invalid call") and got[0].contains("stats_window.gd:12"), "names the test, the error and where: %s" % got[0])
		check_eq(got[1], "hud_windows_test.test_four printed an error: boom (f (res://x.gd:1))", "a user script error")
