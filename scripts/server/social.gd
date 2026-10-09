class_name TDSocial
extends RefCounted
## Everything players do with each other, run by the server: chat (map, whisper, party,
## guild, buddies), invitations, buddy lists, parties (with shared EXP), trading,
## guilds, fame, and player shops in the free market.
##
## Each player's client gets a summary of their buddies, party and guild (`ev_social`)
## whenever it changes, and the state of their trade (`ev_trade`) and of any player shop
## they're looking at (`ev_player_shop`).

const PARTY_MAX := 6
const BUDDY_MAX := 20
const GUILD_MAX := 30
const GUILD_COST := 15000
const GUILD_LEVEL := 10
## Fame can be given from this level, once a day, and to the same player once a month.
const FAME_LEVEL := 15
const FAME_REPEAT_DAYS := 30
const TRADE_SLOTS := 9
const SHOP_SLOTS := 12
const CHAT_MAX := 120
## Share of a kill's EXP every other party member on the map gets.
const PARTY_SHARE := 0.4
## Ticks an invitation waits for an answer.
const INVITE_TICKS := 3600
const GOOD := Color("8cf0a6")
const INFO := Color("c9e4ff")

class Party:
	var id := 0
	var leader := ""
	var members: Array[String] = []

class Trade:
	var peers: Array[int] = []
	## peer -> Array of ItemStack offered (held here until the trade ends)
	var items := {}
	## peer -> Dawnshards offered (also held here)
	var shards := {}
	## peer -> pressed Trade
	var ready := {}

	func other(peer: int) -> int:
		return peers[1] if peers[0] == peer else peers[0]

class Shop:
	var owner := 0
	var title := ""
	## [ItemStack, price] for each thing still for sale
	var items: Array = []
	## peers with the shop open
	var viewers := {}

var server: TDServer
var parties := {}
var _party_ids := 0
## lowercased guild name -> {"name": String, "master": String, "members": Array of names}
var guilds := {}
var guild_path := ""
## invitation id -> {"kind", "from" (name), "to" (peer), "data", "t"}
var invites := {}
var _invite_ids := 0
## peer -> Trade (both peers of a trade share one)
var trades := {}
## owner peer -> Shop
var shops := {}
## peer -> the last social summary sent
var _sent := {}

func _init(s: TDServer, save_folder: String) -> void:
	server = s
	guild_path = save_folder.path_join("guilds.data")
	_load_guilds()

# ---------- lookups ----------

## The online player with this name (any case), or null.
func player_named(char_name: String) -> SimPlayer:
	var want := char_name.strip_edges().to_lower()
	for p: SimPlayer in server.sessions.values():
		if p.character.name.to_lower() == want:
			return p
	return null

func party_of(char_name: String) -> Party:
	for party: Party in parties.values():
		if party.members.has(char_name):
			return party
	return null

func guild_of(char_name: String) -> Dictionary:
	for g: Dictionary in guilds.values():
		if (g["members"] as Array).has(char_name):
			return g
	return {}

func _tell(p: SimPlayer, text: String, col := INFO) -> void:
	if p and p.map:
		p.map.tell(p, text, col)

func _chat(p: SimPlayer, kind: String, from: String, text: String, from_peer := 0) -> void:
	Net.send(p.peer, &"ev_chat", [kind, from, text, from_peer])

# ---------- coming and going ----------

func joined(p: SimPlayer) -> void:
	var g := guild_of(p.character.name)
	p.character.guild = g.get("name", "")
	for other: SimPlayer in server.sessions.values():
		if other != p and other.character.buddies.has(p.character.name):
			_tell(other, "%s is online." % p.character.name)

func left(p: SimPlayer) -> void:
	var peer := p.peer
	if trades.has(peer):
		cancel_trade(peer, "%s left." % p.character.name)
	if shops.has(peer):
		close_shop(peer)
	for s: Shop in shops.values():
		s.viewers.erase(peer)
	var party := party_of(p.character.name)
	if party:
		_leave_party(party, p.character.name, "%s left the game." % p.character.name)
	for id in invites.keys():
		if invites[id]["to"] == peer:
			invites.erase(id)
	_sent.erase(peer)

## A player moved to another map: trades and shop visits end.
func changed_map(p: SimPlayer) -> void:
	if trades.has(p.peer):
		cancel_trade(p.peer, "%s left the map." % p.character.name)
	for s: Shop in shops.values():
		s.viewers.erase(p.peer)

