extends TestCase
## Players together through the server: chat channels and whispers, invitations,
## parties (and their shared EXP), buddy lists and the ev_social summary.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var ann: SimPlayer
var bob: SimPlayer
var cat: SimPlayer

func before_each() -> void:
	h = ServerHarness.new()
	ann = h.join(2, "Ann", ServerHarness.FIELD, 300.0)
	bob = h.join(3, "Bob", ServerHarness.FIELD, 900.0)
	cat = h.join(4, "Cat", ServerHarness.TOWN, 300.0)

func after_each() -> void:
	h.close()

func _chat(peer: int, text: String) -> void:
	h.ask(peer, &"req_chat", [text])

## `from` invites `to` (a peer) to `kind`; returns the invitation id, or 0 if none was sent.
func _invite(from: int, kind: String, to: int) -> int:
	var to_name: String = h.server.sessions[to].character.name
	h.ask(from, &"req_social", [StringName(kind), to_name])
	var inv := h.last(to, &"ev_invite")
	return inv[0] if not inv.is_empty() and inv[1] == kind else 0

func _accept(from: int, kind: String, to: int) -> void:
	var id := _invite(from, kind, to)
	h.ask(to, &"req_invite_answer", [id, true])

# ---------- chat ----------

func test_map_chat_reaches_everyone_on_the_map_only() -> void:
	_chat(2, "  hello there  ")
	check_eq(h.last(2, &"ev_chat"), ["all", "Ann", "hello there", 2], "Ann sees her line")
	check_eq(h.last(3, &"ev_chat"), ["all", "Ann", "hello there", 2], "Bob on the map sees it")
	check_eq(h.count(4, &"ev_chat"), 0, "Cat in town doesn't")

func test_chat_is_cut_to_the_limit_and_kept_on_one_line() -> void:
	_chat(2, "a\nb" + "x".repeat(200))
	var text: String = h.last(3, &"ev_chat")[2]
	check_eq(text.length(), TDSocial.CHAT_MAX, "cut")
	check(text.begins_with("a b"), "newline replaced")

func test_empty_chat_is_dropped() -> void:
	_chat(2, "   ")
	check_eq(h.count(3, &"ev_chat"), 0, "nothing sent")

func test_whispers_reach_one_player_on_any_map() -> void:
	_chat(2, "/w cat psst over here")
	check_eq(h.last(4, &"ev_chat"), ["whisper", "Ann", "psst over here", 2], "Cat gets it")
	check_eq(h.last(2, &"ev_chat"), ["whisper_sent", "Cat", "psst over here", 2], "Ann sees what she sent")
	check_eq(h.count(3, &"ev_chat"), 0, "Bob doesn't")

func test_whispering_someone_offline() -> void:
	_chat(2, "/w Dan hi")
	check(h.told(2, "Dan isn't online."), "told")

func test_party_chat_needs_a_party() -> void:
	_chat(2, "/p anyone?")
	check(h.told(2, "You aren't in a party."), "told")

func test_party_chat_reaches_the_party_across_maps() -> void:
	_accept(2, "party", 4)
	h.clear()
	_chat(2, "/p on my way")
	check_eq(h.last(4, &"ev_chat"), ["party", "Ann", "on my way", 2], "Cat in town gets it")
	check_eq(h.count(2, &"ev_chat"), 1, "Ann too")
	check_eq(h.count(3, &"ev_chat"), 0, "Bob isn't in the party")

func test_buddy_chat_reaches_buddies() -> void:
	_accept(2, "buddy", 4)
	h.clear()
	_chat(2, "/b hi friends")
	check_eq(h.last(4, &"ev_chat"), ["buddy", "Ann", "hi friends", 2], "buddy gets it")
	check_eq(h.count(3, &"ev_chat"), 0, "others don't")

func test_unknown_commands_show_help() -> void:
	_chat(2, "/dance")
	check(h.told(2, "Chat: /w Name"), "help shown")
	check_eq(h.count(3, &"ev_chat"), 0, "not said out loud")

# ---------- invitations ----------

func test_an_invitation_reaches_the_player() -> void:
	_chat(2, "/invite Bob")
	var inv := h.last(3, &"ev_invite")
	check_eq(inv.slice(1), ["party", "Ann", "Ann invites you to a party."], "invitation")
	check(h.told(2, "You asked Bob."), "Ann told")

