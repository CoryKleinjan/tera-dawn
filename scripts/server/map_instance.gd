class_name MapInstance
extends RefCounted
## One map running on the server: its monsters, the items on the ground and the players
## on it. The server keeps one per map that has been visited and steps the ones with
## players on them. Everything the players see happen here (hits, kills, EXP, drops,
## pickups) is decided here and sent to the clients on this map as events.

## Game pixels between the items a monster drops.
const DROP_SPACING := 26.0
const BAD := Color("ff8a99")

var server: TDServer
var def: MapDef
var layout: MapLayout
var tick := 0
## peer id -> SimPlayer
var players := {}
var mobs: Array[SimMob] = []
## drop id -> SimDrop
var drops := {}

func _init(s: TDServer, map_def: MapDef) -> void:
	server = s
	def = map_def
	layout = MapLayout.new(map_def)
	for spawn in def.spawns:
		for i in spawn.count:
			mobs.append(SimMob.new(self, mobs.size(), spawn.monster, layout.platforms[spawn.platform]))

func step() -> void:
	tick += 1
	for p in players.values():
		if p.step():
			server.revive(p)
	for m in mobs:
		m.step()
	for id in drops.keys():
		var d: SimDrop = drops[id]
		d.step()
		if d.expired():
			_remove_drop(d, 0)
		elif d.item.is_currency:
			for p in players.values():
				if d.can_loot(p):
					pick_up(p, d)
					break

# ---------- players coming and going ----------

func add_player(p: SimPlayer, x: float) -> void:
	p.map = self
	p.position = Vector2(x, layout.platforms[0].y)
	p.climbing = false
	p.since_move = 0
	p.character.map_id = def.id
	players[p.peer] = p

func remove_player(p: SimPlayer) -> void:
	players.erase(p.peer)
	for m in mobs:
		if m.target == p.peer:
			m.aggro = 0

## Everything a client needs on arriving: monsters and items as they are right now.
func full_state() -> Dictionary:
	return {"mobs": mobs.map(func(m: SimMob) -> Array: return m.snapshot()),
		"drops": drops.values().map(func(d: SimDrop) -> Array: return d.snapshot())}

## Where everyone and everything is, sent to this map's players many times a second.
func snapshot() -> Dictionary:
	return {"tick": tick,
		"mobs": mobs.map(func(m: SimMob) -> Array: return m.snapshot()),
		"players": players.values().map(func(p: SimPlayer) -> Array: return p.snapshot())}

## Sends an event to every player on this map (except `skip`).
func broadcast(event: StringName, args: Array, skip := 0) -> void:
	for peer in players:
		if peer != skip:
			Net.send(peer, event, args)

func tell(p: SimPlayer, text: String, col: Color) -> void:
	Net.send(p.peer, &"ev_log", [text, col.to_html()])

# ---------- combat ----------

## Resolves a player's skill against the monsters in front of them. Returns how many were hit.
func use_skill(p: SimPlayer, skill: SkillDef) -> int:
	var area := Hitbox.attack_area(p.position, p.face, skill.reach, skill.height)
	var targets: Array[SimMob] = []
	for m in mobs:
		if not m.dead and area.intersects(m.hurtbox.rect_at(m.body_position())):
			targets.append(m)
	targets.sort_custom(func(a: SimMob, b: SimMob) -> bool:
		return absf(a.position.x - p.position.x) < absf(b.position.x - p.position.x))
	if targets.size() > skill.max_targets:
		targets.resize(skill.max_targets)
	# [mob index, [[damage, kind], ...]] for every monster hit, shown by every client
	var lines := []
	var killed: Array[SimMob] = []
	for m in targets:
		var hits := []
		for i in skill.hits:
			if m.health.is_dead():
				break
			var hit := Combat.player_hit(skill, m.def, p.character)
			if hit["miss"]:
				hits.append([0, "miss"])
				continue
			m.health.damage(hit["damage"])
			hits.append([hit["damage"], "crit" if hit["crit"] else "hit"])
		lines.append([m.index, hits])
		if m.health.is_dead():
			killed.append(m)
		else:
			m.hurt(p.face, p.peer)
	broadcast(&"ev_skill", [p.peer, skill.id, p.position.x, p.position.y, p.face, lines])
	for m in killed:
		kill_mob(m, p)
	return targets.size()

