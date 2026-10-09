extends Node
## The entry scene. Starts a dedicated server when run with `-- --server [--port N]`
## (usually together with --headless), and the game otherwise.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--server" in args:
		add_child(load("res://scenes/world.tscn").instantiate())
		return
	var port := Net.DEFAULT_PORT
	var i := args.find("--port")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		port = int(args[i + 1])
	var problem := Net.run_dedicated(port)
	if problem != "":
		printerr(problem)
		get_tree().quit(1)
