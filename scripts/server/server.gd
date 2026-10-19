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
## Chat, buddies, parties, trades, guilds and fame.
var social: TDSocial
## The requests about the player's things, NPC shops, storage, enchanting, getting around,
## quests and jobs, one part each (scripts/server/services/).
var items: ServerItems
var npc_shop: ServerNpcShop
var storage: ServerStorage
var enchanting: ServerEnchanting
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
	enchanting = ServerEnchanting.new(self)
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

## Takes the player off their map. A map nobody is on any more (a solo map as soon as its
## player leaves) is dropped, so it starts fresh next time: its monsters back, its ground
## cleared.
func _off_map(p: SimPlayer) -> void:
	p.map.remove_player(p)
	p.map.broadcast(&"ev_player_left", [p.peer])
	if p.map.players.is_empty():
		maps.erase(instance_key(p.map.def.id, p))

## Sends the player what changed about their character this tick.
func _flush(p: SimPlayer) -> void:
	if p.dirty_character or p.dirty_vitals or tick % 60 == 0:
		check_achievements(p)
	if p.dirty_character:
		Net.send(p.peer, &"ev_character", [p.character.to_dict()])
	elif p.dirty_vitals:
		var c := p.character
		Net.send(p.peer, &"ev_vitals", [c.health.hp, c.mp, c.shards])
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
## while fainted is revived first, so they come back where they'd wake (`_wake_spot`).
func leave(peer: int) -> void:
	var p := player_of(peer)
	if p == null:
		return
	if p.fainted():
		_wake(p)
		p.character.map_id = _wake_spot(p)[0]
	social.left(p)
	sessions.erase(peer)
	_off_map(p)
	save(p)
	print("%s left" % p.character.name)

## Moves the player to map `id` at `x` (through a portal, a trip, a return scroll or
## reviving), standing on platform `platform` (the floor unless a portal says otherwise),
## and tells them what's there. `arrive` is the side of the room they come in through when
## they come through a way out of the last one (RoomExits): through a top way they drop in
## from above.
func enter_map(p: SimPlayer, id: StringName, x: float, platform := 0, arrive := RoomExits.Side.NONE) -> void:
	if p.map:
		social.changed_map(p)
		_off_map(p)
	scenes.stop(p)
	var m := map_instance(id, p)
	if platform < 0 or platform >= m.layout.platforms.size():
		platform = 0
	p.sitting = false
	p.character.visit(id)
	m.add_player(p, x, platform)
	if arrive == RoomExits.Side.TOP:
		p.position.y -= RoomExits.DROP_IN
	Net.send(p.peer, &"ev_enter_map", [id, x, m.full_state(), platform, arrive])
	quests.progress(p, p.character.quests.record_visit(id))
	save(p)
	scenes.play(p, m.def.intro_scene)

## Sends a fainted player back to their rest spot or town (`_wake_spot`) with every heart
## back and no Mana.
func revive(p: SimPlayer) -> void:
	_wake(p)
	var at := _wake_spot(p)
	enter_map(p, at[0], at[1], at[2])

## Where a fainted player wakes up, as [map, x, platform]: the rest spot they last rested at
## (`_rest`) when they fainted in its region outside a town, else the town (`_town_for`) at
## its start.
func _wake_spot(p: SimPlayer) -> Array:
	var c := p.character
	var rest: MapDef = Content.maps.get(c.rest_map)
	if rest and p.map and not p.map.def.town and rest.region == p.map.def.region and c.rest_spot < rest.rest_spots.size():
		var r := rest.rest_spots[c.rest_spot]
		return [rest.id, float(r.x), r.y]
	var town := _town_for(p)
	return [town, Content.map(town).start_x, 0]

## Rests the player at rest spot `spot` of their map (MapDef.rest_spots): every heart comes
## back (Mana stays as it is), and fainting in this region wakes them here from now on.
func _rest(p: SimPlayer, spot: int) -> void:
	var c := p.character
	c.refill()
	p.dirty_vitals = true
	if c.rest_map != p.map.def.id or c.rest_spot != spot:
		c.rest_map = p.map.def.id
		c.rest_spot = spot
		p.map.tell(p, "You rested. You'll wake here if you faint nearby.", Palette.INFO)
		save(p)

