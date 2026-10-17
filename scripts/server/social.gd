class_name TDSocial
extends RefCounted
## Everything players do with each other, run by the server: chat (map, whisper, party,
## guild, buddies), invitations, buddy lists, parties (with shared EXP), trading,
## guilds and fame.
##
## Each player's client gets a summary of their buddies, party and guild (`ev_social`)
## whenever it changes, and the state of their trade (`ev_trade`).
##
## This holds the shared state and the lookups; the work is split into parts under
## scripts/server/social/ (chat, parties, trades, guilds). The methods the
## server and Net call are all here and hand off to the right part.

const PARTY_MAX := 6
const BUDDY_MAX := 20
const GUILD_MAX := 30
const GUILD_COST := 15000
## Fame can be given once a day, and to the same player once a month.
const FAME_REPEAT_DAYS := 30
const TRADE_SLOTS := 9
const CHAT_MAX := 120
## Share of a kill's Dawn Essence and EXP every other party member on the map gets.
const PARTY_SHARE := 0.4
## Ticks an invitation waits for an answer.
const INVITE_TICKS := 3600
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

var server: TDServer
var parties := {}
var party_ids := 0
## lowercased guild name -> {"name": String, "master": String, "members": Array of names}
var guilds := {}
var guild_path := ""
## invitation id -> {"kind", "from" (name), "to" (peer), "data", "t"}
var invites := {}
var invite_ids := 0
## peer -> Trade (both peers of a trade share one)
var trades := {}
## peer -> the last social summary sent
var _sent := {}

var chat: SocialChat
var party: SocialParties
var trade: SocialTrade
var guild: SocialGuilds

func _init(s: TDServer, save_folder: String) -> void:
	server = s
	chat = SocialChat.new(self)
	party = SocialParties.new(self)
	trade = SocialTrade.new(self)
	guild = SocialGuilds.new(self)
	guild_path = save_folder.path_join("guilds.data")
	guild.load_guilds()

# ---------- lookups ----------

## The online player with this name (any case), or null.
func player_named(char_name: String) -> SimPlayer:
	var want := char_name.strip_edges().to_lower()
	for p: SimPlayer in server.sessions.values():
		if p.character.name.to_lower() == want:
			return p
	return null

func party_of(char_name: String) -> Party:
	for pt: Party in parties.values():
		if pt.members.has(char_name):
			return pt
	return null

func guild_of(char_name: String) -> Dictionary:
	for g: Dictionary in guilds.values():
		if (g["members"] as Array).has(char_name):
			return g
	return {}

## A system message to one player (nothing if they're gone).
func tell(p: SimPlayer, text: String, col := INFO) -> void:
	if p and p.map:
		p.map.tell(p, text, col)

# ---------- coming and going ----------

func joined(p: SimPlayer) -> void:
	var g := guild_of(p.character.name)
	p.character.guild = g.get("name", "")
	for other: SimPlayer in server.sessions.values():
		if other != p and other.character.buddies.has(p.character.name):
			tell(other, "%s is online." % p.character.name)

func left(p: SimPlayer) -> void:
	var peer := p.peer
	if trades.has(peer):
		cancel_trade(peer, "%s left." % p.character.name)
	var pt := party_of(p.character.name)
	if pt:
		party.leave(pt, p.character.name, "%s left the game." % p.character.name)
	for id in invites.keys():
		if invites[id]["to"] == peer:
			invites.erase(id)
	_sent.erase(peer)

## A player moved to another map: trades end.
func changed_map(p: SimPlayer) -> void:
	if trades.has(p.peer):
		cancel_trade(p.peer, "%s left the map." % p.character.name)

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
	var pt := party_of(c.name)
	if pt:
		var members := []
		for m in pt.members:
			var o := player_named(m)
			if o:
				members.append([m, o.peer, String(o.character.job.id), o.character.health.fraction(), String(o.map.def.id) if o.map else ""])
		out["party"] = {"leader": pt.leader, "members": members}
	var g := guild_of(c.name)
	if not g.is_empty():
		var members := []
		for m in g["members"]:
			members.append([m, player_named(m) != null])
		out["guild"] = {"name": g["name"], "master": g["master"], "members": members}
	return out

# ---------- requests (see Net) and calls from the server ----------

func on_chat(peer: int, raw: String) -> void:
	chat.on_chat(peer, raw)

func on_social(peer: int, action: StringName, arg: String) -> void:
	chat.on_social(peer, action, arg)

func whisper(p: SimPlayer, to: String, text: String) -> void:
	chat.whisper(p, to, text)

func invite(p: SimPlayer, kind: String, to: String) -> void:
	party.invite(p, kind, to)

func on_answer(peer: int, id: int, accept: bool) -> void:
	party.on_answer(peer, id, accept)

func party_shares(killer: SimPlayer, amount: int) -> Array:
	return party.shares(killer, amount)

## Party members on the same map within `reach` of `p` (for party buffs).
func party_near(p: SimPlayer, reach: float) -> Array[SimPlayer]:
	return party.near(p, reach)

func on_trade_offer(peer: int, tab: int, slot: int, count: int) -> void:
	trade.on_offer(peer, tab, slot, count)

func on_trade_shards(peer: int, amount: int) -> void:
	trade.on_shards(peer, amount)

func on_trade_ready(peer: int) -> void:
	trade.on_ready(peer)

func cancel_trade(peer: int, why := "The trade was cancelled.") -> void:
	trade.cancel(peer, why)

func on_guild_create(peer: int, npc_id: StringName, guild_name: String) -> void:
	guild.on_create(peer, npc_id, guild_name)

func save_guilds() -> void:
	guild.save_guilds()

func on_fame(peer: int, target_peer: int, up: bool) -> void:
	guild.on_fame(peer, target_peer, up)