func step(tick: int) -> void:
	if tick % 30 != 0:
		return
	for id in invites.keys():
		if tick - int(invites[id]["t"]) > INVITE_TICKS:
			invites.erase(id)
	for p: SimPlayer in server.sessions.values():
		var s := summary(p)
		if _sent.get(p.peer) != s:
			_sent[p.peer] = s
			Net.send(p.peer, &"ev_social", [s])

## What a player's community window shows: buddies (online and where), their party
## (with each member's HP and map) and their guild.
func summary(p: SimPlayer) -> Dictionary:
	var c := p.character
	var buddies := []
	for b in c.buddies:
		var o := player_named(b)
		buddies.append([b, o != null, o.map.def.display_name if o and o.map else ""])
	var out := {"buddies": buddies, "fame": c.fame}
	var party := party_of(c.name)
	if party:
		var members := []
		for m in party.members:
			var o := player_named(m)
			if o:
				members.append([m, o.peer, o.character.level, String(o.character.job.id), o.character.health.fraction(), String(o.map.def.id) if o.map else ""])
		out["party"] = {"leader": party.leader, "members": members}
	var g := guild_of(c.name)
	if not g.is_empty():
		var members := []
		for m in g["members"]:
			members.append([m, player_named(m) != null])
		out["guild"] = {"name": g["name"], "master": g["master"], "members": members}
	return out

# ---------- chat ----------

func on_chat(peer: int, raw: String) -> void:
	var p: SimPlayer = server.sessions.get(peer)
	if p == null:
		return
	var text := raw.strip_edges().replace("\n", " ").substr(0, CHAT_MAX)
	if text == "":
		return
	if text.begins_with("/"):
		_command(p, text)
		return
	p.map.broadcast(&"ev_chat", ["all", p.character.name, text, peer])

func _command(p: SimPlayer, text: String) -> void:
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	var arg := parts[1] if parts.size() > 1 else ""
	var rest := " ".join(parts.slice(2)) if parts.size() > 2 else ""
	var all_after := " ".join(parts.slice(1)) if parts.size() > 1 else ""
	match cmd:
		"/w", "/whisper":
			whisper(p, arg, rest)
		"/p", "/party":
			party_chat(p, all_after)
		"/g":
			guild_chat(p, all_after)
		"/b":
			buddy_chat(p, all_after)
		"/invite":
			invite(p, "party", arg)
		"/leave":
			leave_party(p)
		"/kick":
			kick(p, arg)
		"/buddy":
			invite(p, "buddy", arg)
		"/unbuddy":
			remove_buddy(p, arg)
		"/trade":
			invite(p, "trade", arg)
		"/fame":
			give_fame(p, arg, true)
		"/defame":
			give_fame(p, arg, false)
		"/guild":
			match arg.to_lower():
				"invite":
					invite(p, "guild", rest)
				"leave":
					leave_guild(p)
				_:
					_tell(p, "Try /guild invite Name or /guild leave.")
		_:
			_tell(p, "Chat: /w Name (whisper), /p, /g, /b (party, guild, buddy chat), /invite, /leave, /kick, /buddy, /unbuddy, /trade, /fame, /defame, /guild invite, /guild leave.")

## Actions from the community window and the player menu, on the player named `arg`.
func on_social(peer: int, action: StringName, arg: String) -> void:
	var p: SimPlayer = server.sessions.get(peer)
	if p == null:
		return
	match action:
		&"party":
			invite(p, "party", arg)
		&"buddy":
			invite(p, "buddy", arg)
		&"trade":
			invite(p, "trade", arg)
		&"guild":
			invite(p, "guild", arg)
		&"leave_party":
			leave_party(p)
		&"kick":
			kick(p, arg)
		&"unbuddy":
			remove_buddy(p, arg)
		&"leave_guild":
			leave_guild(p)

func whisper(p: SimPlayer, to: String, text: String) -> void:
	var o := player_named(to)
	if o == null:
		_tell(p, "%s isn't online." % to, MapInstance.BAD)
		return
	if text.strip_edges() == "":
		return
	_chat(o, "whisper", p.character.name, text, p.peer)
	_chat(p, "whisper_sent", o.character.name, text, p.peer)