## Gets a fainted player up with every heart, no Mana and a moment of invincibility.
func _wake(p: SimPlayer) -> void:
	var c := p.character
	c.refill()
	c.mp = 0
	p.faint_t = 0
	p.inv = 120
	p.dirty_vitals = true

## The town a fainted player wakes up in.
func _town_for(p: SimPlayer) -> StringName:
	var town := p.map.def.return_town() if p.map else Character.START_MAP
	return town if Content.maps.has(town) else Character.START_MAP

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

func on_move(peer: int, at: Vector2, face: int, anim: StringName) -> void:
	var p := player_of(peer)
	if p and not p.report_move(at, face, anim) and not p.fainted():
		Net.send(peer, &"ev_place", [p.position.x, p.position.y])
	elif p:
		quests.reached(p)
		p.map.check_tear(p)
		p.map.check_spots(p)
		p.map.check_secrets(p)

## The player's Slam landed at `at`: what it lands on breaks (MapInstance.slam), if they
## have the move and are where they say.
func on_slam(peer: int, at: Vector2) -> void:
	var p := player_of(peer)
	if p and not p.fainted() and p.character.has_move(RelicDef.Move.SLAM) \
			and at.distance_to(p.position) <= SimPlayer.MAX_STEP * TDPlayer.REPORT_EVERY + 40.0:
		p.map.slam(p, at)

## Sits the player down on the ground (`down`) or gets them up. Sitting by a rest spot's
## bench rests there (`_rest`); moving or getting hit gets them up.
func on_sit(peer: int, down: bool) -> void:
	var p := player_of(peer)
	if p == null or p.sitting == down:
		return
	if down and (p.fainted() or p.in_scene() or p.map.layout.platform_under(p.position) == null):
		p.map.tell(p, "You can't sit here.", MapInstance.BAD)
		Net.send(peer, &"ev_sit", [false])
		return
	p.sitting = down
	if down:
		p.character.count(Counters.SAT)
		p.dirty_character = true
	Net.send(peer, &"ev_sit", [down])
	var spot := p.map.layout.rest_at(p.position) if down else -1
	if spot >= 0:
		_rest(p, spot)

## The player held the heal key long enough (TDPlayer): CharacterStats.HEAL_COST Mana heals
## a heart, if they have it and aren't healing faster than SimPlayer.HEAL_TICKS allows.
func on_heal(peer: int) -> void:
	var p := player_of(peer)
	if p == null or p.fainted() or p.in_scene() or p.heal_cd > COOLDOWN_SLACK or not p.character.heal_heart():
		return
	p.heal_cd = SimPlayer.HEAL_TICKS
	p.dirty_vitals = true
	p.map.broadcast(&"ev_effect", [EffectDef.HEAL, p.position.x, p.position.y, p.face, p.peer])

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
	p.report_move(at, face, skill.animation)
	p.cooldown = CharacterStats.attack_ticks(skill.cooldown, c.stats)
	if skill.recharge_ticks(lvl) > 0:
		p.recharge[skill.id] = skill.recharge_ticks(lvl)
	p.dirty_vitals = true
	var aimed := skill.aim_for(clampi(aim, 0, Hitbox.Aim.size() - 1) as Hitbox.Aim)
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
		p.map.use_skill(p, skill, aimed)

## A buff from `skill` at `lvl` lands on `p` (the caster, or a party member): its heal, then
## the buff itself.
func _cast_buff(p: SimPlayer, skill: SkillDef, lvl: int) -> void:
	var c := p.character
	if skill.heal_at(lvl) > 0.0:
		c.health.heal(roundi(c.max_hp() * skill.heal_at(lvl)))
		p.dirty_vitals = true
	c.skills.add_buff(skill, lvl)
	p.dirty_character = true
	if skill.aura and c.skills.buffs.has(skill.id):
		p.map.broadcast(&"ev_aura", [p.peer, skill.id, c.skills.buffs[skill.id][1]])

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
	if p:
		p.map.loot_near(p)
