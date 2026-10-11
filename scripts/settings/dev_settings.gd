class_name DevSettings
extends SettingsSection
## Developer-only settings, shown on the settings screen's Developer tab in debug builds only
## (the editor, or a debug export). A release build ignores them, whatever settings.cfg says.
##
## `test_characters`: Play solo and Host log in to the test characters' account, one
## max-level character of every job in its best gear (see TestCharacters), instead of the
## player's own characters, which stay as they were.

var test_characters := false
## Make the test characters again at the next local login (picking up new gear). Not saved.
var rebuild_next := false

func section() -> String:
	return "developer"

func reset() -> void:
	test_characters = false
	rebuild_next = false

func load_from(cfg: ConfigFile) -> void:
	test_characters = cfg.get_value(section(), "test_characters", test_characters) == true

func save_to(cfg: ConfigFile) -> void:
	cfg.set_value(section(), "test_characters", test_characters)

## What to ask for when logging in to the local account (a TestCharacters.Mode). Asking to
## rebuild uses it up.
func login_mode() -> TestCharacters.Mode:
	if not test_characters or not TestCharacters.allowed():
		return TestCharacters.Mode.OFF
	if rebuild_next:
		rebuild_next = false
		return TestCharacters.Mode.REBUILD
	return TestCharacters.Mode.ON
