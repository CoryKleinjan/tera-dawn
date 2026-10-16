class_name SocialGuilds
extends SocialPart
## Guilds (founded at a guild NPC, saved to guilds.data) and fame.

# ---------- guilds ----------

func load_guilds() -> void:
	var data: Variant = SafeFile.read_json(social.guild_path)
	if data is Dictionary:
		for k in data:
			var g: Variant = data[k]
			if g is Dictionary and g.get("members") is Array:
				social.guilds[str(k)] = {"name": str(g.get("name", k)), "master": str(g.get("master", "")), "members": (g["members"] as Array).map(func(m) -> String: return str(m))}

func save_guilds() -> void:
	SafeFile.write_text(social.guild_path, JSON.stringify(social.guilds))

## Founds a guild named `guild_name` at a guild NPC.
func on_create(peer: int, npc_id: StringName, guild_name: String) -> void:
	var p := server.player_of(peer)
	if p == null:
		return
	var npc := p.map.npc_near(p, npc_id)
	if npc == null or not npc.guild:
		return
	var n := CharacterStore.clean_name(guild_name)
	var c := p.character
	var problem := ""
	if not social.guild_of(c.name).is_empty():
		problem = "You're already in a guild."
	elif c.level < TDSocial.GUILD_LEVEL:
		problem = "You need to be level %d to found a guild." % TDSocial.GUILD_LEVEL
	elif c.shards < TDSocial.GUILD_COST:
		problem = "Founding a guild costs %d Dawnshards." % TDSocial.GUILD_COST
	elif n.length() < 3:
		problem = "Pick a guild name of at least 3 letters."
	elif social.guilds.has(n.to_lower()):
		problem = "There's already a guild called %s." % n
	if problem != "":
		tell(p, problem, MapInstance.BAD)
		return
	c.shards -= TDSocial.GUILD_COST
	social.guilds[n.to_lower()] = {"name": n, "master": c.name, "members": [c.name]}
	c.guild = n
	p.dirty_character = true
	save_guilds()
	tell(p, "You founded the guild %s!" % n, Palette.GOOD)
	p.map.broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, peer])

func join_guild(g: Dictionary, p: SimPlayer) -> void:
	if g.is_empty():
		return
	(g["members"] as Array).append(p.character.name)
	p.character.guild = g["name"]
	p.dirty_character = true
	save_guilds()
	for m in g["members"]:
		tell(social.player_named(m), "%s joined the guild." % p.character.name, Palette.GOOD)

func leave_guild(p: SimPlayer) -> void:
	var g := social.guild_of(p.character.name)
	if g.is_empty():
		tell(p, "You aren't in a guild.", MapInstance.BAD)
		return
	var members: Array = g["members"]
	members.erase(p.character.name)
	p.character.guild = ""
	p.dirty_character = true
	if members.is_empty():
		social.guilds.erase(String(g["name"]).to_lower())
		tell(p, "%s was disbanded." % g["name"])
	else:
		if g["master"] == p.character.name:
			g["master"] = members[0]
		for m in members:
			tell(social.player_named(m), "%s left the guild." % p.character.name)
		tell(p, "You left %s." % g["name"])
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
	if c.level < TDSocial.FAME_LEVEL:
		return "You can give fame from level %d." % TDSocial.FAME_LEVEL
	var day := today()
	if c.fame_day == day:
		return "You've already given fame today."
	if c.fame_given.has(o.character.name) and day - int(c.fame_given[o.character.name]) < TDSocial.FAME_REPEAT_DAYS:
		return "You gave %s fame this month already." % o.character.name
	return ""

func give_fame(p: SimPlayer, to: String, up: bool) -> void:
	var o := social.player_named(to)
	var problem := fame_problem(p, o)
	if problem != "":
		tell(p, problem, MapInstance.BAD)
		return
	var day := today()
	p.character.fame_day = day
	p.character.fame_given[o.character.name] = day
	o.character.fame += 1 if up else -1
	p.dirty_character = true
	o.dirty_character = true
	tell(p, "You %s %s's fame." % ["raised" if up else "lowered", o.character.name], Palette.GOOD)
	tell(o, "%s %s your fame." % [p.character.name, "raised" if up else "lowered"], Palette.GOOD if up else MapInstance.BAD)

func on_fame(peer: int, target_peer: int, up: bool) -> void:
	var p := server.player_of(peer)
	var o := server.player_of(target_peer)
	if p and o:
		give_fame(p, o.character.name, up)
