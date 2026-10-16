extends TestCase
## The characters saved on this computer (CharacterStore): making them with clean, unique
## names, the slot limit, the order character select shows them in, deleting them, and saves
## the host sends back.

var store: CharacterStore
var dir := ""

func before_each() -> void:
	dir = "user://test_character_store_%d" % OS.get_process_id()
	_wipe(dir)
	store = CharacterStore.new(dir)

func after_each() -> void:
	_wipe(dir)

static func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func test_an_empty_name_is_refused() -> void:
	check_eq(store.create("  !!  ", NewCharacter.new()), "Please pick a name.", "why")
	check_eq(store.names(), [] as Array[String], "nothing saved")

func test_names_lose_characters_that_are_not_allowed() -> void:
	check_eq(store.create("  An<n>!  ", NewCharacter.new()), "", "made")
	check_eq(store.names(), ["Ann"] as Array[String], "cleaned name")

func test_names_are_unique_in_any_case() -> void:
	store.create("Ann", NewCharacter.new())
	check_eq(store.create("aNN", NewCharacter.new()), "You already have a character called Ann.", "why")
	check_eq(store.names(), ["Ann"] as Array[String], "not made")

func test_names_that_share_a_save_file_are_too_close() -> void:
	store.create("Al pha", NewCharacter.new())
	check_eq(store.create("Al_pha", NewCharacter.new()), "That name is too close to one you have.", "why")

func test_there_is_room_for_six() -> void:
	for i in CharacterStore.MAX_CHARACTERS:
		check_eq(store.create("Hero%d" % i, NewCharacter.new()), "", "Hero%d made" % i)
	check_eq(store.create("OneMore", NewCharacter.new()), "You can have up to %d characters." % CharacterStore.MAX_CHARACTERS, "why")
	check_eq(store.slots().size(), CharacterStore.MAX_CHARACTERS, "six slots")

func test_listed_in_the_order_they_were_made() -> void:
	for n in ["Zed", "Ann", "Mo"]:
		store.create(n, NewCharacter.new())
	check_eq(store.names(), ["Zed", "Ann", "Mo"] as Array[String], "made order, not by name")
	var slot: Dictionary = store.slots()[0]
	check_eq(slot["name"], "Zed", "slot name")
	check_eq(int(slot["level"]), 1, "slot level")
	check(slot.has("job"), "slot job")

func test_a_new_character_is_a_beginner_with_the_outfit_picked() -> void:
	var made := NewCharacter.new()
	made.outfit[EquipDef.Slot.TOP] = Content.item(&"meadow_shirt")
	store.create("Ann", made)
	var c := store.load_character("ann")
	check_eq(c.name, "Ann", "the name as it was made")
	check_eq(c.job.id, Character.START_JOB, "a Beginner")
	check_eq(c.equipment.at(&"top").item.id, &"meadow_shirt", "the top picked")

func test_deleting_moves_the_save_aside_and_frees_the_name() -> void:
	store.create("Ann", NewCharacter.new())
	store.create("Bob", NewCharacter.new())
	store.remove("ann")
	check_eq(store.names(), ["Bob"] as Array[String], "gone from the list")
	check(FileAccess.file_exists(dir.path_join("deleted/ann.json")), "kept in deleted/")
	check_eq(store.create("Ann", NewCharacter.new()), "", "the name is free again")
	check_eq(store.names(), ["Bob", "Ann"] as Array[String], "at the end")

func test_a_save_from_the_host_replaces_the_character() -> void:
	store.create("Ann", NewCharacter.new())
	var c := store.load_character("Ann")
	c.shards = 321
	store.save_data("Ann", c.to_dict())
	check_eq(store.load_character("Ann").shards, 321, "saved")
	check_eq(store.names(), ["Ann"] as Array[String], "still one")

func test_saves_without_an_order_are_listed_by_name() -> void:
	store.save(Character.create("Mo"))
	store.save(Character.create("Al"))
	DirAccess.remove_absolute(dir.path_join(CharacterStore.ORDER_FILE))
	DirAccess.remove_absolute(dir.path_join(CharacterStore.ORDER_FILE + SafeFile.BACKUP))
	check_eq(store.names(), ["Al", "Mo"] as Array[String], "by name")

func test_a_save_keeps_the_last_good_one_as_a_backup() -> void:
	store.create("Ann", NewCharacter.new())
	var c := store.load_character("Ann")
	c.level = 7
	store.save(c)
	var path := dir.path_join("ann.json")
	check(FileAccess.file_exists(path + SafeFile.BACKUP), "the save before it is kept")
	check(not FileAccess.file_exists(path + SafeFile.TEMP), "no half-written file left")
	check_eq(store.load_character("Ann").level, 7, "the new save loads")

func test_a_broken_save_loads_from_its_backup() -> void:
	store.create("Ann", NewCharacter.new())
	var c := store.load_character("Ann")
	c.level = 7
	store.save(c)
	var f := FileAccess.open(dir.path_join("ann.json"), FileAccess.WRITE)
	f.store_string("{\"name\": \"Ann\", \"lev") # cut off mid-write
	f.close()
	var back := store.load_character("Ann")
	check(back != null, "still loads")
	if back:
		check_eq(back.level, 1, "from the save before")
	check_eq(store.names(), ["Ann"] as Array[String], "still listed")

func test_a_lost_save_is_found_from_its_backup() -> void:
	store.create("Ann", NewCharacter.new())
	store.save(store.load_character("Ann"))
	DirAccess.remove_absolute(dir.path_join("ann.json"))
	check(store.exists("Ann"), "still there")
	check_eq(store.names(), ["Ann"] as Array[String], "still listed")

func test_deleting_moves_the_backup_aside_too() -> void:
	store.create("Ann", NewCharacter.new())
	store.save(store.load_character("Ann"))
	store.remove("Ann")
	check(not store.exists("Ann"), "gone")
	check_eq(store.names(), [] as Array[String], "not listed")