func test_inviting_yourself_or_nobody() -> void:
	_chat(2, "/invite ann")
	check(h.told(2, "That's you!"), "yourself")
	_chat(2, "/invite")
	check(h.told(2, "Who? Add a name."), "nobody")

func test_the_same_invitation_isnt_sent_twice() -> void:
	_invite(2, "party", 3)
	_invite(2, "party", 3)
	check_eq(h.count(3, &"ev_invite"), 1, "once")
	check(h.told(2, "You've already asked Bob."), "told")

func test_saying_no_tells_the_inviter() -> void:
	var id := _invite(2, "party", 3)
	h.ask(3, &"req_invite_answer", [id, false])
	check(h.server.social.party_of("Ann") == null, "no party")
	check(h.told(2, "Bob said no."), "told")

func test_only_the_invited_player_can_answer() -> void:
	var id := _invite(2, "party", 3)
	h.ask(4, &"req_invite_answer", [id, true])
	check(h.server.social.party_of("Cat") == null, "Cat can't take Bob's invitation")
	h.ask(3, &"req_invite_answer", [id, true])
	check(h.server.social.party_of("Bob") != null, "Bob still can")

func test_invitations_run_out() -> void:
	var id := _invite(2, "party", 3)
	h.step(TDSocial.INVITE_TICKS + 30)
	h.ask(3, &"req_invite_answer", [id, true])
	check(h.server.social.party_of("Bob") == null, "too late")

# ---------- parties ----------

func test_accepting_makes_a_party_led_by_the_inviter() -> void:
	_accept(2, "party", 3)
	var party = h.server.social.party_of("Ann")
	check(party != null, "party made")
	check_eq(party.leader, "Ann", "leader")
	check_eq(party.members, ["Ann", "Bob"] as Array[String], "members")
	check(h.told(3, "Bob joined the party."), "told")

func test_only_the_leader_can_invite() -> void:
	_accept(2, "party", 3)
	_invite(3, "party", 4)
	check_eq(h.count(4, &"ev_invite"), 0, "not sent")
	check(h.told(3, "Only the party leader can invite."), "told")

func test_a_party_holds_six() -> void:
	for i in 4:
		h.join(10 + i, "Mate%d" % i, ServerHarness.FIELD, 500.0)
	_accept(2, "party", 3)
	_accept(2, "party", 4)
	_accept(2, "party", 10)
	_accept(2, "party", 11)
	check_eq(h.server.social.party_of("Ann").members.size(), 5, "five so far")
	_accept(2, "party", 12)
	check_eq(h.server.social.party_of("Ann").members.size(), TDSocial.PARTY_MAX, "six")
	_invite(2, "party", 13)
	check(h.told(2, "Your party is full."), "the seventh is refused")
	check(h.server.social.party_of("Mate3") == null, "Mate3 stays out")

func test_party_members_on_the_map_share_kill_exp() -> void:
	_accept(2, "party", 3)
	_accept(2, "party", 4)
	var d := ServerHarness.monster(&"test_mob", 1, 10)
	var map := h.server.map_instance(ServerHarness.FIELD)
	var m := SimMob.new(map, 0, d, map.layout.platforms[0])
	map.mobs.append(m)
	ServerHarness.no_cards(ann, d)
	map.kill_mob(m, ann)
	check_eq(ann.character.xp, 10, "the killer gets it all")
	check_eq(bob.character.xp, 4, "Bob on the map gets 40%")
	check_eq(cat.character.xp, 0, "Cat in town gets nothing")

func test_a_fainted_party_member_gets_no_share() -> void:
	_accept(2, "party", 3)
	bob.faint_t = 10
	var shares: Array = h.server.social.party_shares(ann, 10)
	check(shares.is_empty(), "no share")

func test_the_smallest_share_is_one() -> void:
	_accept(2, "party", 3)
	var shares: Array = h.server.social.party_shares(ann, 1)
	check(shares.size() == 1 and shares[0][0] == bob and shares[0][1] == 1, "one EXP")

func test_leaving_a_party_of_two_breaks_it_up() -> void:
	_accept(2, "party", 3)
	_chat(3, "/leave")
	check(h.server.social.party_of("Ann") == null, "gone")
	check(h.told(2, "The party broke up."), "Ann told")
	check(h.told(3, "You left the party."), "Bob told")

