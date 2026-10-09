extends Node
## Autoload "Game": this player's side of the game. It keeps a copy of the player's own
## Character (`me`) that the server refreshes, fonts, and the username and server address
## typed on the title screen (saved with the other settings, see the Settings autoload;
## the password is never saved).
## The real Character lives on the server (see TDServer); to change it, ask through Net.

## The input action of each quickslot (Character.quickslots), in order.
const QUICKSLOT_ACTIONS: Array[String] = ["quick_1", "quick_2", "quick_3", "quick_4", "quick_5", "quick_6", "quick_7", "quick_8"]

## The server sent a new copy of the whole character (inventory, gear, stats).
signal character_changed

## The player's character as the server last described it. Read it; don't change it.
var me: Character
## Buddies, party and guild as the server last described them (TDSocial.summary).
var social := {}
## The username and server last logged in to.
var last_username := ""
var last_address := "127.0.0.1"

var ui_font: Font
var num_font: Font

func _ready() -> void:
	ui_font = load("res://assets/fonts/Baloo2-Bold.ttf")
	num_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_load_settings()
	me = Character.create("")

func apply_character(data: Dictionary) -> void:
	if me == null or me.name != str(data.get("name", "")):
		me = Character.create(str(data.get("name", "")))
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

## Remembers the username and server address in settings.cfg (never the password).
func save_settings() -> void:
	if Settings.file.has_section_key("player", "name"):
		Settings.file.erase_section_key("player", "name") # from before accounts
	Settings.file.set_value("player", "username", last_username)
	Settings.file.set_value("player", "address", last_address)
	Settings.save()

func _load_settings() -> void:
	last_username = str(Settings.file.get_value("player", "username", last_username))
	last_address = str(Settings.file.get_value("player", "address", last_address))
