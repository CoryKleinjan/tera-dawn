extends TestCase
## Guilds (founding cost and level, names, invitations, leaving, saving) and fame (from
## level 15, once a day, the same player once a month).

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

const CLERK_X := 400.0

var h: ServerHarness
var ann: SimPlayer
var bob: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()
	var town := ServerHarness.town_def()
	ServerHarness.npc(town, &"test_clerk", CLERK_X).guild = true
	ServerHarness.npc(town, &"test_elder", 1500.0)
	h.add_map(town)
	ann = h.join(2, "Ann", ServerHarness.TOWN, CLERK_X)
	bob = h.join(3, "Bob", ServerHarness.TOWN, 600.0)

func after_each() -> void:
	h.close()

func _found(name := "Dawnguard") -> void:
	ann.character.level = TDSocial.GUILD_LEVEL
	ann.character.shards = TDSocial.GUILD_COST
	h.ask(2, &"req_guild_create", [&"test_clerk", name])

# ---------- guilds ----------

func test_founding_a_guild_costs_its_fee() -> void:
	_found()
	check_eq(ann.character.shards, 0, "15000 paid")
	check_eq(ann.character.guild, "Dawnguard", "Ann's guild")
	var g: Dictionary = h.server.social.guild_of("Ann")
	check_eq(g["master"], "Ann", "master")
	check(h.told(2, "You founded the guild Dawnguard!"), "told")

func test_founding_needs_the_level() -> void:
	ann.character.level = TDSocial.GUILD_LEVEL - 1
	ann.character.shards = TDSocial.GUILD_COST
	h.ask(2, &"req_guild_create", [&"test_clerk", "Dawnguard"])
	check_eq(ann.character.guild, "", "no guild")
	check_eq(ann.character.shards, TDSocial.GUILD_COST, "nothing paid")
	check(h.told(2, "You need to be level 10 to found a guild."), "told")

func test_founding_needs_the_dawnshards() -> void:
	ann.character.level = TDSocial.GUILD_LEVEL
	ann.character.shards = TDSocial.GUILD_COST - 1
	h.ask(2, &"req_guild_create", [&"test_clerk", "Dawnguard"])
	check_eq(ann.character.guild, "", "no guild")
	check_eq(ann.character.shards, TDSocial.GUILD_COST - 1, "nothing paid")
	check(h.told(2, "Founding a guild costs 15000 Dawnshards."), "told")

func test_guild_names_need_three_letters() -> void:
	_found("Ab!")
	check_eq(ann.character.guild, "", "no guild")
	check(h.told(2, "Pick a guild name of at least 3 letters."), "told")

func test_guild_names_are_unique_in_any_case() -> void:
	_found()
	h.ask(2, &"req_social", [&"leave_guild", ""])
	h.server.social.guilds["dawnguard"] = {"name": "Dawnguard", "master": "Old", "members": ["Old"]}
	_found("DAWNGUARD")
	check_eq(ann.character.guild, "", "no guild")
	check(h.told(2, "There's already a guild called DAWNGUARD."), "told")

func test_guilds_are_founded_only_at_the_guild_npc() -> void:
	ann.character.level = TDSocial.GUILD_LEVEL
	ann.character.shards = TDSocial.GUILD_COST
	h.place(ann, 1500.0)
	h.ask(2, &"req_guild_create", [&"test_elder", "Dawnguard"])
	check_eq(ann.character.shards, TDSocial.GUILD_COST, "an NPC without guilds does nothing")
	h.ask(2, &"req_guild_create", [&"test_clerk", "Dawnguard"])
	check_eq(ann.character.shards, TDSocial.GUILD_COST, "the clerk is too far away")

func test_guilds_are_saved_and_loaded_by_a_new_server() -> void:
	_found()
	h.leave(2)
	h.leave(3)
	h.restart()
	check_eq(h.server.social.guild_of("Ann").get("name"), "Dawnguard", "loaded from guilds.data")
	var again := h.join(2, "Ann", ServerHarness.TOWN)
	check_eq(again.character.guild, "Dawnguard", "Ann is back in it")

func test_the_master_invites_and_members_join() -> void:
	_found()
	h.ask(2, &"req_chat", ["/guild invite Bob"])
	check_eq(h.last(3, &"ev_invite").slice(1), ["guild", "Ann", "Ann invites you to the guild Dawnguard."], "asked")
	h.ask(3, &"req_invite_answer", [h.last(3, &"ev_invite")[0], true])
	check_eq(bob.character.guild, "Dawnguard", "Bob joined")
	check_has(h.server.social.guild_of("Ann")["members"], "Bob", "on the roll")
	h.clear()
	h.ask(3, &"req_chat", ["/g hello guild"])
	check_eq(h.last(2, &"ev_chat"), ["guild", "Bob", "hello guild", 3], "guild chat")