func kill_mob(m: SimMob, killer: SimPlayer) -> void:
	m.die()
	broadcast(&"ev_mob_died", [m.index])
	server.give_xp(killer, m.def.exp_reward)
	var loot := []
	for entry in m.def.drops:
		var amount := entry.roll()
		if amount > 0:
			loot.append([entry.item, amount])
	# spread out in a row under the monster, like MapleStory
	for i in loot.size():
		var x := clampf(m.position.x + (i - (loot.size() - 1) / 2.0) * DROP_SPACING, m.plat.x + 8, m.plat.x + m.plat.w - 8)
		spawn_drop(loot[i][0], loot[i][1], null, DropFlight.create(m.position + Vector2(0, -20), m.plat.y, x), killer.peer)

## A monster touched a player.
func touch_player(p: SimPlayer, m: SimMob) -> void:
	if p.inv > 0 or p.fainted():
		return
	var dmg := Combat.monster_hit(m.def, p.character)
	p.inv = 40 if dmg == 0 else SimPlayer.HURT_INV
	broadcast(&"ev_number", [p.position.x, p.position.y - 70, dmg, "miss" if dmg == 0 else "taken"])
	if dmg == 0:
		return
	p.character.health.damage(dmg)
	p.dirty_vitals = true
	Net.send(p.peer, &"ev_hurt", [m.position.x])
	if p.character.health.is_dead():
		p.faint_t = SimPlayer.FAINT_TICKS
		p.climbing = false
		var lost := Combat.faint_penalty(p.character.xp)
		p.character.xp -= lost
		Net.send(p.peer, &"ev_fainted", [])
		tell(p, "You fainted and lost %d EXP." % lost, BAD)

# ---------- items ----------

func spawn_drop(item: ItemDef, amount: int, stack: ItemStack, flight: DropFlight, owner: int) -> void:
	var d := SimDrop.new(server.next_drop_id(), item, amount, flight, owner)
	d.stack = stack
	drops[d.id] = d
	broadcast(&"ev_drop", [d.snapshot()])

func _remove_drop(d: SimDrop, by: int) -> void:
	d.taken = true
	drops.erase(d.id)
	broadcast(&"ev_drop_gone", [d.id, by])

## Picks up the nearest drop the player is standing by (the loot key). True if one was taken.
func loot_near(p: SimPlayer) -> bool:
	var best: SimDrop = null
	for d in drops.values():
		if d.can_loot(p) and (best == null or absf(d.flight.position.x - p.position.x) < absf(best.flight.position.x - p.position.x)):
			best = d
	return best != null and pick_up(p, best)

## Puts a drop in the player's wallet or bag. False (with a message) if there's no room.
func pick_up(p: SimPlayer, d: SimDrop) -> bool:
	var ch := p.character
	var full := "Your %s inventory is full." % ItemDef.TAB_NAMES[d.item.tab()]
	if d.item.is_currency:
		ch.shards += d.amount
		p.dirty_vitals = true
	elif d.stack:
		if not ch.inventory.add_stack(d.stack):
			tell(p, full, BAD)
			return false
		p.dirty_character = true
	elif not ch.inventory.has_room(d.item, d.amount):
		tell(p, full, BAD)
		return false
	else:
		ch.inventory.add(d.item, d.amount)
		p.dirty_character = true
	_remove_drop(d, p.peer)
	tell(p, "Picked up %s" % amount_name(d.item, d.amount), Palette.MIST)
	return true

## Drops a stack from the player's bag onto the ground at their feet.
func drop_from_player(p: SimPlayer, stack: ItemStack) -> void:
	var ground := layout.ground_below(p.position)
	spawn_drop(stack.item, stack.count, stack, DropFlight.create(p.position + Vector2(0, -30), ground, p.position.x + p.face * 14), 0)
	tell(p, "Dropped %s" % amount_name(stack.item, stack.count), Palette.MIST)

static func amount_name(item: ItemDef, amount: int) -> String:
	return "%d %s" % [amount, item.display_name] if amount > 1 or item.is_currency else item.display_name
