class_name TDServer
extends Node
## The authoritative game server. It holds every connected player's Character, runs a
## MapInstance for each map with players on it 60 times a second, and answers the
## requests clients send through Net. This file keeps the players, maps, saving and the
## requests about moving and fighting; the rest are handled by its parts under
## scripts/server/services/ (items, NPC shops, storage, travel, quests, jobs) and by
## TDSocial (everything players do with each other). A single-player or hosted game runs
## it next to its own client. Characters are saved by each player's own game (`save`).

## Ticks between position snapshots (60 / 3 = 20 a second).
const SNAPSHOT_EVERY := 3
## Ticks between snapshots that include every monster, changed or not (once a second), so
## a client that lost an update catches up.
const FULL_SNAPSHOT_EVERY := 60
## Ticks between saving everyone.
const SAVE_EVERY := 600
## Attack requests may arrive this many ticks early, to allow for network jitter.
const COOLDOWN_SLACK := 4

## Letting players in and putting the characters they bring into the world.
var lobby: TDLobby
## peer id -> SimPlayer
var sessions := {}
## map id -> MapInstance (a solo map's copies are keyed by `instance_key`)
var maps := {}
var tick := 0
var _drop_ids := 0
## Chat, buddies, parties, trades, guilds, fame and player shops.
var social: TDSocial
## The requests about the player's things, NPC shops, storage, getting around, quests and
## jobs, one part each (scripts/server/services/).
var items: ServerItems
var npc_shop: ServerNpcShop
var storage: ServerStorage
var travel: ServerTravel
var quests: ServerQuests
var jobs: ServerJobs
var scenes: ServerScenes

## `save_dir` is where this game keeps what the server owns (its guilds).
func _init(save_dir := "user://characters") -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	social = TDSocial.new(self, save_dir)
	lobby = TDLobby.new(self)
	items = ServerItems.new(self)
	npc_shop = ServerNpcShop.new(self)
	storage = ServerStorage.new(self)
	travel = ServerTravel.new(self)
	quests = ServerQuests.new(self)
	jobs = ServerJobs.new(self)
	scenes = ServerScenes.new(self)

func _physics_process(_delta: float) -> void:
	tick += 1
	for m: MapInstance in maps.values():
		if not m.players.is_empty():
			m.step()
	social.step(tick)
	lobby.step(tick)
	for p: SimPlayer in sessions.values():
		scenes.step(p)
		_flush(p)
	if tick % SNAPSHOT_EVERY == 0:
		for m: MapInstance in maps.values():
			if not m.players.is_empty():
				m.send_player_info()
				m.broadcast(&"ev_snapshot", [m.snapshot(tick % FULL_SNAPSHOT_EVERY == 0)])
	if tick % SAVE_EVERY == 0:
		save_all()

func save_all() -> void:
	for p: SimPlayer in sessions.values():
		save(p)

## Saves the player's character: the server sends it to their own game, which keeps it on
## their computer (CharacterStore), so it goes with them to the next game they play.
func save(p: SimPlayer) -> void:
	Net.send(p.peer, &"ev_save", [p.character.to_dict()])

func next_drop_id() -> int:
	_drop_ids += 1
	return _drop_ids

## The running map `id` (for a solo map, `p`'s own copy).
func map_instance(id: StringName, p: SimPlayer = null) -> MapInstance:
	var key := instance_key(id, p)
	if not maps.has(key):
		maps[key] = MapInstance.new(self, Content.map(id))
	return maps[key]

## Where `maps` keeps map `id` for `p`: the id, or for a solo map the id and their peer.
func instance_key(id: StringName, p: SimPlayer) -> StringName:
	if p != null and Content.map(id).solo:
		return StringName("%s#%d" % [id, p.peer])
	return id

## Takes the player off their map, dropping a solo map's copy so it starts fresh next time.
func _off_map(p: SimPlayer) -> void:
	p.map.remove_player(p)
	p.map.broadcast(&"ev_player_left", [p.peer])
	if p.map.def.solo:
		maps.erase(instance_key(p.map.def.id, p))

