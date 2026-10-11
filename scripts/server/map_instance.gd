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
## Each monster's record as last sent in a snapshot, so unchanged ones can be left out.
var _sent_mobs: Array[PackedByteArray] = []
## peer -> the player info (info() + shop sign) last sent to this map's players.
var _sent_info := {}

func _init(s: TDServer, map_def: MapDef) -> void:
	server = s
	def = map_def
	layout = MapLayout.new(map_def)
	for r in def.roster():
		var plat := layout.platforms[r[1]]
		var m := SimMob.new(self, mobs.size(), r[0], plat, r[3].patrol_area(plat))
		if r[2] >= 0:
			m.sleep()
			m.parent = mobs[r[2]]
			mobs[r[2]].children.append(m)
		mobs.append(m)

func step() -> void:
	tick += 1
	for p in players.values():
		if p.step():
			server.revive(p)
		elif p.character.pet != &"":
			_pet_step(p)
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
	# the newcomer needs everyone's info, and everyone needs theirs: resend it all
	_sent_info.clear()

func remove_player(p: SimPlayer) -> void:
	players.erase(p.peer)
	_sent_info.erase(p.peer)
	for m in mobs:
		if m.target == p.peer:
			m.aggro = 0

## Everything a client needs on arriving: monsters and items as they are right now.
func full_state() -> Dictionary:
	return {"mobs": mobs.map(func(m: SimMob) -> Array: return m.snapshot()),
		"drops": drops.values().map(func(d: SimDrop) -> Array: return d.snapshot())}

## Where everyone and everything is, sent to this map's players many times a second as
## bytes (SnapshotCodec). Monsters that haven't changed since the last one are left out
## unless `full`, which the server asks for now and then in case an update was lost.
func snapshot(full := false) -> PackedByteArray:
	if _sent_mobs.size() != mobs.size():
		_sent_mobs.resize(mobs.size())
		full = true
	var records: Array[PackedByteArray] = []
	for i in mobs.size():
		var r := SnapshotCodec.mob_record(i, mobs[i].snapshot())
		if full or r != _sent_mobs[i]:
			records.append(r)
			_sent_mobs[i] = r
	return SnapshotCodec.encode(tick, records, players.values().map(func(p: SimPlayer) -> Array: return p.motion()))

## Sends this map's players the info (name, level, look, gear, chair, pet, shop sign) of
## every player whose info changed since it was last sent. Reliable, unlike snapshots.
func send_player_info() -> void:
	for p: SimPlayer in players.values():
		var info := p.info() + [server.social.shop_title(p.peer)]
		if _sent_info.get(p.peer) != info:
			_sent_info[p.peer] = info
			broadcast(&"ev_player_info", [p.peer, info])

## Sends an event to every player on this map (except `skip`).
func broadcast(event: StringName, args: Array, skip := 0) -> void:
	for peer in players:
		if peer != skip:
			Net.send(peer, event, args)

func tell(p: SimPlayer, text: String, col: Color) -> void:
	Net.send(p.peer, &"ev_log", [text, col.to_html()])

## Shows the player what they just gained (&"exp" or &"shards") as a small number rising
## over them, rather than a line in the message log.
func show_gain(p: SimPlayer, kind: StringName, amount: int) -> void:
	Net.send(p.peer, &"ev_gain", [kind, amount])

## The NPC with this id when the player is close enough to deal with them, or null.
func npc_near(p: SimPlayer, npc_id: StringName, reach := 160.0) -> NpcDef:
	for placement in def.npcs:
		var at := Vector2(placement.x, layout.platforms[placement.platform].y)
		if placement.npc.id == npc_id and p.position.distance_to(at) <= reach:
			return placement.npc
	return null

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
	for i in m.children.size():
		m.children[i].wake(m.position.x + (i - (m.children.size() - 1) / 2.0) * 30.0, killer.peer)
	server.give_xp(killer, m.def.exp_reward)
	for share in server.social.party_shares(killer, m.def.exp_reward):
		server.give_xp(share[0], share[1])
	server.quests.record_kill(killer, m.def)
	var loot := []
	for entry in m.def.drops:
		var amount := entry.roll()
		if amount > 0:
			loot.append([entry.item, amount])
	# a Monster Book card, until the killer's page for it is complete
	if not killer.character.book.complete(m.def) and randf() < CardDef.CHANCE:
		loot.append([Content.card(m.def), 1])
	# quest items only drop for someone on that quest
	for pair in killer.character.quests.quest_drops(m.def, killer.character):
		if randf() < pair[1]:
			loot.append([pair[0], 1])
	# spread out in a row under the monster, like MapleStory
	for i in loot.size():
		var x := clampf(m.position.x + (i - (loot.size() - 1) / 2.0) * DROP_SPACING, m.plat.x + 8, m.plat.x + m.plat.w - 8)
		spawn_drop(loot[i][0], loot[i][1], null, DropFlight.create(m.position + Vector2(0, -20), m.plat.y, x), killer.peer)

