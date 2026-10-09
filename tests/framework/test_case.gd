class_name TestCase
extends Node
## Base for a test file. Every method whose name starts with `test_` is a test; it may
## `await`. `before_each` and `after_each` run around every test. A test fails if any
## check in it fails, and the run carries on with the next test.
##
## Tests live in tests/unit/, tests/server/, tests/content/ and tests/ui/, in files ending
## in `_test.gd`, and are found by tests/run_tests.gd on their own.

## Failures in the test that is running, filled in by the checks.
var failures: Array[String] = []

func before_each() -> void:
	pass

func after_each() -> void:
	pass

# ---------- checks ----------

func check(ok: bool, what: String) -> bool:
	if not ok:
		failures.append(what)
	return ok

# The messages below are only built when a check fails: printing some values (objects
# that point at each other) is slow or recurses.

func check_eq(got: Variant, want: Variant, what: String) -> bool:
	if _same(got, want):
		return true
	return check(false, "%s: got %s, want %s" % [what, _show(got), _show(want)])

func check_ne(got: Variant, unwanted: Variant, what: String) -> bool:
	if not _same(got, unwanted):
		return true
	return check(false, "%s: got %s, wanted anything else" % [what, _show(got)])

func check_near(got: float, want: float, what: String, within := 0.001) -> bool:
	return check(absf(got - want) <= within, "%s: got %s, want %s (±%s)" % [what, got, want, within])

func check_between(got: float, low: float, high: float, what: String) -> bool:
	return check(got >= low and got <= high, "%s: got %s, want %s to %s" % [what, got, low, high])

func check_has(list: Variant, item: Variant, what: String) -> bool:
	if item in list:
		return true
	return check(false, "%s: %s not in %s" % [what, _show(item), _show(list)])

func fail(what: String) -> void:
	failures.append(what)

# ---------- helpers ----------

## Waits for n physics ticks.
func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _same(a: Variant, b: Variant) -> bool:
	# 3 == 3.0 and &"a" == "a" count as the same.
	if typeof(a) != typeof(b):
		if (a is int or a is float) and (b is int or b is float):
			return is_equal_approx(float(a), float(b))
		if (a is String or a is StringName) and (b is String or b is StringName):
			return String(a) == String(b)
		return false
	return a == b

func _show(v: Variant) -> String:
	if v is Object:
		return str(v)
	var s := var_to_str(v)
	return s if s.length() <= 120 else s.substr(0, 117) + "..."