## Sends the player what changed about their character this tick.
func _flush(p: SimPlayer) -> void:
	if p.dirty_character or p.dirty_vitals or tick % 60 == 0:
		check_achievements(p)
	if p.dirty_character:
		Net.send(p.peer, &"ev_character", [p.character.to_dict()])
	elif p.dirty_vitals:
		var c := p.character
		Net.send(p.peer, &"ev_vitals", [c.health.hp, c.mp, c.xp, c.level, c.shards])
	p.dirty_character = false
	p.dirty_vitals = false

# ---------- joining and leaving ----------

## Puts the character `c` a player brought (picked at their character select, see TDLobby)
## into the world.
func enter_game(peer: int, c: Character) -> void:
	if social.player_named(c.name) != null:
		lobby.refuse(peer, "%s is already playing." % c.name)
		return
	var p := SimPlayer.new(peer, c)
	sessions[peer] = p
	social.joined(p)
	Net.send(peer, &"ev_joined", [c.to_dict()])
	enter_map(p, c.map_id, Content.map(c.map_id).start_x)
	print("%s joined (peer %d)" % [c.name, peer])

## A connection closed: out of the world.
func disconnected(peer: int) -> void:
	leave(peer)
	lobby.dropped(peer)

## Takes a player out of the world (saving them). They stay connected. A player who leaves
## while fainted is revived first, so they come back in town.
func leave(peer: int) -> void:
	var p := player_of(peer)
	if p == null:
		return
	if p.fainted():
		_wake(p)
		p.character.map_id = _town_for(p)
	social.left(p)
	sessions.erase(peer)
	_off_map(p)
	save(p)
	print("%s left" % p.character.name)

## Moves the player to map `id` at `x` (through a portal, a trip, a return scroll or
## reviving), and tells them what's there.
func enter_map(p: SimPlayer, id: StringName, x: float) -> void:
	if p.map:
		social.changed_map(p)
		_off_map(p)
	scenes.stop(p)
	var m := map_instance(id, p)
	p.chair = &""
	p.character.visit(id)
	m.add_player(p, x)
	Net.send(p.peer, &"ev_enter_map", [id, x, m.full_state()])
	quests.progress(p, p.character.quests.record_visit(id))
	save(p)
	scenes.play(p, m.def.intro_scene)

## Sends a fainted player back to town with half their HP and MP.
func revive(p: SimPlayer) -> void:
	_wake(p)
	var town := _town_for(p)
	enter_map(p, town, Content.map(town).start_x)

## Gets a fainted player up with half their HP and MP and a moment of invincibility.
func _wake(p: SimPlayer) -> void:
	var c := p.character
	c.health.reset(c.max_hp())
	c.health.set_hp(ceili(c.max_hp() / 2.0))
	c.mp = ceili(c.max_mp() / 2.0)
	p.faint_t = 0
	p.inv = 120
	p.dirty_vitals = true

## The town a fainted player wakes up in.
func _town_for(p: SimPlayer) -> StringName:
	var town := p.map.def.return_town() if p.map else Character.START_MAP
	return town if Content.maps.has(town) else Character.START_MAP

func give_xp(p: SimPlayer, amount: int) -> void:
	var c := p.character
	if c.at_max_level():
		return
	var levels := c.gain_xp(amount)
	p.dirty_vitals = true
	p.map.show_gain(p, &"exp", amount)
	if levels > 0:
		p.dirty_character = true
		p.map.broadcast(&"ev_level_up", [p.peer, c.level])
		p.map.tell(p, "Level up! You reached Lv. %d" % c.level, Palette.SUN)
		save(p)

## Tells the player about achievements they've just reached; their game unlocks them on Steam.
func check_achievements(p: SimPlayer) -> void:
	for a in Achievements.check(p.character):
		p.dirty_character = true
		Net.send(p.peer, &"ev_achievement", [String(a.id)])
		p.map.broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, p.peer])

