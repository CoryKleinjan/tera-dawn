class_name BotClient
extends Node
## A second player for the smoke test's multiplayer check. It registers an account on the
## host on the port given after `--` (over the encrypted connection), makes a character and
## plays it, keeps attacking for a while (at least 20 swings), and writes what it saw to the
## file given after the port (RESULT_PATH if none):
##   godot --headless --path . res://tests/bot_client.tscn -- 7391 user://smoke_test_bot.json

const RESULT_PATH := "user://smoke_test_bot.json"
const USERNAME := "smoke_bot"
const PASSWORD := "bot password 123"

var world: TDWorld
var result := {"joined": false, "saw_host": false, "saw_mobs": false, "saw_hits": false}

func _ready() -> void:
	_run.call_deferred()

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else Net.DEFAULT_PORT
	var result_path: String = args[1] if args.size() > 1 else RESULT_PATH
	world = load("res://scenes/world.tscn").instantiate() as TDWorld
	add_child(world)
	await _ticks(2)
	Net.characters_changed.connect(func(_selected: String) -> void: Net.play("Bot"))
	Net.logged_in.connect(func() -> void: Net.create_character("Bot", NewCharacter.new()))
	Net.log_in("127.0.0.1", USERNAME, PASSWORD, true, port)
	for i in 900:
		await _ticks(1)
		if world.started:
			break
	result["joined"] = world.started
	# attack again and again; the host holds a monster in front of us
	for i in 60:
		Input.action_press("attack")
		await _ticks(2)
		Input.action_release("attack")
		await _ticks(26)
		for a in world.avatars.values():
			result["saw_host"] = result["saw_host"] or a.char_name == "Host"
		result["saw_mobs"] = result["saw_mobs"] or world.mobs().any(func(m: TDMob) -> bool: return m.known)
		for f in world.fx_layer.get_children():
			result["saw_hits"] = result["saw_hits"] or (f is TDFloatText and f.kind != "taken")
		# keep swinging long enough for the host to see a monster defeated
		if i >= 20 and result.values().all(func(v: bool) -> bool: return v):
			break
	var f := FileAccess.open(result_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	Net.stop()
	await _ticks(10)
	get_tree().quit()