func party_chat(p: SimPlayer, text: String) -> void:
	var party := party_of(p.character.name)
	if party == null:
		_tell(p, "You aren't in a party.", MapInstance.BAD)
		return
	for m in party.members:
		var o := player_named(m)
		if o and text != "":
			_chat(o, "party", p.character.name, text, p.peer)

func guild_chat(p: SimPlayer, text: String) -> void:
	var g := guild_of(p.character.name)
	if g.is_empty():
		_tell(p, "You aren't in a guild.", MapInstance.BAD)
		return
	for m in g["members"]:
		var o := player_named(m)
		if o and text != "":
			_chat(o, "guild", p.character.name, text, p.peer)

func buddy_chat(p: SimPlayer, text: String) -> void:
	if text == "":
		return
	_chat(p, "buddy", p.character.name, text, p.peer)
	for b in p.character.buddies:
		var o := player_named(b)
		if o:
			_chat(o, "buddy", p.character.name, text, p.peer)

# ---------- invitations ----------

## Asks `to` (a name) to join `p` in a party, a buddy list, a trade or a guild.
func invite(p: SimPlayer, kind: String, to: String) -> void:
	var o := player_named(to)
	if o == null:
		_tell(p, "%s isn't online." % to if to != "" else "Who? Add a name.", MapInstance.BAD)
		return
	if o == p:
		_tell(p, "That's you!", MapInstance.BAD)
		return
	var problem := _invite_problem(p, kind, o)
	if problem != "":
		_tell(p, problem, MapInstance.BAD)
		return
	for i in invites.values():
		if i["to"] == o.peer and i["kind"] == kind and i["from"] == p.character.name:
			_tell(p, "You've already asked %s." % o.character.name, MapInstance.BAD)
			return
	_invite_ids += 1
	invites[_invite_ids] = {"kind": kind, "from": p.character.name, "to": o.peer, "t": server.tick}
	var what: String = {"party": "%s invites you to a party.", "buddy": "%s wants to be your buddy.",
		"trade": "%s wants to trade.", "guild": "%s invites you to the guild %s."}[kind]
	var text: String = what % [p.character.name, p.character.guild] if kind == "guild" else what % p.character.name
	Net.send(o.peer, &"ev_invite", [_invite_ids, kind, p.character.name, text])
	_tell(p, "You asked %s." % o.character.name)

func _invite_problem(p: SimPlayer, kind: String, o: SimPlayer) -> String:
	var me := p.character.name
	var them := o.character.name
	match kind:
		"party":
			var party := party_of(me)
			if party and party.leader != me:
				return "Only the party leader can invite."
			if party and party.members.size() >= PARTY_MAX:
				return "Your party is full."
			if party_of(them):
				return "%s is already in a party." % them
		"buddy":
			if p.character.buddies.has(them):
				return "%s is already your buddy." % them
			if p.character.buddies.size() >= BUDDY_MAX:
				return "Your buddy list is full."
		"trade":
			if o.map != p.map:
				return "%s needs to be on this map to trade." % them
			if trades.has(p.peer) or trades.has(o.peer):
				return "One of you is already trading."
			if shops.has(p.peer) or shops.has(o.peer):
				return "Not while minding a shop."
		"guild":
			var g := guild_of(me)
			if g.is_empty() or g["master"] != me:
				return "Only a guild master can invite."
			if (g["members"] as Array).size() >= GUILD_MAX:
				return "Your guild is full."
			if not guild_of(them).is_empty():
				return "%s is already in a guild." % them
	return ""

func on_answer(peer: int, id: int, accept: bool) -> void:
	var inv: Dictionary = invites.get(id, {})
	if inv.is_empty() or inv["to"] != peer:
		return
	invites.erase(id)
	var p: SimPlayer = server.sessions.get(peer)
	var from := player_named(inv["from"])
	if p == null:
		return
	if from == null:
		_tell(p, "%s isn't online any more." % inv["from"], MapInstance.BAD)
		return
	if not accept:
		_tell(from, "%s said no." % p.character.name)
		return
	var problem := _invite_problem(from, inv["kind"], p)
	if problem != "":
		_tell(p, problem, MapInstance.BAD)
		return
	match inv["kind"]:
		"party":
			_join_party(from, p)
		"buddy":
			for pair in [[from, p], [p, from]]:
				var a: SimPlayer = pair[0]
				if not a.character.buddies.has(pair[1].character.name):
					a.character.buddies.append(pair[1].character.name)
			_tell(from, "%s is now your buddy." % p.character.name, GOOD)
			_tell(p, "%s is now your buddy." % from.character.name, GOOD)
		"trade":
			_open_trade(from, p)
		"guild":
			_join_guild(guild_of(from.character.name), p)

