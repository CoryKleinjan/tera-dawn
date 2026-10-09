class_name SettingsSection
extends RefCounted
## One group of the player's settings (controls, audio, video), kept in settings.cfg under
## its own [section]. The Settings autoload holds one of each. To add a new group, extend
## this, fill in the methods below and add it to Settings.sections.

## The [section] name in settings.cfg.
func section() -> String:
	return ""

## Puts every value back to its default.
func reset() -> void:
	pass

## Reads the values saved in `cfg`, keeping the current value for anything missing or bad.
func load_from(_cfg: ConfigFile) -> void:
	pass

func save_to(_cfg: ConfigFile) -> void:
	pass

## Makes the game use the current values.
func apply() -> void:
	pass
