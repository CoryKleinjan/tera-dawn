extends Node
## Autoload "Settings": the player's settings, kept in user://settings.cfg and applied when
## the game starts. Each group is a SettingsSection (scripts/settings/): the keyboard
## controls, audio and video. The settings screen changes a section, calls `apply` so the
## change shows at once, and `save` when it closes. Game keeps its own [player] section in
## the same file through `file`.

## A section was applied; listeners (the stage, the key hints) read what they need from it.
signal changed(section: SettingsSection)

const PATH := "user://settings.cfg"

var keybinds := Keybinds.new()
var audio := AudioSettings.new()
var video := VideoSettings.new()
var sections: Array[SettingsSection] = [keybinds, audio, video]
## The whole file, so sections this doesn't own (Game's [player]) survive a save.
var file := ConfigFile.new()
## Where the file is saved (tests point this somewhere else).
var path := PATH

func _ready() -> void:
	load_file()

## Reads the file (defaults for anything missing) and applies every section.
func load_file() -> void:
	file = ConfigFile.new()
	file.load(path)
	for s in sections:
		s.reset()
		s.load_from(file)
		s.apply()

func apply(s: SettingsSection) -> void:
	s.apply()
	changed.emit(s)

func reset(s: SettingsSection) -> void:
	s.reset()
	apply(s)

func save() -> void:
	for s in sections:
		s.save_to(file)
	file.save(path)