# ---------- buddies ----------

func remove_buddy(p: SimPlayer, char_name: String) -> void:
	var i := -1
	for k in p.character.buddies.size():
		if p.character.buddies[k].to_lower() == char_name.to_lower():
			i = k
	if i < 0:
		_tell(p, "%s isn't on your buddy list." % char_name, MapInstance.BAD)
		return
	var them := p.character.buddies[i]
	p.character.buddies.remove_at(i)
	var o := player_named(them)
	if o:
		o.character.buddies.erase(p.character.name)
	_tell(p, "%s was taken off your buddy list." % them)

# ---------- parties ----------

func _join_party(leader: SimPlayer, p: SimPlayer) -> void:
	var party := party_of(leader.character.name)
	if party == null:
		_party_ids += 1
		party = Party.new()
		party.id = _party_ids
		party.leader = leader.character.name
		party.members.append(leader.character.name)
		parties[party.id] = party
	party.members.append(p.character.name)
	for m in party.members:
		_tell(player_named(m), "%s joined the party." % p.character.name, GOOD)

func leave_party(p: SimPlayer) -> void:
	var party := party_of(p.character.name)
	if party == null:
		_tell(p, "You aren't in a party.", MapInstance.BAD)
		return
	_leave_party(party, p.character.name, "%s left the party." % p.character.name)
	_tell(p, "You left the party.")

func kick(p: SimPlayer, char_name: String) -> void:
	var party := party_of(p.character.name)
	if party == null or party.leader != p.character.name:
		_tell(p, "Only the party leader can do that.", MapInstance.BAD)
		return
	for m in party.members:
		if m.to_lower() == char_name.to_lower() and m != p.character.name:
			_leave_party(party, m, "%s was removed from the party." % m)
			_tell(player_named(m), "You were removed from the party.", MapInstance.BAD)
			return
	_tell(p, "%s isn't in your party." % char_name, MapInstance.BAD)

func _leave_party(party: Party, char_name: String, why: String) -> void:
	party.members.erase(char_name)
	if party.members.size() <= 1:
		for m in party.members:
			_tell(player_named(m), "The party broke up.")
		parties.erase(party.id)
		return
	if party.leader == char_name:
		party.leader = party.members[0]
	for m in party.members:
		_tell(player_named(m), why)

## The EXP each other party member on `killer`'s map gets for their kill: [[player, exp], ...].
func party_shares(killer: SimPlayer, xp: int) -> Array:
	var out := []
	var party := party_of(killer.character.name)
	if party == null:
		return out
	for m in party.members:
		var o := player_named(m)
		if o and o != killer and o.map == killer.map and not o.fainted():
			out.append([o, maxi(1, roundi(xp * PARTY_SHARE))])
	return out

# ---------- trading ----------

func _open_trade(a: SimPlayer, b: SimPlayer) -> void:
	var t := Trade.new()
	t.peers = [a.peer, b.peer]
	for p in t.peers:
		t.items[p] = []
		t.shards[p] = 0
		t.ready[p] = false
		trades[p] = t
	_send_trade(t)

func _send_trade(t: Trade) -> void:
	for peer in t.peers:
		var other := t.other(peer)
		var o: SimPlayer = server.sessions.get(other)
		Net.send(peer, &"ev_trade", [{
			"partner": o.character.name if o else "?",
			"mine": {"items": t.items[peer].map(func(s: ItemStack) -> Dictionary: return s.to_dict()), "shards": t.shards[peer], "ready": t.ready[peer]},
			"theirs": {"items": t.items[other].map(func(s: ItemStack) -> Dictionary: return s.to_dict()), "shards": t.shards[other], "ready": t.ready[other]},
		}])