## A monster touched a player.
func touch_player(p: SimPlayer, m: SimMob) -> void:
	hurt_player(p, m.def, m.position.x)

## A monster (`def`, standing at `from_x`) hit a player, by touch or with a shot.
func hurt_player(p: SimPlayer, def: MonsterDef, from_x: float) -> void:
	if p.inv > 0 or p.fainted():
		return
	var dmg := Combat.monster_hit(def, p.character)
	p.inv = 40 if dmg == 0 else SimPlayer.HURT_INV
	broadcast(&"ev_number", [p.position.x, p.position.y - 70, dmg, "miss" if dmg == 0 else "taken"])
	if dmg == 0:
		return
	p.character.health.damage(dmg)
	p.dirty_vitals = true
	Net.send(p.peer, &"ev_hurt", [from_x])
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
	if d.item is CardDef:
		_remove_drop(d, p.peer)
		_add_card(p, (d.item as CardDef).monster)
		return true
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
	if d.item.is_currency:
		show_gain(p, &"shards", d.amount)
	else:
		# the client merges pickups of the same item into one log line
		Net.send(p.peer, &"ev_pickup", [d.item.id, d.amount])
	server.quests.picked_up(p, d.item)
	return true

## Whether the player has room for a drop (a pet only picks up what fits).
func has_room(p: SimPlayer, d: SimDrop) -> bool:
	if d.item.is_currency or d.item is CardDef:
		return true
	if d.stack:
		return p.character.inventory.room_for([d.stack])
	return p.character.inventory.has_room(d.item, d.amount)

func _add_card(p: SimPlayer, m: MonsterDef) -> void:
	var book := p.character.book
	var level := book.level()
	if not book.add_card(m):
		tell(p, "Your %s page is already complete." % m.display_name, Palette.MIST)
		return
	p.dirty_character = true
	tell(p, "Monster Book: %s card (%d/%d)" % [m.display_name, book.cards(m), CardDef.SET], Palette.CARD)
	if book.complete(m):
		tell(p, "You completed the %s page!" % m.display_name, Palette.SUN)
	if book.level() > level:
		p.character.recalc()
		tell(p, "Your Monster Book reached level %d: +%d to every stat." % [book.level(), book.level() - 1], Palette.SUN)
		broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, p.peer])

## The pet that's out gets hungrier, and picks up what it can reach.
func _pet_step(p: SimPlayer) -> void:
	var c := p.character
	var pet := c.pet_def()
	if pet == null:
		c.pet = &""
		return
	if tick % pet.hunger_ticks == 0:
		c.pet_full = maxi(0, c.pet_full - PetDef.HUNGER_STEP)
		p.dirty_character = true
		if c.pet_full == 0:
			c.pet = &""
			tell(p, "%s got hungry and went home." % pet.display_name, BAD)
			return
		if c.pet_full == PetDef.HUNGRY:
			tell(p, "%s is getting hungry. Feed it some pet food." % pet.display_name, BAD)
	if tick % 2400 == 0 and not pet.chatter.is_empty() and randf() < 0.5:
		broadcast(&"ev_chat", ["pet", pet.display_name, pet.chatter.pick_random(), p.peer])
	if tick % pet.loot_every != 0 or p.climbing:
		return
	var best: SimDrop = null
	for d in drops.values():
		if d.can_loot(p, pet.loot_reach) and has_room(p, d) \
				and (best == null or absf(d.flight.position.x - p.position.x) < absf(best.flight.position.x - p.position.x)):
			best = d
	if best:
		pick_up(p, best)

## Drops a stack from the player's bag onto the ground at their feet.
func drop_from_player(p: SimPlayer, stack: ItemStack) -> void:
	var ground := layout.ground_below(p.position)
	spawn_drop(stack.item, stack.count, stack, DropFlight.create(p.position + Vector2(0, -30), ground, p.position.x + p.face * 14), 0)
	tell(p, "Dropped %s" % amount_name(stack.item, stack.count), Palette.MIST)

static func amount_name(item: ItemDef, amount: int) -> String:
	return "%d %s" % [amount, item.display_name] if amount > 1 or item.is_currency else item.display_name
