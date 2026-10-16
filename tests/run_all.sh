#!/usr/bin/env bash
# Runs every test: the test runner (unit, content, server and UI tests) and the smoke test.
# Fails if any test fails, if Godot printed a script error (which GDScript doesn't
# otherwise turn into a failed test), or if Godot crashed or timed out before printing
# its result line.
#   tests/run_all.sh            everything
#   tests/run_all.sh inventory  only runner tests whose file or name contains "inventory"
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
out="$(mktemp)"
status=0

run() {
	echo "== $1"
	timeout 900 "$GODOT" --headless --path . "${@:2}" 2>&1 | tee "$out" | grep -E "^(FAIL|SCRIPT ERROR|Parse Error)|passed, |FAILURES|stopped"
	local codes=("${PIPESTATUS[@]}")
	if [ "${codes[0]}" -ne 0 ]; then
		echo "Godot exited with code ${codes[0]}$([ "${codes[0]}" -eq 124 ] && echo " (timed out)")"
		status=1
	fi
	if ! grep -qE "passed, |FAILURES" "$out"; then
		echo "No result line: Godot stopped before the tests finished"
		tail -20 "$out"
		status=1
	fi
	if grep -qE "SCRIPT ERROR|Parse Error" "$out"; then
		echo "Godot printed script errors:"
		grep -E -A2 "SCRIPT ERROR|Parse Error" "$out" | head -40
		status=1
	fi
}

run "tests" res://tests/run_tests.tscn -- "${1:-}"
if [ -z "${1:-}" ]; then
	run "smoke test" res://tests/smoke_test.tscn
fi
rm -f "$out"
exit $status