## Puts `count` from bag slot `slot` of `tab` on the table.
func on_trade_offer(peer: int, tab: int, slot: int, count: int) -> void:
	var t: Trade = trades.get(peer)
	var p: SimPlayer = server.sessions.get(peer)
	if t == null or p == null or tab < 0 or tab >= ItemDef.Tab.size() or slot < 0 or slot >= Inventory.SLOTS:
		return
	var held := p.character.inventory.at(tab, slot)
	if held == null:
		return
	if held.item.quest_item:
		_tell(p, "Quest items can't be traded.", MapInstance.BAD)
		return
	if (t.items[peer] as Array).size() >= TRADE_SLOTS:
		_tell(p, "The trade window is full.", MapInstance.BAD)
		return
	var stack := p.character.inventory.take(tab, slot, clampi(count, 1, held.count) if count > 0 else -1)
	t.items[peer].append(stack)
	p.dirty_character = true
	_unready(t)

## Offers `amount` Dawnshards (replacing any offered before).
func on_trade_shards(peer: int, amount: int) -> void:
	var t: Trade = trades.get(peer)
	var p: SimPlayer = server.sessions.get(peer)
	if t == null or p == null:
		return
	p.character.shards += t.shards[peer]
	t.shards[peer] = clampi(amount, 0, p.character.shards)
	p.character.shards -= t.shards[peer]
	p.dirty_vitals = true
	_unready(t)

func _unready(t: Trade) -> void:
	for peer in t.peers:
		t.ready[peer] = false
	_send_trade(t)

## Presses Trade. Once both have, everything changes hands (if both have room).
func on_trade_ready(peer: int) -> void:
	var t: Trade = trades.get(peer)
	if t == null:
		return
	t.ready[peer] = true
	if not t.ready.values().all(func(r: bool) -> bool: return r):
		_send_trade(t)
		return
	var a: SimPlayer = server.sessions.get(t.peers[0])
	var b: SimPlayer = server.sessions.get(t.peers[1])
	for pair in [[a, t.items[t.peers[1]]], [b, t.items[t.peers[0]]]]:
		if not pair[0].character.inventory.room_for(pair[1]):
			_tell(a, "%s doesn't have room for that." % pair[0].character.name, MapInstance.BAD)
			_tell(b, "%s doesn't have room for that." % pair[0].character.name, MapInstance.BAD)
			_unready(t)
			return
	for p: SimPlayer in [a, b]:
		var other := t.other(p.peer)
		for s: ItemStack in t.items[other]:
			p.character.inventory.add_stack(s)
		p.character.shards += t.shards[other]
		p.dirty_character = true
		trades.erase(p.peer)
		Net.send(p.peer, &"ev_trade", [{}])
		_tell(p, "The trade is done.", GOOD)

## Ends a trade: everything goes back to whoever offered it.
func cancel_trade(peer: int, why := "The trade was cancelled.") -> void:
	var t: Trade = trades.get(peer)
	if t == null:
		return
	for pp in t.peers:
		trades.erase(pp)
		var p: SimPlayer = server.sessions.get(pp)
		if p == null:
			continue
		for s: ItemStack in t.items[pp]:
			if not p.character.inventory.add_stack(s):
				p.character.storage.add_stack(s)
		p.character.shards += t.shards[pp]
		p.dirty_character = true
		Net.send(pp, &"ev_trade", [{}])
		_tell(p, why)

# ---------- guilds ----------

