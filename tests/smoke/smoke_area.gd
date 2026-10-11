class_name SmokeArea
extends RefCounted
## One area of the smoke test (tests/smoke_test.gd): a group of checks the smoke runner calls
## in order, one file per area in tests/smoke/. The runner owns the world, the saves and the
## failure count; an area reaches them, and the runner's helpers, through the forwards below,
## so its checks read as they would in the runner itself.
##
## To add an area: a script here that extends SmokeArea with its checks in a method
## (`check()`, which may `await`), a `var` for it in tests/smoke_test.gd, and a call in its
## `_run()` where it belongs in the play-through.

## The smoke runner (tests/smoke_test.gd).
var runner: Node

## The game the play-through runs in (the runner's).
var world: TDWorld:
	get:
		return runner.world

## The run's test-only character folder (the runner's).
var save_dir: String:
	get:
		return runner.save_dir

func _init(smoke: Node) -> void:
	runner = smoke

func _check(ok: bool, what: String) -> void:
	runner._check(ok, what)

func _ticks(n: int) -> void:
	await runner._ticks(n)

func _hold(action: String, n: int) -> void:
	await runner._hold(action, n)

func _tap(action: String) -> void:
	await runner._tap(action)

func _press(action: String) -> void:
	await runner._press(action)

func _until(cond: Callable, max_ticks: int) -> bool:
	return await runner._until(cond, max_ticks)

func _clear_drops(map: MapInstance) -> void:
	runner._clear_drops(map)

func _hold_mobs(map: MapInstance, keep: Array) -> Array[SimMob]:
	return runner._hold_mobs(map, keep)

func _release_mobs(held: Array[SimMob]) -> void:
	runner._release_mobs(held)

func _first_filled(c: Character, tab: int) -> int:
	return runner._first_filled(c, tab)

func _me() -> SimPlayer:
	return runner._me()

func _teleport(at: Vector2) -> void:
	runner._teleport(at)

func get_viewport() -> Viewport:
	return runner.get_viewport()
