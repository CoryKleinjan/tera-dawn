class_name TDSocial
extends RefCounted
## Everything players do with each other, run by the server: chat (map, whisper, party),
## invitations, parties and trading.
##
## Each player's client gets a summary of their party (`ev_social`) whenever it changes,
## and the state of their trade (`ev_trade`).
##
## This holds the shared state and the lookups; the work is split into parts under
## scripts/server/social/ (chat, parties, trades). The methods the
## server and Net call are all here and hand off to the right part.

const PARTY_MAX := 6
const TRADE_SLOTS := 9
const CHAT_MAX := 120
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

func _init(s: TDServer) -> void:
	server = s
	chat = SocialChat.new(self)
	party = SocialParties.new(self)
	trade = SocialTrade.new(self)

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

## A system message to one player (nothing if they're gone).
func tell(p: SimPlayer, text: String, col := INFO) -> void:
	if p and p.map:
		p.map.tell(p, text, col)

# ---------- coming and going ----------

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

## What a player's community window shows: their party, with each member's HP and map.
func summary(p: SimPlayer) -> Dictionary:
	var c := p.character
	var out := {}
	var pt := party_of(c.name)
	if pt:
		var members := []
		for m in pt.members:
			var o := player_named(m)
			if o:
				members.append([m, o.peer, String(o.character.job.id), o.character.health.fraction(), String(o.map.def.id) if o.map else ""])
		out["party"] = {"leader": pt.leader, "members": members}
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

## The other members of `killer`'s party on the same map who are up (a kill counts for their
## quests too).
func party_here(killer: SimPlayer) -> Array[SimPlayer]:
	return party.here(killer)

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