func _load_guilds() -> void:
	var f := FileAccess.open(guild_path, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if data is Dictionary:
		for k in data:
			var g: Variant = data[k]
			if g is Dictionary and g.get("members") is Array:
				guilds[str(k)] = {"name": str(g.get("name", k)), "master": str(g.get("master", "")), "members": (g["members"] as Array).map(func(m) -> String: return str(m))}

func save_guilds() -> void:
	var f := FileAccess.open(guild_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(guilds))

## Founds a guild named `guild_name` at a guild NPC.
func on_guild_create(peer: int, npc_id: StringName, guild_name: String) -> void:
	var p: SimPlayer = server.sessions.get(peer)
	if p == null:
		return
	var npc := p.map.npc_near(p, npc_id)
	if npc == null or not npc.guild:
		return
	var n := CharacterStore.clean_name(guild_name)
	var c := p.character
	var problem := ""
	if not guild_of(c.name).is_empty():
		problem = "You're already in a guild."
	elif c.level < GUILD_LEVEL:
		problem = "You need to be level %d to found a guild." % GUILD_LEVEL
	elif c.shards < GUILD_COST:
		problem = "Founding a guild costs %d Dawnshards." % GUILD_COST
	elif n.length() < 3:
		problem = "Pick a guild name of at least 3 letters."
	elif guilds.has(n.to_lower()):
		problem = "There's already a guild called %s." % n
	if problem != "":
		_tell(p, problem, MapInstance.BAD)
		return
	c.shards -= GUILD_COST
	guilds[n.to_lower()] = {"name": n, "master": c.name, "members": [c.name]}
	c.guild = n
	p.dirty_character = true
	save_guilds()
	_tell(p, "You founded the guild %s!" % n, GOOD)
	p.map.broadcast(&"ev_effect", [&"level_up", p.position.x, p.position.y, 1, peer])

func _join_guild(g: Dictionary, p: SimPlayer) -> void:
	if g.is_empty():
		return
	(g["members"] as Array).append(p.character.name)
	p.character.guild = g["name"]
	p.dirty_character = true
	save_guilds()
	for m in g["members"]:
		_tell(player_named(m), "%s joined the guild." % p.character.name, GOOD)

func leave_guild(p: SimPlayer) -> void:
	var g := guild_of(p.character.name)
	if g.is_empty():
		_tell(p, "You aren't in a guild.", MapInstance.BAD)
		return
	var members: Array = g["members"]
	members.erase(p.character.name)
	p.character.guild = ""
	p.dirty_character = true
	if members.is_empty():
		guilds.erase(String(g["name"]).to_lower())
		_tell(p, "%s was disbanded." % g["name"])
	else:
		if g["master"] == p.character.name:
			g["master"] = members[0]
		for m in members:
			_tell(player_named(m), "%s left the guild." % p.character.name)
		_tell(p, "You left %s." % g["name"])
	save_guilds()

# ---------- fame ----------

static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)

## Why `p` can't give `o` fame today, or "".
func fame_problem(p: SimPlayer, o: SimPlayer) -> String:
	if o == null:
		return "They need to be online and on this map."
	if o == p:
		return "You can't give yourself fame."
	if o.map != p.map:
		return "%s needs to be on this map." % o.character.name
	var c := p.character
	if c.level < FAME_LEVEL:
		return "You can give fame from level %d." % FAME_LEVEL
	var day := today()
	if c.fame_day == day:
		return "You've already given fame today."
	if c.fame_given.has(o.character.name) and day - int(c.fame_given[o.character.name]) < FAME_REPEAT_DAYS:
		return "You gave %s fame this month already." % o.character.name
	return ""

func give_fame(p: SimPlayer, to: String, up: bool) -> void:
	var o := player_named(to)
	var problem := fame_problem(p, o)
	if problem != "":
		_tell(p, problem, MapInstance.BAD)
		return
	var day := today()
	p.character.fame_day = day
	p.character.fame_given[o.character.name] = day
	o.character.fame += 1 if up else -1
	p.dirty_character = true
	o.dirty_character = true
	_tell(p, "You %s %s's fame." % ["raised" if up else "lowered", o.character.name], GOOD)
	_tell(o, "%s %s your fame." % [p.character.name, "raised" if up else "lowered"], GOOD if up else MapInstance.BAD)

func on_fame(peer: int, target_peer: int, up: bool) -> void:
	var p: SimPlayer = server.sessions.get(peer)
	var o: SimPlayer = server.sessions.get(target_peer)
	if p and o:
		give_fame(p, o.character.name, up)

# ---------- player shops ----------