func test_the_leader_leaving_hands_on_the_lead() -> void:
	_accept(2, "party", 3)
	_accept(2, "party", 4)
	h.ask(2, &"req_social", [&"leave_party", ""])
	var party = h.server.social.party_of("Bob")
	check_eq(party.leader, "Bob", "Bob leads")
	check_eq(party.members, ["Bob", "Cat"] as Array[String], "two left")

func test_the_leader_can_kick() -> void:
	_accept(2, "party", 3)
	_accept(2, "party", 4)
	_chat(2, "/kick cat")
	check(h.server.social.party_of("Cat") == null, "Cat out")
	check(h.told(4, "You were removed from the party."), "Cat told")
	_chat(3, "/kick ann")
	check(h.told(3, "Only the party leader can do that."), "Bob can't kick")

func test_disconnecting_leaves_the_party() -> void:
	_accept(2, "party", 3)
	_accept(2, "party", 4)
	h.leave(2)
	var party = h.server.social.party_of("Bob")
	check_eq(party.members, ["Bob", "Cat"] as Array[String], "Ann gone")
	check(h.told(3, "Ann left the game."), "told")

func test_the_social_summary_lists_the_party() -> void:
	_accept(2, "party", 3)
	h.step(30)
	var s: Dictionary = h.last(3, &"ev_social")[0]
	check_eq(s["party"]["leader"], "Ann", "leader")
	var names := (s["party"]["members"] as Array).map(func(r: Array) -> String: return r[0])
	check_eq(names, ["Ann", "Bob"], "members")
	var count := h.count(3, &"ev_social")
	h.step(30)
	check_eq(h.count(3, &"ev_social"), count, "not sent again when nothing changed")

# ---------- buddies ----------

func test_accepting_a_buddy_adds_both_ways() -> void:
	_accept(2, "buddy", 3)
	check_has(ann.character.buddies, "Bob", "Ann's list")
	check_has(bob.character.buddies, "Ann", "Bob's list")

func test_a_buddy_cant_be_added_twice() -> void:
	_accept(2, "buddy", 3)
	h.clear()
	_invite(3, "buddy", 2)
	check_eq(h.count(2, &"ev_invite"), 0, "not asked")
	check(h.told(3, "Ann is already your buddy."), "told")

func test_removing_a_buddy_removes_both_ways() -> void:
	_accept(2, "buddy", 3)
	_chat(2, "/unbuddy BOB")
	check(not ann.character.buddies.has("Bob"), "off Ann's list")
	check(not bob.character.buddies.has("Ann"), "off Bob's list")

func test_buddies_are_told_when_you_come_online() -> void:
	_accept(2, "buddy", 4)
	h.leave(4)
	h.clear()
	h.api.peers.append(4)
	h.server.join(4, "Cat")
	check(h.told(2, "Cat is online."), "Ann told")
	check(not h.told(3, "Cat is online."), "Bob isn't her buddy")

func test_buddies_are_saved_with_the_character() -> void:
	_accept(2, "buddy", 3)
	h.leave(2)
	check_has(h.server.store.load_character("Ann").buddies, "Bob", "saved")

func test_the_social_summary_shows_buddies_online() -> void:
	_accept(2, "buddy", 4)
	h.step(30)
	var s: Dictionary = h.last(2, &"ev_social")[0]
	check_eq(s["buddies"], [["Cat", true, "Test Town"]], "Cat, online, in town")

func test_accepting_a_buddy_with_a_full_list_is_refused() -> void:
	var id := _invite(2, "buddy", 3)
	check_ne(id, 0, "invited while Bob had room")
	for i in TDSocial.BUDDY_MAX:
		bob.character.buddies.append("Friend%d" % i)
	h.ask(3, &"req_invite_answer", [id, true])
	check_eq(bob.character.buddies.size(), TDSocial.BUDDY_MAX, "Bob's list stays at the limit")
	check(not ann.character.buddies.has("Bob"), "Ann isn't half-buddied")
	check(h.told(3, "Your buddy list is full."), "Bob is told why")
	check(h.told(2, "Bob's buddy list is full."), "Ann is told why")

func test_inviting_someone_with_a_full_buddy_list_is_refused() -> void:
	for i in TDSocial.BUDDY_MAX:
		bob.character.buddies.append("Friend%d" % i)
	check_eq(_invite(2, "buddy", 3), 0, "no invite sent")
	check(h.told(2, "Bob's buddy list is full."), "Ann is told why")
