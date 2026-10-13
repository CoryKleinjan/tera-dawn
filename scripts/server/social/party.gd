class_name SocialParties
extends SocialPart
## Invitations (to a party, a buddy list, a trade or a guild), buddy lists and parties
## (with shared EXP).

# ---------- invitations ----------

## Asks `to` (a name) to join `p` in a party, a buddy list, a trade or a guild.
func invite(p: SimPlayer, kind: String, to: String) -> void:
	var o := social.player_named(to)
	if o == null:
		tell(p, "%s isn't online." % to if to != "" else "Who? Add a name.", MapInstance.BAD)
		return
	if o == p:
		tell(p, "That's you!", MapInstance.BAD)
		return
	var problem := _invite_problem(p, kind, o)
	if problem != "":
		tell(p, problem, MapInstance.BAD)
		return
	for i in social.invites.values():
		if i["to"] == o.peer and i["kind"] == kind and i["from"] == p.character.name:
			tell(p, "You've already asked %s." % o.character.name, MapInstance.BAD)
			return
	social.invite_ids += 1
	social.invites[social.invite_ids] = {"kind": kind, "from": p.character.name, "to": o.peer, "t": server.tick}
	var what: String = {"party": "%s invites you to a party.", "buddy": "%s wants to be your buddy.",
		"trade": "%s wants to trade.", "guild": "%s invites you to the guild %s."}[kind]
	var text: String = what % [p.character.name, p.character.guild] if kind == "guild" else what % p.character.name
	Net.send(o.peer, &"ev_invite", [social.invite_ids, kind, p.character.name, text])
	tell(p, "You asked %s." % o.character.name)

func _invite_problem(p: SimPlayer, kind: String, o: SimPlayer) -> String:
	var me := p.character.name
	var them := o.character.name
	match kind:
		"party":
			var pt := social.party_of(me)
			if pt and pt.leader != me:
				return "Only the party leader can invite."
			if pt and pt.members.size() >= TDSocial.PARTY_MAX:
				return "Your party is full."
			if social.party_of(them):
				return "%s is already in a party." % them
		"buddy":
			if p.character.buddies.has(them):
				return "%s is already your buddy." % them
			if p.character.buddies.size() >= TDSocial.BUDDY_MAX:
				return "Your buddy list is full."
			if o.character.buddies.size() >= TDSocial.BUDDY_MAX and not o.character.buddies.has(me):
				return "%s's buddy list is full." % them
		"trade":
			if o.map != p.map:
				return "%s needs to be on this map to trade." % them
			if social.trades.has(p.peer) or social.trades.has(o.peer):
				return "One of you is already trading."
		"guild":
			var g := social.guild_of(me)
			if g.is_empty() or g["master"] != me:
				return "Only a guild master can invite."
			if (g["members"] as Array).size() >= TDSocial.GUILD_MAX:
				return "Your guild is full."
			if not social.guild_of(them).is_empty():
				return "%s is already in a guild." % them
	return ""

func on_answer(peer: int, id: int, accept: bool) -> void:
	var inv: Dictionary = social.invites.get(id, {})
	if inv.is_empty() or inv["to"] != peer:
		return
	social.invites.erase(id)
	var p := server.player_of(peer)
	var from := social.player_named(inv["from"])
	if p == null:
		return
	if from == null:
		tell(p, "%s isn't online any more." % inv["from"], MapInstance.BAD)
		return
	if not accept:
		tell(from, "%s said no." % p.character.name)
		return
	if inv["kind"] == "buddy" and p.character.buddies.size() >= TDSocial.BUDDY_MAX and not p.character.buddies.has(from.character.name):
		tell(p, "Your buddy list is full.", MapInstance.BAD)
		tell(from, "%s's buddy list is full." % p.character.name, MapInstance.BAD)
		return
	var problem := _invite_problem(from, inv["kind"], p)
	if problem != "":
		tell(p, problem, MapInstance.BAD)
		return
	match inv["kind"]:
		"party":
			_join_party(from, p)
		"buddy":
			for pair in [[from, p], [p, from]]:
				var a: SimPlayer = pair[0]
				if not a.character.buddies.has(pair[1].character.name):
					a.character.buddies.append(pair[1].character.name)
			tell(from, "%s is now your buddy." % p.character.name, Palette.GOOD)
			tell(p, "%s is now your buddy." % from.character.name, Palette.GOOD)
		"trade":
			social.trade.open(from, p)
		"guild":
			social.guild.join_guild(social.guild_of(from.character.name), p)

# ---------- buddies ----------

func remove_buddy(p: SimPlayer, char_name: String) -> void:
	var i := -1
	for k in p.character.buddies.size():
		if p.character.buddies[k].to_lower() == char_name.to_lower():
			i = k
	if i < 0:
		tell(p, "%s isn't on your buddy list." % char_name, MapInstance.BAD)
		return
	var them := p.character.buddies[i]
	p.character.buddies.remove_at(i)
	var o := social.player_named(them)
	if o:
		o.character.buddies.erase(p.character.name)
	tell(p, "%s was taken off your buddy list." % them)

# ---------- parties ----------

func _join_party(leader: SimPlayer, p: SimPlayer) -> void:
	var pt := social.party_of(leader.character.name)
	if pt == null:
		social.party_ids += 1
		pt = TDSocial.Party.new()
		pt.id = social.party_ids
		pt.leader = leader.character.name
		pt.members.append(leader.character.name)
		social.parties[pt.id] = pt
	pt.members.append(p.character.name)
	for m in pt.members:
		tell(social.player_named(m), "%s joined the party." % p.character.name, Palette.GOOD)

func leave_party(p: SimPlayer) -> void:
	var pt := social.party_of(p.character.name)
	if pt == null:
		tell(p, "You aren't in a party.", MapInstance.BAD)
		return
	leave(pt, p.character.name, "%s left the party." % p.character.name)
	tell(p, "You left the party.")

func kick(p: SimPlayer, char_name: String) -> void:
	var pt := social.party_of(p.character.name)
	if pt == null or pt.leader != p.character.name:
		tell(p, "Only the party leader can do that.", MapInstance.BAD)
		return
	for m in pt.members:
		if m.to_lower() == char_name.to_lower() and m != p.character.name:
			leave(pt, m, "%s was removed from the party." % m)
			tell(social.player_named(m), "You were removed from the party.", MapInstance.BAD)
			return
	tell(p, "%s isn't in your party." % char_name, MapInstance.BAD)

## Takes `char_name` out of `pt` and tells the rest `why` (or that the party broke up).
func leave(pt: TDSocial.Party, char_name: String, why: String) -> void:
	pt.members.erase(char_name)
	if pt.members.size() <= 1:
		for m in pt.members:
			tell(social.player_named(m), "The party broke up.")
		social.parties.erase(pt.id)
		return
	if pt.leader == char_name:
		pt.leader = pt.members[0]
	for m in pt.members:
		tell(social.player_named(m), why)

## The EXP each other party member on `killer`'s map gets for their kill: [[player, exp], ...].
func shares(killer: SimPlayer, xp: int) -> Array:
	var out := []
	var pt := social.party_of(killer.character.name)
	if pt == null:
		return out
	for m in pt.members:
		var o := social.player_named(m)
		if o and o != killer and o.map == killer.map and not o.fainted():
			out.append([o, maxi(1, roundi(xp * TDSocial.PARTY_SHARE))])
	return out
