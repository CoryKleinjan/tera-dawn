extends Node
## Autoload "Game": this player's side of the game. It keeps a copy of the player's own
## Character (`me`) that the server refreshes, fonts, and the name and server address
## typed on the title screen (saved with the other settings, see the Settings autoload).
## The real Character lives on the server (see TDServer); to change it, ask through Net.

## The input action of each quickslot (Character.quickslots), in order.
const QUICKSLOT_ACTIONS: Array[String] = ["quick_1", "quick_2", "quick_3", "quick_4", "quick_5", "quick_6", "quick_7", "quick_8"]

## The server sent a new copy of the whole character (inventory, gear, stats).
signal character_changed

## The player's character as the server last described it. Read it; don't change it.
var me: Character
## Buddies, party and guild as the server last described them (TDSocial.summary).
var social := {}
## The name typed on the title screen and the last server joined.
var player_name := "Dawnling"
var last_address := "127.0.0.1"

var ui_font: Font
var num_font: Font

func _ready() -> void:
	ui_font = load("res://assets/fonts/Baloo2-Bold.ttf")
	num_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_load_settings()
	me = Character.create(player_name)

func apply_character(data: Dictionary) -> void:
	if me == null or me.name != str(data.get("name", "")):
		me = Character.create(str(data.get("name", player_name)))
	me.load_dict(data)
	character_changed.emit()

func apply_vitals(hp: int, mp: int, xp: int, level: int, shards: int) -> void:
	if level != me.level:
		me.level = level
		me.recalc()
	me.health.set_hp(hp)
	me.mp = mp
	me.xp = xp
	me.shards = shards

## Remembers the name and server address in settings.cfg.
func save_settings() -> void:
	Settings.file.set_value("player", "name", player_name)
	Settings.file.set_value("player", "address", last_address)
	Settings.save()

func _load_settings() -> void:
	player_name = str(Settings.file.get_value("player", "name", player_name))
	last_address = str(Settings.file.get_value("player", "address", last_address))
