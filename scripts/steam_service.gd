extends Node
## Autoload "SteamService": a thin wrapper so the game runs with or without Steam.
##
## Install the GodotSteam GDExtension (addons/godotsteam) and set APP_ID to your
## Steamworks app ID. Until then every call here is a harmless no-op.

const APP_ID := 480 # Valve's public test app "Spacewar". Replace with Tera Dawn's app ID.

var steam: Object = null
var enabled := false

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	var result: Variant = steam.call("steamInitEx", false, APP_ID)
	enabled = result is Dictionary and int(result.get("status", 1)) == 0
	if not enabled:
		push_warning("Steam did not start: %s" % [result])

func _process(_delta: float) -> void:
	if enabled:
		steam.call("run_callbacks")

func unlock_achievement(id: String) -> void:
	if not enabled:
		return
	steam.call("setAchievement", id)
	steam.call("storeStats")
