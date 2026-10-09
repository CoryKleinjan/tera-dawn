class_name AudioSettings
extends SettingsSection
## Volume for each audio bus (see default_bus_layout.tres) and a mute for everything.
## Sounds should play on the Music or Effects bus so these sliders reach them.

const BUSES: Array[String] = ["Master", "Music", "Effects"]
const DEFAULT_VOLUME := {"Master": 1.0, "Music": 0.8, "Effects": 0.8}

## Bus name -> volume from 0 (silent) to 1 (full).
var volume := {}
var muted := false

func section() -> String:
	return "audio"

func reset() -> void:
	volume = DEFAULT_VOLUME.duplicate()
	muted = false

func load_from(cfg: ConfigFile) -> void:
	for bus in BUSES:
		var v: Variant = cfg.get_value(section(), bus.to_lower(), volume[bus])
		if v is float or v is int:
			volume[bus] = clampf(float(v), 0.0, 1.0)
	muted = bool(cfg.get_value(section(), "muted", muted))

func save_to(cfg: ConfigFile) -> void:
	for bus in BUSES:
		cfg.set_value(section(), bus.to_lower(), volume[bus])
	cfg.set_value(section(), "muted", muted)

func apply() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v: float = volume[bus]
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.0 or (bus == "Master" and muted))