func test_only_the_master_invites() -> void:
	_found()
	h.ask(2, &"req_social", [&"guild", "Bob"])
	h.ask(3, &"req_invite_answer", [h.last(3, &"ev_invite")[0], true])
	h.join(4, "Cat", ServerHarness.TOWN)
	h.ask(3, &"req_social", [&"guild", "Cat"])
	check_eq(h.count(4, &"ev_invite"), 0, "not asked")
	check(h.told(3, "Only a guild master can invite."), "told")

func test_the_master_leaving_hands_the_guild_on() -> void:
	_found()
	h.ask(2, &"req_social", [&"guild", "Bob"])
	h.ask(3, &"req_invite_answer", [h.last(3, &"ev_invite")[0], true])
	h.ask(2, &"req_chat", ["/guild leave"])
	check_eq(ann.character.guild, "", "Ann left")
	check_eq(h.server.social.guild_of("Bob")["master"], "Bob", "Bob is master")

func test_the_last_member_leaving_disbands_the_guild() -> void:
	_found()
	h.ask(2, &"req_social", [&"leave_guild", ""])
	check(h.server.social.guilds.is_empty(), "gone")
	check(h.told(2, "Dawnguard was disbanded."), "told")

func test_founding_twice_is_refused() -> void:
	_found()
	_found("Second")
	check(not h.server.social.guilds.has("second"), "no second guild")
	check(h.told(2, "You're already in a guild."), "told")

# ---------- fame ----------

func _famous() -> void:
	ann.character.level = TDSocial.FAME_LEVEL

func test_fame_needs_level_15() -> void:
	ann.character.level = TDSocial.FAME_LEVEL - 1
	h.ask(2, &"req_fame", [3, true])
	check_eq(bob.character.fame, 0, "no fame")
	check(h.told(2, "You can give fame from level 15."), "told")

func test_raising_someones_fame() -> void:
	_famous()
	h.ask(2, &"req_fame", [3, true])
	check_eq(bob.character.fame, 1, "+1")
	check_eq(ann.character.fame_day, SocialGuilds.today(), "Ann's daily fame spent")
	check(h.told(3, "Ann raised your fame."), "Bob told")

func test_lowering_someones_fame() -> void:
	_famous()
	h.ask(2, &"req_chat", ["/defame bob"])
	check_eq(bob.character.fame, -1, "-1")

func test_fame_once_a_day() -> void:
	_famous()
	h.join(4, "Cat", ServerHarness.TOWN)
	h.ask(2, &"req_fame", [3, true])
	h.ask(2, &"req_fame", [4, true])
	check_eq(h.server.sessions[4].character.fame, 0, "Cat gets none today")
	check(h.told(2, "You've already given fame today."), "told")

func test_someone_else_the_next_day() -> void:
	_famous()
	h.join(4, "Cat", ServerHarness.TOWN)
	ann.character.fame_day = SocialGuilds.today() - 1
	ann.character.fame_given["Bob"] = SocialGuilds.today() - 1
	h.ask(2, &"req_fame", [4, true])
	check_eq(h.server.sessions[4].character.fame, 1, "Cat gets it")

func test_the_same_player_once_a_month() -> void:
	_famous()
	var day := SocialGuilds.today()
	ann.character.fame_day = day - 29
	ann.character.fame_given["Bob"] = day - 29
	h.ask(2, &"req_fame", [3, true])
	check_eq(bob.character.fame, 0, "29 days is too soon")
	check(h.told(2, "You gave Bob fame this month already."), "told")
	ann.character.fame_given["Bob"] = day - TDSocial.FAME_REPEAT_DAYS
	h.ask(2, &"req_fame", [3, true])
	check_eq(bob.character.fame, 1, "30 days later is fine")

func test_no_fame_for_yourself_or_across_maps() -> void:
	_famous()
	h.ask(2, &"req_chat", ["/fame ann"])
	check(h.told(2, "You can't give yourself fame."), "yourself")
	h.move_to(bob, ServerHarness.FIELD)
	h.ask(2, &"req_chat", ["/fame bob"])
	check(h.told(2, "Bob needs to be on this map."), "other map")
	check_eq(bob.character.fame, 0, "no fame")

func test_fame_is_saved() -> void:
	_famous()
	h.ask(2, &"req_fame", [3, true])
	h.leave(3)
	check_eq(h.saved("Bob").fame, 1, "Bob's fame saved")
