class_name SocialChat
extends SocialPart
## Chat: map chat, slash commands, whispers and the party channel, plus the actions from
## the community window and the player menu.

func on_chat(peer: int, raw: String) -> void:
	var p := server.player_of(peer)
	if p == null:
		return
	var text := raw.strip_edges().replace("\n", " ").substr(0, TDSocial.CHAT_MAX)
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
		"/invite":
			social.party.invite(p, "party", arg)
		"/leave":
			social.party.leave_party(p)
		"/kick":
			social.party.kick(p, arg)
		"/trade":
			social.party.invite(p, "trade", arg)
		_:
			tell(p, "Chat: /w Name (whisper), /p (party chat), /invite, /leave, /kick, /trade.")

## Actions from the community window and the player menu, on the player named `arg`.
func on_social(peer: int, action: StringName, arg: String) -> void:
	var p := server.player_of(peer)
	if p == null:
		return
	match action:
		&"party":
			social.party.invite(p, "party", arg)
		&"trade":
			social.party.invite(p, "trade", arg)
		&"leave_party":
			social.party.leave_party(p)
		&"kick":
			social.party.kick(p, arg)

func _chat(p: SimPlayer, kind: String, from: String, text: String, from_peer := 0) -> void:
	Net.send(p.peer, &"ev_chat", [kind, from, text, from_peer])

func whisper(p: SimPlayer, to: String, text: String) -> void:
	var o := social.player_named(to)
	if o == null:
		tell(p, "%s isn't online." % to, MapInstance.BAD)
		return
	if text.strip_edges() == "":
		return
	_chat(o, "whisper", p.character.name, text, p.peer)
	_chat(p, "whisper_sent", o.character.name, text, p.peer)

func party_chat(p: SimPlayer, text: String) -> void:
	var pt := social.party_of(p.character.name)
	if pt == null:
		tell(p, "You aren't in a party.", MapInstance.BAD)
		return
	for m in pt.members:
		var o := social.player_named(m)
		if o and text != "":
			_chat(o, "party", p.character.name, text, p.peer)

