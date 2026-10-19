class_name BotClient
extends Node
## A second player for the smoke test's multiplayer check. It joins the host on the port
## given after `--` (over the encrypted connection), makes a character on its own side and
## brings it in, keeps attacking for a while (at least 20 swings), and writes what it saw to
## the file given after the port (RESULT_PATH if none), and what its own save of the
## character holds once it's done:
##   godot --headless --path . res://tests/bot_client.tscn -- 7391 user://smoke_test_bot.json

const RESULT_PATH := "user://smoke_test_bot.json"
const CHARACTER := "Bot"

var world: TDWorld
var result := {"joined": false, "saw_host": false, "saw_mobs": false, "saw_hits": false, "saved": false}

func _ready() -> void:
	_run.call_deferred()

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else Net.DEFAULT_PORT
	var result_path: String = args[1] if args.size() > 1 else RESULT_PATH
	# the bot's characters are its own, apart from the host's
	Net.save_dir = "user://smoke_test_bot_characters_%d" % OS.get_process_id()
	world = load("res://scenes/world.tscn").instantiate() as TDWorld
	add_child(world)
	await _ticks(2)
	Net.welcomed.connect(func() -> void:
		Net.create_character(CHARACTER, NewCharacter.new())
		Net.play(CHARACTER))
	Net.join("127.0.0.1", port)
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
		# landed hits fill the Mana orb (hits show no numbers)
		result["saw_hits"] = result["saw_hits"] or Game.me.mp > 0
		# keep swinging long enough for the host to see a monster defeated
		if i >= 20 and result.keys().all(func(k: String) -> bool: return k == "saved" or result[k]):
			break
	# the host sends the character back to be saved here, at least every few seconds
	var saves := CharacterStore.new(Net.save_dir)
	for i in TDServer.SAVE_EVERY + 60:
		await _ticks(1)
		var c := saves.load_character(CHARACTER)
		if c and c.essence > 0:
			result["saved"] = true
			break
	var f := FileAccess.open(result_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	Net.stop()
	await _ticks(10)
	for file in DirAccess.get_files_at(Net.save_dir):
		DirAccess.remove_absolute(Net.save_dir.path_join(file))
	DirAccess.remove_absolute(Net.save_dir)
	get_tree().quit()