# ---------- requests from clients (see Net) ----------
## The rest are in the parts under scripts/server/services/ (see `items` and the others).

## The player on this peer, or null.
func player_of(peer: int) -> SimPlayer:
	return sessions.get(peer)

func on_move(peer: int, at: Vector2, face: int, anim: StringName, climbing: bool) -> void:
	var p := player_of(peer)
	if p and social.shops.has(peer):
		# minding a shop: stay put
		if p.position.distance_to(at) > 2.0:
			Net.send(peer, &"ev_place", [p.position.x, p.position.y])
		return
	if p and not p.report_move(at, face, anim, climbing) and not p.fainted():
		Net.send(peer, &"ev_place", [p.position.x, p.position.y])
	elif p:
		quests.reached(p)
		p.map.check_tear(p)

## `aim` is a Hitbox.Aim: up or down for an aiming attack, else ahead.
func on_skill(peer: int, skill_id: StringName, at: Vector2, face: int, aim := 0) -> void:
	var p := player_of(peer)
	var skill: SkillDef = Content.skills.get(skill_id)
	if p == null or skill == null or p.fainted() or p.cooldown > COOLDOWN_SLACK:
		return
	if p.recharge.get(skill.id, 0) > COOLDOWN_SLACK:
		return
	# fighting means no cutscene is playing on their screen, so monsters may hit them again
	scenes.stop(p)
	var c := p.character
	var problem := c.skills.use_problem(skill)
	if problem != "":
		p.map.tell(p, problem, Palette.INFO)
		return
	var lvl := c.skills.level(skill)
	c.spend_mp(skill.mp_at(lvl))
	p.report_move(at, face, skill.animation, false)
	p.cooldown = CharacterStats.attack_ticks(skill.cooldown, c.stats)
	if skill.recharge_ticks(lvl) > 0:
		p.recharge[skill.id] = skill.recharge_ticks(lvl)
	p.dirty_vitals = true
	if skill.kind == SkillDef.Kind.BUFF:
		_cast_buff(p, skill, lvl)
		if skill.party:
			for o in social.party_near(p, SkillDef.PARTY_REACH):
				_cast_buff(o, skill, lvl)
				if skill.effect:
					p.map.broadcast(&"ev_effect", [skill.effect.id, o.position.x, o.position.y, o.face, o.peer])
		p.map.broadcast(&"ev_skill", [p.peer, skill.id, p.position.x, p.position.y, p.face, [], Hitbox.Aim.AHEAD])
	else:
		# attacking gives a hidden player away
		if c.skills.end_hiding():
			p.dirty_character = true
		p.map.use_skill(p, skill, skill.aim_for(clampi(aim, 0, Hitbox.Aim.size() - 1) as Hitbox.Aim))

## A buff from `skill` at `lvl` lands on `p` (the caster, or a party member): its heal, then
## the buff itself.
func _cast_buff(p: SimPlayer, skill: SkillDef, lvl: int) -> void:
	var c := p.character
	if skill.heal_at(lvl) > 0.0:
		c.health.heal(roundi(c.max_hp() * skill.heal_at(lvl)))
		p.dirty_vitals = true
	c.skills.add_buff(skill, lvl)
	p.dirty_character = true

## Puts a skill or item on a quickslot (an empty `kind` clears it).
func on_set_quickslot(peer: int, i: int, kind: StringName, id: StringName) -> void:
	var p := player_of(peer)
	if p == null or not kind in [&"", &"skill", &"item"]:
		return
	if kind == &"skill" and not Content.skills.has(id) or kind == &"item" and not Content.items.has(id):
		return
	p.character.set_quickslot(i, kind, id)
	p.dirty_character = true

func on_loot(peer: int) -> void:
	var p := player_of(peer)
	if p and not p.climbing:
		p.map.loot_near(p)