## Opens a shop: `entries` is [[tab, slot, count, price], ...] from the bag.
func on_shop_open(peer: int, title: String, entries: Array) -> void:
	var p: SimPlayer = server.sessions.get(peer)
	if p == null or shops.has(peer) or trades.has(peer):
		return
	if not p.map.def.market:
		_tell(p, "Shops can only be opened in the Free Market.", MapInstance.BAD)
		return
	if entries.is_empty() or entries.size() > SHOP_SLOTS:
		_tell(p, "Put up 1 to %d things for sale." % SHOP_SLOTS, MapInstance.BAD)
		return
	for other: Shop in shops.values():
		var o: SimPlayer = server.sessions.get(other.owner)
		if o and o.map == p.map and absf(o.position.x - p.position.x) < 90:
			_tell(p, "You're too close to %s's shop." % o.character.name, MapInstance.BAD)
			return
	var shop := Shop.new()
	shop.owner = peer
	shop.title = title.strip_edges().substr(0, 24) if title.strip_edges() != "" else "%s's Shop" % p.character.name
	var inv := p.character.inventory
	# check everything first so nothing moves if one entry is bad
	var used := {}
	for e in entries:
		if not e is Array or e.size() != 4:
			return
		var tab := int(e[0])
		var slot := int(e[1])
		if tab < 0 or tab >= ItemDef.Tab.size() or slot < 0 or slot >= Inventory.SLOTS or used.has([tab, slot]):
			return
		used[[tab, slot]] = true
		var held := inv.at(tab, slot)
		if held == null or held.item.quest_item or int(e[3]) <= 0:
			_tell(p, "Something on your list can't be sold.", MapInstance.BAD)
			return
	for e in entries:
		var held := inv.at(int(e[0]), int(e[1]))
		var n := clampi(int(e[2]), 1, held.count)
		shop.items.append([inv.take(int(e[0]), int(e[1]), n), clampi(int(e[3]), 1, 999999999)])
	shops[peer] = shop
	p.dirty_character = true
	_tell(p, "Your shop is open. Others can click you to browse.", GOOD)
	shop.viewers[peer] = true
	_send_shop(shop)

func _send_shop(shop: Shop) -> void:
	var o: SimPlayer = server.sessions.get(shop.owner)
	var items := shop.items.map(func(e: Array) -> Array: return [(e[0] as ItemStack).to_dict(), e[1]])
	for v in shop.viewers.keys():
		Net.send(v, &"ev_player_shop", [shop.owner, o.character.name if o else "", shop.title, items])

func on_shop_view(peer: int, owner: int) -> void:
	var shop: Shop = shops.get(owner)
	var p: SimPlayer = server.sessions.get(peer)
	var o: SimPlayer = server.sessions.get(owner)
	if shop == null or p == null or o == null or o.map != p.map:
		return
	shop.viewers[peer] = true
	_send_shop(shop)

## Buys entry `index` of `owner`'s shop. `item_id` must still match (the list may have moved).
func on_shop_buy(peer: int, owner: int, index: int, item_id: StringName) -> void:
	var shop: Shop = shops.get(owner)
	var p: SimPlayer = server.sessions.get(peer)
	var o: SimPlayer = server.sessions.get(owner)
	if shop == null or p == null or o == null or peer == owner or o.map != p.map or index < 0 or index >= shop.items.size():
		return
	var entry: Array = shop.items[index]
	var stack: ItemStack = entry[0]
	if stack.item.id != item_id:
		return
	var price: int = entry[1]
	if p.character.shards < price:
		_tell(p, "You need %d Dawnshards." % price, MapInstance.BAD)
		return
	if not p.character.inventory.room_for([stack]):
		_tell(p, "Your %s inventory is full." % ItemDef.TAB_NAMES[stack.item.tab()], MapInstance.BAD)
		return
	p.character.shards -= price
	o.character.shards += price
	p.character.inventory.add_stack(stack)
	shop.items.remove_at(index)
	p.dirty_character = true
	o.dirty_character = true
	_tell(p, "You bought %s." % MapInstance.amount_name(stack.item, stack.count), GOOD)
	_tell(o, "%s bought %s for %d Dawnshards." % [p.character.name, MapInstance.amount_name(stack.item, stack.count), price], GOOD)
	if shop.items.is_empty():
		close_shop(owner)
	else:
		_send_shop(shop)

func on_shop_leave(peer: int, owner: int) -> void:
	if peer == owner:
		close_shop(owner)
	elif shops.has(owner):
		(shops[owner] as Shop).viewers.erase(peer)

## Closes a shop: unsold things go back to the owner.
func close_shop(owner: int) -> void:
	var shop: Shop = shops.get(owner)
	if shop == null:
		return
	shops.erase(owner)
	var o: SimPlayer = server.sessions.get(owner)
	if o:
		for e in shop.items:
			if not o.character.inventory.add_stack(e[0]):
				o.character.storage.add_stack(e[0])
		o.dirty_character = true
		_tell(o, "Your shop is closed.")
	for v in shop.viewers.keys():
		Net.send(v, &"ev_player_shop", [owner, "", "", []])

## The shop sign over a player, or "".
func shop_title(peer: int) -> String:
	var s: Shop = shops.get(peer)
	return s.title if s else ""
